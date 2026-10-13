import QtQuick

// Creates an applet's QML file with the `applet` API. The revision in the URL
// bypasses the component cache, so saved edits reload live. Load errors are
// shown in place instead of breaking the shell.
Item {
    id: holder

    required property var owner
    required property string file
    // Fill this item (window content) or size to the created item (bar).
    property bool fill: false
    property Item userItem: null // the created root item
    property string loadError: ""

    implicitWidth: fill ? 0 : userItem ? userItem.width : errorText.implicitWidth
    implicitHeight: fill ? 0 : userItem ? userItem.height : errorText.implicitHeight

    function load() {
        if (userItem) {
            userItem.destroy();
            userItem = null;
        }
        loadError = "";
        var component = Qt.createComponent("file://" + file + "?rev=" + owner.reloadToken, Component.PreferSynchronous);
        if (component.status === Component.Error) {
            loadError = component.errorString().trim();
            console.warn("applets:", owner.name + ":", loadError);
            return;
        }
        var item = component.createObject(holder, {
            "applet": owner.api
        });
        if (!item) {
            loadError = "could not create the root item (does it declare `required property var applet`?)";
            return;
        }
        if (fill)
            item.anchors.fill = holder;

        item.focus = true;
        userItem = item;
    }

    Component.onCompleted: load()

    Connections {
        target: holder.owner

        function onReloadTokenChanged() {
            holder.load();
        }
    }

    AppletText {
        id: errorText

        anchors.fill: holder.fill ? parent : undefined
        anchors.verticalCenter: holder.fill ? undefined : parent.verticalCenter
        visible: !!holder.loadError
        width: holder.fill ? parent.width : Math.min(implicitWidth, 240)
        // Bars have no room for the message; it is logged instead.
        text: holder.fill ? holder.loadError : "⚠ " + holder.owner.name
        color: AppletTheme.error
        wrapMode: holder.fill ? Text.Wrap : Text.NoWrap
        elide: holder.fill ? Text.ElideNone : Text.ElideRight
    }
}
