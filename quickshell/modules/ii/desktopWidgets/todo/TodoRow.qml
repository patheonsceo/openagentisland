import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * One task row in the desktop todo card.
 *
 * Anatomy follows the macOS Reminders widget: a hollow circle that fills on
 * completion, a single-line label that truncates rather than wraps so the card
 * height stays predictable, and a start affordance that only appears on hover
 * so the resting state stays quiet.
 */
Item {
    id: root

    required property var item
    // 1-based position in the list. -1 hides the number entirely, which is what
    // the Completed section wants — a finished task has no queue position.
    property int position: -1
    property bool compact: false
    readonly property bool done: root.item?.done ?? false
    readonly property bool isRunning: FocusTimer.active && FocusTimer.taskId === (root.item?.id ?? "")

    signal toggleRequested()
    signal startRequested()
    signal deleteRequested()

    // Height only. Width comes from Layout.fillWidth on the delegate — deriving
    // it from parent.width inside a layout is a binding loop, and the layout
    // resolves it by giving up and handing back zero.
    implicitHeight: 40

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton) root.deleteRequested();
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -5
            anchors.rightMargin: -5
            radius: Appearance.rounding.small
            color: rowArea.containsMouse
                ? Appearance.colors.colLayer1Hover
                : "transparent"
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 11

            // Reads as a numbered list at rest; the checkbox only appears when
            // you reach for it. A row of empty circles is a form to fill in — a
            // numbered list is something you have already decided to do.
            //
            // Both occupy the same 20px slot and cross-fade, so nothing shifts
            // sideways on hover.
            Item {
                id: marker
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 20
                implicitHeight: 20

                // Once done, the tick stays put — a completed row should not
                // fall back to showing a queue number.
                readonly property bool showCheckbox: root.done
                    || rowArea.containsMouse
                    || checkArea.containsMouse
                    || root.position < 0

                StyledText {
                    anchors.centerIn: parent
                    text: `${root.position}`
                    visible: opacity > 0
                    opacity: marker.showCheckbox ? 0 : 1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                Rectangle {
                    id: checkbox
                    anchors.fill: parent
                    radius: width / 2
                    visible: opacity > 0
                    opacity: marker.showCheckbox ? 1 : 0
                    scale: marker.showCheckbox ? 1 : 0.7
                    color: root.done ? Appearance.colors.colPrimary : "transparent"
                    border.width: 2
                    border.color: root.done
                        ? Appearance.colors.colPrimary
                        : (checkArea.containsMouse
                            ? Appearance.colors.colPrimary
                            : Appearance.m3colors.m3outline)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on border.color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 14
                        fill: 1
                        color: Appearance.colors.colOnPrimary
                        opacity: root.done ? 1 : 0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }

                MouseArea {
                    id: checkArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleRequested()
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.item?.content ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.done
                    ? Appearance.colors.colOnLayer1Inactive
                    : Appearance.colors.colOnLayer1
                elide: Text.ElideRight
                maximumLineCount: 1
                font.strikeout: root.done
            }

            // Remembered duration, shown only when the task has one.
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: !root.done && !root.isRunning && (root.item?.lastDuration ?? 0) > 0
                text: FocusTimer.formatLogged(root.item?.lastDuration ?? 0)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
            }

            // Live countdown replaces the start button while this task is running.
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.isRunning
                text: FocusTimer.formatDuration(FocusTimer.secondsLeft)
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colPrimary
            }

            Rectangle {
                id: startButton
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26
                radius: width / 2
                visible: !root.done && !root.isRunning
                color: startArea.containsMouse
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colPrimary
                opacity: rowArea.containsMouse || startArea.containsMouse ? 1 : 0
                scale: opacity < 1 ? 0.82 : 1

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    iconSize: 16
                    fill: 1
                    color: Appearance.colors.colOnPrimary
                }

                MouseArea {
                    id: startArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: startButton.visible
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startRequested()
                }
            }
        }
    }
}
