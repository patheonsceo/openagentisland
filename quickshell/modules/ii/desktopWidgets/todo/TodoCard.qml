import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
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
 * The frost is drawn in QML rather than by the compositor — see
 * FrostedBackdrop for why that turned out to be necessary here.
 */
Item {
    id: root

    readonly property var config: Config.options.background.widgets.todo
    readonly property var unfinished: Todo.unfinished
    readonly property var completed: Todo.completed
    readonly property real padding: 16
    readonly property real cardRadius: 22

    // The host window raises keyboard focus only while we actually need typing.
    readonly property bool inputActive: addField.activeFocus || root.pickerTask !== null

    // Needed to lay the frost's wallpaper copy out exactly as the real one.
    property int screenWidth: 1920
    property int screenHeight: 1080

    property bool menuOpen: false
    property point menuPos: Qt.point(0, 0)

    property var pickerTask: null
    property bool completedExpanded: false

    // Size is driven bottom-up from the content, once: content column sizes
    // itself from its children, the card takes that plus padding. Anchoring the
    // column to fill the card instead would put height on both sides of the same
    // binding and QML would resolve it to zero.
    implicitWidth: root.config.width
    implicitHeight: contentColumn.implicitHeight + root.padding * 2

    // Resizing vertically changes the height of the SCROLLABLE task area, not
    // the whole card. The header, Completed section and add-row keep their
    // natural size, so the card grows exactly by what you dragged and never
    // fights the content-driven height binding above (which is what collapsed
    // it to zero the first time round).
    // An empty list has no rows, so fall back to a sensible block for the
    // centred empty state rather than collapsing the area to nothing.
    readonly property real naturalListHeight: root.unfinished.length > 0
        ? taskColumn.implicitHeight
        : 130
    readonly property bool listIsClamped: root.config.listHeight > 0
    readonly property real effectiveListHeight: root.listIsClamped
        ? Math.max(40, root.config.listHeight)
        : root.naturalListHeight

    function startTask(task) {
        root.pickerTask = task;
    }


    // Frosted glass, drawn in QML. See FrostedBackdrop for why not the compositor.
    FrostedBackdrop {
        anchors.fill: parent
        radius: root.cardRadius
        surfaceX: root.x
        surfaceY: root.y
        screenWidth: root.screenWidth
        screenHeight: root.screenHeight
        tintOpacity: root.config.tintOpacity
        baseOpacity: root.config.baseOpacity
        blurMax: root.config.blurRadius
        solid: root.config.solidMaterial
    }

    Rectangle {
        id: cardBackground
        anchors.fill: parent
        radius: root.cardRadius
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Dragging happens from the header strip, like a titlebar. Rows own their
        // own mouse areas, so making the whole card draggable would fight with
        // checkbox and start clicks. Sits behind the content, not inside the
        // layout — anchors on a layout-managed item are undefined behaviour.
        MouseArea {
            id: dragArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 56
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: containsPress ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            // Left drags, right opens settings. Rows keep their own right-click
            // (delete), so the menu lives on the header strip rather than the
            // whole card.
            drag.target: pressedButtons & Qt.LeftButton ? root : null
            drag.axis: Drag.XAndYAxis
            onPressed: mouse => {
                if (mouse.button !== Qt.RightButton) return;
                root.menuPos = Qt.point(mouse.x, mouse.y);
                root.menuOpen = true;
            }
            onReleased: {
                root.config.x = Math.round(root.x);
                root.config.y = Math.round(root.y);
            }
        }

        ColumnLayout {
            id: contentColumn
            // Left/right/top only. No bottom anchor, so height stays the layout's
            // own implicitHeight and the card can size itself from it.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padding
            spacing: 0

            // ── Header ────────────────────────────────────────────
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

            // ── Unfinished ────────────────────────────────────────
            // One area that either holds the rows or the empty state. The empty
            // state lives INSIDE it and centres, because sitting it after the
            // list in the column parked it at the bottom of a tall card with a
            // wall of dead space above.
            Item {
                id: listArea
                Layout.fillWidth: true
                implicitHeight: root.effectiveListHeight

                // ── Empty state ───────────────────────────────
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
                                Layout.fillWidth: true
                                item: modelData
                                onToggleRequested: Todo.toggleDoneById(modelData.id)
                                onDeleteRequested: Todo.deleteById(modelData.id)
                                onStartRequested: root.startTask(modelData)
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

            // ── Completed ─────────────────────────────────────────
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

            // ── Add a task ────────────────────────────────────────
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
    }


        // ── Resize grips ──────────────────────────────────────────
        // Siblings of the content, declared after it so they sit on top of the
        // rows without the rows' own mouse areas swallowing the drag.
        //
        // Deltas are measured in GLOBAL coordinates. A grip's local mouse x/y
        // shift as the card resizes underneath it, which feeds the resize back
        // into its own input and makes the card judder — the same trap the dock
        // magnification fell into.
        ResizeGrip { edge: "right" }
        ResizeGrip { edge: "bottom" }
        ResizeGrip { edge: "corner" }

    // ── Settings menu ─────────────────────────────────────────────
    // Click-away catcher, only alive while the menu is. Sized to the whole
    // surface so a click anywhere outside dismisses it.
    MouseArea {
        parent: root.parent
        anchors.fill: parent
        visible: root.menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 90
        onClicked: root.menuOpen = false
    }

    TodoMenu {
        id: settingsMenu
        open: root.menuOpen
        z: 100
        // Kept inside the card's surface: flip to the other side when the menu
        // would run off the bottom or right of the screen.
        x: Math.min(root.menuPos.x, root.screenWidth - root.x - width - 8)
        y: root.menuPos.y + height + root.y > root.screenHeight
            ? root.menuPos.y - height
            : root.menuPos.y
        onRequestClose: root.menuOpen = false
    }

    // ── Duration picker ───────────────────────────────────────────
    Rectangle {
        anchors.fill: cardBackground
        radius: root.cardRadius
        visible: root.pickerTask !== null
        color: Qt.rgba(
            Appearance.colors.colLayer0.r,
            Appearance.colors.colLayer0.g,
            Appearance.colors.colLayer0.b,
            0.94)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Swallow clicks so they don't reach the card underneath.
        MouseArea { anchors.fill: parent }

        DurationPicker {
            anchors.centerIn: parent
            width: parent.width
            task: root.pickerTask
            focus: root.pickerTask !== null
            onAccepted: seconds => {
                FocusTimer.start(root.pickerTask.id, root.pickerTask.content, seconds);
                root.pickerTask = null;
            }
            onCancelled: root.pickerTask = null
        }
    }

    // One resize handle. `edge` picks which dimensions it drives and where it
    // sits; everything else is shared.
    component ResizeGrip: MouseArea {
        id: grip
        required property string edge
        readonly property int thickness: 10

        parent: cardBackground
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        z: 50

        anchors.right: grip.edge !== "bottom" ? parent.right : undefined
        anchors.left: grip.edge === "bottom" ? parent.left : undefined
        anchors.bottom: grip.edge !== "right" ? parent.bottom : undefined
        anchors.top: grip.edge === "right" ? parent.top : undefined
        anchors.bottomMargin: grip.edge === "right" ? grip.thickness : 0
        anchors.rightMargin: grip.edge === "bottom" ? grip.thickness : 0

        implicitWidth: grip.edge === "bottom" ? 0 : grip.thickness
        implicitHeight: grip.edge === "right" ? 0 : grip.thickness
        width: grip.edge === "bottom" ? parent.width - grip.thickness : grip.thickness
        height: grip.edge === "right" ? parent.height - grip.thickness : grip.thickness

        cursorShape: grip.edge === "right" ? Qt.SizeHorCursor
            : grip.edge === "bottom" ? Qt.SizeVerCursor
            : Qt.SizeFDiagCursor

        property real startWidth: 0
        property real startList: 0
        property point startGlobal: Qt.point(0, 0)

        onPressed: mouse => {
            grip.startWidth = root.width;
            grip.startList = root.effectiveListHeight;
            grip.startGlobal = grip.mapToGlobal(mouse.x, mouse.y);
        }

        onPositionChanged: mouse => {
            if (!grip.pressed) return;
            const now = grip.mapToGlobal(mouse.x, mouse.y);
            const dx = now.x - grip.startGlobal.x;
            const dy = now.y - grip.startGlobal.y;

            if (grip.edge !== "bottom") {
                root.config.width = Math.max(root.config.minWidth,
                    Math.min(root.config.maxWidth, grip.startWidth + dx));
            }
            if (grip.edge !== "right") {
                root.config.listHeight = Math.max(40,
                    Math.min(900, grip.startList + dy));
            }
        }

        onReleased: {
            root.config.width = Math.round(root.config.width);
            root.config.listHeight = Math.round(root.config.listHeight);
        }

        // Corner gets a visible grip; the edges stay invisible so the card keeps
        // its clean silhouette until you actually reach for them.
        MaterialSymbol {
            visible: grip.edge === "corner"
            anchors.centerIn: parent
            text: "drag_handle"
            rotation: -45
            iconSize: 12
            color: Appearance.colors.colSubtext
            opacity: grip.containsMouse || grip.pressed ? 0.9 : 0.28
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

}
