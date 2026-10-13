import QtQuick
import qs.Applets

// The label and date come from [config]; edits are kept in applet.store.
Item {
    id: root

    required property var applet
    property string label: applet.store.get("label", applet.config.label || "Countdown")
    property string target: applet.store.get("date", applet.config.date || "")
    property date now: new Date()
    property bool editing: false
    readonly property int days: {
        var end = new Date(target + "T00:00:00");
        var start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        return isNaN(end) ? 0 : Math.round((end - start) / 86400000);
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Column {
        anchors.centerIn: parent
        spacing: 4
        visible: !root.editing

        AppletText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.days === 0 ? "Today" : Math.abs(root.days)
            color: root.days < 0 ? AppletTheme.muted : AppletTheme.accent
            font.pixelSize: 44
            font.bold: true
        }

        AppletText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.days === 0 ? root.label : (root.days > 0 ? "days until " : "days since ") + root.label
            color: AppletTheme.foregroundDim
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: !root.editing
        onClicked: {
            labelField.text = root.label;
            dateField.text = root.target;
            root.editing = true;
        }
    }

    Column {
        anchors.fill: parent
        spacing: 6
        visible: root.editing

        AppletField {
            id: labelField

            width: parent.width
            placeholderText: "Label"
        }

        Row {
            width: parent.width
            spacing: 6

            AppletField {
                id: dateField

                width: parent.width - save.width - parent.spacing
                placeholderText: "YYYY-MM-DD"
                onAccepted: save.clicked()
            }

            AppletButton {
                id: save

                text: "Save"
                onClicked: {
                    if (isNaN(new Date(dateField.text + "T00:00:00")))
                        return;

                    root.applet.store.set("label", labelField.text || "Countdown");
                    root.applet.store.set("date", dateField.text);
                    root.editing = false;
                }
            }
        }
    }
}
