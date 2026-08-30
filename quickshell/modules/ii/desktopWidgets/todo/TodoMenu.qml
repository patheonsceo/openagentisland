pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Right-click settings menu for the todo widget.
 *
 * Rendered as a plain Item inside the widget's own layer surface rather than a
 * PopupWindow — the surface is already full-screen, so a child positioned at the
 * click point is enough, and it avoids a second Wayland surface for a menu.
 *
 * Destructive entries confirm in place: the row turns into "Sure?" rather than
 * opening a dialog, so an accidental click on "Clear all tasks" cannot wipe the
 * list in one go.
 */
Item {
    id: root

    readonly property var config: Config.options.background.widgets.todo
    property bool open: false
    signal requestClose()

    // Which destructive row is currently armed, "" when none.
    property string armed: ""

    visible: opacity > 0
    opacity: root.open ? 1 : 0
    implicitWidth: 232
    implicitHeight: menuColumn.implicitHeight + 12

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onOpenChanged: if (!root.open) root.armed = ""

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Swallow clicks so they neither reach the card nor dismiss the menu.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }

        ColumnLayout {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 2

            SectionLabel { text: Translation.tr("Material") }

            // Solid vs translucent. Solid keeps a faint tint so the card still
            // belongs to the wallpaper's palette rather than becoming a grey box.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                Layout.bottomMargin: 2
                spacing: 4

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

            // Opacity of the card's base layer. Named "Opacity" rather than
            // "baseOpacity" — the tint on top is not something to expose twice.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                spacing: 8

                StyledText {
                    text: Translation.tr("Opacity")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
                StyledSlider {
                    Layout.fillWidth: true
                    value: root.config.baseOpacity
                    stopIndicatorValues: []
                    onMoved: root.config.baseOpacity = Math.max(0.05, Math.min(1, value))
                }
                StyledText {
                    Layout.minimumWidth: 32
                    horizontalAlignment: Text.AlignRight
                    text: `${Math.round(root.config.baseOpacity * 100)}%`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                }
            }

            MenuSeparator {}
            SectionLabel { text: Translation.tr("List") }

            MenuRow {
                symbol: "expand_all"
                label: root.config.showCompleted
                    ? Translation.tr("Hide completed") : Translation.tr("Show completed")
                onTriggered: {
                    root.config.showCompleted = !root.config.showCompleted;
                    root.requestClose();
                }
            }

            MenuRow {
                symbol: "remove_done"
                label: Translation.tr("Clear completed")
                detail: `${Todo.completed.length}`
                enabled: Todo.completed.length > 0
                destructive: true
                armedKey: "clearDone"
                onTriggered: { Todo.clearCompleted(); root.requestClose(); }
            }

            MenuRow {
                symbol: "delete_sweep"
                label: Translation.tr("Clear all tasks")
                detail: `${Todo.list.length}`
                enabled: Todo.list.length > 0
                destructive: true
                armedKey: "clearAll"
                onTriggered: { Todo.clearAll(); root.requestClose(); }
            }

            MenuSeparator {}
            SectionLabel { text: Translation.tr("Widget") }

            MenuRow {
                symbol: "aspect_ratio"
                label: Translation.tr("Reset size")
                onTriggered: {
                    root.config.width = 320;
                    root.config.listHeight = 0;
                    root.requestClose();
                }
            }

            MenuRow {
                symbol: "restart_alt"
                label: Translation.tr("Reset position")
                onTriggered: {
                    root.config.x = 1400;
                    root.config.y = 120;
                    root.requestClose();
                }
            }

            MenuRow {
                symbol: "visibility_off"
                label: Translation.tr("Hide widget")
                destructive: true
                armedKey: "hide"
                onTriggered: { root.config.enable = false; root.requestClose(); }
            }
        }
    }

    // ── Building blocks ──────────────────────────────────────────
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
        property string detail: ""
        property bool destructive: false
        property string armedKey: ""
        signal triggered()

        readonly property bool isArmed: row.destructive && root.armed === row.armedKey

        Layout.fillWidth: true
        implicitHeight: 32
        hoverEnabled: true
        enabled: true
        cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        opacity: row.enabled ? 1 : 0.4

        // Destructive rows arm on the first click and fire on the second, so a
        // stray click can never wipe the list outright.
        onClicked: {
            if (!row.enabled) return;
            if (row.destructive && !row.isArmed) { root.armed = row.armedKey; return; }
            row.triggered();
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: Appearance.rounding.verysmall
            color: row.isArmed ? Appearance.m3colors.m3errorContainer
                : row.containsMouse && row.enabled ? Appearance.colors.colLayer1Hover
                : "transparent"

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
                text: row.isArmed ? "warning" : row.symbol
                iconSize: 17
                color: row.isArmed ? Appearance.m3colors.m3onErrorContainer
                    : row.destructive && row.containsMouse ? Appearance.m3colors.m3error
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
            StyledText {
                visible: row.detail.length > 0 && !row.isArmed
                text: row.detail
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
            }
        }
    }
}
