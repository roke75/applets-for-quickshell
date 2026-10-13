import QtQuick
import QtQuick.Controls

// Renders a script applet's state: title, optional input, body text and a
// keyboard-navigable item list. The view itself (or the text field) holds
// keyboard focus and moves the list's selection; the list never takes focus.
// Enter submits typed text, otherwise it activates the selected item.
FocusScope {
    id: view

    required property var owner
    readonly property var applet: owner.applet
    readonly property var output: owner.state
    readonly property var items: Array.isArray(output.items) ? output.items : []
    readonly property int rowHeight: AppletTheme.fontSize * 2 + 22

    implicitHeight: column.implicitHeight

    function move(delta) {
        if (list.count)
            list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta));
    }

    Keys.onEscapePressed: owner.hide()
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onReturnPressed: owner.activate(items[list.currentIndex])
    Keys.onEnterPressed: owner.activate(items[list.currentIndex])

    Column {
        id: column

        width: parent.width
        spacing: 10

        Row {
            width: parent.width
            spacing: 8

            AppletText {
                id: title

                width: parent.width - summary.width - parent.spacing
                text: view.output.title || view.applet.title
                font.pixelSize: AppletTheme.fontSize + 4
                font.bold: true
            }

            AppletText {
                id: summary

                text: view.output.text || ""
                color: AppletTheme.tone(view.output.class)
                font.pixelSize: AppletTheme.fontSize + 4
                anchors.baseline: title.baseline
            }
        }

        AppletField {
            id: field

            // Typed text is submitted; an empty field activates the selected item.
            function enter(event) {
                event.accepted = true;
                if (text.trim())
                    view.owner.submit(text);
                else
                    view.owner.activate(view.items[list.currentIndex]);
            }

            visible: view.applet.input
            width: parent.width
            placeholderText: view.output.placeholder || view.applet.placeholder || "Type and press Enter…"
            focus: view.applet.input
            // Handled here and accepted: TextField lets Enter propagate after
            // `accepted`, which would also activate the selected item.
            Keys.onReturnPressed: event => field.enter(event)
            Keys.onEnterPressed: event => field.enter(event)
            Keys.onUpPressed: view.move(-1)
            Keys.onDownPressed: view.move(1)
            Keys.onEscapePressed: view.owner.hide()
        }

        AppletText {
            visible: !!view.output.body
            width: parent.width
            text: view.output.body || ""
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }

        ListView {
            id: list

            visible: count > 0
            width: parent.width
            height: Math.min(contentHeight, 9 * view.rowHeight)
            clip: true
            model: view.items
            currentIndex: 0
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool actionable: modelData.run !== undefined || modelData.copy !== undefined || modelData.open !== undefined

                width: ListView.view.width
                height: view.rowHeight
                radius: AppletTheme.rounding
                color: ListView.isCurrentItem && actionable ? AppletTheme.surfaceAlt : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    AppletText {
                        visible: !!modelData.icon
                        text: modelData.icon || ""
                        width: visible ? AppletTheme.fontSize * 2 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: AppletTheme.fontSize + 4
                        color: AppletTheme.tone(modelData.class)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x

                        AppletText {
                            width: parent.width
                            text: modelData.text || ""
                            color: AppletTheme.tone(modelData.class)
                        }

                        AppletText {
                            visible: !!modelData.detail
                            width: parent.width
                            text: modelData.detail || ""
                            color: AppletTheme.foregroundDim
                            font.pixelSize: AppletTheme.fontSize - 1
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: list.currentIndex = index
                    onClicked: view.owner.activate(modelData)
                }
            }
        }

        // Footer: the error, progress, a notice, or when the state last changed.
        AppletText {
            objectName: "footer"
            width: parent.width
            text: view.owner.error ? view.owner.error : view.owner.busy ? "Working…" : view.owner.notice ? view.owner.notice : view.owner.updated.getTime() ? "Updated " + Qt.formatTime(view.owner.updated, Locale.ShortFormat) : ""
            color: view.owner.error ? AppletTheme.error : AppletTheme.muted
            font.pixelSize: AppletTheme.fontSize - 2
            wrapMode: Text.Wrap
        }
    }
}
