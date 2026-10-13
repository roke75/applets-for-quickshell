"""Exercise real Process objects and timers in headless Quickshell."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

TESTS = Path(__file__).resolve().parent
SCRIPT = '''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
event = sys.argv[2] if len(sys.argv) > 2 else "refresh"
log = Path(os.environ["APPLET_DATA"]) / "events.log"
with log.open("a") as file:
    file.write("start " + event + "\\n")
time.sleep(3 if event == "hang" or event == "refresh" and json.loads(os.environ["APPLET_CONFIG"]).get("hang") else 0.25)
with log.open("a") as file:
    file.write("end " + event + "\\n")
print(json.dumps({"text": event}))
'''

with tempfile.TemporaryDirectory(prefix="qsa-runtime-test-") as tmp:
    root = Path(tmp)
    module = root / "Applets"
    shutil.copytree(TESTS.parent / "runtime/Applets", module)
    qmldir = module / "qmldir"
    qmldir.write_text(qmldir.read_text().replace("internal AppletInstance", "AppletInstance 1.0"))
    # No windows are opened in these tests. Stub the surface types so their
    # definitions do not require a Wayland backend under offscreen Qt.
    for surface in ("AppletPopup", "AppletAnchoredPopup", "AppletWindow", "AppletDesktop"):
        (module / f"{surface}.qml").write_text("import Quickshell\nScope { required property var owner }\n")
    shutil.copyfile(TESTS / "runtime.qml", root / "shell.qml")
    entry = root / "main.py"
    entry.write_text(SCRIPT)
    entry.chmod(0o755)
    runtime = root / "run"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
               XDG_RUNTIME_DIR=str(runtime), APPLETS_HOME=str(root / "applets"))
    result = subprocess.run(["qs", "--no-color", "-p", str(root)], env=env,
                            capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or not all(marker in output for marker in
            ("PASS action serialization and timeout", "PASS refresh timeout and queued action")):
        log = root / "events.log"
        if log.exists():
            print(log.read_text())
        raise SystemExit("Runtime tests failed")
    events = (root / "events.log").read_text().splitlines()
    expected = ["start refresh", "end refresh", "start quick", "end quick", "start hang",
                "start final", "end final", "start refresh", "start after-refresh", "end after-refresh"]
    if events != expected:
        raise SystemExit(f"Runs were not serialized: {events!r}")
    print("Process ordering and timeout integration checks passed")
