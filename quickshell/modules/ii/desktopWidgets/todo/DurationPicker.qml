import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * "How long for <task>?" — presets plus a stepper.
 *
 * Deliberately a stepper rather than a spinbox: Qt draws no native spinner
 * chrome worth having, and the drafts settled on -/+ circles in the card's own
 * language. Presets and the custom value are mutually exclusive, so it's always
 * obvious which one is armed.
 */
Item {
    id: root

    required property var task
    property int customMinutes: Config.options.background.widgets.todo.defaultDuration
    property int selectedPreset: -1   // index into presets, -1 when custom is armed
    // Parsed from a comma-separated string; see Config for why it is not a list.
    // Falls back rather than throwing, so a mistyped config cannot break the picker.
    readonly property var presets: {
        const raw = Config.options.background.widgets.todo.durationPresets ?? "";
        const parsed = `${raw}`.split(",")
            .map(v => parseInt(v.trim(), 10))
            .filter(v => !isNaN(v) && v > 0);
        return parsed.length > 0 ? parsed : [15, 25, 50];
    }
    readonly property int chosenSeconds: root.selectedPreset >= 0
        ? root.presets[root.selectedPreset] * 60
        : root.customMinutes * 60

    signal accepted(int seconds)
    signal cancelled()

    implicitWidth: 250
    implicitHeight: contentColumn.implicitHeight + 30

    Component.onCompleted: {
        // Pre-arm whatever this task was last run with, so a repeat is one click.
        const remembered = Math.round((root.task?.lastDuration ?? 0) / 60);
        if (remembered > 0) {
            const index = root.presets.indexOf(remembered);
            if (index >= 0) root.selectedPreset = index;
            else { root.customMinutes = remembered; root.selectedPreset = -1; }
        } else {
            const index = root.presets.indexOf(Config.options.background.widgets.todo.defaultDuration);
            root.selectedPreset = index >= 0 ? index : -1;
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.cancelled(); event.accepted = true; }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.accepted(root.chosenSeconds); event.accepted = true;
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.centerIn: parent
        width: parent.width - 30
        spacing: 11

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("How long for “%1”?").arg(root.task?.content ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Repeater {
                model: root.presets
                delegate: Rectangle {
                    id: presetChip
                    required property int index
                    required property var modelData
                    readonly property bool active: root.selectedPreset === presetChip.index

                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Appearance.rounding.small
                    color: presetChip.active
                        ? Appearance.colors.colPrimary
                        : (presetArea.containsMouse
                            ? Appearance.colors.colLayer2Hover
                            : Appearance.colors.colLayer2)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: `${presetChip.modelData}m`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: presetChip.active
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer2
                    }

                    MouseArea {
                        id: presetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedPreset = presetChip.index
                    }
                }
            }
        }

        // Custom row: label left, -/+ stepper right.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.small
            color: root.selectedPreset < 0
                ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer2
            border.width: 1
            border.color: root.selectedPreset < 0
                ? Appearance.colors.colPrimary
                : "transparent"

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 8

                StyledText {
                    text: Translation.tr("Custom")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.selectedPreset < 0
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
                }

                Item { Layout.fillWidth: true }

                StepButton {
                    symbol: "remove"
                    onTriggered: {
                        root.customMinutes = Math.max(1, root.customMinutes - 5);
                        root.selectedPreset = -1;
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    Layout.minimumWidth: 52
                    text: `${root.customMinutes} min`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colOnLayer2
                }

                StepButton {
                    symbol: "add"
                    onTriggered: {
                        root.customMinutes = Math.min(600, root.customMinutes + 5);
                        root.selectedPreset = -1;
                    }
                }
            }
        }

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 38
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: root.accepted(root.chosenSeconds)

            contentItem: StyledText {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Start focus")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    component StepButton: Rectangle {
        id: stepButton
        required property string symbol
        signal triggered()

        implicitWidth: 26
        implicitHeight: 26
        radius: width / 2
        color: stepArea.containsMouse
            ? Appearance.colors.colPrimary
            : Appearance.colors.colLayer3

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: stepButton.symbol
            iconSize: 16
            color: stepArea.containsMouse
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnLayer3
        }

        MouseArea {
            id: stepArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: stepButton.triggered()
        }
    }
}
