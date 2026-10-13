import QtQuick
import Quickshell.Services.Mpris
import qs.Applets

// Bar item for the active MPRIS player: artwork and title, expanding on hover
// to previous / play-pause / next. Hidden when nothing has a track.
Item {
    id: root

    required property var applet
    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.isPlaying) || players.find(p => !!p.trackTitle) || null
    readonly property bool expanded: hover.hovered

    visible: !!player
    width: visible ? (expanded ? 340 : 220) : 0
    height: 24
    clip: true

    Behavior on width {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        radius: AppletTheme.rounding
        color: root.expanded ? AppletTheme.surfaceAlt : "transparent"
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 3
        anchors.rightMargin: 6
        spacing: 7

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 3
            color: AppletTheme.surfaceAlt
            clip: true

            Image {
                id: art

                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            AppletText {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: "♪"
                color: AppletTheme.accent
            }
        }

        AppletText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 27 - (controls.visible ? controls.width + 7 : 0)
            text: root.player ? [root.player.trackTitle, root.player.trackArtist].filter(s => !!s).join(" · ") : ""
            color: root.player && root.player.isPlaying ? AppletTheme.foreground : AppletTheme.foregroundDim
        }

        Row {
            id: controls

            anchors.verticalCenter: parent.verticalCenter
            visible: root.expanded
            spacing: 2

            Repeater {
                model: [
                    {
                        "glyph": "⏮",
                        "can": "canGoPrevious",
                        "run": p => p.previous()
                    },
                    {
                        "glyph": root.player && root.player.isPlaying ? "⏸" : "▶",
                        "can": "canTogglePlaying",
                        "run": p => p.togglePlaying()
                    },
                    {
                        "glyph": "⏭",
                        "can": "canGoNext",
                        "run": p => p.next()
                    }
                ]

                Rectangle {
                    required property var modelData

                    width: 22
                    height: 20
                    radius: AppletTheme.rounding
                    color: tap.pressed ? AppletTheme.border : buttonHover.hovered ? AppletTheme.background : "transparent"
                    opacity: root.player && root.player[modelData.can] ? 1 : 0.35

                    AppletText {
                        anchors.centerIn: parent
                        text: modelData.glyph
                    }

                    HoverHandler {
                        id: buttonHover
                    }

                    TapHandler {
                        id: tap

                        onTapped: {
                            if (root.player && root.player[modelData.can])
                                modelData.run(root.player);
                        }
                    }
                }
            }
        }
    }
}
