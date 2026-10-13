import QtQuick
import QtQuick.Controls

// Text field in the applet theme.
TextField {
    id: field

    implicitHeight: 36
    color: AppletTheme.foreground
    placeholderTextColor: AppletTheme.muted
    selectionColor: AppletTheme.accent
    selectedTextColor: AppletTheme.background
    font.family: AppletTheme.fontFamily
    font.pixelSize: AppletTheme.fontSize

    background: Rectangle {
        color: AppletTheme.background
        radius: AppletTheme.rounding
        border.width: 1
        border.color: field.activeFocus ? AppletTheme.accent : AppletTheme.border
    }
}
