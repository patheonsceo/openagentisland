pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import Quickshell.Io

Singleton {
    id: root
    property bool available: UPower.displayDevice.isLaptopBattery
    property var chargeState: UPower.displayDevice.state
    property bool isCharging: chargeState == UPowerDeviceState.Charging
    property bool isPluggedIn: isCharging || chargeState == UPowerDeviceState.PendingCharge
    property real percentage: UPower.displayDevice?.percentage ?? 1
    readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend
    readonly property bool soundEnabled: Config.options.sounds.battery

    property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
    property bool isFull: available && (percentage >= Config.options.battery.full / 100)

    property bool isLowAndNotCharging: isLow && !isCharging
    property bool isCriticalAndNotCharging: isCritical && !isCharging
    property bool isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && !isCharging
    property bool isFullAndCharging: isFull && isCharging

    // ── Automatic power profile ───────────────────────────────────
    readonly property var autoProfileCfg: Config.options?.battery?.autoProfile

    // Set through powerprofilesctl rather than PowerProfiles.profile.
    // Quickshell's DBus property was observed reporting Balanced(1) while the
    // daemon itself reported power-saver, so comparing against it skipped the
    // write every time and the profile never actually changed.
    function profileCliName(name) {
        switch (name) {
        case "performance": return "performance";
        case "powerSaver": return "power-saver";
        case "balanced": return "balanced";
        default: return "power-saver";
        }
    }

    function applyAutoProfile() {
        if (!(root.autoProfileCfg?.enable ?? false)) return;
        if (!root.available) return;
        const want = root.profileCliName(root.runningOnBattery
            ? (root.autoProfileCfg?.onBattery ?? "powerSaver")
            : (root.autoProfileCfg?.onAc ?? "balanced"));
        // Written unconditionally: setting the profile it is already on is a
        // no-op for the daemon, and it is the only way to be sure.
        Quickshell.execDetached(["powerprofilesctl", "set", want]);
    }

    // NOT applied straight from Component.onCompleted. UPower has not populated
    // its adapter state that early, so the first read says "on battery" even on
    // mains — which parked this machine in power-saver while plugged in, and
    // then never corrected itself because no plug/unplug transition followed.
    Timer {
        id: initialProfileTimer
        interval: 4000
        running: root.autoProfileCfg?.applyOnStart ?? true
        repeat: false
        onTriggered: root.applyAutoProfile()
    }

    property real energyRate: UPower.displayDevice.changeRate

    // ── Smoothed time remaining ───────────────────────────────────
    // UPower's timeToEmpty is derived from the instantaneous draw, so it
    // swings with whatever the CPU did in the last second — measured here it
    // ranged 12W to 29W inside seventy seconds, which is the difference
    // between "3.8 hours left" and "1.6 hours left". A number that halves
    // while you look at it is worse than no number, so this averages the draw
    // over a couple of minutes before dividing.
    readonly property real energyNow: UPower.displayDevice.energy
    property var rateSamples: []
    readonly property int rateWindow: 12          // samples, at 10s each

    readonly property real smoothedRate: {
        const s = root.rateSamples;
        if (s.length === 0) return 0;
        return s.reduce((a, b) => a + b, 0) / s.length;
    }

    // Seconds until empty at the averaged draw. 0 when it cannot be known:
    // charging, or not enough samples collected yet to mean anything.
    readonly property real timeRemaining: {
        if (root.isPluggedIn || root.rateSamples.length < 3) return 0;
        if (root.smoothedRate <= 0 || root.energyNow <= 0) return 0;
        return (root.energyNow / root.smoothedRate) * 3600;
    }

    function formatRemaining(seconds) {
        if (seconds <= 0) return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        if (h <= 0) return `${m}m`;
        return `${h}h ${m}m`;
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            // Charging or a bogus reading contributes nothing; keeping zeros
            // in the window would drag the average toward "forever".
            if (root.isPluggedIn) { root.rateSamples = []; return; }
            const r = root.energyRate;
            if (!(r > 0)) return;
            const next = root.rateSamples.concat([r]);
            root.rateSamples = next.slice(Math.max(0, next.length - root.rateWindow));
        }
    }
    property real timeToEmpty: UPower.displayDevice.timeToEmpty
    property real timeToFull: UPower.displayDevice.timeToFull

    property real health: (function() {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery && dev.healthSupported) {
                const health = dev.healthPercentage;
                if (health === 0) {
                    return 0.01;
                } else if (health < 1) {
                    return health * 100;
                } else {
                    return health;
                }
            }
        }
        return 0;
    })()


    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Low battery"), 
            Translation.tr("Consider plugging in your device"), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ])

        if (root.soundEnabled) Audio.playSystemSound("dialog-warning");
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Critically low battery"), 
            Translation.tr("Please charge!\nAutomatic suspend triggers at %1%").arg(Config.options.battery.suspend), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("suspend-error");
    }

    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging) {
            Quickshell.execDetached(["bash", "-c", `systemctl suspend || loginctl suspend`]);
        }
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Battery full"),
            Translation.tr("Please unplug the charger"),
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("complete");
    }

    onIsPluggedInChanged: {
        if (!root.available || !root.soundEnabled) return;
        if (isPluggedIn) {
            Audio.playSystemSound("power-plug")
        } else {
            Audio.playSystemSound("power-unplug")
        }
    }
}
