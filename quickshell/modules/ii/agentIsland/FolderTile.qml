pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects

// A premium dark-glass folder for one project. Graphite glass body, crisp hairline
// edges, a per-project iridescent accent sheen (cohesive brand, distinct identity),
// a soft drop shadow, refined (non-bouncy) hover, a live-session dot, and a gear
// on hover. Click the folder → launch.
Item {
    id: tile
    property var project
    property string name: project?.name ?? ""
    property bool running: project?.running ?? false
    signal activated()

    implicitWidth: 130
    implicitHeight: 132

    // per-project accent — same brand family, distinct hue per project
    readonly property color accent: {
        let h = 0;
        const n = tile.name;
        for (let i = 0; i < n.length; i++) h = (h * 37 + n.charCodeAt(i)) % 360;
        return Qt.hsla(h / 360, 0.58, 0.62, 1);
    }

    property bool hovered: hover.hovered
    scale: tap.pressed ? 0.975 : (tile.hovered ? 1.04 : 1.0)
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    z: tile.hovered ? 2 : 1

    // refined accent glow behind (subtle)
    Rectangle {
        anchors.horizontalCenter: folder.horizontalCenter
        anchors.verticalCenter: folder.verticalCenter
        width: folder.width * 1.3
        height: folder.height * 1.35
        radius: 20
        color: tile.accent
        opacity: tile.hovered ? 0.26 : (tile.running ? 0.14 : 0.0)
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 40 }
    }

    Item {
        id: folder
        width: 92
        height: 72
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 6
        antialiasing: true

        // back tab
        Rectangle {
            width: parent.width * 0.34
            height: 11
            radius: 4
            x: 5
            y: 6
            gradient: Gradient {
                GradientStop { position: 0; color: "#2F2F39" }
                GradientStop { position: 1; color: "#23232B" }
            }
        }
        // back body
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height - 8
            radius: 9
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0; color: "#2A2A33" }
                GradientStop { position: 1; color: "#1B1B21" }
            }
        }
        // front panel (dark glass)
        Rectangle {
            id: front
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height - 18
            radius: 9
            antialiasing: true
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.07)
            gradient: Gradient {
                GradientStop { position: 0; color: "#33333E" }
                GradientStop { position: 1; color: "#1C1C23" }
            }

            // iridescent accent sheen (brand identity per project)
            Rectangle {
                anchors.fill: parent
                radius: 9
                opacity: tile.hovered ? 0.32 : 0.16
                Behavior on opacity { NumberAnimation { duration: 200 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.0) }
                    GradientStop { position: 0.55; color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.10) }
                    GradientStop { position: 1.0; color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.5) }
                }
            }
            // crisp top hairline highlight
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 1; rightMargin: 1; topMargin: 1 }
                height: 1
                color: Qt.rgba(1, 1, 1, 0.15)
            }
            // monogram
            StyledText {
                anchors.centerIn: parent
                text: tile.name.charAt(0).toUpperCase()
                color: Qt.rgba(1, 1, 1, 0.62)
                font.pixelSize: 23
                font.weight: Font.Medium
            }
        }

        // soft drop shadow, lifts subtly on hover
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.6)
            shadowBlur: 0.5
            shadowVerticalOffset: tile.hovered ? 9 : 4
            shadowHorizontalOffset: 0
            autoPaddingEnabled: true
            Behavior on shadowVerticalOffset { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        // live session dot
        Rectangle {
            visible: tile.running
            width: 12; height: 12; radius: 6
            color: "#34D399"
            border.width: 2.5
            border.color: "#0A0A0D"
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 1
            anchors.topMargin: 7
            SequentialAnimation on opacity {
                running: tile.running; loops: Animation.Infinite
                NumberAnimation { to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
            }
        }
    }

    // label
    StyledText {
        anchors.top: folder.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: tile.width - 6
        horizontalAlignment: Text.AlignHCenter
        text: tile.name
        elide: Text.ElideRight
        maximumLineCount: 1
        color: tile.hovered ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.74)
        Behavior on color { ColorAnimation { duration: 150 } }
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: tile.activated() }
}
