import QtQuick

// A window's content: script applets render their JSON state; QML applets
// load their entry file.
FocusScope {
    id: content

    required property var owner
    readonly property var applet: owner.applet

    implicitWidth: applet.width
    // Manifest height, else script views size to their content (up to 640)
    // and QML applets get 300.
    implicitHeight: applet.height > 0 ? applet.height : applet.kind === "script" ? Math.min(view.item ? view.item.implicitHeight : 80, 640) : 300

    Loader {
        id: view

        anchors.fill: parent
        focus: true
        sourceComponent: content.applet.kind === "script" ? scriptView : qmlView
    }

    Component {
        id: scriptView

        AppletScriptView {
            owner: content.owner
            focus: true
        }
    }

    Component {
        id: qmlView

        AppletQmlItem {
            owner: content.owner
            file: content.applet.entry
            fill: true
            focus: true
        }
    }
}
