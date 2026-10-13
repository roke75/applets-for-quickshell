import QtQuick
import Quickshell
import Quickshell.Wayland

// A centered overlay on the chosen screen. Clicking outside or Escape closes.
// Uses layer-shell, so it works on Hyprland, Sway, niri and other wlroots-style
// compositors.
PanelWindow {
    id: window

    required property var owner

    screen: owner.screen()
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "applet-" + owner.name

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: window.owner.hide()
    }

    AppletCard {
        anchors.centerIn: parent
        owner: window.owner
        focus: true
        Keys.onEscapePressed: window.owner.hide()
    }
}
