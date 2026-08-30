pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.desktopWidgets
import QtQuick
import QtQuick.Layouts

/**
 * The desktop todo widget.
 *
 * macOS Reminders anatomy — count-led header, accent list name, hairline rule,
 * hollow circle checkboxes, 40px row rhythm, 16px content margin, concentric
 * corner radii — rendered entirely from Appearance tokens so it retints with
 * the wallpaper instead of pinning a palette.
 *
 * Everything that is not the face — frost, dragging, resizing, snapping,
 * position persistence, menu placement — comes from DesktopWidget.
 */
DesktopWidget {
    id: root

    widgetId: "todo"
    config: Config.options.background.widgets.todo

    minWidth: root.config.minWidth
    maxWidth: root.config.maxWidth
    maxVertical: 900

    // The board keeps asking for keys while a field holds focus.
    inputActive: addField.activeFocus || root.pickerTask !== null

    readonly property var unfinished: Todo.unfinished
    readonly property var completed: Todo.completed

    property var pickerTask: null
    property bool completedExpanded: false

    // Resizing vertically changes the height of the SCROLLABLE task area, not
    // the whole card. The header, Completed section and add-row keep their
    // natural size, so the card grows by exactly what you dragged and never
    // fights the content-driven height binding (which is what collapsed it to
    // zero the first time round).
    //
    // An empty list has no rows, so fall back to a sensible block for the
    // centred empty state rather than collapsing the area to nothing.
    readonly property real naturalListHeight: root.unfinished.length > 0
        ? taskColumn.implicitHeight
        : 130
    // `contentHeight` is the container's generic vertical size; `listHeight` is
    // what this used to be called, kept as a fallback so an existing config
    // keeps the size the user already chose.
    readonly property real storedListHeight: root.verticalSize > 0
        ? root.verticalSize
        : (root.config.listHeight ?? 0)
    readonly property real effectiveListHeight: root.storedListHeight > 0
        ? Math.max(40, root.storedListHeight)
        : root.naturalListHeight

    function startTask(task) {
        root.pickerTask = task;
    }

    menuComponent: Component { TodoMenu {} }

    // ── Face ──────────────────────────────────────────────────────
    ColumnLayout {
        id: contentColumn
        // Width from the container's content slot; height is this layout's own
        // implicitHeight, which the card sizes itself from. Never anchor this
        // to a bottom edge.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // ── Header ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: `${root.unfinished.length}`
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.config.listName
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colPrimary
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 30
                implicitHeight: 30
                radius: width / 2
                color: Appearance.colors.colPrimary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "checklist"
                    iconSize: 17
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 13
            Layout.bottomMargin: 5
            implicitHeight: 1
            color: Appearance.m3colors.m3outlineVariant
        }

        // ── Unfinished ────────────────────────────────────────────
        // One area that holds either the rows or the empty state. The empty
        // state lives INSIDE it and centres, because sitting it after the list
        // in the column parked it at the bottom of a tall card with a wall of
        // dead space above.
        Item {
            id: listArea
            Layout.fillWidth: true
            implicitHeight: root.effectiveListHeight

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                spacing: 10
                visible: root.unfinished.length === 0

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.completed.length > 0 ? "task_alt" : "checklist"
                    iconSize: 34
                    fill: root.completed.length > 0 ? 1 : 0
                    color: Appearance.colors.colPrimary
                    opacity: 0.55
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.completed.length > 0
                        ? Translation.tr("All done")
                        : Translation.tr("Nothing here yet")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.completed.length > 0
                        ? Translation.tr("%1 finished today").arg(root.completed.length)
                        : Translation.tr("Add one below to get started")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }

            Flickable {
                anchors.fill: parent
                visible: root.unfinished.length > 0
                contentHeight: taskColumn.implicitHeight
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 6000

                ColumnLayout {
                    id: taskColumn
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.unfinished
                        delegate: TodoRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            item: modelData
                            position: index + 1
                            onToggleRequested: Todo.toggleDoneById(modelData.id)
                            onDeleteRequested: Todo.deleteById(modelData.id)
                            onStartRequested: root.startTask(modelData)
                            onMenuRequested: {
                                root.menuPos = Qt.point(root.width / 2, 60);
                                root.menuOpen = true;
                            }
                        }
                    }
                }
            }

            // Fades the cut-off row so a clipped list reads as scrollable
            // rather than as a rendering glitch.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 18
                visible: root.unfinished.length > 0
                    && taskColumn.implicitHeight > listArea.height
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(Appearance.colors.colLayer0.r,
                                       Appearance.colors.colLayer0.g,
                                       Appearance.colors.colLayer0.b, 0.55)
                    }
                }
            }
        }

        // ── Completed ─────────────────────────────────────────────
        MouseArea {
            Layout.fillWidth: true
            implicitHeight: 30
            visible: root.config.showCompleted && root.completed.length > 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.completedExpanded = !root.completedExpanded

            RowLayout {
                anchors.fill: parent
                spacing: 6

                StyledText {
                    text: Translation.tr("Completed")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: `${root.completed.length}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    text: root.completedExpanded ? "expand_less" : "expand_more"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Repeater {
            model: root.completedExpanded ? root.completed : []
            delegate: TodoRow {
                required property var modelData
                Layout.fillWidth: true
                item: modelData
                onToggleRequested: Todo.toggleDoneById(modelData.id)
                onDeleteRequested: Todo.deleteById(modelData.id)
            }
        }

        // ── Undo ──────────────────────────────────────────────────
        // Any removal is recoverable for a while. A task list that can lose
        // work to one click is not one you can trust with real work.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Todo.canUndo ? 6 : 0
            implicitHeight: Todo.canUndo ? 34 : 0
            visible: implicitHeight > 0
            clip: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 8

                MaterialSymbol {
                    text: "history"
                    iconSize: 15
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Todo.undoLabel
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
                Rectangle {
                    implicitWidth: undoText.implicitWidth + 18
                    implicitHeight: 24
                    radius: Appearance.rounding.verysmall
                    color: undoArea.containsMouse
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colPrimaryContainer

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    StyledText {
                        id: undoText
                        anchors.centerIn: parent
                        text: Translation.tr("Undo")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: undoArea.containsMouse
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnPrimaryContainer
                    }

                    MouseArea {
                        id: undoArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Todo.undoLast()
                    }
                }
            }
        }

        // ── Add a task ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: 38
            spacing: 11

            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: addField.activeFocus
                    ? Appearance.colors.colPrimary
                    : Appearance.m3colors.m3outline

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: 14
                    color: addField.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.m3colors.m3outline
                }
            }

            StyledTextInput {
                id: addField
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1

                onAccepted: {
                    Todo.addTask(text);
                    text = "";
                }
                Keys.onEscapePressed: {
                    text = "";
                    focus = false;
                    root.dismissed();
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    visible: addField.text.length === 0
                    text: Translation.tr("Add a task…")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Duration picker ───────────────────────────────────────────
    // Full-bleed, so it goes in the overlay slot rather than the padded content.
    overlayData: Rectangle {
        anchors.fill: parent
        radius: root.cardRadius
        visible: root.pickerTask !== null
        color: Qt.rgba(
            Appearance.colors.colLayer0.r,
            Appearance.colors.colLayer0.g,
            Appearance.colors.colLayer0.b,
            0.94)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Clicking off the picker cancels rather than silently swallowing the
        // click. Swallowing it made the picker a dead end: no button, and
        // Escape only works if the surface happens to hold keyboard focus.
        MouseArea {
            anchors.fill: parent
            onClicked: root.pickerTask = null
        }

        DurationPicker {
            anchors.centerIn: parent
            width: parent.width
            task: root.pickerTask
            focus: root.pickerTask !== null
            onAccepted: seconds => {
                FocusTimer.start(root.pickerTask.id, root.pickerTask.content, seconds);
                root.pickerTask = null;
            }
            onCancelled: {
                root.pickerTask = null;
                root.dismissed();
            }
        }
    }
}
