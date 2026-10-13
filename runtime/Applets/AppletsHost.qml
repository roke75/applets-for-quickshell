import QtQuick
import Quickshell
import Quickshell.Io

// Discovers applets and owns one AppletInstance per applet. Put exactly one in
// a shell; place AppletBar items in bars to show `bar` applets.
//
//   AppletsHost { id: applets; theme: Theme }
Scope {
    id: root

    // A QtObject or plain object with theme token properties (see SPEC.md).
    // Missing tokens fall back to theme.json, then to built-in defaults.
    property var theme: null
    // Path of the `qsa` CLI. Empty finds it relative to this module,
    // following the symlink `qsa setup` creates.
    property string cli: ""

    // Name -> manifest, from the latest `qsa watch` line.
    property var registry: ({})
    // Sorted names; only reassigned when the set changes, so Variants keeps
    // existing instances (and their state) across manifest edits.
    property var names: []
    // Name -> AppletInstance. Replaced rather than mutated so bindings update.
    property var instances: ({})
    // Invalid applets already reported, to notify only about new problems.
    property string invalidKey: ""
    readonly property string moduleDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))

    // Handles one registry line from `qsa watch`.
    function apply(line) {
        var data;
        try {
            data = JSON.parse(line);
        } catch (e) {
            console.warn("applets: bad registry line:", line);
            return;
        }
        var map = {};
        for (var i = 0; i < data.applets.length; i++)
            map[data.applets[i].name] = data.applets[i];
        var sorted = Object.keys(map).sort();
        // Removed applets keep their last manifest for this one update, so
        // their instances and open windows never see null while being torn
        // down. The next update drops it.
        for (var k = 0; k < names.length; k++) {
            if (!map[names[k]] && registry[names[k]])
                map[names[k]] = registry[names[k]];
        }
        registry = map;
        if (JSON.stringify(sorted) !== JSON.stringify(names))
            names = sorted;

        var key = JSON.stringify(data.invalid);
        if (key !== invalidKey) {
            invalidKey = key;
            for (var j = 0; j < data.invalid.length; j++) {
                var bad = data.invalid[j];
                console.warn("applets:", bad.name + ":", bad.error);
                Quickshell.execDetached(["notify-send", "-a", "Applets", "Applet " + bad.name + " is invalid", bad.error]);
            }
        }
    }

    function register(name, instance) {
        var copy = Object.assign({}, instances);
        copy[name] = instance;
        instances = copy;
    }

    function unregister(name, instance) {
        if (instances[name] !== instance)
            return;

        var copy = Object.assign({}, instances);
        delete copy[name];
        instances = copy;
    }

    // IPC helper: runs toggle/show/hide on an applet that has a window.
    function call(name, method) {
        var instance = instances[name];
        if (!instance)
            return "unknown applet: " + name;

        if (!instance.hasSurface)
            return "applet has no window: " + name;

        instance[method]();
        return "ok";
    }

    onThemeChanged: AppletTheme.source = theme
    Component.onCompleted: AppletTheme.source = theme
    // The singleton can outlive this shell's theme object (reloads, exit).
    Component.onDestruction: AppletTheme.source = null

    Process {
        id: watcher

        // The module folder may be a symlink into the applets repository;
        // the CLI lives at ../../bin/qsa from its real location.
        command: root.cli ? [root.cli, "watch"] : ["sh", "-c", "exec \"$(readlink -f \"$1\")/../../bin/qsa\" watch", "sh", root.moduleDir]
        running: true
        onExited: code => {
            console.warn("applets: registry watcher exited with code", code, "- restarting");
            restart.start();
        }

        stdout: SplitParser {
            onRead: data => root.apply(data)
        }

        stderr: SplitParser {
            onRead: data => console.warn(data)
        }
    }

    Timer {
        id: restart

        interval: 2000
        onTriggered: watcher.running = true
    }

    Variants {
        model: root.names

        AppletInstance {
            required property string modelData

            shell: root
            applet: root.registry[modelData] || null
        }
    }

    IpcHandler {
        target: "applets"

        function toggle(name: string): string {
            return root.call(name, "toggle");
        }

        // `show` and `hide` collide with qs ipc subcommands, hence open/close.
        function open(name: string): string {
            return root.call(name, "show");
        }

        function close(name: string): string {
            return root.call(name, "hide");
        }

        function action(name: string, id: string): string {
            var instance = root.instances[name];
            if (!instance || !instance.isScript)
                return "unknown script applet: " + name;

            instance.runAction(id);
            return "ok";
        }

        function submit(name: string, text: string): string {
            var instance = root.instances[name];
            if (!instance || !instance.isScript || !instance.applet.input)
                return "applet does not take input: " + name;

            instance.submit(text);
            return "ok";
        }

        function list(): string {
            return root.names.join("\n");
        }
    }
}
