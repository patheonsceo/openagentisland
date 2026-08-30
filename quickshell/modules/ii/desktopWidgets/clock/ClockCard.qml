pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.desktopWidgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

/**
 * Desktop clock, in the currently selected timezone.
 *
 * Several zones can be configured; exactly one is on the face at a time and a
 * click cycles to the next, the way the macOS clock widget behaves rather than
 * the World Clock list.
 *
 * Timezone maths is done against offsets read from the system, because
 * Quickshell's JS engine has no `Intl` — `new Intl.DateTimeFormat(...)` throws
 * "Intl is not defined", so none of the usual zone formatting is available.
 * `date` is asked for each zone's current offset instead and the result is
 * cached; refreshing every half hour keeps DST transitions honest without
 * spawning a process on a tick.
 */
DesktopWidget {
    id: root

    widgetId: "clock"
    config: Config.options.background.widgets.clockCard

    minWidth: 220
    maxWidth: 480
    // Height follows the face; there is nothing inside worth scrolling.
    resizableVertical: false
    dragHandleHeight: 44

    menuComponent: Component { WidgetMenu { config: root.config } }

    // ── Zones ─────────────────────────────────────────────────────
    readonly property var zones: `${root.config.timezones}`
        .split(",").map(z => z.trim()).filter(z => z.length > 0)
    readonly property string activeZone: root.zones.indexOf(root.config.activeTimezone) >= 0
        ? root.config.activeTimezone
        : (root.zones[0] ?? "local")

    // Friendly names people actually say, mapped to the IANA zone the system
    // needs and the label to show. Typing the IANA name directly still works;
    // this just means "San Francisco" does not have to be spelled
    // "America/Los_Angeles" to be understood.
    readonly property var zoneAliases: ({
        "sf":            { zone: "America/Los_Angeles", label: "San Francisco" },
        "san francisco": { zone: "America/Los_Angeles", label: "San Francisco" },
        "los angeles":   { zone: "America/Los_Angeles", label: "Los Angeles" },
        "seattle":       { zone: "America/Los_Angeles", label: "Seattle" },
        "nyc":           { zone: "America/New_York",    label: "New York" },
        "new york":      { zone: "America/New_York",    label: "New York" },
        "chicago":       { zone: "America/Chicago",     label: "Chicago" },
        "toronto":       { zone: "America/Toronto",     label: "Toronto" },
        "london":        { zone: "Europe/London",       label: "London" },
        "paris":         { zone: "Europe/Paris",        label: "Paris" },
        "berlin":        { zone: "Europe/Berlin",       label: "Berlin" },
        "dubai":         { zone: "Asia/Dubai",          label: "Dubai" },
        "india":         { zone: "Asia/Kolkata",        label: "India" },
        "delhi":         { zone: "Asia/Kolkata",        label: "Delhi" },
        "mumbai":        { zone: "Asia/Kolkata",        label: "Mumbai" },
        "bangalore":     { zone: "Asia/Kolkata",        label: "Bangalore" },
        "singapore":     { zone: "Asia/Singapore",      label: "Singapore" },
        "tokyo":         { zone: "Asia/Tokyo",          label: "Tokyo" },
        "sydney":        { zone: "Australia/Sydney",    label: "Sydney" }
    })

    function aliasFor(zone) {
        return root.zoneAliases[`${zone}`.trim().toLowerCase()] ?? null;
    }

    // What to hand to `TZ=`.
    function resolveZone(zone) {
        if (zone === "local") return "local";
        const a = root.aliasFor(zone);
        return a ? a.zone : zone;
    }

    // Keyed by RESOLVED zone, so two entries naming the same place share one
    // lookup: minutes east of UTC.
    property var offsets: ({})
    readonly property int localOffset: -(new Date().getTimezoneOffset())

    function offsetFor(zone) {
        if (zone === "local") return root.localOffset;
        const v = root.offsets[root.resolveZone(zone)];
        return v === undefined ? root.localOffset : v;
    }

    // Shift UTC by the zone's offset, then read the UTC fields — that gives the
    // zone's wall clock without needing the engine to know about zones at all.
    function zoneNow(zone) {
        return new Date(root.tickMs + root.offsetFor(zone) * 60000);
    }

    function zoneLabel(zone) {
        if (zone === "local") return Translation.tr("Local");
        const a = root.aliasFor(zone);
        if (a) return a.label;
        const tail = `${zone}`.split("/").pop();
        return tail.replace(/_/g, " ");
    }

    function cycleZone() {
        if (root.zones.length < 2) return;
        const i = root.zones.indexOf(root.activeZone);
        root.config.activeTimezone = root.zones[(i + 1) % root.zones.length];
    }

    // ── Ticking ───────────────────────────────────────────────────
    property double tickMs: Date.now()

    Timer {
        // A seconds hand costs a repaint every second for the whole card; when
        // seconds are off, a ten-second tick is enough to keep the minute
        // honest and costs almost nothing.
        interval: root.config.showSeconds ? 1000 : 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tickMs = Date.now()
    }

    // ── Offsets ───────────────────────────────────────────────────
    Process {
        id: offsetProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {};
                for (const line of text.trim().split("\n")) {
                    const parts = line.trim().split(/\s+/);
                    if (parts.length !== 2) continue;
                    const m = parts[1].match(/^([+-])(\d{2})(\d{2})$/);
                    if (!m) continue;
                    const mins = parseInt(m[2]) * 60 + parseInt(m[3]);
                    next[parts[0]] = m[1] === "-" ? -mins : mins;
                }
                root.offsets = next;
            }
        }
    }

    function refreshOffsets() {
        const wanted = [];
        for (const z of root.zones) {
            const r = root.resolveZone(z);
            if (r !== "local" && wanted.indexOf(r) < 0) wanted.push(r);
        }
        if (wanted.length === 0) { root.offsets = ({}); return; }
        // Single shell doing every zone at once, rather than a process each.
        const script = wanted
            .map(z => `printf '%s %s\\n' '${z}' "$(TZ='${z}' date +%z)"`)
            .join("; ");
        offsetProc.command = ["sh", "-c", script];
        offsetProc.running = true;
    }

    onZonesChanged: root.refreshOffsets()
    Component.onCompleted: root.refreshOffsets()

    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refreshOffsets()
    }

    // ── Face ──────────────────────────────────────────────────────
    readonly property var now: root.zoneNow(root.activeZone)
    readonly property int hour24: root.now.getUTCHours()
    readonly property string timeText: {
        const h24 = root.hour24;
        const h = root.config.twelveHour ? (h24 % 12 === 0 ? 12 : h24 % 12) : h24;
        const hh = root.config.twelveHour ? `${h}` : `${h}`.padStart(2, "0");
        const mm = `${root.now.getUTCMinutes()}`.padStart(2, "0");
        const ss = `${root.now.getUTCSeconds()}`.padStart(2, "0");
        return root.config.showSeconds ? `${hh}:${mm}:${ss}` : `${hh}:${mm}`;
    }
    readonly property string meridiem: root.hour24 < 12
        ? Translation.tr("AM") : Translation.tr("PM")

    // No Intl, so the names are spelled out here.
    readonly property var dayNames: [
        Translation.tr("Sunday"), Translation.tr("Monday"), Translation.tr("Tuesday"),
        Translation.tr("Wednesday"), Translation.tr("Thursday"), Translation.tr("Friday"),
        Translation.tr("Saturday")
    ]
    readonly property var monthNames: [
        Translation.tr("January"), Translation.tr("February"), Translation.tr("March"),
        Translation.tr("April"), Translation.tr("May"), Translation.tr("June"),
        Translation.tr("July"), Translation.tr("August"), Translation.tr("September"),
        Translation.tr("October"), Translation.tr("November"), Translation.tr("December")
    ]

    readonly property string dateText:
        `${root.dayNames[root.now.getUTCDay()]}, ${root.monthNames[root.now.getUTCMonth()]} ${root.now.getUTCDate()}`

    // How far ahead or behind the machine's own clock this zone is.
    readonly property string deltaText: {
        if (root.activeZone === "local") return "";
        const d = root.offsetFor(root.activeZone) - root.localOffset;
        if (d === 0) return Translation.tr("Same as local");
        const sign = d > 0 ? "+" : "−";
        const a = Math.abs(d);
        const h = Math.floor(a / 60);
        const m = a % 60;
        const span = m === 0 ? `${h}h` : `${h}h ${m}m`;
        return d > 0 ? Translation.tr("%1%2 ahead").arg(sign).arg(span)
                     : Translation.tr("%1%2 behind").arg(sign).arg(span);
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: root.zoneLabel(root.activeZone)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
                elide: Text.ElideRight
            }

            MaterialSymbol {
                visible: root.zones.length > 1
                text: "public"
                iconSize: 16
                color: Appearance.colors.colSubtext
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            StyledText {
                text: root.timeText
                // Serif, and a display cut at that — at 46px the time is the
                // card's heading, not UI chrome, and the sans face read as a
                // status readout rather than something worth looking at.
                font.family: Appearance.font.family.serif
                // StyledText applies the MAIN font's variable axes unless the
                // text is pure digits, and "6:24" is not. Left alone, Google
                // Sans Flex's wght axis rides along and overrides the weight
                // set here, so the serif never renders at its own default.
                font.variableAxes: ({})
                font.pixelSize: 46
                font.weight: Font.Normal
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: 8
                visible: root.config.twelveHour
                text: root.meridiem
                font.family: Appearance.font.family.serif
                font.variableAxes: ({})
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.config.showDate
            text: root.dateText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.deltaText.length > 0
            text: root.deltaText
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }

        // ── Zone switcher ─────────────────────────────────────────
        // Only earns its space when there is more than one zone to switch to.
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            visible: root.zones.length > 1
            spacing: 6

            Repeater {
                model: root.zones
                delegate: Rectangle {
                    id: pill
                    required property string modelData
                    readonly property bool isActive: pill.modelData === root.activeZone

                    implicitWidth: pillText.implicitWidth + 16
                    implicitHeight: 22
                    radius: height / 2
                    color: pill.isActive ? Appearance.colors.colPrimary
                        : pillArea.containsMouse ? Appearance.colors.colLayer2Hover
                        : Appearance.colors.colLayer2

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    StyledText {
                        id: pillText
                        anchors.centerIn: parent
                        text: root.zoneLabel(pill.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: pill.isActive ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer2
                    }

                    MouseArea {
                        id: pillArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.config.activeTimezone = pill.modelData
                    }
                }
            }
        }
    }
}
