"""CLI regressions using only temporary applets; run with python3 tests/test_cli.py."""
import json
import argparse
import contextlib
import io
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

QSA = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin/qsa"))


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="qsa-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_non_object_answers_are_validation_errors(self):
        for value in ([], None, "answer", 42, True):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "JSON object"):
                QSA["parse_answer"](json.dumps(value))

    def test_non_object_answer_enters_repair_loop(self):
        staging = self.root / "test"
        staging.mkdir()
        valid = json.dumps({"summary": "repaired", "files": {
            "applet.toml": 'name = "test"\nentry = "main.sh"\n',
            "main.sh": '#!/bin/sh\nprintf \'{}\\n\'\n'}})
        with patch.dict(QSA["generate"].__globals__, {
                "ask_model": unittest.mock.Mock(side_effect=["[]", valid]),
                "guide": lambda: "test guide"}):
            summary = QSA["generate"]({"provider": "codex", "model": None, "source": "test"},
                                      "prompt", staging, "test")
        self.assertEqual(summary, "repaired")
        self.assertIsNone(QSA["load"](staging)[1])

    def test_linked_files_and_directories_cannot_be_written(self):
        staging = self.root / "staging"
        staging.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        original = outside / "file.txt"
        original.write_text("original")
        (staging / "file.txt").symlink_to(original)
        (staging / "directory").symlink_to(outside, target_is_directory=True)
        for path in ("file.txt", "directory/file.txt", "directory/new.txt"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "symlink"):
                QSA["apply_files"](staging, {"safe.txt": "safe", path: "changed"}, [])
            self.assertFalse((staging / "safe.txt").exists())
        self.assertEqual(original.read_text(), "original")
        self.assertFalse((outside / "new.txt").exists())
        with self.assertRaisesRegex(ValueError, "symlink"):
            QSA["reject_symlinks"](staging)

    def test_linked_root_and_delete_paths_are_rejected(self):
        staging = self.root / "staging"
        staging.mkdir()
        original = staging / "file.txt"
        original.write_text("original")
        link = self.root / "link"
        link.symlink_to(staging, target_is_directory=True)
        with self.assertRaises(ValueError):
            QSA["apply_files"](link, {}, ["file.txt"])
        with self.assertRaises(ValueError):
            QSA["reject_symlinks"](link)
        self.assertEqual(original.read_text(), "original")

    def test_write_boundary_rejects_traversal(self):
        for path in ("../outside.txt", str(self.root / "outside.txt"), ".hidden/file", ""):
            with self.subTest(path=path), self.assertRaises(ValueError):
                QSA["apply_files"](self.root, {path: "changed"}, [])

    def test_revision_detects_deletion_with_a_newer_file_present(self):
        older, newer = self.root / "helper.qml", self.root / "applet.toml"
        older.write_text("older")
        newer.write_text("newer")
        os.utime(older, ns=(100, 100))
        os.utime(newer, ns=(200, 200))
        before = QSA["revision"](self.root)
        self.assertEqual(before, QSA["revision"](self.root))
        older.unlink()
        self.assertNotEqual(before, QSA["revision"](self.root))

    def test_revision_detects_preserved_mtime_and_permissions(self):
        file = self.root / "main.py"
        file.write_text("before")
        timestamp = file.stat().st_mtime_ns
        before = QSA["revision"](self.root)
        file.write_text("after!")
        os.utime(file, ns=(timestamp, timestamp))
        self.assertNotEqual(before, QSA["revision"](self.root))
        before = QSA["revision"](self.root)
        file.chmod(0o755)
        after = QSA["revision"](self.root)
        self.assertNotEqual(before, after)
        self.assertLess(after, 2 ** 53)

    def replacement_folders(self):
        staging, target = self.root / "staging", self.root / "target"
        staging.mkdir()
        target.mkdir()
        (staging / "new.txt").write_text("new")
        (target / "old.txt").write_text("old")
        return staging, target

    def test_replacement_succeeds_and_cleans_backup(self):
        staging, target = self.replacement_folders()
        QSA["replace_applet"](staging, target)
        self.assertEqual((target / "new.txt").read_text(), "new")
        self.assertFalse((target / "old.txt").exists())
        self.assertFalse(list(self.root.glob(".target.swap-*")))

    def test_copy_failure_leaves_original_live(self):
        staging, target = self.replacement_folders()
        with patch("shutil.copytree", side_effect=OSError("copy failed")):
            with self.assertRaisesRegex(OSError, "copy failed"):
                QSA["replace_applet"](staging, target)
        self.assertEqual((target / "old.txt").read_text(), "old")

    def test_switch_failure_restores_original(self):
        staging, target = self.replacement_folders()
        rename = Path.rename

        def fail_switch(path, destination):
            if path.name == "new":
                # Preparation completed before the live directory was moved.
                self.assertEqual((path / "new.txt").read_text(), "new")
                raise OSError("switch failed")
            return rename(path, destination)

        with patch.object(Path, "rename", fail_switch):
            with self.assertRaisesRegex(OSError, "switch failed"):
                QSA["replace_applet"](staging, target)
        self.assertEqual((target / "old.txt").read_text(), "old")
        self.assertFalse(list(self.root.glob(".target.swap-*")))

    def test_failed_rollback_preserves_backup(self):
        staging, target = self.replacement_folders()
        rename = Path.rename

        def fail_switch_and_rollback(path, destination):
            if path.name in ("new", "old"):
                raise OSError("rename failed")
            return rename(path, destination)

        with patch.object(Path, "rename", fail_switch_and_rollback):
            with self.assertRaisesRegex(OSError, "rename failed"):
                QSA["replace_applet"](staging, target)
        backups = list(self.root.glob(".target.swap-*/old/old.txt"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old")


class RemoveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="qsa-remove-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "applets"
        self.data_root = self.root / "data"
        self.home.mkdir()
        self.data_root.mkdir()
        self.folder = self.home / "test"
        self.data = self.data_root / "test"
        for folder in (self.folder, self.data):
            folder.mkdir()
            (folder / "marker.txt").write_text("keep until removed")
        self.output = io.StringIO()
        self.globals = {"applets_home": lambda: self.home, "data_dir": lambda name: self.data_root / name}

    def remove(self, name="test", keep=False, yes=True):
        with patch.dict(QSA["cmd_remove"].__globals__, self.globals), \
                contextlib.redirect_stdout(self.output), contextlib.redirect_stderr(self.output):
            QSA["cmd_remove"](argparse.Namespace(name=name, keep_data=keep, yes=yes))

    def assert_preserved(self):
        self.assertTrue((self.folder / "marker.txt").exists())
        self.assertTrue((self.data / "marker.txt").exists())

    def test_normal_removal_deletes_only_named_applet_and_data(self):
        other = self.home / "other"
        other.mkdir()
        (other / "marker.txt").write_text("unrelated")
        other_data = self.data_root / "other"
        other_data.mkdir()
        self.remove()
        self.assertFalse(self.folder.exists())
        self.assertFalse(self.data.exists())
        self.assertTrue((other / "marker.txt").exists())
        self.assertTrue(other_data.is_dir())

    def test_keep_data_preserves_it(self):
        self.remove(keep=True)
        self.assertFalse(self.folder.exists())
        self.assertTrue((self.data / "marker.txt").exists())

    def test_missing_data_does_not_block_removal(self):
        (self.data / "marker.txt").unlink()
        self.data.rmdir()
        self.remove()
        self.assertFalse(self.folder.exists())

    def test_path_arguments_are_rejected(self):
        for name in ("", ".", "..", "../applets/test", "test/../test", "test/", str(self.folder), "test\n"):
            with self.subTest(name=name), self.assertRaises(SystemExit):
                self.remove(name)
            self.assert_preserved()

    def test_symlink_alias_cannot_delete_sibling_or_its_data(self):
        alias = self.home / "alias"
        alias.symlink_to(self.folder, target_is_directory=True)
        for keep in (False, True):
            with self.subTest(keep=keep), self.assertRaises(SystemExit):
                self.remove("alias", keep=keep)
            self.assert_preserved()
            self.assertTrue(alias.is_symlink())

    def test_external_and_broken_applet_links_are_rejected(self):
        alias = self.home / "alias"
        for destination in (self.root, self.root / "missing"):
            alias.symlink_to(destination, target_is_directory=True)
            with self.subTest(destination=destination), self.assertRaises(SystemExit):
                self.remove("alias")
            self.assert_preserved()
            alias.unlink()

    def test_data_symlink_is_rejected_before_applet_deletion(self):
        original = self.data_root / "original"
        self.data.rename(original)
        self.data.symlink_to(original, target_is_directory=True)
        with self.assertRaises(SystemExit):
            self.remove()
        self.assertTrue((self.folder / "marker.txt").exists())
        self.assertTrue((original / "marker.txt").exists())

    def test_data_namespace_symlink_is_rejected(self):
        original = self.root / "original-data"
        self.data_root.rename(original)
        self.data_root.symlink_to(original, target_is_directory=True)
        with self.assertRaises(SystemExit):
            self.remove()
        self.assert_preserved()

    def test_keep_data_allows_untouched_data_symlink(self):
        alias = self.data_root / "alias"
        alias.symlink_to(self.data, target_is_directory=True)
        self.globals["data_dir"] = lambda name: alias
        self.remove(keep=True)
        self.assertFalse(self.folder.exists())
        self.assertTrue((self.data / "marker.txt").exists())
        self.assertTrue(alias.is_symlink())

    def test_unexpected_data_file_prevents_any_deletion(self):
        (self.data / "marker.txt").unlink()
        self.data.rmdir()
        self.data.write_text("unrelated file")
        with self.assertRaises(SystemExit):
            self.remove()
        self.assertTrue((self.folder / "marker.txt").exists())
        self.assertEqual(self.data.read_text(), "unrelated file")

    def test_overlapping_folders_are_rejected(self):
        for data in (self.folder, self.folder / "nested", self.home):
            for keep in (False, True):
                self.globals["data_dir"] = lambda name, data=data: data
                with self.subTest(data=data, keep=keep), self.assertRaises(SystemExit):
                    self.remove(keep=keep)
                self.assert_preserved()

    def test_cancel_preserves_everything(self):
        with patch("sys.stdin.isatty", return_value=True), patch("builtins.input", return_value="n"):
            with self.assertRaises(SystemExit):
                self.remove(yes=False)
        self.assert_preserved()

    def test_changed_target_during_confirmation_aborts_before_deleting(self):
        for target in (self.folder, self.data):
            saved = target.with_name(target.name + "-saved")

            def change(prompt):
                target.rename(saved)
                target.symlink_to(saved, target_is_directory=True)
                return "y"

            with self.subTest(target=target), patch("sys.stdin.isatty", return_value=True), \
                    patch("builtins.input", side_effect=change), self.assertRaises(SystemExit):
                self.remove(yes=False)
            self.assert_preserved()
            target.unlink()
            saved.rename(target)

    def test_replacement_directory_during_confirmation_is_rejected(self):
        saved = self.data.with_name("saved")

        def change(prompt):
            self.data.rename(saved)
            self.data.mkdir()
            return "y"

        with patch("sys.stdin.isatty", return_value=True), patch("builtins.input", side_effect=change):
            with self.assertRaises(SystemExit):
                self.remove(yes=False)
        self.assertTrue((self.folder / "marker.txt").exists())
        self.assertTrue((saved / "marker.txt").exists())
        self.assertTrue(self.data.is_dir())

    def test_symlink_children_do_not_delete_external_contents(self):
        outside = self.root / "outside"
        outside.mkdir()
        marker = outside / "marker.txt"
        marker.write_text("unrelated")
        (self.folder / "linked-directory").symlink_to(outside, target_is_directory=True)
        (self.data / "linked-file").symlink_to(marker)
        self.remove()
        self.assertEqual(marker.read_text(), "unrelated")

    def test_changed_parent_during_confirmation_preserves_original(self):
        saved = self.root / "saved-data"

        def change(prompt):
            self.data_root.rename(saved)
            self.data_root.mkdir()
            return "y"

        with patch("sys.stdin.isatty", return_value=True), patch("builtins.input", side_effect=change):
            with self.assertRaises(SystemExit):
                self.remove(yes=False)
        self.assertTrue((self.folder / "marker.txt").exists())
        self.assertTrue((saved / "test" / "marker.txt").exists())

    def test_invalid_manifest_folder_can_still_be_removed(self):
        # Removal does not require a valid manifest or strict manifest name.
        target = self.home / "invalid_name"
        target.mkdir()
        self.remove("invalid_name")
        self.assertFalse(target.exists())
        self.assert_preserved()


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="qsa-install-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "installed"
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "applet.toml").write_text('name = "test"\nentry = "main.py"\n')
        script = self.source / "main.py"
        script.write_text('#!/usr/bin/env python3\nprint("{}")\n')
        script.chmod(0o755)
        self.output = io.StringIO()
        self.addCleanup(patch.stopall)
        patch.dict(QSA["cmd_install"].__globals__, {"applets_home": lambda: self.home}).start()

    def install(self, source=None, yes=True):
        with contextlib.redirect_stdout(self.output), contextlib.redirect_stderr(self.output):
            QSA["cmd_install"](argparse.Namespace(source=str(source or self.source), yes=yes))

    def assert_no_install(self):
        self.assertFalse((self.home / "test").exists())
        self.assertEqual(list(self.home.iterdir()), [])

    def test_success_is_prepared_on_destination_filesystem(self):
        publish = QSA["publish_applet"]

        def inspect(staged, target):
            self.assertEqual(staged.parent.parent, self.home)
            self.assertTrue(staged.parent.name.startswith("."))
            self.assertEqual(QSA["applet_folders"](), [])
            self.assertEqual((staged / "main.py").read_text(), (self.source / "main.py").read_text())
            publish(staged, target)

        with patch.dict(QSA["cmd_install"].__globals__, {"publish_applet": inspect}):
            self.install()
        self.assertEqual([p.name for p in self.home.iterdir()], ["test"])
        self.assertIsNone(QSA["load"](self.home / "test")[1])
        self.assertIn("Python syntax", self.output.getvalue())

    def test_local_symlinks_are_rejected_before_copy(self):
        outside = self.root / "outside.txt"
        outside.write_text("external")
        for name, target in (("asset", outside), ("directory", self.root), ("broken", self.root / "missing")):
            link = self.source / name
            link.symlink_to(target)
            with self.subTest(name=name), patch("shutil.copytree") as copy:
                with self.assertRaises(SystemExit):
                    self.install()
                copy.assert_not_called()
                self.assert_no_install()
            link.unlink()
        self.assertEqual(outside.read_text(), "external")

    def test_local_root_symlink_is_rejected(self):
        link = self.root / "linked-source"
        link.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(SystemExit):
            self.install(link)
        self.assert_no_install()

    def test_git_symlinks_are_rejected_before_manifest_read(self):
        def clone(command, **kwargs):
            self.assertEqual(command[-3], "--")
            staged = Path(command[-1])
            staged.mkdir()
            # A malicious manifest link must be rejected before it is opened.
            (staged / "applet.toml").symlink_to(self.root / "missing")
            return SimpleNamespace(returncode=0)

        with patch("subprocess.run", side_effect=clone), self.assertRaises(SystemExit):
            self.install("https://example.invalid/applet.git")
        self.assertIn("symlinks are not supported", self.output.getvalue())
        self.assert_no_install()

    def test_git_clone_failure_is_cleaned_up(self):
        with patch("subprocess.run", return_value=SimpleNamespace(returncode=1)), self.assertRaises(SystemExit):
            self.install("https://example.invalid/applet.git")
        self.assert_no_install()

    def test_invalid_python_and_shell_are_rejected_without_running(self):
        for entry, content in (("main.py", "#!/usr/bin/env python3\ndef broken(\n"),
                               ("main.sh", "#!/bin/bash\nif then\n")):
            (self.source / "applet.toml").write_text(f'name = "test"\nentry = "{entry}"\n')
            script = self.source / entry
            script.write_text(content)
            script.chmod(0o755)
            with self.subTest(entry=entry), self.assertRaises(SystemExit):
                self.install()
            self.assert_no_install()
            script.unlink()

    def test_valid_script_is_not_executed_during_install(self):
        marker = self.root / "executed"
        (self.source / "main.py").write_text(f'#!/usr/bin/env python3\nfrom pathlib import Path\nPath({str(marker)!r}).touch()\n')
        self.install()
        self.assertFalse(marker.exists())

    def test_qml_helpers_do_not_require_applet_api(self):
        (self.source / "applet.toml").write_text('name = "test"\nentry = "Main.qml"\n')
        (self.source / "Main.qml").write_text('import QtQuick\nimport qs.Applets\nItem { required property var applet; Helper {} }\n')
        (self.source / "Helper.qml").write_text('import QtQuick\nRectangle { width: 10; height: 10 }\n')
        self.install()
        self.assertTrue((self.home / "test" / "Helper.qml").is_file())

    def test_invalid_qml_is_rejected_when_linter_is_available(self):
        if not QSA["qml_linter"]():
            self.skipTest("Qt 6 qmllint unavailable")
        (self.source / "applet.toml").write_text('name = "test"\nentry = "Main.qml"\n')
        (self.source / "Main.qml").write_text('import QtQuick\nItem { required property var applet; this is invalid QML }\n')
        with self.assertRaises(SystemExit):
            self.install()
        self.assert_no_install()

    def test_missing_linter_is_reported(self):
        (self.source / "applet.toml").write_text('name = "test"\nentry = "Main.qml"\n')
        (self.source / "Main.qml").write_text('import QtQuick\nItem { required property var applet }\n')
        with patch.dict(QSA["static_problems"].__globals__, {"qml_linter": lambda: None}):
            self.install()
        self.assertIn("full QML lint skipped", self.output.getvalue())

    def test_copy_failure_leaves_no_live_or_staged_applet(self):
        def partial_copy(source, destination, **kwargs):
            destination.mkdir()
            (destination / "partial.txt").write_text("partial")
            raise OSError("copy failed")

        with patch("shutil.copytree", side_effect=partial_copy), self.assertRaises(SystemExit):
            self.install()
        self.assert_no_install()

    def test_large_python_files_are_still_checked(self):
        (self.source / "main.py").write_text("#" + "x" * 100_001 + "\ndef broken(\n")
        with self.assertRaises(SystemExit):
            self.install()
        self.assert_no_install()

    def test_cancelled_review_leaves_no_applet(self):
        with patch("builtins.input", return_value="n"), self.assertRaises(SystemExit):
            self.install(yes=False)
        self.assert_no_install()

    def test_existing_and_broken_symlink_destinations_are_rejected(self):
        self.home.mkdir()
        target = self.home / "test"
        for directory in (True, False):
            if directory:
                target.mkdir()
            else:
                target.symlink_to(self.root / "missing")
            with self.subTest(directory=directory), self.assertRaises(SystemExit):
                self.install()
            self.assertEqual(list(self.home.iterdir()), [target])
            if directory:
                target.rmdir()
            else:
                target.unlink()

    def test_concurrent_install_cannot_be_overwritten(self):
        publish = QSA["publish_applet"]

        def competing_install(staged, target):
            # Even an empty directory created after review must not be replaced.
            target.mkdir()
            publish(staged, target)

        with patch.dict(QSA["cmd_install"].__globals__, {"publish_applet": competing_install}), self.assertRaises(SystemExit):
            self.install()
        self.assertTrue((self.home / "test").is_dir())
        self.assertEqual(list((self.home / "test").iterdir()), [])
        self.assertEqual([p.name for p in self.home.iterdir()], ["test"])


if __name__ == "__main__":
    unittest.main()
