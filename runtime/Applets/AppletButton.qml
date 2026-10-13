import QtQuick
import QtQuick.Controls

// Button in the applet theme.
Button {
    id: button

    implicitHeight: 32
    implicitWidth: Math.max(80, label.implicitWidth + 24)

    contentItem: Text {
        id: label

        text: button.text
        color: AppletTheme.foreground
        opacity: button.enabled ? 1 : 0.4
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: AppletTheme.fontFamily
        font.pixelSize: AppletTheme.fontSize
    }

    background: Rectangle {
        color: button.down || button.hovered ? AppletTheme.border : AppletTheme.surfaceAlt
        radius: AppletTheme.rounding
        border.width: button.activeFocus ? 1 : 0
        border.color: AppletTheme.accent
    }
}
