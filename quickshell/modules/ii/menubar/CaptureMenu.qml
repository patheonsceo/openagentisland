pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Screen capture, colour and OCR.
 *
 * These run the same commands the Hyprland keybinds do, so the menu and
 * the shortcuts cannot drift apart in what they actually do.
 */
Item {
    id: root

    property bool open: false
    signal requestClose()
    property string armed: ""
    onOpenChanged: if (!root.open) root.armed = ""

    readonly property string screenshotCmd: "mkdir -p ~/Pictures/Screenshots && grim ~/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H.%M.%S).png"
    readonly property string ocrCmd: 'grim -g "$(slurp)" /tmp/ocr.png && tesseract /tmp/ocr.png stdout | wl-copy && rm -f /tmp/ocr.png'


    implicitWidth: 248
    implicitHeight: menuColumn.implicitHeight + 12

    ColumnLayout {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 0

        MenuRow {
            symbol: "crop"
            label: Translation.tr("Screenshot Region")
            onTriggered: { GlobalStates.regionSelectorOpen = true; root.requestClose(); }
        }
        MenuRow {
            symbol: "fullscreen"
            label: Translation.tr("Screenshot Screen")
            onTriggered: { Quickshell.execDetached(["bash","-c", root.screenshotCmd]); root.requestClose(); }
        }
        MenuSeparator {}
        MenuRow {
            symbol: "videocam"
            label: Translation.tr("Record Region")
            onTriggered: { Quickshell.execDetached([`${Directories.config}/quickshell/openagentisland/scripts/videos/record.sh`]); root.requestClose(); }
        }
        MenuRow {
            symbol: "screen_record"
            label: Translation.tr("Record Screen")
            onTriggered: { Quickshell.execDetached([`${Directories.config}/quickshell/openagentisland/scripts/videos/record.sh`, "--fullscreen"]); root.requestClose(); }
        }
        MenuSeparator {}
        MenuRow {
            symbol: "colorize"
            label: Translation.tr("Pick Colour")
            onTriggered: { Quickshell.execDetached(["hyprpicker","-a"]); root.requestClose(); }
        }
        MenuRow {
            symbol: "translate"
            label: Translation.tr("Text from Screen")
            onTriggered: { Quickshell.execDetached(["bash","-c", root.ocrCmd]); root.requestClose(); }
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
