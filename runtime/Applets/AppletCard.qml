import QtQuick

// Themed frame around an applet's content, shared by every surface. A
// FocusScope, so `focus: true` on the card passes keyboard focus to the content.
FocusScope {
    id: card

    required property var owner

    implicitWidth: content.implicitWidth + 24
    implicitHeight: content.implicitHeight + 24

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(AppletTheme.surface, AppletTheme.opacity)
        radius: AppletTheme.rounding + 4
        border.width: AppletTheme.borderSize
        border.color: AppletTheme.border
    }

    // Clicks on the card must not reach the popup's dismiss area behind it.
    MouseArea {
        anchors.fill: parent
    }

    AppletContent {
        id: content

        anchors.fill: parent
        anchors.margins: 12
        owner: card.owner
        focus: true
    }
}
