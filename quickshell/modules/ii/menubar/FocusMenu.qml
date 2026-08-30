pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Focus and attention: the timer, the task list, and notifications.
 *
 * The quick timer uses a fixed task id, because FocusTimer.start refuses
 * an empty one — that id lets the desktop widget show the countdown
 * without a real task having been chosen.
 */
Item {
    id: root

    property bool open: false
    signal requestClose()
    property string armed: ""
    onOpenChanged: if (!root.open) root.armed = ""


    implicitWidth: 256
    implicitHeight: menuColumn.implicitHeight + 12

    ColumnLayout {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 0

        MenuRow {
            visible: !FocusTimer.active
            symbol: "timer"
            label: Translation.tr("Start 25-minute focus")
            onTriggered: { FocusTimer.start("quick-focus", Translation.tr("Focus"), 25 * 60); root.requestClose(); }
        }
        MenuRow {
            visible: FocusTimer.active
            symbol: "timer_off"
            label: Translation.tr("Stop timer")
            detail: FocusTimer.formatDuration(FocusTimer.secondsLeft)
            onTriggered: { FocusTimer.stop(); root.requestClose(); }
        }
        MenuSeparator {}
        MenuRow {
            symbol: "checklist"
            label: Config.options.background.widgets.todo.enable ? Translation.tr("Hide task list") : Translation.tr("Show task list")
            detail: `${Todo.unfinished.length}`
            onTriggered: { Config.options.background.widgets.todo.enable = !Config.options.background.widgets.todo.enable; root.requestClose(); }
        }
        MenuSeparator {}
        MenuRow {
            symbol: "do_not_disturb_on"
            label: Notifications.silent ? Translation.tr("Do Not Disturb — on") : Translation.tr("Do Not Disturb")
            onTriggered: { Notifications.silent = !Notifications.silent; root.requestClose(); }
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
        property string detail: ""
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: row.visible ? 32 : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.triggered()

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: Appearance.rounding.verysmall
            color: row.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 9

            MaterialSymbol {
                text: row.symbol
                iconSize: 17
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: row.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            StyledText {
                visible: row.detail.length > 0
                text: row.detail
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
