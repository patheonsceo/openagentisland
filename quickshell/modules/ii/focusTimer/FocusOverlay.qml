pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The running focus session, in its two states.
 *
 * Maximised is a full-screen take-over on the overlay layer, so it covers
 * fullscreen apps too — the point of a focus screen is that you cannot ignore
 * it. Minimised is a small draggable pill, also on the overlay layer so it
 * survives whatever you put in front of it.
 *
 * Both are driven entirely off the FocusTimer singleton, so a shell reload
 * mid-session rebuilds them against the same wall-clock state.
 */
Scope {
    id: root

    // Only the focused monitor gets the take-over; the pill likewise. Showing
    // either on all three would be three countdowns of the same session.
    // Pinned to the monitor the session started on. Binding straight to
    // Hyprland.focusedMonitor meant the overlay hopped displays every time the
    // cursor did, which is the opposite of what a focus timer is for.
    readonly property string pinnedScreenName: Persistent.states.timer.focus.screenName ?? ""

    readonly property string activeScreenName: {
        const pinned = root.pinnedScreenName;
        // Fall back if that monitor has since been unplugged, or the overlay
        // would have nowhere to live.
        if (pinned.length > 0 && Quickshell.screens.some(s => s.name === pinned))
            return pinned;
        return Hyprland.focusedMonitor?.name ?? "";
    }

    function pinCurrentScreen() {
        if (!FocusTimer.active) return;
        if ((Persistent.states.timer.focus.screenName ?? "").length > 0) return;
        Persistent.states.timer.focus.screenName = Hyprland.focusedMonitor?.name ?? "";
    }

    // Pin when a session starts, and also at startup — the countdown is
    // wall-clock based and survives a shell reload, so it can already be
    // running with nothing pinned yet.
    Connections {
        target: FocusTimer
        function onActiveChanged() { root.pinCurrentScreen(); }
    }
    Component.onCompleted: root.pinCurrentScreen()


    // ── Maximised ────────────────────────────────────────────────
    LazyLoader {
        active: FocusTimer.active && !FocusTimer.minimized

        component: PanelWindow {
            id: focusWindow
            screen: Quickshell.screens.find(s => s.name === root.activeScreenName) ?? null
            visible: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:focusTimer"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Keys.onEscapePressed: FocusTimer.setMinimized(true)

            Rectangle {
                id: scrim
                anchors.fill: parent
                // Opaque enough on its own — there is no compositor blur here to
                // help, so the scrim has to do all the work of quieting whatever
                // is behind it.
                color: Qt.rgba(
                    Appearance.colors.colLayer0.r,
                    Appearance.colors.colLayer0.g,
                    Appearance.colors.colLayer0.b,
                    0.93)

                // Clicking the backdrop minimises rather than cancels — losing a
                // running session to a stray click would be hostile.
                MouseArea {
                    anchors.fill: parent
                    onClicked: FocusTimer.setMinimized(true)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: focusWindow.width * 0.6
                        Layout.bottomMargin: 26
                        text: FocusTimer.taskContent
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 30
                        implicitWidth: 216
                        implicitHeight: 216

                        CircularProgress {
                            anchors.centerIn: parent
                            implicitSize: 216
                            lineWidth: 9
                            value: FocusTimer.progress
                            colPrimary: Appearance.colors.colPrimary
                            colSecondary: Qt.rgba(1, 1, 1, 0.13)
                            enableAnimation: false
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: FocusTimer.formatDuration(FocusTimer.secondsLeft)
                            font.pixelSize: 44
                            font.family: Appearance.font.family.monospace
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 11

                        FocusButton {
                            symbol: FocusTimer.running ? "pause" : "play_arrow"
                            label: FocusTimer.running ? Translation.tr("Pause") : Translation.tr("Resume")
                            onTriggered: FocusTimer.toggle()
                        }
                        FocusButton {
                            symbol: "check"
                            label: Translation.tr("Done")
                            primary: true
                            onTriggered: FocusTimer.complete()
                        }
                        FocusButton {
                            symbol: "remove"
                            label: Translation.tr("Minimise")
                            onTriggered: FocusTimer.setMinimized(true)
                        }
                        FocusButton {
                            symbol: "close"
                            label: Translation.tr("Stop")
                            onTriggered: FocusTimer.stop()
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 34
                        text: {
                            const item = Todo.getById(FocusTimer.taskId);
                            const logged = Todo.totalSeconds(item);
                            const count = (item?.sessions?.length ?? 0) + 1;
                            return logged > 0
                                ? Translation.tr("Session %1 · %2 logged on this task")
                                    .arg(count).arg(FocusTimer.formatLogged(logged))
                                : Translation.tr("Session %1").arg(count);
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.m3colors.m3outline
                    }
                }
            }
        }
    }

    // ── Minimised ────────────────────────────────────────────────
    LazyLoader {
        active: FocusTimer.active && FocusTimer.minimized

        component: PanelWindow {
            id: pillWindow
            screen: Quickshell.screens.find(s => s.name === root.activeScreenName) ?? null
            visible: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:focusPill"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Only the pill itself eats clicks; the rest of the screen is untouched.
            mask: Region { item: pill }

            Rectangle {
                id: pill
                x: Math.max(0, Math.min(Persistent.states.timer.focus.pillX, pillWindow.width - width))
                y: Math.max(0, Math.min(Persistent.states.timer.focus.pillY, pillWindow.height - height))
                implicitWidth: pillRow.implicitWidth + 26
                implicitHeight: 42
                radius: Appearance.rounding.full
                // Opaque, not glass. The pill floats over whatever window you are
                // working in, so a wallpaper-sampled frost would show the wrong
                // thing entirely, and compositor blur is unavailable here.
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                MouseArea {
                    anchors.fill: parent
                    cursorShape: containsPress ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: pill
                    drag.axis: Drag.XAndYAxis
                    onReleased: {
                        Persistent.states.timer.focus.pillX = Math.round(pill.x);
                        Persistent.states.timer.focus.pillY = Math.round(pill.y);
                    }
                }

                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 10

                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: Appearance.colors.colPrimary
                        opacity: FocusTimer.running ? 1 : 0.35

                        SequentialAnimation on opacity {
                            running: FocusTimer.running
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 1200; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutQuad }
                        }
                    }

                    StyledText {
                        text: FocusTimer.formatDuration(FocusTimer.secondsLeft)
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.monospace
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.maximumWidth: 150
                        text: FocusTimer.taskContent
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    PillButton {
                        symbol: FocusTimer.running ? "pause" : "play_arrow"
                        onTriggered: FocusTimer.toggle()
                    }
                    PillButton {
                        symbol: "open_in_full"
                        onTriggered: FocusTimer.setMinimized(false)
                    }
                }
            }
        }
    }

    // ── Shared button types ──────────────────────────────────────
    component FocusButton: Rectangle {
        id: focusButton
        required property string symbol
        required property string label
        property bool primary: false
        signal triggered()

        implicitWidth: buttonRow.implicitWidth + 42
        implicitHeight: 44
        radius: Appearance.rounding.full
        color: focusButton.primary
            ? (buttonArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
            : (buttonArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
        border.width: focusButton.primary ? 0 : 1
        border.color: Appearance.colors.colLayer0Border

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                text: focusButton.symbol
                iconSize: 18
                color: focusButton.primary
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: focusButton.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: focusButton.primary
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer2
            }
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: focusButton.triggered()
        }
    }

    component PillButton: Rectangle {
        id: pillButton
        required property string symbol
        signal triggered()

        implicitWidth: 24
        implicitHeight: 24
        radius: width / 2
        color: pillButtonArea.containsMouse
            ? Appearance.colors.colPrimary
            : Qt.rgba(1, 1, 1, 0.13)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: pillButton.symbol
            iconSize: 14
            color: pillButtonArea.containsMouse
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnLayer0
        }

        MouseArea {
            id: pillButtonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pillButton.triggered()
        }
    }
}
