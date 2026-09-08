pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * The desktop icon board.
 *
 * One layer surface per screen showing the contents of ~/Desktop. Sits on
 * WlrLayer.Bottom like DesktopWidgets — above the wallpaper, below every
 * normal window — so icons are visible whenever the desktop is and never in
 * the way when it isn't.
 *
 * Placement is FREE: an icon stays where you drop it. Two positions matter and
 * they are not the same thing:
 *
 *   intended  — where you dropped it. Persisted. Never overwritten by us.
 *   displayed — intended, pushed aside if a widget now covers that spot.
 *               Derived at render time, never stored.
 *
 * Keeping displacement derived is what makes widgets and icons coexist: move a
 * widget over an icon and the icon steps aside; move the widget away and the
 * icon returns home on its own, because home was never lost. The same path
 * handles a resolution change, a widget being toggled off, and a corrupt
 * position file — all of them just fall back to the first free slot.
 */
Scope {
    id: root

    readonly property string desktopDir: `${Quickshell.env("HOME")}/Desktop`
    readonly property string stateFile:
        `${Quickshell.env("HOME")}/.local/state/quickshell/user/generated/desktop-icons.json`

    // Grid geometry. Cell is deliberately larger than the icon so a two-line
    // label has somewhere to go without overlapping its neighbour.
    readonly property int iconSize: 64
    readonly property int cellW: 112
    readonly property int cellH: 126
    readonly property int margin: 28

    // { "filename": { x, y } } — the intended positions, as read from disk.
    property var positions: ({})

    function savePositions() {
        positionsFile.setText(JSON.stringify(root.positions, null, 2));
    }

    FileView {
        id: positionsFile
        path: root.stateFile
        blockLoading: false
        onLoaded: {
            try {
                const parsed = JSON.parse(positionsFile.text());
                // Guard the shape: a stray array or scalar here would make
                // every lookup below silently undefined.
                root.positions = (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                    ? parsed : ({});
            } catch (e) {
                // A corrupt file must not cost you your desktop. Start clean;
                // every icon falls back to a free grid slot.
                root.positions = ({});
            }
        }
        onLoadFailed: root.positions = ({})
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: board
            required property var modelData

            // Icons belong on one screen, like the widget board. Empty config
            // means the first screen.
            readonly property bool isTargetScreen:
                Quickshell.screens.length > 0 && modelData.name === Quickshell.screens[0].name

            screen: modelData
            visible: board.isTargetScreen && !GlobalStates.screenLocked
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:desktopIcons"
            WlrLayershell.layer: WlrLayer.Bottom

            // OnDemand, matching DesktopWidgets: accepts focus when clicked
            // (inline rename needs it) but never steals it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }

            readonly property real boardW: board.width
            readonly property real boardH: board.height

            // The board owns selection: a delegate cannot know you clicked
            // elsewhere, so the highlight would never clear if it latched
            // its own.
            property string selectedName: ""
            // Where the last right-click landed, so "New Folder" appears
            // under your cursor instead of in the first free slot.
            property real lastMenuX: 0
            property real lastMenuY: 0

            // ── Placement ─────────────────────────────────────────
            // Grid slot n, walking top-to-bottom then across, the way macOS
            // fills a desktop.
            function slotFor(n) {
                const rows = Math.max(1, Math.floor((board.boardH - root.margin * 2) / root.cellH));
                const col = Math.floor(n / rows);
                const row = n % rows;
                return {
                    x: root.margin + col * root.cellW,
                    y: root.margin + row * root.cellH
                };
            }

            // First slot that neither collides with a widget nor is already
            // taken by an earlier icon this frame.
            function firstFreeSlot(taken) {
                for (let n = 0; n < 200; n++) {
                    const s = board.slotFor(n);
                    if (DesktopLayout.collides(s.x, s.y, root.cellW, root.cellH)) continue;
                    if (taken.some(t => Math.abs(t.x - s.x) < 4 && Math.abs(t.y - s.y) < 4)) continue;
                    return s;
                }
                return board.slotFor(0);
            }

            // Does this rect hit another icon? macOS never stacks icons, so a
            // drop onto an occupied cell is refused the same way a widget is.
            function iconCollides(x, y, exceptName) {
                const pad = 4;
                const L = board.layout;
                for (let i = 0; i < L.length; i++) {
                    const o = L[i];
                    if (!o || o.name === exceptName) continue;
                    if (x < o.x + root.cellW - pad && x + root.cellW > o.x + pad
                     && y < o.y + root.cellH - pad && y + root.cellH > o.y + pad)
                        return true;
                }
                return false;
            }

            // Push a colliding position to the nearest free slot. Returns the
            // original when it is already clear, so a normal icon costs nothing.
            function resolve(pos, taken) {
                if (!DesktopLayout.collides(pos.x, pos.y, root.cellW, root.cellH))
                    return pos;
                return board.firstFreeSlot(taken);
            }

            FolderListModel {
                id: folderModel
                folder: `file://${root.desktopDir}`
                showDirs: true
                showFiles: true
                showDotAndDotDot: false
                showHidden: false
                sortField: FolderListModel.Name
            }

            // Recomputed whenever the listing, the widget rects or the board
            // size changes — the three things that can move an icon.
            readonly property var layout: {
                const out = [];
                const taken = [];
                const n = folderModel.count;
                for (let i = 0; i < n; i++) {
                    const name = folderModel.get(i, "fileName");
                    const isDir = folderModel.get(i, "fileIsDir");
                    const saved = root.positions[name];
                    let pos = (saved && typeof saved.x === "number" && typeof saved.y === "number")
                        ? { x: saved.x, y: saved.y }
                        : board.firstFreeSlot(taken);
                    pos = board.resolve(pos, taken);
                    taken.push(pos);
                    out.push({
                        name: name,
                        isDir: isDir,
                        path: `${root.desktopDir}/${name}`,
                        x: pos.x,
                        y: pos.y
                    });
                }
                return out;
            }

            // ── Icons ─────────────────────────────────────────────
            Repeater {
                model: board.layout

                DesktopIcon {
                    required property var modelData
                    itemName: modelData.name
                    itemPath: modelData.path
                    isDir: modelData.isDir
                    iconSize: root.iconSize
                    width: root.cellW
                    height: root.cellH
                    x: modelData.x
                    y: modelData.y
                    boardWidth: board.boardW
                    boardHeight: board.boardH

                    selected: board.selectedName === modelData.name
                    onSelectRequested: board.selectedName = modelData.name
                    onContextRequested: (gx, gy) => {
                        board.selectedName = modelData.name;
                        contextMenu.targetDir = root.desktopDir;
                        contextMenu.targetPath = modelData.path;
                        contextMenu.popupAt(gx, gy);
                    }

                    onDropped: (nx, ny) => {
                        // Reject a drop onto a widget OR onto another icon:
                        // the icon animates home and nothing is written, so
                        // intended stays intended.
                        if (DesktopLayout.collides(nx, ny, root.cellW, root.cellH))
                            return false;
                        if (board.iconCollides(nx, ny, modelData.name))
                            return false;
                        const p = root.positions;
                        p[modelData.name] = { x: nx, y: ny };
                        root.positions = p;
                        root.savePositions();
                        return true;
                    }

                    onActivated: {
                        // Folders open in the Finder you already built; files
                        // go to whatever owns their type.
                        // Both go through xdg-open: folders land in Nautilus,
                        // files in whatever owns their type. The yazi Finder
                        // stays on Super+E where it was always the deliberate
                        // choice — a double-click here should not drop you
                        // into a terminal.
                        Quickshell.execDetached(["xdg-open", modelData.path]);
                    }
                }
            }

            // Empty-desktop right click.
            MouseArea {
                anchors.fill: parent
                z: -1                       // never above an icon
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    board.selectedName = "";          // clicking away deselects
                    if (event.button !== Qt.RightButton) return;
                    board.lastMenuX = event.x;
                    board.lastMenuY = event.y;
                    contextMenu.targetDir = root.desktopDir;
                    contextMenu.targetPath = "";
                    contextMenu.popupAt(event.x, event.y);
                }
            }

            DesktopContextMenu {
                id: contextMenu
                boardWidth: board.boardW
                boardHeight: board.boardH
                onCreateRequested: kind => {
                    // Unique name first, so we can seed its position before the
                    // model sees it — otherwise the new item flashes into the
                    // first free slot and then jumps to the cursor.
                    const taken = board.layout.map(i => i.name);
                    const base = kind === "folder" ? "untitled folder" : "untitled";
                    const ext = kind === "folder" ? "" : ".txt";
                    let name = base + ext, n = 2;
                    while (taken.indexOf(name) >= 0) { name = `${base} ${n}${ext}`; n++; }

                    // Snap the click to a spot that is free of widgets and of
                    // other icons, so a new folder never lands underneath one.
                    let px = Math.max(0, Math.min(board.boardW - root.cellW, board.lastMenuX - root.cellW / 2));
                    let py = Math.max(0, Math.min(board.boardH - root.cellH, board.lastMenuY - root.cellH / 2));
                    if (DesktopLayout.collides(px, py, root.cellW, root.cellH)
                        || board.iconCollides(px, py, name)) {
                        const free = board.firstFreeSlot(board.layout.map(i => ({ x: i.x, y: i.y })));
                        px = free.x; py = free.y;
                    }
                    const p = root.positions;
                    p[name] = { x: px, y: py };
                    root.positions = p;
                    root.savePositions();

                    const full = `${root.desktopDir}/${name}`;
                    Quickshell.execDetached(kind === "folder"
                        ? ["mkdir", "-p", full]
                        : ["touch", full]);
                }
                onRefreshRequested: folderModel.folder = folderModel.folder
                onCleanUpRequested: {
                    // Drop every stored position; each icon falls back to a
                    // free slot, which is exactly "snap everything to grid".
                    root.positions = ({});
                    root.savePositions();
                }
            }
        }
    }
}
