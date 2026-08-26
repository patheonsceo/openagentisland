pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

/**
 * macOS-style dock, built from scratch rather than restyling the old one.
 *
 * The details that actually make it read as a dock, in rough order of how much
 * they matter:
 *   - icons sit on the BOTTOM baseline and grow upward out of the container,
 *     never swelling from their centres
 *   - magnification falls off as a raised cosine over ~3 icon widths, so many
 *     icons each move a little rather than one icon moving a lot; a squared
 *     cosine peaks too sharply and reads as a snap
 *   - each item grows in width as well as scale, so neighbours slide outward
 *     instead of being overlapped
 *   - running apps get a small dot BELOW the icon, not a bar or an underline
 *   - a hairline separator divides launchers from the trailing group
 *   - a 1px top inset highlight on the container is what sells the glass
 *
 * Peak and spread were tuned live against the draft and settled at 1.28 / 2.9.
 *
 * Magnification geometry is measured from each item's CURRENT centre rather than
 * its resting one. That is technically a feedback loop — widths change, so
 * centres move, which changes the widths — but the easing Behaviour damps it and
 * it is what the reference implementation does. Deriving from resting positions
 * instead needs a mapping from stretched space back to rest space, which costs
 * more than it buys.
 */
Scope {
    id: root

    readonly property var cfg: Config.options?.dock
    readonly property real iconSize: root.cfg?.macStyle?.iconSize ?? 42
    readonly property real itemSpacing: 8
    readonly property real containerPadding: 7
    // Container height, and what the dock reserves at the bottom. The
    // magnification headroom above it is deliberately NOT reserved —
    // icons rise into free space rather than pushing every window down.
    readonly property real containerHeight: root.iconSize + root.containerPadding * 2 + root.dotSize + 5
    readonly property real bottomGap: 6
    readonly property real dotSize: 4
    readonly property real peak: root.cfg?.magnification?.peak ?? 1.28
    readonly property real spread: root.cfg?.magnification?.spread ?? 2.9
    readonly property bool magnifyEnabled: root.cfg?.magnification?.enable ?? true

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockWindow
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            WlrLayershell.namespace: "quickshell:macDock"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            // Reserve the container's own strip so maximised windows stop above
            // the dock instead of sliding under it.
            exclusionMode: (root.cfg?.reserveSpace ?? true)
                ? ExclusionMode.Normal : ExclusionMode.Ignore
            exclusiveZone: (root.cfg?.reserveSpace ?? true)
                ? root.containerHeight + root.bottomGap : 0

            anchors {
                bottom: true
                left: true
                right: true
            }

            // Tall enough for a magnified icon to rise clear of the container AND
            // for the name label above it. The window clips its own contents, so
            // anything not budgeted for here gets cut off — which is exactly what
            // happened to the tooltip.
            implicitHeight: root.containerHeight + root.bottomGap
                + root.iconSize * (root.peak - 1)   // magnification headroom
                + 46                                 // name label + its gap

            // Only the container takes clicks; the rest of the strip stays
            // click-through so the desktop underneath keeps working.
            mask: Region { item: hoverArea }

            // Pointer position along the dock, in container coordinates.
            // -1 relaxes every icon back to rest.
            property real pointerX: hoverArea.containsMouse
                ? hoverArea.mouseX - (hoverArea.width - itemRow.width) / 2
                : -1

            function magScaleFor(centerX) {
                if (!root.magnifyEnabled || dockWindow.pointerX < 0)
                    return 1;
                const d = Math.abs(centerX - dockWindow.pointerX) / (root.iconSize * root.spread);
                if (d >= 1)
                    return 1;
                // Raised cosine: flat tangent at both ends, so there is no kink
                // where an icon settles back to rest.
                return 1 + (root.peak - 1) * 0.5 * (1 + Math.cos(d * Math.PI));
            }

            MouseArea {
                id: hoverArea
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.bottomGap
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                implicitWidth: itemRow.implicitWidth + root.containerPadding * 2
                implicitHeight: root.containerHeight

                Rectangle {
                    id: container
                    anchors.fill: parent
                    radius: root.iconSize * 0.4
                    color: Qt.rgba(Appearance.colors.colLayer0.r,
                                   Appearance.colors.colLayer0.g,
                                   Appearance.colors.colLayer0.b, 0.82)
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                }

                Row {
                    id: itemRow
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.containerPadding
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.itemSpacing

                    Repeater {
                        model: ScriptModel {
                            objectProp: "appId"
                            values: TaskbarApps.apps
                        }

                        delegate: DockItem {
                            required property var modelData
                            entry: modelData
                        }
                    }

                    // Trailing group: separator, then the app grid.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: root.iconSize * 0.62
                        color: Qt.rgba(1, 1, 1, 0.2)
                    }

                    DockItem {
                        entry: null
                        symbol: "apps"
                        label: Translation.tr("Applications")
                        onActivated: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                    }
                }
            }

            // ── One dock item ────────────────────────────────────
            component DockItem: Item {
                id: item
                property var entry: null
                property string symbol: ""
                property string label: ""
                signal activated()

                readonly property bool isSeparator: item.entry?.appId === "SEPARATOR"
                readonly property var toplevels: item.entry?.toplevels ?? []
                readonly property bool isRunning: item.toplevels.length > 0
                readonly property string appId: item.entry?.appId ?? ""
                property int lastFocused: -1

                readonly property real centerX: item.x + item.width / 2
                readonly property real magScale: item.isSeparator
                    ? 1
                    : dockWindow.magScaleFor(item.centerX)

                // Width is FIXED. Growing it as well as the scale made neighbours
                // slide apart like the real dock, but it also fed the result back
                // into its own input: widths move centres, centres decide widths.
                // The easing Behaviour did not damp that, it just gave the
                // oscillation a nicer curve, and it read as jitter. Scale alone is
                // stable, and at peak 1.28 with this spacing the icons stay clear
                // of each other anyway.
                implicitWidth: item.isSeparator ? 1 : root.iconSize
                implicitHeight: root.iconSize + root.dotSize + 5

                // Separators in the model become a hairline, matching the trailing one.
                Rectangle {
                    visible: item.isSeparator
                    anchors.centerIn: parent
                    width: 1
                    height: root.iconSize * 0.62
                    color: Qt.rgba(1, 1, 1, 0.2)
                }

                Item {
                    id: iconWrapper
                    visible: !item.isSeparator
                    width: root.iconSize
                    height: root.iconSize
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.dotSize + 5

                    // Grow upward off the dock's baseline. Icons rising out of the
                    // container is the entire silhouette of the effect.
                    transformOrigin: Item.Bottom
                    scale: item.magScale
                    Behavior on scale {
                        NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                    }

                    IconImage {
                        id: iconImage
                        anchors.fill: parent
                        visible: item.symbol.length === 0
                        // Icon-theme init can race a hot reload: guessIcon resolves
                        // once, comes back empty, and nothing re-fires the binding —
                        // so icons "vanish" until the next reload. Retry until it
                        // resolves, then stop.
                        property int retryTick: 0
                        source: {
                            const _ = iconImage.retryTick;
                            if (item.appId.length === 0) return "";
                            return Quickshell.iconPath(AppSearch.guessIcon(item.appId), "image-missing");
                        }
                        Timer {
                            interval: 500
                            repeat: true
                            running: iconImage.retryTick < 6 && iconImage.status === Image.Error
                            onTriggered: iconImage.retryTick++
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: item.symbol.length > 0
                        text: item.symbol
                        iconSize: root.iconSize * 0.55
                        color: Appearance.colors.colOnLayer0
                    }
                }

                // Running indicator: a dot below, never a bar.
                Rectangle {
                    visible: item.isRunning
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    implicitWidth: root.dotSize
                    implicitHeight: root.dotSize
                    radius: root.dotSize / 2
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                }

                // Name label above the icon, the way the dock does it.
                Rectangle {
                    id: tip
                    visible: opacity > 0
                    opacity: (itemArea.containsMouse && !item.isSeparator) ? 1 : 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 10 + (root.iconSize * (item.magScale - 1))
                    implicitWidth: tipText.implicitWidth + 20
                    implicitHeight: tipText.implicitHeight + 10
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    z: 10

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    StyledText {
                        id: tipText
                        anchors.centerIn: parent
                        // heuristicLookup misses for plenty of ids, and a raw
                        // "org.gnome.clocks" in a dock tooltip looks broken. Fall
                        // back to the last dotted segment, tidied up.
                        text: {
                            if (item.label.length > 0) return item.label;
                            const name = DesktopEntries.heuristicLookup(item.appId)?.name;
                            if (name && name.length > 0) return name;
                            const last = item.appId.split(".").pop().replace(/[-_]/g, " ");
                            return last.charAt(0).toUpperCase() + last.slice(1);
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }
                }

                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    enabled: !item.isSeparator
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: mouse => {
                        if (item.entry === null) {
                            item.activated();
                            return;
                        }
                        if (mouse.button === Qt.RightButton) {
                            TaskbarApps.togglePin(item.appId);
                            return;
                        }
                        // Middle click always opens a new window; left click focuses
                        // the next window of an already-running app, or launches it.
                        if (mouse.button === Qt.MiddleButton || !item.isRunning) {
                            DesktopEntries.heuristicLookup(item.appId)?.execute();
                            return;
                        }
                        item.lastFocused = (item.lastFocused + 1) % item.toplevels.length;
                        item.toplevels[item.lastFocused].activate();
                    }
                }
            }
        }
    }
}
