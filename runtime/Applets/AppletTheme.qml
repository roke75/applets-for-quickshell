pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Theme tokens, looked up in order: `source` (the shell's own theme object,
// set through AppletsHost.theme), $APPLETS_HOME/theme.json, then the neutral
// defaults below. See SPEC.md for the token names.
Singleton {
    id: theme

    property var source: null // set by AppletsHost
    property var tokens: ({}) // parsed theme.json

    function pick(key, fallback) {
        var value = source ? source[key] : undefined;
        if (value === undefined || value === null)
            value = tokens ? tokens[key] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    readonly property color background: pick("background", "#16161a")
    readonly property color surface: pick("surface", "#1e1e24")
    readonly property color surfaceAlt: pick("surfaceAlt", "#2a2a32")
    readonly property color border: pick("border", "#3a3a44")
    readonly property color foreground: pick("foreground", "#e6e6eb")
    readonly property color foregroundDim: pick("foregroundDim", "#a6a6b0")
    readonly property color muted: pick("muted", "#70707c")
    readonly property color accent: pick("accent", "#8ab4f8")
    readonly property color warning: pick("warning", "#e7c787")
    readonly property color error: pick("error", "#e07070")
    readonly property color success: pick("success", "#8fbf8f")
    readonly property real opacity: pick("opacity", 1)
    readonly property int rounding: pick("rounding", 8)
    readonly property int borderSize: pick("borderSize", 1)
    readonly property string fontFamily: pick("fontFamily", Qt.application.font.family)
    readonly property int fontSize: pick("fontSize", 12)

    // Color for a script output `class` (SPEC.md "Output").
    function tone(name) {
        switch (name) {
        case "warning":
            return warning;
        case "error":
            return error;
        case "success":
            return success;
        case "accent":
            return accent;
        case "muted":
            return muted;
        default:
            return foreground;
        }
    }

    FileView {
        // Same location rules as the CLI's applets folder.
        path: (Quickshell.env("APPLETS_HOME") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/applets") + "/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                theme.tokens = JSON.parse(text());
            } catch (e) {
                console.warn("applets: ignoring invalid theme.json:", e);
                theme.tokens = {};
            }
        }
        onLoadFailed: theme.tokens = {}
    }
}
