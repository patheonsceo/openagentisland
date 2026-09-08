pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

/**
 * Idle inhibition.
 *
 * Two independent sources feed the single Wayland idle inhibitor:
 *   - manualInhibit: the "Keep awake" (coffee) toggle, remembered across shell restarts
 *   - acInhibit:     the "Awake on AC" policy — while plugged in, never idle at all
 *
 * While the inhibitor is on, Hyprland stops reporting idle, so hypridle never
 * locks the session, never blanks the screen and never suspends.
 */
Singleton {
    id: root

    // Manual override (coffee toggle)
    property bool manualInhibit: false

    // AC policy
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property bool onAc: !UPower.onBattery
    readonly property bool keepAwakeWhenPluggedIn: Config.options?.battery?.keepAwakeWhenPluggedIn ?? false
    readonly property bool acInhibit: root.keepAwakeWhenPluggedIn && root.hasBattery && root.onAc

    property alias inhibit: idleInhibitor.enabled
    inhibit: root.manualInhibit || root.acInhibit

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.manualInhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.manualInhibit;
            }
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.manualInhibit = active;
        } else {
            root.manualInhibit = !root.manualInhibit;
        }
        Persistent.states.idle.inhibit = root.manualInhibit;
    }

    function toggleKeepAwakeWhenPluggedIn(active = null) {
        Config.options.battery.keepAwakeWhenPluggedIn = (active !== null) ? active : !root.keepAwakeWhenPluggedIn;
    }

    // Called from shell.qml so the singleton (and its inhibitor) exists from startup,
    // not only once some panel happens to reference it.
    function load() {}

    // `qs -c openagentisland ipc call idle status`
    IpcHandler {
        target: "idle"

        function status(): string {
            return JSON.stringify({
                inhibited: root.inhibit,
                manual: root.manualInhibit,
                keepAwakeWhenPluggedIn: root.keepAwakeWhenPluggedIn,
                hasBattery: root.hasBattery,
                onAc: root.onAc,
                acInhibit: root.acInhibit
            });
        }
        function toggleAc(): string {
            root.toggleKeepAwakeWhenPluggedIn();
            return root.keepAwakeWhenPluggedIn ? "on" : "off";
        }
    }

    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
