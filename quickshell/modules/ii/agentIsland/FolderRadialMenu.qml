pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Radial action ring for a focused project folder. The folder lifts to center,
// the background blurs (handled by the parent), and actions arc out around it in
// a wave-staggered fan. "Launch from…" swaps the ring for a subfolder picker.
Item {
    id: menu
    anchors.fill: parent

    property var project
    property var subdirs: []          // populated by parent for "Launch from…"
    property bool dirMode: false      // showing the subfolder picker
    property bool shown: false        // drives the open/close animation

    signal launch()
    signal launchFromRequested()
    signal pickDir(string dir)
    signal openFolder()
    signal settings()
    signal removeRecent()
    signal closed()

    readonly property real cx: width / 2
    readonly property real cy: height / 2 + 6
    readonly property real ringRadius: 150
    readonly property string pname: project?.name ?? ""
    readonly property color accent: {
        let h = 0;
        for (let i = 0; i < menu.pname.length; i++) h = (h * 37 + menu.pname.charCodeAt(i)) % 360;
        return Qt.hsla(h / 360, 0.6, 0.62, 1);
    }

    // single driver for the staggered fan-out
    property real wave: shown ? 1 : 0
    Behavior on wave { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }

    focus: true
    Keys.onEscapePressed: menu.closed()

    // dim (click outside to close)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: menu.wave
        TapHandler { onTapped: menu.closed() }
    }

    // ---------------- focused folder ----------------
    Item {
        id: focus
        width: 132
        height: 104
        x: menu.cx - width / 2
        y: menu.cy - height / 2
        opacity: menu.wave
        scale: 0.7 + 0.3 * menu.wave

        Rectangle {
            id: back
            anchors.bottom: parent.bottom
            width: parent.width; height: parent.height - 12; radius: 14
            gradient: Gradient { GradientStop { position: 0; color: "#2A2A33" } GradientStop { position: 1; color: "#1B1B21" } }
        }
        Rectangle {
            width: parent.width * 0.34; height: 14; radius: 5; x: 8; y: 8
            gradient: Gradient { GradientStop { position: 0; color: "#2F2F39" } GradientStop { position: 1; color: "#23232B" } }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: parent.height - 26; radius: 14
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08)
            gradient: Gradient { GradientStop { position: 0; color: "#34343F" } GradientStop { position: 1; color: "#1C1C23" } }
            Rectangle {
                anchors.fill: parent; radius: 14; opacity: 0.22
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(menu.accent.r, menu.accent.g, menu.accent.b, 0) }
                    GradientStop { position: 1; color: Qt.rgba(menu.accent.r, menu.accent.g, menu.accent.b, 0.55) }
                }
            }
            StyledText {
                anchors.centerIn: parent
                text: menu.pname.charAt(0).toUpperCase()
                color: Qt.rgba(1, 1, 1, 0.85)
                font.pixelSize: 34; font.weight: Font.DemiBold
            }
        }
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: focus.bottom
        anchors.topMargin: 14
        spacing: 2
        opacity: menu.wave
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: menu.pname
            color: "#FFFFFF"; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: menu.project?.running ? "● live session" : (menu.project?.path ?? "")
            color: menu.project?.running ? "#34D399" : Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideMiddle
            width: Math.min(implicitWidth, 360)
        }
    }

    // ---------------- radial actions ----------------
    component RadialAction: Item {
        id: ra
        property string sym
        property string label
        property real angle
        property int idx: 0
        property bool primary: false
        signal act
        width: 60; height: 82
        // per-button progress derived from the shared wave (staggered)
        readonly property real t: Math.max(0, Math.min(1, (menu.wave - idx * 0.08) / 0.6))
        readonly property real homeX: menu.cx - width / 2
        readonly property real homeY: menu.cy - height / 2
        readonly property real targetX: menu.cx + menu.ringRadius * Math.cos(angle * Math.PI / 180) - width / 2
        readonly property real targetY: menu.cy - menu.ringRadius * Math.sin(angle * Math.PI / 180) - height / 2
        x: homeX + (targetX - homeX) * t
        y: homeY + (targetY - homeY) * t
        opacity: t
        scale: 0.5 + 0.5 * t
        visible: !menu.dirMode

        Rectangle {
            id: circle
            width: ra.primary ? 60 : 52
            height: width; radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            color: ra.primary ? menu.accent : (raHover.hovered ? "#26262E" : "#191920")
            border.width: 1
            border.color: ra.primary ? "transparent" : Qt.rgba(1, 1, 1, 0.12)
            scale: raHover.hovered ? 1.1 : 1.0
            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
            MaterialSymbol {
                anchors.centerIn: parent
                text: ra.sym
                iconSize: ra.primary ? 26 : 22
                fill: ra.primary ? 1 : 0
                color: ra.primary ? "#0A0A0D" : "#FFFFFF"
            }
            HoverHandler { id: raHover }
            TapHandler { onTapped: ra.act() }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: circle.bottom
            anchors.topMargin: 6
            text: ra.label
            color: raHover.hovered ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    RadialAction { sym: "folder_open"; label: "Open"; angle: 170; idx: 4; onAct: menu.openFolder() }
    RadialAction { sym: "drive_folder_upload"; label: "From…"; angle: 130; idx: 2; onAct: menu.launchFromRequested() }
    RadialAction { sym: "play_arrow"; label: "Launch"; angle: 90; idx: 0; primary: true; onAct: menu.launch() }
    RadialAction { sym: "tune"; label: "Settings"; angle: 50; idx: 1; onAct: menu.settings() }
    RadialAction { sym: "do_not_disturb_on"; label: "Remove"; angle: 10; idx: 3; onAct: menu.removeRecent() }

    // ---------------- "Launch from…" subfolder picker ----------------
    Rectangle {
        id: dirPanel
        visible: menu.dirMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: focus.bottom
        anchors.topMargin: 56
        width: 380
        height: Math.min(300, dirCol.implicitHeight + 20)
        radius: 16
        color: "#15151A"
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.09)
        opacity: menu.dirMode ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentHeight: dirCol.implicitHeight
            clip: true
            Column {
                id: dirCol
                width: parent.width
                spacing: 2

                // project root
                Rectangle {
                    width: parent.width; height: 40; radius: 10
                    color: rootHover.hovered ? "#23232B" : "transparent"
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 10
                        spacing: 10
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "home"; iconSize: 19; color: menu.accent }
                        StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Project root"; color: "#FFFFFF"; font.pixelSize: Appearance.font.pixelSize.normal }
                    }
                    HoverHandler { id: rootHover }
                    TapHandler { onTapped: menu.pickDir(menu.project?.path ?? "") }
                }
                Repeater {
                    model: menu.subdirs
                    Rectangle {
                        required property var modelData
                        width: dirCol.width; height: 38; radius: 10
                        color: subHover.hovered ? "#23232B" : "transparent"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.leftMargin: 10
                            spacing: 10
                            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "folder"; iconSize: 18; color: Qt.rgba(1, 1, 1, 0.55) }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.name; color: Qt.rgba(1, 1, 1, 0.85); font.pixelSize: Appearance.font.pixelSize.normal }
                        }
                        HoverHandler { id: subHover }
                        TapHandler { onTapped: menu.pickDir(parent.modelData.path) }
                    }
                }
                StyledText {
                    visible: menu.subdirs.length === 0
                    padding: 12
                    text: "No subfolders — use Project root."
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    // back chip when in dir mode
    Rectangle {
        visible: menu.dirMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: dirPanel.bottom
        anchors.topMargin: 12
        width: backRow.implicitWidth + 24; height: 34; radius: 17
        color: backHover.hovered ? "#23232B" : "#17171C"
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
        Row {
            id: backRow
            anchors.centerIn: parent; spacing: 6
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "arrow_back"; iconSize: 17; color: "#FFFFFF" }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Back"; color: "#FFFFFF"; font.pixelSize: Appearance.font.pixelSize.smaller }
        }
        HoverHandler { id: backHover }
        TapHandler { onTapped: menu.dirMode = false }
    }
}
