pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services
import qs.modules.ii.desktopWidgets.todo
import qs.modules.ii.desktopWidgets.clock
import qs.modules.ii.desktopWidgets.calendar
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The desktop widget board.
 *
 * One layer surface per screen carrying every wallpaper widget. Sits on
 * WlrLayer.Bottom: above the wallpaper, below every normal window, so a widget
 * is visible whenever the desktop is and never in the way when it isn't.
 *
 * Separate from Background.qml on purpose — Background takes no keyboard focus,
 * so a text field there could never be typed into.
 *
 * One surface for all widgets rather than one each: a layer surface costs a
 * Wayland surface, a mask and a commit path, and widgets need to see each
 * other's geometry anyway in order to snap against it.
 *
 * Adding a widget is a Loader, a Region line and a config block — the chrome,
 * the gestures and the snapping all come from DesktopWidget.
 */
Scope {
    id: root

    readonly property var widgetsConfig: Config.options.background.widgets

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: boardWindow
            required property var modelData

            // One board across three monitors would just be three copies of
            // itself. Empty means the first screen.
            readonly property bool isTargetScreen: root.widgetsConfig.screenName.length === 0
                ? (Quickshell.screens.length > 0 && modelData.name === Quickshell.screens[0].name)
                : modelData.name === root.widgetsConfig.screenName

            screen: modelData
            visible: Config.ready && boardWindow.isTargetScreen && !GlobalStates.screenLocked

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:desktopWidgets"
            WlrLayershell.layer: WlrLayer.Bottom

            // OnDemand means "grant this surface keyboard focus when the user
            // clicks it", so it has to already be set when the click lands.
            // Raising it in response to a field taking focus was circular: the
            // surface was still None at the moment of the click, the compositor
            // had nothing to grant, and the caret blinked in a field that could
            // not take a keystroke until you clicked a second time. OnDemand
            // does not steal focus — it only accepts it on click.
            WlrLayershell.keyboardFocus: boardWindow.releasingFocus
                ? WlrKeyboardFocus.None
                : WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }

            // ── Board API used by DesktopWidget ───────────────────
            readonly property real screenWidth: boardWindow.width
            readonly property real screenHeight: boardWindow.height

            // Publish widget rects for the icon board. The two are separate
            // layer surfaces, so DesktopIcons cannot see widgetItems directly;
            // without this an icon would happily sit underneath a widget.
            // QML tracks the w.x/w.y/w.width reads below, so this re-evaluates
            // whenever a widget is moved or resized.
            readonly property var publishedRects: boardWindow.widgetItems
                .filter(w => w)
                .map(w => ({ x: w.x, y: w.y, width: w.width, height: w.height }))
            onPublishedRectsChanged: DesktopLayout.publishRects(boardWindow.publishedRects)

            property var widgetItems: []
            function register(w) {
                if (boardWindow.widgetItems.indexOf(w) < 0)
                    boardWindow.widgetItems = boardWindow.widgetItems.concat([w]);
            }
            function unregister(w) {
                boardWindow.widgetItems = boardWindow.widgetItems.filter(x => x !== w);
            }

            readonly property bool anyInteracting:
                boardWindow.widgetItems.some(w => w && (w.interacting || w.menuOpen))
            readonly property bool anyInputActive:
                boardWindow.widgetItems.some(w => w && w.inputActive)

            readonly property string placementMode: root.widgetsConfig.placementMode
            readonly property int snapThreshold: root.widgetsConfig.snapThreshold
            readonly property int gridSize: Math.max(2, root.widgetsConfig.gridSize)
            readonly property int screenMargin: root.widgetsConfig.screenMargin
            // Gap left when a widget snaps alongside another one.
            readonly property int neighbourGap: 16

            property var guides: []

            // ── Placement ─────────────────────────────────────────
            // Candidate edges a widget can snap to, built in one place so the
            // guide preview and the committed position can never disagree.
            function candidatesX(self, w) {
                const out = [
                    { at: boardWindow.screenMargin, guide: boardWindow.screenMargin },
                    { at: boardWindow.screenWidth - w - boardWindow.screenMargin,
                      guide: boardWindow.screenWidth - boardWindow.screenMargin },
                    { at: (boardWindow.screenWidth - w) / 2, guide: boardWindow.screenWidth / 2 }
                ];
                for (let i = 0; i < boardWindow.widgetItems.length; i++) {
                    const o = boardWindow.widgetItems[i];
                    if (!o || o === self) continue;
                    out.push({ at: o.x, guide: o.x });                          // left edges align
                    out.push({ at: o.x + o.width - w, guide: o.x + o.width });  // right edges align
                    out.push({ at: o.x + o.width + boardWindow.neighbourGap, guide: o.x + o.width });
                    out.push({ at: o.x - w - boardWindow.neighbourGap, guide: o.x });
                }
                return out;
            }

            function candidatesY(self, h) {
                const out = [
                    { at: boardWindow.screenMargin, guide: boardWindow.screenMargin },
                    { at: boardWindow.screenHeight - h - boardWindow.screenMargin,
                      guide: boardWindow.screenHeight - boardWindow.screenMargin },
                    { at: (boardWindow.screenHeight - h) / 2, guide: boardWindow.screenHeight / 2 }
                ];
                for (let i = 0; i < boardWindow.widgetItems.length; i++) {
                    const o = boardWindow.widgetItems[i];
                    if (!o || o === self) continue;
                    out.push({ at: o.y, guide: o.y });
                    out.push({ at: o.y + o.height - h, guide: o.y + o.height });
                    out.push({ at: o.y + o.height + boardWindow.neighbourGap, guide: o.y + o.height });
                    out.push({ at: o.y - h - boardWindow.neighbourGap, guide: o.y });
                }
                return out;
            }

            function nearest(candidates, value, threshold) {
                let best = null;
                for (let i = 0; i < candidates.length; i++) {
                    const c = candidates[i];
                    const d = Math.abs(c.at - value);
                    if (d <= threshold && (best === null || d < best.dist))
                        best = { at: c.at, guide: c.guide, dist: d };
                }
                return best;
            }

            // Returns { x, y, guides } for a proposed position. `guides` drives
            // the live preview only; `x`/`y` are what gets stored.
            function resolve(self, x, y) {
                const mode = boardWindow.placementMode;
                if (mode === "grid") {
                    const g = boardWindow.gridSize;
                    return { x: Math.round(x / g) * g, y: Math.round(y / g) * g, guides: [] };
                }
                if (mode !== "snap") return { x: x, y: y, guides: [] };

                const t = boardWindow.snapThreshold;
                const sx = boardWindow.nearest(boardWindow.candidatesX(self, self.width), x, t);
                const sy = boardWindow.nearest(boardWindow.candidatesY(self, self.height), y, t);
                const guides = [];
                if (sx) guides.push({ vertical: true, pos: sx.guide });
                if (sy) guides.push({ vertical: false, pos: sy.guide });
                return { x: sx ? sx.at : x, y: sy ? sy.at : y, guides: guides };
            }

            function placeWidget(self, x, y) {
                return boardWindow.resolve(self, x, y);
            }

            function previewGuides(self, x, y) {
                boardWindow.guides = boardWindow.resolve(self, x, y).guides;
            }

            function clearGuides() {
                boardWindow.guides = [];
            }

            // Grid mode quantises size too — otherwise widgets line up on one
            // edge and disagree on the other.
            function sizeWidget(self, width, vertical) {
                if (boardWindow.placementMode !== "grid")
                    return { width: width, vertical: vertical };
                const g = boardWindow.gridSize;
                return {
                    width: Math.round(width / g) * g,
                    vertical: vertical >= 0 ? Math.round(vertical / g) * g : vertical
                };
            }

            // ── Keyboard hand-back ────────────────────────────────
            property bool releasingFocus: false
            Timer {
                id: focusReleaseTimer
                interval: 120
                onTriggered: boardWindow.releasingFocus = false
            }
            function releaseFocus() {
                boardWindow.releasingFocus = true;
                focusReleaseTimer.restart();
            }

            // ── Input mask ────────────────────────────────────────
            // Everything outside the widgets stays clickable through to the
            // desktop — except during a gesture or while a menu is open, when
            // the whole surface has to accept input: a menu extends past its
            // widget, and a drag routinely takes the pointer outside it.
            mask: boardWindow.anyInteracting ? null : widgetsRegion
            Region {
                id: widgetsRegion
                Region { item: todoLoader.item }
                Region { item: clockLoader.item }
                Region { item: calendarLoader.item }
            }

            // ── Snap guides ───────────────────────────────────────
            Repeater {
                model: boardWindow.guides
                delegate: Rectangle {
                    required property var modelData
                    color: Appearance.colors.colPrimary
                    opacity: 0.8
                    z: 80
                    x: modelData.vertical ? modelData.pos : 0
                    y: modelData.vertical ? 0 : modelData.pos
                    width: modelData.vertical ? 1 : boardWindow.width
                    height: modelData.vertical ? boardWindow.height : 1
                }
            }

            // ── Widgets ───────────────────────────────────────────
            Loader {
                id: todoLoader
                active: Config.ready && root.widgetsConfig.todo.enable
                sourceComponent: TodoCard { board: boardWindow }
            }

            Loader {
                id: clockLoader
                active: Config.ready && root.widgetsConfig.clockCard.enable
                sourceComponent: ClockCard { board: boardWindow }
            }

            Loader {
                id: calendarLoader
                active: Config.ready && root.widgetsConfig.calendar.enable
                sourceComponent: CalendarCard { board: boardWindow }
            }
        }
    }
}
