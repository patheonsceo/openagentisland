pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Quick navigation, in the spirit of Finder's Go menu.
 *
 * Each entry hands a path to xdg-open, so it opens in whatever file
 * manager is actually registered rather than one hardcoded here.
 */
Item {
    id: root

    property bool open: false
    signal requestClose()
    property string armed: ""
    onOpenChanged: if (!root.open) root.armed = ""


    implicitWidth: 232
    implicitHeight: menuColumn.implicitHeight + 12

    ColumnLayout {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 0

        MenuRow {
            symbol: "home"
            label: Translation.tr("Home")
            onTriggered: { Quickshell.execDetached([Config.options.apps.fileManager, Directories.home]); root.requestClose(); }
        }
        MenuRow {
            symbol: "description"
            label: Translation.tr("Documents")
            onTriggered: { Quickshell.execDetached([Config.options.apps.fileManager, `${Directories.home}/Documents`]); root.requestClose(); }
        }
        MenuRow {
            symbol: "download"
            label: Translation.tr("Downloads")
            onTriggered: { Quickshell.execDetached([Config.options.apps.fileManager, `${Directories.home}/Downloads`]); root.requestClose(); }
        }
        MenuRow {
            symbol: "image"
            label: Translation.tr("Pictures")
            onTriggered: { Quickshell.execDetached([Config.options.apps.fileManager, `${Directories.home}/Pictures`]); root.requestClose(); }
        }
        MenuSeparator {}
        MenuRow {
            symbol: "code"
            label: Translation.tr("Projects")
            onTriggered: { Quickshell.execDetached([Config.options.apps.fileManager, `${Directories.home}/Projects`]); root.requestClose(); }
        }
        MenuRow {
            symbol: "screenshot"
            label: Translation.tr("Screenshots")
            onTriggered: { Quickshell.execDetached([Config.options.apps.fileManager, `${Directories.home}/Pictures/Screenshots`]); root.requestClose(); }
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
            color: row.containsMouse ? Qt.rgba(1, 1, 1, 0.075) : "transparent"
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
