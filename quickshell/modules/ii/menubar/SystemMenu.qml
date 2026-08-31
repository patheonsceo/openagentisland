pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * The  menu — this bar's equivalent of the Apple menu.
 *
 * Deliberately NOT an application menu. Apps on Linux export their menus over
 * DBus inconsistently at best, so a File/Edit/View strip would be empty or
 * wrong most of the time. macOS's leftmost menu was always the system's own
 * anyway, and it is the one that actually gets used daily — so this bar keeps
 * that half and drops the half that cannot be made reliable.
 *
 * Log Out, Restart and Shut Down arm on the first click and fire on the
 * second. macOS puts up a confirmation dialog; this is the same idea without a
 * second surface, and it means a mis-aimed click cannot end the session.
 */
Item {
    id: root

    property bool open: false
    signal requestClose()

    property string armed: ""
    onOpenChanged: if (!root.open) root.armed = ""

    implicitWidth: 268
    implicitHeight: menuColumn.implicitHeight + 12

    // Read once — the kernel does not change while the session is up.
    property string kernel: ""
    Process {
        running: true
        command: ["uname", "-r"]
        stdout: StdioCollector { onStreamFinished: root.kernel = text.trim() }
    }

    ColumnLayout {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 0

        // ── About, inline ─────────────────────────────────────────
        // A separate About window would be a whole extra surface for four
        // facts; they fit here.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: 6
            spacing: 1

            StyledText {
                text: SystemInfo.distroName
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: root.kernel.length > 0
                    ? `${root.kernel} · ${SystemInfo.windowingSystem}`
                    : SystemInfo.windowingSystem
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        MenuSeparator {}

        MenuRow {
            symbol: "settings"
            label: Translation.tr("System Settings…")
            onTriggered: {
                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
                root.requestClose();
            }
        }
        MenuRow {
            symbol: "wallpaper"
            label: Translation.tr("Wallpaper…")
            onTriggered: {
                GlobalStates.wallpaperSelectorOpen = true;
                root.requestClose();
            }
        }
        MenuRow {
            symbol: "widgets"
            label: Translation.tr("Desktop Widgets")
            onTriggered: {
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
                root.requestClose();
            }
        }

        MenuSeparator {}

        MenuRow {
            symbol: "lock"
            label: Translation.tr("Lock Screen")
            onTriggered: { Session.lock(); root.requestClose(); }
        }
        MenuRow {
            symbol: "bedtime"
            label: Translation.tr("Sleep")
            onTriggered: { Session.suspend(); root.requestClose(); }
        }

        MenuSeparator {}

        MenuRow {
            symbol: "logout"
            label: Translation.tr("Log Out")
            destructive: true
            armedKey: "logout"
            onTriggered: Session.logout()
        }
        MenuRow {
            symbol: "restart_alt"
            label: Translation.tr("Restart")
            destructive: true
            armedKey: "restart"
            onTriggered: Session.reboot()
        }
        MenuRow {
            symbol: "power_settings_new"
            label: Translation.tr("Shut Down")
            destructive: true
            armedKey: "poweroff"
            onTriggered: Session.poweroff()
        }
    }

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 3
        implicitHeight: 1
        color: Appearance.m3colors.m3outlineVariant
    }

    component MenuRow: MouseArea {
        id: row
        required property string symbol
        required property string label
        property bool destructive: false
        property string armedKey: ""
        signal triggered()

        readonly property bool isArmed: row.destructive && root.armed === row.armedKey

        Layout.fillWidth: true
        implicitHeight: 32
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (row.destructive && !row.isArmed) { root.armed = row.armedKey; return; }
            row.triggered();
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: Appearance.rounding.verysmall
            color: row.isArmed ? Appearance.m3colors.m3errorContainer
                : row.containsMouse ? Qt.rgba(1, 1, 1, 0.075)
                : "transparent"

            // Slower than elementMoveFast: a highlight that snaps draws the eye
            // to the transition rather than to the row.
            Behavior on color {
                ColorAnimation { duration: 160; easing.type: Easing.OutQuad }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 9

            MaterialSymbol {
                text: row.isArmed ? "warning" : row.symbol
                iconSize: 17
                color: row.isArmed ? Appearance.m3colors.m3onErrorContainer
                    : Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: row.isArmed ? Translation.tr("Click again to confirm") : row.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: row.isArmed ? Appearance.m3colors.m3onErrorContainer
                    : Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }
    }
}
