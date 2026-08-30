pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

/**
 * Compact workspace indicator for the menu strip.
 *
 * Shows only what exists: workspaces that hold windows, plus the one you are
 * on, plus a floor of three so the pill does not collapse to a single dot on a
 * fresh login. The old one drew a fixed ten regardless, which meant seven dots
 * that stood for nothing.
 *
 * The trailing + moves to the next workspace after the last one in use, which
 * on Hyprland creates it by arriving.
 */
Item {
    id: root

    property real dotSize: 6
    property real capsuleWidth: 16
    property real gap: 5
    property int minimumShown: 3
    property color usedColor: Appearance.colors.colOnLayer0
    property color activeColor: Appearance.colors.colPrimary

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int activeWs: monitor?.activeWorkspace?.id ?? 1

    // Recomputed on Hyprland's signals: a binding over .values does not
    // reliably re-evaluate when a workspace gains or loses its last window.
    property var liveIds: []
    property int shownCount: root.minimumShown

    function refresh() {
        const ids = Hyprland.workspaces.values
            .filter(w => (w?.id ?? 0) > 0)
            .map(w => w.id);
        root.liveIds = ids;
        const highest = ids.length > 0 ? Math.max(...ids) : 1;
        root.shownCount = Math.max(root.minimumShown, highest, root.activeWs);
    }

    Component.onCompleted: root.refresh()
    onActiveWsChanged: root.refresh()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.refresh(); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh(); }
    }

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    Rectangle {
        id: pill
        anchors.centerIn: parent
        radius: height / 2
        color: Qt.rgba(Appearance.colors.colOnLayer0.r,
                       Appearance.colors.colOnLayer0.g,
                       Appearance.colors.colOnLayer0.b, 0.10)
        implicitWidth: dotRow.implicitWidth + 16
        implicitHeight: 20

        // Scroll anywhere on the pill to step through workspaces, which is what
        // the strip used to do and is worth keeping.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                if (wheel.angleDelta.y < 0)
                    Hyprland.dispatch(`hl.dsp.focus({workspace = ${root.activeWs + 1}})`);
                else
                    Hyprland.dispatch(`hl.dsp.focus({workspace = ${Math.max(1, root.activeWs - 1)}})`);
            }
        }

        RowLayout {
            id: dotRow
            anchors.centerIn: parent
            spacing: root.gap

            Repeater {
                model: root.shownCount
                delegate: Item {
                    id: del
                    required property int index
                    readonly property int wsId: del.index + 1
                    readonly property bool isActive: root.activeWs === del.wsId
                    readonly property bool isOccupied: root.liveIds.indexOf(del.wsId) >= 0

                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: del.isActive ? root.capsuleWidth : root.dotSize
                    implicitHeight: root.dotSize

                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: del.isActive ? root.activeColor : root.usedColor
                        // Occupied but not current reads solid; never visited
                        // stays faint, so the pill shows where you have been.
                        opacity: del.isActive ? 1 : (del.isOccupied ? 0.75 : 0.28)
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onPressed: Hyprland.dispatch(`hl.dsp.focus({workspace = ${del.wsId}})`)
                    }
                }
            }

            // New workspace: step past the last one in use. Hyprland creates a
            // workspace by being sent to it, so there is nothing else to do.
            MaterialSymbol {
                id: plus
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 1
                text: "add"
                iconSize: 13
                color: root.usedColor
                opacity: plusArea.containsMouse ? 0.95 : 0.4

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MouseArea {
                    id: plusArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: Hyprland.dispatch(`hl.dsp.focus({workspace = ${root.shownCount + 1}})`)
                }
            }
        }
    }
}
