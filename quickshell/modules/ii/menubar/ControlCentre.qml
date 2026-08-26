pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower

/**
 * Control Centre panel, dropped from the menubar.
 *
 * Everything here is a live control, not a readout with a link to somewhere
 * else: the power modes switch the profile, the sliders move volume and
 * brightness, the toggles turn the radios on and off.
 *
 * GPU is reported as a CLOCK, not utilisation. Intel integrated graphics expose
 * `gt_act_freq_mhz` and no busy-percent at all, so anything labelled "GPU load"
 * here would be a guess dressed up as a measurement.
 */
Item {
    id: root

    // Passed in from the menubar. Deriving it here from QsWindow does not work:
    // inside a popup that resolves to the popup's own window, whose screen is not
    // the same object as the shell's ShellScreen, and Brightness matches monitors
    // by identity — so the lookup silently found nothing and pinned the slider at 0.
    property var targetScreen: null

    readonly property real rowSpacing: 14
    implicitWidth: 340
    implicitHeight: content.implicitHeight + 28

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        width: parent.width - 28
        spacing: root.rowSpacing

        // ── Power mode ───────────────────────────────────────────
        SectionLabel { text: Translation.tr("Power mode") }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ModeChip {
                mode: PowerProfile.PowerSaver
                symbol: "energy_savings_leaf"
                label: Translation.tr("Saver")
            }
            ModeChip {
                mode: PowerProfile.Balanced
                symbol: "airwave"
                label: Translation.tr("Balanced")
            }
            ModeChip {
                mode: PowerProfile.Performance
                symbol: "local_fire_department"
                label: Translation.tr("Performance")
                enabled: PowerProfiles.hasPerformanceProfile
            }
        }

        // ── Stats ────────────────────────────────────────────────
        SectionLabel { text: Translation.tr("System") }

        StatRow {
            symbol: "speed"
            label: Translation.tr("CPU")
            value: ResourceUsage.cpuUsage
            detail: ResourceUsage.cpuTemperature > 0
                ? `${Math.round(ResourceUsage.cpuUsage * 100)}%  ·  ${Math.round(ResourceUsage.cpuTemperature)}°C`
                : `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            warn: ResourceUsage.cpuTemperature >= 85 || ResourceUsage.cpuUsage > 0.9
        }

        StatRow {
            symbol: "memory"
            label: Translation.tr("Memory")
            value: ResourceUsage.memoryUsedPercentage
            detail: `${ResourceUsage.kbToSizeString(ResourceUsage.memoryUsed)} / ${ResourceUsage.kbToSizeString(ResourceUsage.memoryTotal)}`
            warn: ResourceUsage.memoryUsedPercentage > 0.9
        }

        StatRow {
            symbol: "swap_horiz"
            label: Translation.tr("Swap")
            visible: ResourceUsage.swapTotal > 0
            value: ResourceUsage.swapUsedPercentage
            detail: `${ResourceUsage.kbToSizeString(ResourceUsage.swapUsed)} / ${ResourceUsage.kbToSizeString(ResourceUsage.swapTotal)}`
            warn: ResourceUsage.swapUsedPercentage > 0.5
        }

        StatRow {
            symbol: "monitor"
            label: Translation.tr("GPU clock")
            visible: ResourceUsage.gpuMaxFreq > 0
            value: ResourceUsage.gpuLoad
            // Clock, not utilisation — this GPU reports no busy-percent.
            detail: `${Math.round(ResourceUsage.gpuFreq)} / ${Math.round(ResourceUsage.gpuMaxFreq)} MHz`
        }

        StatRow {
            symbol: Battery.isCharging ? "battery_charging_full" : "battery_full"
            label: Translation.tr("Battery")
            visible: Battery.available
            value: Battery.percentage
            detail: {
                const pct = `${Math.round(Battery.percentage * 100)}%`;
                const secs = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
                if (Battery.chargeState === 4 || secs <= 0 || Battery.energyRate <= 0.01)
                    return pct;
                const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60);
                const left = h > 0 ? `${h}h ${m}m` : `${m}m`;
                return `${pct}  ·  ${left} ${Battery.isCharging ? Translation.tr("to full") : Translation.tr("left")}`;
            }
            warn: Battery.isLow && !Battery.isCharging
        }

        // ── Sliders ──────────────────────────────────────────────
        SectionLabel { text: Translation.tr("Output") }

        SliderRow {
            symbol: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
            value: Audio.sink?.audio?.volume ?? 0
            onMoved: v => { if (Audio.sink?.audio) Audio.sink.audio.volume = v; }
            onSymbolClicked: { if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted; }
        }

        SliderRow {
            id: brightnessRow
            symbol: "brightness_6"
            // QsWindow.window.screen, not QsWindow.screen — the latter is undefined
            // and silently yields no monitor, which pins the slider at zero.
            readonly property var monitor: Brightness.getMonitorForScreen(root.targetScreen)
            visible: !!brightnessRow.monitor   // find() returns undefined, not null
            value: brightnessRow.monitor?.brightness ?? 0
            onMoved: v => brightnessRow.monitor?.setBrightness(v)
        }

        // ── Radios ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 8

            ToggleTile {
                symbol: Network.wifiEnabled ? "wifi" : "wifi_off"
                label: Translation.tr("Wi-Fi")
                sub: Network.ethernet ? Translation.tr("Ethernet")
                    : Network.wifiEnabled ? (Network.active?.ssid ?? Translation.tr("Not connected"))
                    : Translation.tr("Off")
                on: Network.wifiEnabled
                onToggled: Network.toggleWifi()
            }

            ToggleTile {
                symbol: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                label: Translation.tr("Bluetooth")
                sub: !BluetoothStatus.enabled ? Translation.tr("Off")
                    : BluetoothStatus.connected
                        ? (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Connected"))
                        : Translation.tr("On")
                on: BluetoothStatus.enabled
                enabled: BluetoothStatus.available
                onToggled: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                }
            }
        }
    }

    // ── Building blocks ──────────────────────────────────────────
    component SectionLabel: StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    component ModeChip: Rectangle {
        id: chip
        required property var mode
        required property string symbol
        required property string label
        property bool enabled: true
        readonly property bool active: PowerProfiles.profile === chip.mode

        Layout.fillWidth: true
        implicitHeight: 52
        radius: Appearance.rounding.small
        opacity: chip.enabled ? 1 : 0.4
        color: chip.active ? Appearance.colors.colPrimary
            : chipArea.containsMouse ? Appearance.colors.colLayer2Hover
            : Appearance.colors.colLayer2

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: chip.symbol
                iconSize: 19
                fill: chip.active ? 1 : 0
                color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            enabled: chip.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PowerProfiles.profile = chip.mode
        }
    }

    component StatRow: RowLayout {
        id: statRow
        required property string symbol
        required property string label
        required property real value
        required property string detail
        property bool warn: false

        Layout.fillWidth: true
        spacing: 10

        MaterialSymbol {
            text: statRow.symbol
            iconSize: 18
            fill: 1
            color: statRow.warn ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: statRow.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: statRow.detail
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: statRow.warn ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Appearance.colors.colLayer2

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, statRow.value))
                    radius: 2
                    color: statRow.warn ? Appearance.m3colors.m3error : Appearance.colors.colPrimary

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    component SliderRow: RowLayout {
        id: sliderRow
        required property string symbol
        property real value: 0
        signal moved(real v)
        signal symbolClicked()

        Layout.fillWidth: true
        spacing: 10

        MaterialSymbol {
            text: sliderRow.symbol
            iconSize: 18
            fill: 1
            color: symbolArea.containsMouse
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer1

            MouseArea {
                id: symbolArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sliderRow.symbolClicked()
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            value: sliderRow.value
            stopIndicatorValues: []
            onMoved: sliderRow.moved(value)
        }
    }

    component ToggleTile: Rectangle {
        id: tile
        required property string symbol
        required property string label
        property string sub: ""
        property bool on: false
        property bool enabled: true
        signal toggled()

        Layout.fillWidth: true
        implicitHeight: 60
        radius: Appearance.rounding.small
        opacity: tile.enabled ? 1 : 0.4
        color: tile.on ? Appearance.colors.colPrimaryContainer
            : tileArea.containsMouse ? Appearance.colors.colLayer2Hover
            : Appearance.colors.colLayer2

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 9

            MaterialSymbol {
                text: tile.symbol
                iconSize: 20
                fill: tile.on ? 1 : 0
                color: tile.on ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: tile.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: tile.on ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: tile.sub
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        MouseArea {
            id: tileArea
            anchors.fill: parent
            enabled: tile.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.toggled()
        }
    }
}
