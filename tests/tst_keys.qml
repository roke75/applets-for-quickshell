import QtQuick
import QtTest
import qs.Applets

// Keyboard handling of popups: drives the real AppletCard and
// AppletScriptView with a fake applet instance. Run with tests/run.
Item {
    id: top
    width: 500
    height: 600

    component FakeOwner: QtObject {
        property var applet: ({
                name: "t",
                title: "T",
                kind: "script",
                width: 400,
                height: 0,
                input: false,
                placeholder: "",
                surface: "popup"
            })
        property var state: ({})
        property string error: ""
        property date updated
        property bool busy: false
        property string notice: ""
        property int reloadToken: 0
        property var api: null
        property var submitted: []
        property var activated: []
        property int hidden: 0
        function hide() {
            hidden++;
        }
        function submit(text) {
            submitted = submitted.concat([text]);
        }
        function activate(item) {
            if (item)
                activated = activated.concat([item.text]);
        }
    }

    FakeOwner {
        id: calcOwner
    }
    FakeOwner {
        id: diceOwner
    }

    FocusScope {
        id: holder
        anchors.fill: parent
        focus: true
    }
    property Item card: null
    Component {
        id: cardComponent
        AppletCard {}
    }

    TestCase {
        name: "AppletKeys"
        when: windowShown

        function open(owner) {
            if (top.card)
                top.card.destroy();
            top.card = cardComponent.createObject(holder, {
                owner: owner,
                focus: true
            });
            wait(50);
        }

        // Each test starts from a clean fake applet.
        function init() {
            for (const owner of [calcOwner, diceOwner]) {
                owner.state = {};
                owner.submitted = [];
                owner.activated = [];
                owner.hidden = 0;
                owner.notice = "";
            }
        }

        function test_calc_enter_twice() {
            calcOwner.applet = Object.assign({}, calcOwner.applet, {
                input: true
            });
            open(calcOwner);
            keyClick("2");
            keyClick(Qt.Key_Plus);
            keyClick("2");
            keyClick(Qt.Key_Return);
            compare(calcOwner.submitted, ["2+2"]);
            // The script answers with history rows that copy on activation.
            calcOwner.state = {
                items: [
                    {
                        text: "= 4",
                        copy: "4"
                    }
                ]
            };
            wait(20);
            keyClick(Qt.Key_Return);
            compare(calcOwner.submitted, ["2+2", "2+2"], "second Enter submits again");
            compare(calcOwner.activated, [], "Enter with text must not activate a row");
            compare(calcOwner.hidden, 0);
        }

        function test_calc_empty_field_selects_row() {
            calcOwner.applet = Object.assign({}, calcOwner.applet, {
                input: true
            });
            calcOwner.state = {
                items: [
                    {
                        text: "= 4",
                        copy: "4",
                        close: false
                    },
                    {
                        text: "= 9",
                        copy: "9",
                        close: false
                    }
                ]
            };
            open(calcOwner);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(calcOwner.activated, ["= 9"], "Enter on an empty field activates the selected row");
            calcOwner.notice = "Copied";
            wait(20);
            verify(findChild(top.card, "footer").text === "Copied", "footer shows the notice");
        }

        function test_dice_keys_after_items_arrive() {
            open(diceOwner);              // opens with no items yet, as on first show
            diceOwner.state = {
                items: [
                    {
                        text: "coin",
                        run: "coin"
                    },
                    {
                        text: "d6",
                        run: "d6"
                    },
                    {
                        text: "d20",
                        run: "d20"
                    }
                ]
            };
            wait(20);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(diceOwner.activated, ["d20"]);
            keyClick(Qt.Key_Escape);
            compare(diceOwner.hidden, 1);
        }
    }
}
