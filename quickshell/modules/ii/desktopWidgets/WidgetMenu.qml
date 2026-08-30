pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Right-click menu shared by every desktop widget.
 *
 * Rendered as a plain Item inside the board's own layer surface rather than a
 * PopupWindow — the surface is already full-screen, so a child positioned at
 * the click point is enough and it avoids a second Wayland surface.
 *
 * Only carries settings that mean the same thing for every widget. Anything
 * specific to one widget belongs on that widget's own face.
 */
Item {
    id: root

    required property var config
    property bool open: false
    signal requestClose()

    readonly property var board: Config.options.background.widgets

    visible: opacity > 0
    opacity: root.open ? 1 : 0
    implicitWidth: 232
    implicitHeight: menuColumn.implicitHeight + 12

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 0

            SectionLabel { text: Translation.tr("Material") }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                spacing: 6

                MaterialChip {
                    label: Translation.tr("Translucent")
                    active: !root.config.solidMaterial
                    onTriggered: root.config.solidMaterial = false
                }
                MaterialChip {
                    label: Translation.tr("Solid")
                    active: root.config.solidMaterial
                    onTriggered: root.config.solidMaterial = true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: 6
                spacing: 8

                StyledText {
                    text: Translation.tr("Opacity")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 18

                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Appearance.colors.colLayer2

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.config.baseOpacity))
                            height: parent.height
                            radius: 2
                            color: Appearance.colors.colPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: mouse => {
                            if (pressed) root.config.baseOpacity =
                                Math.max(0, Math.min(1, mouse.x / track.width));
                        }
                        onClicked: mouse => {
                            root.config.baseOpacity =
                                Math.max(0, Math.min(1, mouse.x / track.width));
                        }
                    }
                }

                StyledText {
                    text: `${Math.round(root.config.baseOpacity * 100)}%`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                }
            }

            MenuSeparator {}
            SectionLabel { text: Translation.tr("Placement") }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                spacing: 6

                MaterialChip {
                    label: Translation.tr("Free")
                    active: root.board.placementMode === "free"
                    onTriggered: root.board.placementMode = "free"
                }
                MaterialChip {
                    label: Translation.tr("Snap")
                    active: root.board.placementMode === "snap"
                    onTriggered: root.board.placementMode = "snap"
                }
                MaterialChip {
                    label: Translation.tr("Grid")
                    active: root.board.placementMode === "grid"
                    onTriggered: root.board.placementMode = "grid"
                }
            }

            MenuSeparator {}
            SectionLabel { text: Translation.tr("Widget") }

            MenuRow {
                symbol: "resize"
                label: Translation.tr("Reset size")
                onTriggered: {
                    root.config.width = 320;
                    root.config.contentHeight = 0;
                    root.requestClose();
                }
            }
            MenuRow {
                symbol: "restart_alt"
                label: Translation.tr("Reset position")
                onTriggered: {
                    root.config.x = 24;
                    root.config.y = 24;
                    root.requestClose();
                }
            }
            MenuRow {
                symbol: "visibility_off"
                label: Translation.tr("Hide widget")
                onTriggered: {
                    root.config.enable = false;
                    root.requestClose();
                }
            }
        }
    }

    component SectionLabel: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 4
        Layout.bottomMargin: 2
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 2
        implicitHeight: 1
        color: Appearance.m3colors.m3outlineVariant
    }

    component MaterialChip: Rectangle {
        id: chip
        required property string label
        property bool active: false
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 28
        radius: Appearance.rounding.verysmall
        color: chip.active ? Appearance.colors.colPrimary
            : chipArea.containsMouse ? Appearance.colors.colLayer2Hover
            : Appearance.colors.colLayer2

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StyledText {
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.triggered()
        }
    }

    component MenuRow: MouseArea {
        id: row
        required property string symbol
        required property string label
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 32
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
        }
    }
}
