import QtQuick
import Quickshell

// A popup attached to the bar item that opened it. The compositor places it
// below the item and flips it above when there is no room (bottom bars).
// Clicking outside or Escape closes it. Wayland only grants the focus grab
// right after input on the bar, which the chip's click provides.
PopupWindow {
    id: window

    required property var owner
    readonly property int gap: 6

    // Anchor to the item's bottom edge, centered horizontally on it.
    anchor.item: owner.anchorItem
    anchor.rect.x: owner.anchorItem ? owner.anchorItem.width / 2 - implicitWidth / 2 : 0
    anchor.rect.width: implicitWidth
    anchor.rect.height: owner.anchorItem ? owner.anchorItem.height : 0
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.All
    grabFocus: true
    visible: true
    color: "transparent"
    implicitWidth: card.implicitWidth + gap * 2
    implicitHeight: card.implicitHeight + gap * 2
    onVisibleChanged: {
        if (!visible)
            owner.hide();
    }

    AppletCard {
        id: card

        anchors.fill: parent
        anchors.margins: window.gap
        owner: window.owner
        focus: true
        Keys.onEscapePressed: window.owner.hide()
    }
}
