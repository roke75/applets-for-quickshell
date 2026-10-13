import QtQuick
import QtTest
import Quickshell
import qs.Applets

// Runs inside a temporary, headless Quickshell config via test_runtime.py.
ShellRoot {
    id: root
    property int timeoutCount: 0
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => root.ready = true)

    QtObject {
        id: fakeShell
        function register(name, instance) {}
        function unregister(name, instance) {}
    }

    AppletInstance {
        id: subject
        shell: fakeShell
        applet: ({ name: "test", title: "Test", entry: Qt.resolvedUrl("main.py").toString().replace("file://", ""),
                   dir: Qt.resolvedUrl(".").toString().replace("file://", ""),
                   dataDir: Qt.resolvedUrl(".").toString().replace("file://", ""),
                   kind: "script", bar: "none", surface: "popup", config: {},
                   icon: "", screen: "", stream: false, interval: 0, timeout: 1, revision: 0 })
        onErrorChanged: {
            if (error.startsWith("timed out after"))
                root.timeoutCount++;
        }
    }

    TestCase {
        name: "AppletRuns"
        when: root.ready

        function test_actions_wait_for_refresh_and_keep_their_deadlines() {
            subject.refresh();
            subject.runAction("quick");
            subject.runAction("hang");
            subject.runAction("final");
            tryCompare(subject, "state", { text: "final" }, 5000);
            compare(root.timeoutCount, 1, "hung action keeps its own timeout");
            compare(subject.pendingActors.length, 0);
            verify(!subject.busy);
            console.warn("PASS action serialization and timeout");
        }

        function test_hung_refresh_times_out_before_queued_action() {
            subject.applet = Object.assign({}, subject.applet, { config: { hang: true } });
            subject.refresh();
            subject.runAction("after-refresh");
            tryCompare(subject, "state", { text: "after-refresh" }, 5000);
            compare(root.timeoutCount, 2);
            verify(!subject.busy);
            console.warn("PASS refresh timeout and queued action");
        }
    }
}
