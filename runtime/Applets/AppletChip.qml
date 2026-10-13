import QtQuick

// Default bar item: the applet's icon and the script state's `text`, colored
// by `class`. As in Waybar, an empty `text` hides it; without `text` only the
// icon shows. A click toggles the applet's window; popups attach to the chip.
Rectangle {
    id: chip

    required property var owner
    readonly property var output: owner.state
    readonly property string icon: output.icon || owner.applet.icon || ""
    readonly property string label: output.text !== undefined && output.text !== null ? String(output.text) : ""
    // A failing script with nothing to show gets a warning sign instead.
    readonly property bool failed: !!owner.error && !label

    function toggle() {
        if (!owner.hasSurface)
            return;

        if (owner.shown) {
            owner.hide();
            return;
        }
        owner.showFrom(chip);
    }

    visible: failed || (output.text === undefined ? !!icon : !!label)
    implicitWidth: visible ? content.implicitWidth + 12 : 0
    implicitHeight: 24
    radius: AppletTheme.rounding
    color: hover.hovered && owner.hasSurface ? AppletTheme.surfaceAlt : "transparent"

    HoverHandler {
        id: hover

        cursorShape: chip.owner.hasSurface ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        onTapped: chip.toggle()
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 5

        AppletText {
            visible: !!chip.icon || chip.failed
            text: chip.failed ? "⚠" : chip.icon
            color: chip.failed ? AppletTheme.error : AppletTheme.tone(chip.output.class === undefined ? "accent" : chip.output.class)
        }

        AppletText {
            visible: !!chip.label
            text: chip.label
            color: AppletTheme.tone(chip.output.class)
        }
    }
}
