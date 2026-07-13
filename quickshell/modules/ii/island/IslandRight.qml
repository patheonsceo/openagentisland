pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray

// Right floating island — top-right. Pills (left→right):
//   1) stats   — CPU / RAM / SWAP / battery rings (hover → combined tooltip).
//   2) tray    — system tray (only when there are items).
//   3) control — performance toggle + settings gear (gear → right sidebar).
//   4) clock   — 12-hour time, small (hover → IST + SF popup; click a row to pick the pill's zone).
//   5) power   — circular session/power button.
// Styled via shared IslandStyle.
Scope {
    id: root

    readonly property int ringSize: 26

    // Circular metric: progress ring with a metric icon centred (no numbers).
    component MetricRing: Item {
        id: ring
        property string icon
        property real value
        property color ringColor: IslandStyle.textColor
        property int size: 26
        implicitWidth: size
        implicitHeight: size

        CircularProgress {
            anchors.centerIn: parent
            implicitSize: ring.size
            lineWidth: 3
            value: ring.value
            colPrimary: ring.ringColor
            colSecondary: Qt.rgba(1, 1, 1, 0.13)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: ring.icon
            iconSize: 13
            fill: 1
            color: ring.ringColor
        }
    }

    // Shared pill background.
    component Pill: Rectangle {
        radius: IslandStyle.radius
        color: IslandStyle.pillColor
        border.width: IslandStyle.borderWidth
        border.color: IslandStyle.pillBorder
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: islandWindow
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:islandRight"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: true
                right: true
            }
            margins {
                top: IslandStyle.margin
                right: IslandStyle.margin
            }

            implicitWidth: pillRow.implicitWidth
            implicitHeight: IslandStyle.pillHeight

            Row {
                id: pillRow
                anchors.fill: parent
                spacing: 6

                // ---- Pill 1: stats (CPU/RAM/SWAP/battery rings) + combined tooltip ----
                Pill {
                    id: statsPill
                    height: parent.height
                    width: statsRow.implicitWidth + IslandStyle.hPadding * 2

                    HoverHandler { id: statsHover }

                    RowLayout {
                        id: statsRow
                        anchors.centerIn: parent
                        spacing: 6

                        MetricRing {
                            Layout.alignment: Qt.AlignVCenter
                            icon: "speed"
                            value: ResourceUsage.cpuUsage
                            ringColor: ResourceUsage.cpuUsage > 0.9 ? "#FF6B6B" : IslandStyle.textColor
                        }
                        MetricRing {
                            Layout.alignment: Qt.AlignVCenter
                            icon: "memory"
                            value: ResourceUsage.memoryUsedPercentage
                            ringColor: ResourceUsage.memoryUsedPercentage > 0.9 ? "#FF6B6B" : IslandStyle.textColor
                        }
                        MetricRing {
                            Layout.alignment: Qt.AlignVCenter
                            icon: "swap_horiz"
                            value: ResourceUsage.swapUsedPercentage
                            visible: ResourceUsage.swapUsedPercentage > 0
                        }
                        MetricRing {
                            Layout.alignment: Qt.AlignVCenter
                            visible: ResourceUsage.cpuTemperature > 0
                            icon: "device_thermostat"
                            // Ring fills toward 100°C; warm/hot thresholds tint it.
                            value: Math.min(ResourceUsage.cpuTemperature / 100, 1)
                            ringColor: ResourceUsage.cpuTemperature >= 85 ? "#FF6B6B"
                                : ResourceUsage.cpuTemperature >= 70 ? "#FFB454"
                                : IslandStyle.textColor
                        }
                        MetricRing {
                            Layout.alignment: Qt.AlignVCenter
                            visible: Battery.available
                            icon: Battery.isCharging ? "bolt" : "battery_full"
                            value: Battery.percentage
                            ringColor: (Battery.isLow && !Battery.isCharging) ? "#FF6B6B"
                                : Battery.isCharging ? IslandStyle.accent : IslandStyle.textColor
                        }
                    }

                    IslandPopup {
                        anchorItem: statsPill
                        shouldShow: statsHover.hovered
                        contentComponent: Component {
                          Row {
                            spacing: 14
                            Column {
                                spacing: 8
                                StyledPopupHeaderRow { icon: "memory"; label: "RAM" }
                                Column {
                                    spacing: 4
                                    StyledPopupValueRow { icon: "data_usage"; label: Translation.tr("Used:"); value: ResourceUsage.kbToSizeString(ResourceUsage.memoryUsed) }
                                    StyledPopupValueRow { icon: "check_circle"; label: Translation.tr("Free:"); value: ResourceUsage.kbToSizeString(ResourceUsage.memoryFree) }
                                    StyledPopupValueRow { icon: "database"; label: Translation.tr("Total:"); value: ResourceUsage.kbToSizeString(ResourceUsage.memoryTotal) }
                                }
                            }
                            Column {
                                visible: ResourceUsage.swapTotal > 0
                                spacing: 8
                                StyledPopupHeaderRow { icon: "swap_horiz"; label: "Swap" }
                                Column {
                                    spacing: 4
                                    StyledPopupValueRow { icon: "data_usage"; label: Translation.tr("Used:"); value: ResourceUsage.kbToSizeString(ResourceUsage.swapUsed) }
                                    StyledPopupValueRow { icon: "check_circle"; label: Translation.tr("Free:"); value: ResourceUsage.kbToSizeString(ResourceUsage.swapFree) }
                                    StyledPopupValueRow { icon: "database"; label: Translation.tr("Total:"); value: ResourceUsage.kbToSizeString(ResourceUsage.swapTotal) }
                                }
                            }
                            Column {
                                spacing: 8
                                StyledPopupHeaderRow { icon: "speed"; label: "CPU" }
                                Column {
                                    spacing: 4
                                    StyledPopupValueRow { icon: "bolt"; label: Translation.tr("Load:"); value: `${Math.round(ResourceUsage.cpuUsage * 100)}%` }
                                    StyledPopupValueRow {
                                        visible: ResourceUsage.cpuTemperature > 0
                                        icon: "device_thermostat"
                                        label: Translation.tr("Temp:")
                                        value: `${Math.round(ResourceUsage.cpuTemperature)}°C`
                                    }
                                }
                            }
                            Column {
                                visible: Battery.available
                                spacing: 8
                                StyledPopupHeaderRow { icon: "battery_full"; label: Translation.tr("Battery") }
                                Column {
                                    spacing: 4
                                    StyledPopupValueRow { icon: "battery_full"; label: Translation.tr("Level:"); value: `${Math.round(Battery.percentage * 100)}%` }
                                    StyledPopupValueRow {
                                        visible: {
                                            let t = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
                                            return !(Battery.chargeState == 4 || t <= 0 || Battery.energyRate <= 0.01);
                                        }
                                        icon: "schedule"
                                        label: Battery.isCharging ? Translation.tr("To full:") : Translation.tr("To empty:")
                                        value: {
                                            let s = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
                                            let h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
                                            return h > 0 ? `${h}h ${m}m` : `${m}m`;
                                        }
                                    }
                                    StyledPopupValueRow { icon: "heart_check"; label: Translation.tr("Health:"); value: `${Battery.health.toFixed(1)}%` }
                                }
                            }
                          }
                        }
                    }
                }

                // ---- Pill 2: system tray (only when there are tray items) ----
                Pill {
                    id: trayPill
                    visible: SystemTray.items.values.length > 0
                    height: parent.height
                    width: traySysTray.implicitWidth + IslandStyle.hPadding * 2

                    SysTray {
                        id: traySysTray
                        showSeparator: false
                        anchors.centerIn: parent
                    }
                }

                // ---- Pill 3: performance toggle + settings gear ----
                Pill {
                    id: controlPill
                    height: parent.height
                    width: controlRow.implicitWidth + IslandStyle.hPadding * 2

                    RowLayout {
                        id: controlRow
                        anchors.fill: parent
                        anchors.leftMargin: IslandStyle.hPadding
                        anchors.rightMargin: IslandStyle.hPadding
                        spacing: 11

                        // Performance profile toggle
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            iconSize: 18
                            fill: 1
                            color: perfHover.hovered ? IslandStyle.accent : IslandStyle.textColor
                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            text: !PowerProfiles.hasPerformanceProfile ? "airwave"
                                : PowerProfiles.profile === PowerProfile.Performance ? "local_fire_department"
                                : PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf"
                                : "airwave"
                            HoverHandler { id: perfHover }
                            TapHandler {
                                onTapped: {
                                    if (PowerProfiles.hasPerformanceProfile) {
                                        switch (PowerProfiles.profile) {
                                        case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
                                        case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
                                        case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
                                        }
                                    } else {
                                        PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced;
                                    }
                                }
                            }
                        }

                        // Settings gear → right sidebar
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "settings"
                            iconSize: 19
                            fill: 1
                            color: gearHover.hovered ? IslandStyle.accent : IslandStyle.textColor
                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            HoverHandler { id: gearHover }
                            TapHandler {
                                onTapped: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                            }
                        }
                    }
                }

                // ---- Pill 4: capture (pencil → tools surface) ----
                Pill {
                    id: capturePill
                    height: parent.height
                    width: parent.height

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "ink_pen"
                        iconSize: 17
                        fill: 1
                        color: captureHover.hovered ? IslandStyle.accent : IslandStyle.textColor
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                    HoverHandler { id: captureHover }
                    TapHandler {
                        onTapped: Island.toggle("tools", islandWindow.screen.name)
                    }
                }

                // ---- Pill 5: clock (12-hour, small; hover → IST + SF times, click a row to pick which the pill shows) ----
                Pill {
                    id: clockPill
                    height: parent.height
                    width: clockText.implicitWidth + IslandStyle.hPadding * 2

                    // Which zone the pill displays; persisted in the shell config.
                    readonly property string zone: Config.options?.time.islandClockZone ?? "ist"

                    // US Pacific from UTC: -8h standard, -7h during DST
                    // (2nd Sunday of March 10:00 UTC → 1st Sunday of November 9:00 UTC).
                    function sfDate(now) {
                        const year = now.getUTCFullYear();
                        const marchFirstDow = new Date(Date.UTC(year, 2, 1)).getUTCDay();
                        const dstStart = Date.UTC(year, 2, 8 + ((7 - marchFirstDow) % 7), 10);
                        const novFirstDow = new Date(Date.UTC(year, 10, 1)).getUTCDay();
                        const dstEnd = Date.UTC(year, 10, 1 + ((7 - novFirstDow) % 7), 9);
                        const t = now.getTime();
                        const offsetHours = (t >= dstStart && t < dstEnd) ? -7 : -8;
                        return new Date(t + offsetHours * 3600000);
                    }
                    // 12-hour string from a date's UTC fields (sfDate pre-shifts into SF time).
                    function twelveHourUtc(d) {
                        const h24 = d.getUTCHours();
                        const h = h24 % 12 === 0 ? 12 : h24 % 12;
                        return `${h}:${String(d.getUTCMinutes()).padStart(2, "0")} ${h24 >= 12 ? "PM" : "AM"}`;
                    }

                    StyledText {
                        id: clockText
                        anchors.centerIn: parent
                        text: clockPill.zone === "sf"
                            ? "SF " + clockPill.twelveHourUtc(clockPill.sfDate(DateTime.clock.date))
                            : Qt.locale().toString(DateTime.clock.date, "h:mm AP")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: clockHover.hovered ? IslandStyle.accent : IslandStyle.textColor
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }

                    HoverHandler { id: clockHover }

                    IslandPopup {
                        anchorItem: clockPill
                        shouldShow: clockHover.hovered
                        interactive: true
                        contentComponent: Component {
                            ColumnLayout {
                                spacing: 2

                                Repeater {
                                    model: [
                                        { zone: "ist", icon: "home", label: "IST" },
                                        { zone: "sf", icon: "location_on", label: "SF" }
                                    ]

                                    delegate: Rectangle {
                                        id: zoneRow
                                        required property var modelData
                                        readonly property bool active: clockPill.zone === modelData.zone
                                        readonly property string timeText: {
                                            if (modelData.zone !== "sf")
                                                return Qt.locale().toString(DateTime.clock.date, "h:mm AP");
                                            const sf = clockPill.sfDate(DateTime.clock.date);
                                            const time = clockPill.twelveHourUtc(sf);
                                            if (sf.getUTCDay() === DateTime.clock.date.getDay())
                                                return time;
                                            const day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][sf.getUTCDay()];
                                            return `${time} (${day})`;
                                        }

                                        Layout.fillWidth: true
                                        implicitWidth: zoneRowContent.implicitWidth + 20
                                        implicitHeight: zoneRowContent.implicitHeight + 12
                                        radius: 8
                                        color: zoneRowHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutQuad } }

                                        RowLayout {
                                            id: zoneRowContent
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 6

                                            MaterialSymbol {
                                                text: zoneRow.modelData.icon
                                                iconSize: Appearance.font.pixelSize.large
                                                color: zoneRow.active ? IslandStyle.accent : Appearance.colors.colOnSurfaceVariant
                                            }
                                            StyledText {
                                                text: zoneRow.modelData.label
                                                color: zoneRow.active ? IslandStyle.accent : Appearance.colors.colOnSurfaceVariant
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 8
                                                horizontalAlignment: Text.AlignRight
                                                text: zoneRow.timeText
                                                color: zoneRow.active ? IslandStyle.accent : Appearance.colors.colOnSurfaceVariant
                                            }
                                            MaterialSymbol {
                                                text: "check"
                                                iconSize: Appearance.font.pixelSize.large
                                                color: IslandStyle.accent
                                                opacity: zoneRow.active ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                            }
                                        }

                                        HoverHandler { id: zoneRowHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: Config.options.time.islandClockZone = zoneRow.modelData.zone
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Pill 5: power (circular) ----
                Pill {
                    id: powerPill
                    height: parent.height
                    width: parent.height

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "power_settings_new"
                        iconSize: 18
                        fill: 1
                        color: powerHover.hovered ? "#FF6B6B" : IslandStyle.textColor
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                    HoverHandler { id: powerHover }
                    TapHandler {
                        onTapped: Island.toggle("power", islandWindow.screen.name)
                    }
                }
            }
        }
    }
}
