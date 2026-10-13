"""Live Wayland smoke tests using isolated applets and real window surfaces.

Run manually with python3 tests/test_live.py from a Wayland session. A small
test bar and temporary applet windows appear briefly, then are cleaned up.
Hyprland's hyprctl is used to verify that windows actually reach the compositor.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
CLI = REPO / "bin/qsa"
SCRIPT = '''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
event = sys.argv[2] if len(sys.argv) > 2 else "refresh"
if event == "hang":
    time.sleep(4)
print(json.dumps({"text": event, "body": "Temporary live test applet", "items": [
    {"text": "Copy test text", "copy": "QSA live test", "close": False}
]}))
'''


def wait_for(check, description, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"Timed out: {description}")


def run(command, env, check=True):
    result = subprocess.run(list(map(str, command)), env=env, capture_output=True,
                            text=True, timeout=15)
    if check and result.returncode:
        raise AssertionError(result.stderr.strip() or result.stdout.strip())
    return result


if not os.environ.get("WAYLAND_DISPLAY"):
    raise SystemExit("Live tests require an active Wayland session")
if not shutil.which("hyprctl") or not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
    raise SystemExit("Live compositor assertions currently require Hyprland")

with tempfile.TemporaryDirectory(prefix="qsa-live-test-") as tmp:
    root = Path(tmp)
    token = root.name.replace("_", "-")
    live = "live-" + token
    countdown = "countdown-" + token
    added = "added-" + token
    bar_namespace = "bar-" + token
    title = "QSA Live Test " + token
    config = root / "shell"
    config.mkdir()
    (config / "Applets").symlink_to(REPO / "runtime/Applets", target_is_directory=True)
    (config / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Applets
ShellRoot {
    AppletsHost { id: host; cli: CLI_PATH }
    PanelWindow {
        anchors { top: true; right: true }
        implicitWidth: Math.max(160, bar.implicitWidth + 16)
        implicitHeight: 40
        exclusionMode: ExclusionMode.Ignore
        color: "#222222"
        WlrLayershell.namespace: BAR_NAMESPACE
        AppletBar { id: bar; host: host; anchors.centerIn: parent }
    }
    IpcHandler {
        target: "liveTest"
        function inspect(name: string): string {
            var item = host.instances[name];
            return JSON.stringify(item ? { shown: item.shown, error: item.error,
                state: item.state, revision: item.reloadToken, surface: item.surface,
                store: item.storeData } : null);
        }
        function putStore(name: string, value: string): string {
            host.instances[name].api.store.set("test", value);
            return "ok";
        }
    }
}
'''.replace("CLI_PATH", json.dumps(str(CLI))).replace("BAR_NAMESPACE", json.dumps(bar_namespace)))
    env = dict(os.environ, APPLETS_HOME=str(root / "applets"), APPLETS_SHELL=str(config),
               XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"), QT_QPA_PLATFORM="wayland")
    source = root / "source"
    source.mkdir()
    manifest = f'name = "{live}"\ntitle = "{title}"\nentry = "main.py"\nbar = true\ninput = true\ntimeout = 1\nwidth = 420\nheight = 220\n'
    (source / "applet.toml").write_text(manifest)
    (source / "main.py").write_text(SCRIPT)
    (source / "main.py").chmod(0o755)
    run([CLI, "install", source, "--yes"], env)
    qml_source = root / "qml-source"
    shutil.copytree(REPO / "examples/countdown", qml_source)
    qml_manifest = qml_source / "applet.toml"
    qml_manifest.write_text(qml_manifest.read_text().replace('name = "countdown"', f'name = "{countdown}"'))
    run([CLI, "install", qml_source, "--yes"], env)
    log = root / "shell.log"
    with log.open("w") as output:
        shell = subprocess.Popen(["qs", "--no-color", "-p", config], env=env,
                                 stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        def inspect(name=live):
            result = run(["qs", "ipc", "-p", config, "call", "liveTest", "inspect", name], env, check=False)
            if result.returncode:
                return None
            return json.loads(result.stdout)

        def state_is(text):
            value = inspect()
            return value and value["state"].get("text") == text

        def layers_contain(namespace):
            layers = json.loads(run(["hyprctl", "-j", "layers"], env).stdout)

            def find(value):
                if isinstance(value, dict):
                    return value.get("namespace") == namespace or any(find(v) for v in value.values())
                return isinstance(value, list) and any(find(v) for v in value)

            return find(layers)

        def floating_present():
            clients = json.loads(run(["hyprctl", "-j", "clients"], env).stdout)
            return any(c.get("title") == title and c.get("mapped") for c in clients)

        wait_for(lambda: state_is("refresh"), "registry discovery and initial bar refresh")
        wait_for(lambda: layers_contain(bar_namespace), "real test bar")
        wait_for(lambda: layers_contain("applet-" + countdown), "QML desktop widget")
        print("PASS live registry, bar and QML desktop widget", flush=True)

        for surface in ("popup", "floating", "desktop"):
            run([CLI, "hide", live], env)
            applet = root / "applets" / live
            previous = inspect()["revision"]
            (applet / "applet.toml").write_text(manifest + f'surface = "{surface}"\n')
            wait_for(lambda: inspect() and inspect()["surface"] == surface
                     and inspect()["revision"] > previous, f"{surface} manifest reload")
            run([CLI, "show", live], env)
            visible = floating_present if surface == "floating" else lambda: layers_contain("applet-" + live)
            wait_for(visible, f"real {surface} window")
            run([CLI, "hide", live], env)
            wait_for(lambda: not visible(), f"{surface} window closes")
            print(f"PASS real {surface} show/hide", flush=True)

        run([CLI, "send", live, "--action", "quick"], env)
        wait_for(lambda: state_is("quick"), "script action output")
        run([CLI, "send", live, "--input", "typed-live-input"], env)
        wait_for(lambda: state_is("typed-live-input"), "script input output")
        run([CLI, "send", live, "--action", "hang"], env)
        wait_for(lambda: inspect() and inspect()["error"].startswith("timed out after"), "script timeout")
        run([CLI, "send", live, "--action", "recovered"], env)
        wait_for(lambda: state_is("recovered") and not inspect()["error"], "recovery after timeout")
        print("PASS live actions, input, timeout and recovery", flush=True)

        run(["qs", "ipc", "-p", config, "call", "liveTest", "putStore", countdown, "persisted"], env)
        store = root / "data/applets" / countdown / "store.json"
        wait_for(lambda: store.exists() and json.loads(store.read_text()).get("test") == "persisted", "store writes")
        store.write_text('{"test":"external"}\n')
        wait_for(lambda: inspect(countdown)["store"].get("test") == "external", "external store reload")
        print("PASS persistent store writes and external reload", flush=True)

        qml = root / "applets" / countdown / "Countdown.qml"
        previous = inspect(countdown)["revision"]
        info = qml.stat()
        qml.write_text(qml.read_text() + "\n// Live reload with preserved mtime.\n")
        os.utime(qml, ns=(info.st_atime_ns, info.st_mtime_ns))
        wait_for(lambda: inspect(countdown)["revision"] > previous, "QML reload with preserved mtime")
        wait_for(lambda: layers_contain("applet-" + countdown), "QML widget remains visible after reload")
        assert inspect(countdown)["store"].get("test") == "external"
        print("PASS live QML edit, preserved timestamp and persistent state", flush=True)

        helper = root / "applets" / live / "helper.txt"
        previous = inspect()["revision"]
        helper.write_text("old helper")
        wait_for(lambda: inspect()["revision"] > previous, "helper addition reload")
        previous = inspect()["revision"]
        helper.unlink()
        wait_for(lambda: inspect()["revision"] > previous, "helper deletion reload")
        print("PASS live file deletion reload", flush=True)

        run([CLI, "remove", live, "--keep-data", "--yes"], env)
        wait_for(lambda: inspect() is None, "removed applet leaves registry")
        assert (root / "data/applets" / live).is_dir()
        assert (root / "applets" / countdown).is_dir()
        assert inspect(countdown) is not None
        print("PASS live removal, preserved data and unrelated applet", flush=True)

        run([CLI, "new", added, "--qml"], env)
        run([CLI, "check", added], env)
        run([CLI, "show", added], env)
        wait_for(lambda: layers_contain("applet-" + added), "new QML applet popup")
        run([CLI, "hide", added], env)
        wait_for(lambda: not layers_contain("applet-" + added), "new QML popup closes")
        run([CLI, "remove", added, "--yes"], env)
        wait_for(lambda: inspect(added) is None, "new applet removal")
        print("PASS live creation, QML template, IPC discovery and removal", flush=True)
        errors = [line for line in log.read_text().splitlines()
                  if "ERROR" in line or "ReferenceError" in line or "TypeError" in line]
        assert not errors, "\n".join(errors)
        print("Live Wayland tests passed", flush=True)
    except BaseException:
        print(log.read_text())
        raise
    finally:
        shell.terminate()
        try:
            shell.wait(timeout=5)
        except subprocess.TimeoutExpired:
            shell.kill()
            shell.wait()
        wait_for(lambda: not layers_contain(bar_namespace)
                 and not layers_contain("applet-" + countdown) and not floating_present(),
                 "test shell and windows are cleaned up")
