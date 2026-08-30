pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * The month grid behind the menubar clock.
 *
 * Deliberately not qs.modules.common.widgets.CalendarView: that is a grid
 * engine, not a calendar — its default delegate is an empty Text, so dropping
 * it in bare renders a correctly sized box with nothing in it. Supplying it a
 * delegate would also drag in the waffle family's styling, which does not
 * belong in this bar.
 *
 * Same construction as the desktop calendar widget: six fixed rows, so paging
 * months never changes the popup's height.
 */
Item {
    id: root

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

    property int viewYear: root.todayY
    property int viewMonth: root.todayM
    readonly property bool onToday: root.viewYear === root.todayY && root.viewMonth === root.todayM
    readonly property int firstDay: Config.options?.background?.widgets?.calendar?.firstDayOfWeek ?? 1

    function step(delta) {
        let m = root.viewMonth + delta, y = root.viewYear;
        while (m < 0) { m += 12; y -= 1; }
        while (m > 11) { m -= 12; y += 1; }
        root.viewMonth = m; root.viewYear = y;
    }

    readonly property var monthNames: [
        Translation.tr("January"), Translation.tr("February"), Translation.tr("March"),
        Translation.tr("April"), Translation.tr("May"), Translation.tr("June"),
        Translation.tr("July"), Translation.tr("August"), Translation.tr("September"),
        Translation.tr("October"), Translation.tr("November"), Translation.tr("December")
    ]
    readonly property var weekdayInitials: [
        Translation.tr("S"), Translation.tr("M"), Translation.tr("T"),
        Translation.tr("W"), Translation.tr("T"), Translation.tr("F"), Translation.tr("S")
    ]

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
                isToday: d.getDate() === root.todayD && d.getMonth() === root.todayM
                    && d.getFullYear() === root.todayY
            });
        }
        return out;
    }

    implicitWidth: 268
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: root.monthNames[root.viewMonth]
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: `${root.viewYear}`
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                NavButton { symbol: "chevron_left"; onTriggered: root.step(-1) }
                NavButton {
                    symbol: "trip_origin"
                    active: !root.onToday
                    onTriggered: { root.viewYear = root.todayY; root.viewMonth = root.todayM; }
                }
                NavButton { symbol: "chevron_right"; onTriggered: root.step(1) }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
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

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 1
            columnSpacing: 0

            Repeater {
                model: root.cells
                delegate: Item {
                    id: cell
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 28

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, 26)
                        height: 24
                        radius: height / 2
                        color: cell.modelData.isToday ? Appearance.colors.colPrimary : "transparent"
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: `${cell.modelData.day}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: cell.modelData.isToday ? Font.DemiBold : Font.Normal
                        color: cell.modelData.isToday ? Appearance.colors.colOnPrimary
                            : cell.modelData.inMonth ? Appearance.colors.colOnLayer0
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

        implicitWidth: 26
        implicitHeight: 26
        radius: width / 2
        opacity: btn.active ? 1 : 0.32
        color: btnArea.containsMouse && btn.active ? Appearance.colors.colLayer2Hover : "transparent"

        MaterialSymbol {
            anchors.centerIn: parent
            text: btn.symbol
            iconSize: 16
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
