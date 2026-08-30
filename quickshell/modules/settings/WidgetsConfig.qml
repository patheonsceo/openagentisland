import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings page for the desktop widget board.
 *
 * Board-wide placement first, then a section per widget. Everything here writes
 * straight to Config.options.background.widgets, which is the same object the
 * widgets themselves read, so changes land on the wallpaper as you make them.
 */
ContentPage {
    id: page
    forceWidth: true

    readonly property var board: Config.options.background.widgets

    // ── Placement ─────────────────────────────────────────────────
    ContentSection {
        icon: "drag_pan"
        title: Translation.tr("Placement")

        ConfigSelectionArray {
            currentValue: page.board.placementMode
            onSelected: newValue => {
                page.board.placementMode = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Free"),
                    icon: "open_with",
                    value: "free"
                },
                {
                    displayName: Translation.tr("Snap"),
                    icon: "align_horizontal_left",
                    value: "snap"
                },
                {
                    displayName: Translation.tr("Grid"),
                    icon: "grid_on",
                    value: "grid"
                }
            ]
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.bottomMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: page.board.placementMode === "free"
                ? Translation.tr("Widgets land exactly where you drop them.")
                : page.board.placementMode === "snap"
                    ? Translation.tr("Widgets magnet to screen edges, centres and each other, with a guide line while you drag.")
                    : Translation.tr("Position and size both snap to the grid, so nothing can end up slightly misaligned.")
        }

        ConfigSpinBox {
            visible: page.board.placementMode === "snap"
            icon: "settings_ethernet"
            text: Translation.tr("Snap distance (px)")
            value: page.board.snapThreshold
            from: 2
            to: 60
            stepSize: 1
            onValueChanged: {
                page.board.snapThreshold = value;
            }
        }

        ConfigSpinBox {
            visible: page.board.placementMode === "grid"
            icon: "grid_4x4"
            text: Translation.tr("Grid size (px)")
            value: page.board.gridSize
            from: 8
            to: 200
            stepSize: 2
            onValueChanged: {
                page.board.gridSize = value;
            }
        }

        ConfigSpinBox {
            icon: "border_outer"
            text: Translation.tr("Screen margin (px)")
            value: page.board.screenMargin
            from: 0
            to: 200
            stepSize: 2
            onValueChanged: {
                page.board.screenMargin = value;
            }
        }
    }

    // ── To-do ─────────────────────────────────────────────────────
    ContentSection {
        icon: "checklist"
        title: Translation.tr("Widget: To-do")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: page.board.todo.enable
            onCheckedChanged: {
                page.board.todo.enable = checked;
            }
        }

        LabelledField {
            visible: page.board.todo.enable
            label: Translation.tr("List name")
            value: page.board.todo.listName
            onCommitted: v => {
                if (v.length > 0) page.board.todo.listName = v;
            }
        }

        ConfigSwitch {
            visible: page.board.todo.enable
            buttonIcon: "task_alt"
            text: Translation.tr("Show completed section")
            checked: page.board.todo.showCompleted
            onCheckedChanged: {
                page.board.todo.showCompleted = checked;
            }
        }

        ConfigSpinBox {
            visible: page.board.todo.enable
            icon: "timer"
            text: Translation.tr("Default focus duration (min)")
            value: page.board.todo.defaultDuration
            from: 1
            to: 240
            stepSize: 1
            onValueChanged: {
                page.board.todo.defaultDuration = value;
            }
        }

        LabelledField {
            visible: page.board.todo.enable
            label: Translation.tr("Duration presets (min)")
            hint: Translation.tr("Comma separated, e.g. 15,25,50")
            value: page.board.todo.durationPresets
            onCommitted: v => {
                page.board.todo.durationPresets = v;
            }
        }

        MaterialControls {
            visible: page.board.todo.enable
            target: page.board.todo
        }
    }

    // ── Clock ─────────────────────────────────────────────────────
    ContentSection {
        id: clockSection
        icon: "schedule"
        title: Translation.tr("Widget: Clock")

        readonly property var zones: `${page.board.clockCard.timezones}`
            .split(",").map(z => z.trim()).filter(z => z.length > 0)

        function writeZones(list) {
            const unique = [];
            for (const z of list) if (unique.indexOf(z) < 0) unique.push(z);
            page.board.clockCard.timezones = unique.join(",");
            if (unique.indexOf(page.board.clockCard.activeTimezone) < 0)
                page.board.clockCard.activeTimezone = unique[0] ?? "local";
        }

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: page.board.clockCard.enable
            onCheckedChanged: {
                page.board.clockCard.enable = checked;
            }
        }

        ConfigRow {
            visible: page.board.clockCard.enable
            uniform: true

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("12-hour clock")
                checked: page.board.clockCard.twelveHour
                onCheckedChanged: {
                    page.board.clockCard.twelveHour = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "avg_pace"
                text: Translation.tr("Show seconds")
                checked: page.board.clockCard.showSeconds
                onCheckedChanged: {
                    page.board.clockCard.showSeconds = checked;
                }
            }
        }

        ConfigSpinBox {
            visible: page.board.clockCard.enable
            icon: "format_size"
            text: Translation.tr("Time size (px)")
            value: page.board.clockCard.timeSize
            from: 24
            to: 200
            stepSize: 2
            onValueChanged: {
                page.board.clockCard.timeSize = value;
            }
        }

        ConfigSpinBox {
            visible: page.board.clockCard.enable
            icon: "line_weight"
            text: Translation.tr("Time weight")
            value: page.board.clockCard.timeWeight
            from: 100
            to: 900
            stepSize: 100
            onValueChanged: {
                page.board.clockCard.timeWeight = value;
            }
        }

        ConfigSwitch {
            visible: page.board.clockCard.enable
            buttonIcon: "calendar_today"
            text: Translation.tr("Show date")
            checked: page.board.clockCard.showDate
            onCheckedChanged: {
                page.board.clockCard.showDate = checked;
            }
        }

        // ── Timezones ─────────────────────────────────────────────
        ContentSubsectionLabel {
            visible: page.board.clockCard.enable
            text: Translation.tr("Timezones")
        }

        StyledText {
            visible: page.board.clockCard.enable
            Layout.fillWidth: true
            Layout.leftMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Click one to put it on the face. “local” is this machine's own clock. City names work — San Francisco, Tokyo, London — as does any IANA name like Europe/London.")
        }

        Flow {
            visible: page.board.clockCard.enable
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.leftMargin: 4
            spacing: 6

            Repeater {
                model: clockSection.zones
                delegate: Rectangle {
                    id: zonePill
                    required property string modelData
                    readonly property bool isActive:
                        zonePill.modelData === page.board.clockCard.activeTimezone

                    implicitWidth: zoneRow.implicitWidth + 18
                    implicitHeight: 30
                    radius: height / 2
                    color: zonePill.isActive ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer2

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    RowLayout {
                        id: zoneRow
                        anchors.centerIn: parent
                        spacing: 6

                        StyledText {
                            text: zonePill.modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: zonePill.isActive ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer2
                        }
                        MaterialSymbol {
                            // The last zone has no meaningful removal — the
                            // clock has to show something.
                            visible: clockSection.zones.length > 1
                            text: "close"
                            iconSize: 15
                            color: zonePill.isActive ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colSubtext

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clockSection.writeZones(
                                    clockSection.zones.filter(z => z !== zonePill.modelData))
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.board.clockCard.activeTimezone = zonePill.modelData
                    }
                }
            }
        }

        RowLayout {
            visible: page.board.clockCard.enable
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8

            MaterialTextField {
                id: zoneField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Add a zone, e.g. San Francisco or Asia/Tokyo")
                onAccepted: addZone.commit()
            }

            RippleButton {
                id: addZone
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                onClicked: addZone.commit()

                function commit() {
                    const v = zoneField.text.trim();
                    if (v.length === 0) return;
                    clockSection.writeZones(clockSection.zones.concat([v]));
                    zoneField.text = "";
                }

                contentItem: RowLayout {
                    spacing: 4
                    MaterialSymbol {
                        Layout.leftMargin: 10
                        text: "add"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.rightMargin: 12
                        text: Translation.tr("Add")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        MaterialControls {
            visible: page.board.clockCard.enable
            target: page.board.clockCard
        }
    }

    // ── Calendar ──────────────────────────────────────────────────
    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Widget: Calendar")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: page.board.calendar.enable
            onCheckedChanged: {
                page.board.calendar.enable = checked;
            }
        }

        ContentSubsectionLabel {
            visible: page.board.calendar.enable
            text: Translation.tr("Week starts on")
        }

        ConfigSelectionArray {
            visible: page.board.calendar.enable
            currentValue: page.board.calendar.firstDayOfWeek
            onSelected: newValue => {
                page.board.calendar.firstDayOfWeek = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Sunday"),
                    icon: "weekend",
                    value: 0
                },
                {
                    displayName: Translation.tr("Monday"),
                    icon: "work",
                    value: 1
                }
            ]
        }

        MaterialControls {
            visible: page.board.calendar.enable
            target: page.board.calendar
        }
    }

    // ── Shared bits ───────────────────────────────────────────────

    // Material and opacity mean the same thing for every widget, so they are
    // written once here rather than three times above.
    component MaterialControls: ColumnLayout {
        id: mat
        required property var target

        Layout.fillWidth: true
        spacing: 0

        ContentSubsectionLabel { text: Translation.tr("Material") }

        ConfigSwitch {
            buttonIcon: "layers"
            text: Translation.tr("Solid (no wallpaper blur)")
            checked: mat.target.solidMaterial
            onCheckedChanged: {
                mat.target.solidMaterial = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "opacity"
            text: Translation.tr("Opacity")
            value: mat.target.baseOpacity
            from: 0
            to: 1
            onValueChanged: {
                mat.target.baseOpacity = value;
            }
        }
    }

    // Label above a text field, committing on Enter or focus loss rather than
    // per keystroke — every keystroke would push the whole options object
    // through JsonAdapter and restart the debounced file write.
    component LabelledField: ColumnLayout {
        id: field
        required property string label
        property string hint: ""
        property string value: ""
        signal committed(string value)

        Layout.fillWidth: true
        spacing: 2

        ContentSubsectionLabel { text: field.label }

        StyledText {
            visible: field.hint.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: field.hint
        }

        MaterialTextField {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: field.value
            onEditingFinished: field.committed(text.trim())
        }
    }
}
