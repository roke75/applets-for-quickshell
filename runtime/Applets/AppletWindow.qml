import QtQuick
import Quickshell

// An ordinary window the compositor manages; closing it hides the applet.
FloatingWindow {
    id: window

    required property var owner

    title: owner.applet.title
    implicitWidth: content.implicitWidth + 24
    implicitHeight: content.implicitHeight + 24
    color: AppletTheme.surface
    onVisibleChanged: {
        if (!visible)
            owner.hide();
    }

    AppletContent {
        id: content

        anchors.fill: parent
        anchors.margins: 12
        owner: window.owner
        focus: true
    }
}
