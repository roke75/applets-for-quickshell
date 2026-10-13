import QtQuick

// A row of bar applets for one bar. Place one in each bar, for example:
//
//   AppletBar { host: applets }
//
// `names` picks and orders applets; empty shows every applet with `bar` set.
Row {
    id: row

    required property var host
    property var names: []
    readonly property var shownNames: {
        if (!host || !host.names)
            return [];

        var registry = host.registry, instances = host.instances;
        // Instances appear a moment after the registry; skip until they exist.
        return (names.length ? names : host.names).filter(n => registry[n] && registry[n].bar !== "none" && !!instances[n]);
    }

    spacing: 4

    Repeater {
        model: row.shownNames

        Loader {
            id: slot

            required property string modelData
            readonly property var instance: row.host.instances[modelData]

            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            // The instance can vanish just before this slot does (removal).
            sourceComponent: !instance || !instance.applet ? null : instance.applet.bar === "qml" ? custom : chip

            Component {
                id: chip

                AppletChip {
                    owner: slot.instance
                }
            }

            Component {
                id: custom

                AppletQmlItem {
                    owner: slot.instance
                    file: slot.instance.applet.barEntry
                }
            }
        }
    }
}
