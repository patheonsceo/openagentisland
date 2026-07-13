pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell

// Rich hover tooltip anchored directly BELOW an item. Loader-based (crash-safe:
// an always-mapped PopupWindow can trigger a Wayland popup protocol error). The
// content is provided as a `contentComponent` and instantiated fresh inside each
// popup (no shared-item reparenting, which was rendering empty boxes). A keep-alive
// timer holds the window open through the slide+fade exit. Drive `shouldShow` from
// a HoverHandler. Set `interactive: true` for popups with clickable content —
// the popup then also stays open while the cursor is over it (the keep-alive
// timer covers the anchor→popup gap traversal).
Item {
    id: root
    property Item anchorItem
    property bool shouldShow: false
    property Component contentComponent
    property real padding: 12
    property real gap: 8
    property bool interactive: false
    property bool contentHovered: false
    readonly property bool effectiveShow: shouldShow || (interactive && contentHovered)

    property bool alive: false
    onEffectiveShowChanged: {
        if (effectiveShow) {
            hideTimer.stop();
            alive = true;
        } else {
            hideTimer.restart();
        }
    }
    Timer {
        id: hideTimer
        interval: 220
        onTriggered: root.alive = false
    }

    Loader {
        active: root.alive && !!root.anchorItem
        onActiveChanged: if (!active) root.contentHovered = false
        sourceComponent: PopupWindow {
            visible: true
            color: "transparent"
            anchor {
                window: root.anchorItem.QsWindow.window
                item: root.anchorItem
                edges: Edges.Bottom
                gravity: Edges.Bottom
            }
            implicitWidth: bg.implicitWidth
            implicitHeight: bg.implicitHeight + root.gap

            Rectangle {
                id: bg
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                radius: 16
                color: IslandStyle.pillColor
                border.width: IslandStyle.borderWidth
                border.color: IslandStyle.pillBorder
                implicitWidth: (contentLoader.item ? contentLoader.item.implicitWidth : 0) + root.padding * 2
                implicitHeight: (contentLoader.item ? contentLoader.item.implicitHeight : 0) + root.padding * 2

                Loader {
                    id: contentLoader
                    anchors.centerIn: parent
                    sourceComponent: root.contentComponent
                }

                HoverHandler {
                    enabled: root.interactive
                    onHoveredChanged: root.contentHovered = hovered
                }

                // Slide in from the right + fade. Behaviors only fire on changes AFTER
                // construction, so kick the first change via Qt.callLater.
                opacity: 0
                property real slideX: 16
                transform: Translate { x: bg.slideX }
                Behavior on opacity {
                    NumberAnimation { duration: 165; easing.type: Easing.OutCubic }
                }
                Behavior on slideX {
                    NumberAnimation { duration: 165; easing.type: Easing.OutCubic }
                }
                function sync() {
                    bg.opacity = root.effectiveShow ? 1 : 0;
                    bg.slideX = root.effectiveShow ? 0 : 16;
                }
                Component.onCompleted: Qt.callLater(bg.sync)
                Connections {
                    target: root
                    function onEffectiveShowChanged() { bg.sync(); }
                }
            }
        }
    }
}
