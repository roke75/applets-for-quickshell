import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// One applet: its script state or QML API, persistent store and surface.
// Popups and floating windows exist only while shown; desktop widgets start
// shown. A script applet is "active" while shown or while it has a bar item:
// it then refreshes on its interval (or keeps streaming) so the bar stays current.
Scope {
    id: host

    required property var shell // the AppletsHost
    required property var applet // manifest from `qsa watch`
    readonly property string name: applet ? applet.name : ""
    readonly property bool isScript: !!applet && applet.kind === "script"
    readonly property bool hasSurface: !!applet && applet.entry !== ""
    readonly property bool inBar: !!applet && applet.bar !== "none"
    readonly property bool active: shown || inBar
    // Null-safe views of the manifest: `applet` turns null for a moment when
    // the applet is removed, before this instance is destroyed.
    readonly property string surface: applet ? applet.surface : ""
    readonly property bool streams: !!applet && applet.kind === "script" && applet.stream
    property bool shown: hasSurface && surface === "desktop"
    // Output the window opens on, chosen each time it is shown.
    property string screenName: ""
    // The bar item a popup was opened from; null centers the popup.
    property Item anchorItem: null
    // Latest file change in the applet folder; bumping reloadToken makes QML
    // items recreate themselves from the edited files.
    property real revision: applet ? applet.revision : 0
    property int reloadToken: 0

    // Script output (SPEC.md "Output") and the last error.
    property var state: ({})
    property string error: ""
    property date updated
    // Process.running changes asynchronously when a process is started.
    // Reserve the slot before starting it so back-to-back requests cannot race.
    property bool runInProgress: false
    readonly property bool busy: runInProgress || refresher.running || actor.running
    property var pendingActors: []
    property bool pendingRefresh: false
    // Short confirmation in the footer, such as "Copied", cleared after 2 s.
    property string notice: ""

    // Contents of store.json. storeVersion counts changes so bindings that
    // call store.get() re-evaluate.
    property var storeData: ({})
    property int storeVersion: 0

    // The object QML applets and custom bar items receive as `applet`.
    property alias api: api

    function show() {
        showFrom(null);
    }

    // Open attached to a bar item (popup surface only), or centered when null.
    function showFrom(item) {
        if (!hasSurface)
            return;

        screenName = pickScreen();
        anchorItem = surface === "popup" ? item : null;
        shown = true;
        if (isScript && !streams)
            refresh();
    }

    function hide() {
        shown = false;
        anchorItem = null;
    }

    function toggle() {
        shown ? hide() : show();
    }

    function pickScreen() {
        var wanted = applet.screen || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
        for (var i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === wanted)
                return wanted;
        }
        return Quickshell.screens.length ? Quickshell.screens[0].name : "";
    }

    function screen() {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === screenName)
                return Quickshell.screens[i];
        }
        return Quickshell.screens[0];
    }

    function env(event) {
        return {
            "APPLET_NAME": applet.name,
            "APPLET_DIR": applet.dir,
            "APPLET_DATA": applet.dataDir,
            "APPLET_CONFIG": JSON.stringify(applet.config),
            "APPLET_EVENT": event
        };
    }

    // The whole stdout as JSON, else its last line (scripts may print other
    // lines first). Returns null for empty output.
    function parseOutput(text) {
        var trimmed = text.trim();
        if (!trimmed)
            return null;

        try {
            return JSON.parse(trimmed);
        } catch (e) {}
        var lines = trimmed.split("\n");
        return JSON.parse(lines[lines.length - 1]);
    }

    function applyState(next) {
        if (typeof next !== "object" || next === null || Array.isArray(next))
            throw new Error("output must be a JSON object");

        state = next;
        error = next.error || "";
        updated = new Date();
        if (next.notify)
            notify(applet ? applet.title : name, next.notify);
    }

    // Applies a finished run's output. Returns false when there was nothing to
    // apply (empty output or a failed run), so callers can refresh instead.
    function handleOutput(text, code, stderr) {
        if (code !== 0) {
            error = (stderr.trim().split("\n").pop() || "exited with code " + code);
            return false;
        }
        try {
            var next = parseOutput(text);
            if (next === null)
                return false;

            applyState(next);
            return true;
        } catch (e) {
            error = "invalid output: " + e.message;
            return true;
        }
    }

    function refresh() {
        if (!applet || !isScript || streams)
            return;

        if (busy || pendingActors.length) {
            pendingRefresh = true;
            return;
        }
        pendingRefresh = false;
        runInProgress = true;
        refresher.timedOut = false;
        refresher.environment = env("refresh");
        refresher.command = [applet.entry];
        refresher.running = true;
        refreshTimeout.restart();
    }

    function runAction(id) {
        startActor([applet.entry, "action", String(id)], "action");
    }

    function submit(text) {
        startActor([applet.entry, "input", text], "input");
    }

    function startActor(argv, event) {
        if (!applet || !isScript)
            return;

        pendingActors = pendingActors.concat([{ argv: argv, event: event }]);
        drainRuns();
    }

    // Preserve user actions in order and coalesce refreshes while a run is busy.
    function drainRuns() {
        if (!applet || !isScript || busy)
            return;

        if (pendingActors.length) {
            var next = pendingActors[0];
            pendingActors = pendingActors.slice(1);
            runInProgress = true;
            actor.timedOut = false;
            actor.environment = env(next.event);
            actor.command = next.argv;
            actor.running = true;
            actionTimeout.restart();
        } else if (pendingRefresh) {
            pendingRefresh = false;
            refresh();
        }
    }

    function startStream() {
        streamer.running = false;
        if (!streams || !active)
            return;

        streamer.environment = env("refresh");
        streamer.command = [applet.entry];
        streamer.running = true;
    }

    function activate(item) {
        if (!item)
            return;

        if (item.run !== undefined)
            runAction(item.run);

        if (item.copy !== undefined)
            copy(String(item.copy));

        if (item.open !== undefined)
            open(String(item.open));

        // Copying or opening usually ends the task; desktop widgets stay.
        if ((item.copy !== undefined || item.open !== undefined) && item.close !== false && surface !== "desktop") {
            hide();
        } else if (item.copy !== undefined) {
            notice = "Copied";
            noticeTimer.restart();
        }
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Applets", String(title), String(body || "")]);
    }

    function copy(text) {
        Quickshell.clipboardText = text;
    }

    function open(target) {
        Quickshell.execDetached(["xdg-open", target]);
    }

    function storeGet(key, fallback) {
        storeVersion; // dependency for bindings, see storeVersion
        return storeData.hasOwnProperty(key) ? storeData[key] : fallback;
    }

    function storeSet(key, value) {
        var copy = Object.assign({}, storeData);
        if (value === undefined)
            delete copy[key];
        else
            copy[key] = value;
        storeData = copy;
        storeVersion++;
        storeFile.setText(JSON.stringify(copy, null, 2) + "\n");
    }

    // Run argv without a shell; callback(stdout, exitCode, stderr).
    function run(argv, callback) {
        var proc = runner.createObject(host, {
            "command": argv,
            "callback": callback || null
        });
        proc.running = true;
    }

    onRevisionChanged: {
        reloadToken++;
        if (streams)
            streamRestart.restart();
        else if (active)
            refresh();
    }
    onActiveChanged: {
        if (streams)
            startStream();
        else if (active)
            refresh();
    }
    Component.onCompleted: {
        shell.register(name, host);
        if (shown)
            screenName = pickScreen();

        if (active) {
            if (streams)
                startStream();
            else
                refresh();
        }
    }
    Component.onDestruction: shell.unregister(name, host)
    onAppletChanged: {
        if (!applet)
            hide();
    }

    // See SPEC.md "QML applets" for this API.
    QtObject {
        id: api

        readonly property string name: host.name
        readonly property string title: host.applet ? host.applet.title : ""
        readonly property string icon: host.applet ? host.applet.icon : ""
        readonly property string dir: host.applet ? host.applet.dir : ""
        readonly property string dataDir: host.applet ? host.applet.dataDir : ""
        readonly property var config: host.applet ? host.applet.config : ({})
        readonly property var theme: AppletTheme
        readonly property bool shown: host.shown
        readonly property var state: host.state
        readonly property string error: host.error
        readonly property QtObject store: QtObject {
            function get(key, fallback) {
                return host.storeGet(key, fallback);
            }

            function set(key, value) {
                host.storeSet(key, value);
            }
        }

        function toggle() {
            host.toggle();
        }

        function show() {
            host.show();
        }

        function close() {
            host.hide();
        }

        function refresh() {
            host.refresh();
        }

        function action(id) {
            host.runAction(id);
        }

        function submit(text) {
            host.submit(text);
        }

        function notify(title, body) {
            host.notify(title, body);
        }

        function copy(text) {
            host.copy(text);
        }

        function open(target) {
            host.open(target);
        }

        function run(argv, callback) {
            host.run(argv, callback);
        }
    }

    // store.json, reloaded when edited outside the applet too.
    FileView {
        id: storeFile

        path: host.applet ? host.applet.dataDir + "/store.json" : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                host.storeData = JSON.parse(text()) || {};
            } catch (e) {
                console.warn("applets:", host.name, "ignoring invalid store.json");
            }
            host.storeVersion++;
        }
    }

    // Refresh runs: the entry without arguments.
    Process {
        id: refresher

        property bool timedOut: false
        workingDirectory: host.applet ? host.applet.dir : ""
        onExited: code => {
            refreshTimeout.stop();
            host.runInProgress = false;
            if (!timedOut)
                host.handleOutput(refresherOut.text, code, refresherErr.text);
            Qt.callLater(host.drainRuns);
        }

        stdout: StdioCollector {
            id: refresherOut
        }

        stderr: StdioCollector {
            id: refresherErr
        }
    }

    // Action and input runs. Output replaces the state; empty output asks
    // for a refresh, so scripts may handle actions silently.
    Process {
        id: actor

        property bool timedOut: false
        workingDirectory: host.applet ? host.applet.dir : ""
        onExited: code => {
            actionTimeout.stop();
            host.runInProgress = false;
            if (!timedOut && !host.handleOutput(actorOut.text, code, actorErr.text) && code === 0)
                host.pendingRefresh = true;
            Qt.callLater(host.drainRuns);
        }

        stdout: StdioCollector {
            id: actorOut
        }

        stderr: StdioCollector {
            id: actorErr
        }
    }

    // Stream mode: one long-running entry, one state per stdout line.
    Process {
        id: streamer

        workingDirectory: host.applet ? host.applet.dir : ""
        onExited: code => {
            if (host.active && code !== 0)
                host.error = "stream exited with code " + code;
        }

        stdout: SplitParser {
            onRead: data => {
                if (!data.trim())
                    return;

                try {
                    host.applyState(JSON.parse(data));
                } catch (e) {
                    host.error = "invalid output: " + e.message;
                }
            }
        }

        stderr: SplitParser {
            onRead: data => console.warn("applets:", host.name + ":", data)
        }
    }

    // After an edit, give the old stream process a moment to exit.
    Timer {
        id: streamRestart

        interval: 300
        onTriggered: host.startStream()
    }

    Timer {
        id: noticeTimer

        interval: 2000
        onTriggered: host.notice = ""
    }

    // Each run owns its deadline. Ignore its exit output after timing out so
    // the termination status cannot replace the useful timeout message.
    Timer {
        id: refreshTimeout

        interval: host.applet ? host.applet.timeout * 1000 : 20000
        onTriggered: {
            if (refresher.running) {
                refresher.timedOut = true;
                refresher.running = false;
                host.error = "timed out after " + (host.applet ? host.applet.timeout : "?") + "s";
            }
        }
    }

    Timer {
        id: actionTimeout

        interval: host.applet ? host.applet.timeout * 1000 : 20000
        onTriggered: {
            if (actor.running) {
                actor.timedOut = true;
                actor.running = false;
                host.error = "timed out after " + (host.applet ? host.applet.timeout : "?") + "s";
            }
        }
    }

    Timer {
        interval: host.applet ? host.applet.interval * 1000 : 0
        running: host.active && host.isScript && !host.streams && interval > 0
        repeat: true
        onTriggered: host.refresh()
    }

    Component {
        id: runner

        Process {
            id: proc

            property var callback
            property int exitCode: -1
            // Exit plus both streams finishing; the callback waits for all three.
            property int pending: 3

            function settle() {
                if (--pending > 0)
                    return;

                if (callback)
                    callback(out.text, exitCode, err.text);

                proc.destroy();
            }

            workingDirectory: host.applet ? host.applet.dir : ""
            onExited: code => {
                exitCode = code;
                settle();
            }

            stdout: StdioCollector {
                id: out

                onStreamFinished: proc.settle()
            }

            stderr: StdioCollector {
                id: err

                onStreamFinished: proc.settle()
            }
        }
    }

    LazyLoader {
        active: host.shown && host.surface === "popup" && !host.anchorItem

        AppletPopup {
            owner: host
        }
    }

    LazyLoader {
        active: host.shown && host.surface === "popup" && !!host.anchorItem

        AppletAnchoredPopup {
            owner: host
        }
    }

    LazyLoader {
        active: host.shown && host.surface === "floating"

        AppletWindow {
            owner: host
        }
    }

    LazyLoader {
        active: host.shown && host.surface === "desktop"

        AppletDesktop {
            owner: host
        }
    }
}
