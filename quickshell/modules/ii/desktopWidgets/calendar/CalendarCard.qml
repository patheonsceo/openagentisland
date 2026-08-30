pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.desktopWidgets
import QtQuick
import QtQuick.Layouts

/**
 * Desktop calendar — a month grid, the way the macOS Calendar widget reads:
 * month and year led, weekday initials, today picked out in the accent colour,
 * neighbouring months dimmed rather than blank so the grid never has holes.
 *
 * Events are deliberately absent for now. They need a source (a local .ics,
 * khal, or the GoogleCloud service already in the tree) and that is a decision
 * worth making on its own rather than baking a guess into the face.
 */
DesktopWidget {
    id: root

    widgetId: "calendar"
    config: Config.options.background.widgets.calendar

    // Month and year now share a line with the nav cluster, so the floor has to
    // clear the widest case: "September 2026" plus three 30px buttons.
    minWidth: 300
    maxWidth: 520
    resizableVertical: false
    dragHandleHeight: 44

    menuComponent: Component { WidgetMenu { config: root.config } }

    // Ticks once a minute so "today" rolls over without a restart. Cheap: the
    // grid only rebuilds when the day number actually changes.
    property double tickMs: Date.now()
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tickMs = Date.now()
    }

    readonly property var today: new Date(root.tickMs)
    readonly property int todayY: root.today.getFullYear()
    readonly property int todayM: root.today.getMonth()
    readonly property int todayD: root.today.getDate()

    // First of the displayed month.
    property int viewYear: root.todayY
    property int viewMonth: root.todayM

    readonly property bool onToday: root.viewYear === root.todayY && root.viewMonth === root.todayM
    readonly property int firstDay: Math.max(0, Math.min(1, root.config.firstDayOfWeek))

    function step(delta) {
        let m = root.viewMonth + delta;
        let y = root.viewYear;
        while (m < 0) { m += 12; y -= 1; }
        while (m > 11) { m -= 12; y += 1; }
        root.viewMonth = m;
        root.viewYear = y;
    }

    function goToday() {
        root.viewYear = root.todayY;
        root.viewMonth = root.todayM;
    }

    // No Intl in this engine, so the names live here.
    readonly property var monthNames: [
        Translation.tr("January"), Translation.tr("February"), Translation.tr("March"),
        Translation.tr("April"), Translation.tr("May"), Translation.tr("June"),
        Translation.tr("July"), Translation.tr("August"), Translation.tr("September"),
        Translation.tr("October"), Translation.tr("November"), Translation.tr("December")
    ]
    readonly property var weekdayInitials: [
        Translation.tr("S"), Translation.tr("M"), Translation.tr("T"),
        Translation.tr("W"), Translation.tr("T"), Translation.tr("F"),
        Translation.tr("S")
    ]

    // Six rows of seven, always — a fixed grid keeps the card from changing
    // height as you page between months.
    readonly property var cells: {
        const out = [];
        const first = new Date(root.viewYear, root.viewMonth, 1);
        let lead = first.getDay() - root.firstDay;
        if (lead < 0) lead += 7;
        const start = new Date(root.viewYear, root.viewMonth, 1 - lead);
        for (let i = 0; i < 42; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === root.viewMonth && d.getFullYear() === root.viewYear,
                isToday: d.getDate() === root.todayD
                    && d.getMonth() === root.todayM
                    && d.getFullYear() === root.todayY
            });
        }
        return out;
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // ── Header ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Month and year on one line, reading as a single title: the
            // stacked version made the header two rows tall for four
            // characters of information.
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                StyledText {
                    text: root.monthNames[root.viewMonth]
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: `${root.viewYear}`
                    // Same size so the two share a baseline without needing to
                    // be aligned to one; the weight and colour carry the
                    // hierarchy instead.
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Normal
                    color: Appearance.colors.colSubtext
                }
            }

            // An explicit spacer, not Layout.fillWidth on the column above.
            // QtQuick Layouts derives a nested layout's MAXIMUM width from its
            // children, and a Text without its own fillWidth caps that at the
            // widest line — so the column could never grow, there was no space
            // to distribute, and the buttons sat jammed against the month name.
            Item { Layout.fillWidth: true }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                NavButton {
                    symbol: "chevron_left"
                    onTriggered: root.step(-1)
                }
                // Kept in the row even when it does nothing. Hiding it shifted
                // both chevrons sideways the moment you paged away from today,
                // so the control you were aiming at moved under the cursor.
                NavButton {
                    symbol: "trip_origin"
                    active: !root.onToday
                    onTriggered: root.goToday()
                }
                NavButton {
                    symbol: "chevron_right"
                    onTriggered: root.step(1)
                }
            }
        }

        // ── Weekday header ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 14
            spacing: 0

            Repeater {
                model: 7
                delegate: StyledText {
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.weekdayInitials[(index + root.firstDay) % 7]
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 2
            implicitHeight: 1
            color: Appearance.m3colors.m3outlineVariant
        }

        // ── Grid ──────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            columns: 7
            rowSpacing: 1
            columnSpacing: 0

            Repeater {
                model: root.cells
                delegate: Item {
                    id: cell
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 30

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, 28)
                        height: 26
                        radius: height / 2
                        color: cell.modelData.isToday
                            ? Appearance.colors.colPrimary
                            : "transparent"
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: `${cell.modelData.day}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: cell.modelData.isToday ? Font.DemiBold : Font.Normal
                        color: cell.modelData.isToday
                            ? Appearance.colors.colOnPrimary
                            : cell.modelData.inMonth
                                ? Appearance.colors.colOnLayer0
                                : Appearance.colors.colSubtext
                        opacity: cell.modelData.inMonth ? 1 : 0.45
                    }
                }
            }
        }
    }

    component NavButton: Rectangle {
        id: btn
        required property string symbol
        property bool active: true
        signal triggered()

        implicitWidth: 30
        implicitHeight: 30
        radius: width / 2
        opacity: btn.active ? 1 : 0.32
        color: btnArea.containsMouse && btn.active
            ? Appearance.colors.colLayer2Hover
            : "transparent"

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: btn.symbol
            iconSize: 17
            color: Appearance.colors.colOnLayer1
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.active
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.triggered()
        }
    }
}
