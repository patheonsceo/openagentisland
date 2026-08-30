pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * macOS-style hot corners.
 *
 * A small hover target in each screen corner that fires a configured action.
 * A corner set to "none" gets NO input region at all, rather than an inert one
 * — the top corners sit under the menubar's app name and the Control Centre
 * button, and an invisible catcher there would swallow clicks meant for them.
 *
 * Every corner also has to be dwelled on rather than merely touched. Pointers
 * cross corners constantly on the way to somewhere else, and a hot corner that
 * fires on contact is a hot corner you turn off within a day.
 */
Scope {
    id: root

    readonly property var cfg: Config.options?.hotCorners
    readonly property bool enabled: root.cfg?.enable ?? false
    readonly property int size: root.cfg?.size ?? 6
    readonly property int dwell: root.cfg?.dwellMs ?? 260

    function actionFor(corner) {
        switch (corner) {
        case "topLeft": return root.cfg?.topLeft ?? "none";
        case "topRight": return root.cfg?.topRight ?? "none";
        case "bottomLeft": return root.cfg?.bottomLeft ?? "none";
        case "bottomRight": return root.cfg?.bottomRight ?? "none";
        }
        return "none";
    }

    function trigger(action) {
        switch (action) {
        case "overview":
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            break;
        case "search":
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
            break;
        case "notifications":
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            break;
        case "sidebarLeft":
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
            break;
        case "lock":
            Quickshell.execDetached(["loginctl", "lock-session"]);
            break;
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            Corner { corner: "topLeft" }
            Corner { corner: "topRight" }
            Corner { corner: "bottomLeft" }
            Corner { corner: "bottomRight" }

            component Corner: PanelWindow {
                id: win
                required property string corner
                readonly property string action: root.actionFor(win.corner)

                screen: screenScope.modelData
                // A corner with nothing assigned is not created at all.
                visible: Config.ready && root.enabled && win.action !== "none"
                    && !GlobalStates.screenLocked

                WlrLayershell.namespace: `quickshell:hotCorner:${win.corner}`
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                implicitWidth: root.size
                implicitHeight: root.size

                anchors {
                    top: win.corner === "topLeft" || win.corner === "topRight"
                    bottom: win.corner === "bottomLeft" || win.corner === "bottomRight"
                    left: win.corner === "topLeft" || win.corner === "bottomLeft"
                    right: win.corner === "topRight" || win.corner === "bottomRight"
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    // Hover only. Accepting buttons here would eat a click in
                    // the corner, and the corner is not a button.
                    acceptedButtons: Qt.NoButton
                    onEntered: dwellTimer.restart()
                    onExited: dwellTimer.stop()

                    Timer {
                        id: dwellTimer
                        interval: root.dwell
                        onTriggered: root.trigger(win.action)
                    }
                }
            }
        }
    }
}
