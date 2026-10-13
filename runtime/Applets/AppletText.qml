import QtQuick

// Text in the applet theme. Always plain text, so script output cannot inject
// markup.
Text {
    color: AppletTheme.foreground
    font.family: AppletTheme.fontFamily
    font.pixelSize: AppletTheme.fontSize
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
