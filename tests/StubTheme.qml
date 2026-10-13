pragma Singleton

import QtQuick

// Replaces AppletTheme in tests: same tokens, without the Quickshell module,
// which only loads inside Quickshell itself.
QtObject {
    property color background: "#111111"
    property color surface: "#222222"
    property color surfaceAlt: "#333333"
    property color border: "#444444"
    property color foreground: "#eeeeee"
    property color foregroundDim: "#aaaaaa"
    property color muted: "#777777"
    property color accent: "#88aaff"
    property color warning: "#ffcc66"
    property color error: "#ff6666"
    property color success: "#66ff66"
    property real opacity: 1
    property int rounding: 8
    property int borderSize: 1
    property string fontFamily: "sans"
    property int fontSize: 12

    function tone(name) {
        return foreground;
    }
}
