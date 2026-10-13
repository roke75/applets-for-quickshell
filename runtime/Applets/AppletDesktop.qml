import QtQuick
import Quickshell
import Quickshell.Wayland

// A widget placed by the manifest's `position`; an axis without an anchor
// centers it. `layer = "below"` keeps it under windows (on the wallpaper),
// "above" over them.
PanelWindow {
    id: window

    required property var owner
    readonly property string position: owner.applet.position

    screen: owner.screen()
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    WlrLayershell.layer: owner.applet && owner.applet.layer === "above" ? WlrLayer.Top : WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "applet-" + owner.name

    anchors {
        top: position.startsWith("top")
        bottom: position.startsWith("bottom")
        left: position.endsWith("left")
        right: position.endsWith("right")
    }

    margins {
        top: 24
        bottom: 24
        left: 24
        right: 24
    }

    AppletCard {
        id: card

        anchors.fill: parent
        owner: window.owner
    }
}
