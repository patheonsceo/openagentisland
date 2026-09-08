pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
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
    readonly property real iconSize: root.cfg?.macStyle?.iconSize ?? 52
    readonly property real containerOpacity: root.cfg?.macStyle?.opacity ?? 0.55
    // Both scale with the icon, so changing the size keeps the proportions
    // instead of leaving a bigger icon crammed into the same padding.
    readonly property real itemSpacing: Math.round(root.iconSize * 0.19)
    readonly property real containerPadding: Math.round(root.iconSize * 0.17)
    // Container height, and what the dock reserves at the bottom. The
    // magnification headroom above it is deliberately NOT reserved —
    // icons rise into free space rather than pushing every window down.
    readonly property real containerHeight: root.iconSize + root.containerPadding * 2 + root.dotSize + 5
    readonly property real bottomGap: 6
    readonly property real dotSize: 4
    readonly property real peak: root.cfg?.magnification?.peak ?? 1.28
    readonly property real spread: root.cfg?.magnification?.spread ?? 2.9
    readonly property bool magnifyEnabled: root.cfg?.magnification?.enable ?? true

    FolderListModel {
        id: trashModel
        // Directories.home already carries the file:// scheme. Prefixing it
        // again produced file://file:///... — which FolderListModel cannot
        // parse, so it silently fell back to its default folder (the shell's
        // working directory). That is never empty, so the Trash icon read as
        // full no matter what was actually in the Trash.
        folder: `${Directories.home}/.local/share/Trash/files`
        showDirs: true
        showFiles: true
        showHidden: true
    }

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
                + (dockWindow.menuOpen ? dockMenu.implicitHeight + 12 : 0)

            // Only the container takes clicks; the rest of the strip stays
            // click-through so the desktop underneath keeps working.
            // While a menu is open the whole strip has to accept input, or the
            // menu (which sits outside the container) gets no clicks and the
            // click-away catcher never fires.
            mask: dockWindow.menuOpen ? null : hoverRegion
            Region { id: hoverRegion; item: hoverArea }

            // ── Right-click menu state ────────────────────────────
            // The window clips its contents and is only tall enough for the
            // icons, so it has to grow to fit a menu. It is anchored to the
            // bottom, so the extra height goes upward; exclusiveZone stays put
            // so nothing on screen shifts when a menu opens.
            // Drag-to-reorder. Only pinned apps move: the running-but-unpinned
            // ones have no stored position to write back to.
            property string dragAppId: ""
            readonly property bool reordering: dockWindow.dragAppId.length > 0

            function pinnedList() {
                return (Config.options?.dock?.pinnedApps ?? []).slice();
            }

            // Moves `appId` to `to`, writing the whole list back. Returns true
            // if anything actually changed.
            function movePinned(appId, to) {
                const list = dockWindow.pinnedList();
                const from = list.indexOf(appId);
                if (from < 0) return false;
                const target = Math.max(0, Math.min(list.length - 1, to));
                if (target === from) return false;
                list.splice(from, 1);
                list.splice(target, 0, appId);
                Config.options.dock.pinnedApps = list;
                return true;
            }

            property var menuFor: null
            property real menuCenterX: 0
            readonly property bool menuOpen: dockWindow.menuFor !== null
            property string menuArmed: ""

            function openMenu(item, centerX) {
                dockWindow.menuArmed = "";
                dockWindow.menuCenterX = centerX;
                dockWindow.menuFor = item;
            }
            function closeMenu() {
                dockWindow.menuFor = null;
                dockWindow.menuArmed = "";
            }

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
                    radius: root.iconSize * 0.42
                    color: Qt.rgba(Appearance.colors.colLayer0.r,
                                   Appearance.colors.colLayer0.g,
                                   Appearance.colors.colLayer0.b,
                                   root.containerOpacity)
                    // A light hairline rather than the layer border. Once the
                    // fill is this open, a dark edge reads as a hole cut in the
                    // wallpaper; a bright one reads as the rim of a pane.
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.13)
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
                        // The model already puts a separator after the pinned
                        // group. With nothing unpinned running, that separator
                        // IS the last item and sat a few pixels from this one —
                        // two hairlines where the design calls for one.
                        visible: {
                            const a = TaskbarApps.apps;
                            return !(a.length > 0
                                && a[a.length - 1].appId === "SEPARATOR");
                        }
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

                    // Trash, last in the row as on macOS. The icon reflects
                    // whether there is anything in it, which is the only reason
                    // the folder is watched at all — FolderListModel updates on
                    // its own, so nothing here polls.
                    DockItem {
                        entry: null
                        isTrash: true
                        iconName: trashModel.count > 0 ? "user-trash-full" : "user-trash"
                        label: trashModel.count > 0
                            ? Translation.tr("Trash — %1 items").arg(trashModel.count)
                            : Translation.tr("Trash — empty")
                        onActivated: Quickshell.execDetached(["xdg-open", "trash:///"])
                    }
                }
            }

            // ── Right-click menu ─────────────────────────────────
            MouseArea {
                anchors.fill: parent
                visible: dockWindow.menuOpen
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                z: 90
                onClicked: dockWindow.closeMenu()
            }

            Rectangle {
                id: dockMenu
                visible: dockWindow.menuOpen
                z: 100
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                readonly property var item: dockWindow.menuFor
                readonly property bool isTrash: dockMenu.item?.isTrash ?? false
                readonly property bool isApp: (dockMenu.item?.entry ?? null) !== null
                readonly property bool running: dockMenu.item?.isRunning ?? false
                readonly property string appId: dockMenu.item?.appId ?? ""
                readonly property bool pinned: dockMenu.item?.entry?.pinned ?? false

                implicitWidth: 210
                implicitHeight: menuCol.implicitHeight + 10

                // Centred on the icon, kept inside the screen.
                x: Math.max(8, Math.min(dockWindow.menuCenterX + hoverArea.x - width / 2,
                                        dockWindow.width - width - 8))
                y: hoverArea.y - height - 8

                ColumnLayout {
                    id: menuCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 5
                    spacing: 0

                    MenuRow {
                        visible: dockMenu.isApp
                        symbol: dockMenu.running ? "add" : "launch"
                        label: dockMenu.running ? Translation.tr("New Window") : Translation.tr("Open")
                        onTriggered: {
                            DesktopEntries.heuristicLookup(dockMenu.appId)?.execute();
                            dockWindow.closeMenu();
                        }
                    }
                    MenuRow {
                        visible: dockMenu.isApp && dockMenu.running
                        symbol: "keyboard_arrow_up"
                        label: Translation.tr("Show")
                        onTriggered: {
                            dockMenu.item?.toplevels?.[0]?.activate();
                            dockWindow.closeMenu();
                        }
                    }
                    MenuRow {
                        visible: dockMenu.isApp
                        symbol: dockMenu.pinned ? "keep_off" : "keep"
                        label: dockMenu.pinned
                            ? Translation.tr("Remove from Dock")
                            : Translation.tr("Keep in Dock")
                        onTriggered: {
                            TaskbarApps.togglePin(dockMenu.appId);
                            dockWindow.closeMenu();
                        }
                    }
                    MenuRow {
                        visible: dockMenu.isApp && dockMenu.running
                        symbol: "close"
                        label: Translation.tr("Quit")
                        destructive: true
                        armedKey: "quit"
                        onTriggered: {
                            const tls = dockMenu.item?.toplevels ?? [];
                            for (let i = tls.length - 1; i >= 0; i--) tls[i].close();
                            dockWindow.closeMenu();
                        }
                    }

                    MenuRow {
                        visible: dockMenu.isTrash
                        symbol: "folder_open"
                        label: Translation.tr("Open Trash")
                        onTriggered: {
                            Quickshell.execDetached(["xdg-open", "trash:///"]);
                            dockWindow.closeMenu();
                        }
                    }
                    MenuRow {
                        visible: dockMenu.isTrash
                        symbol: "delete_forever"
                        label: Translation.tr("Empty Trash")
                        destructive: true
                        armedKey: "empty"
                        onTriggered: {
                            Quickshell.execDetached(["gio", "trash", "--empty"]);
                            dockWindow.closeMenu();
                        }
                    }
                }
            }

            // Destructive rows arm on the first click and fire on the second.
            // Emptying the Trash and quitting an app are both unrecoverable
            // from a stray click on a menu that opens under the pointer.
            component MenuRow: MouseArea {
                id: row
                required property string symbol
                required property string label
                property bool destructive: false
                property string armedKey: ""
                signal triggered()

                readonly property bool isArmed: row.destructive
                    && dockWindow.menuArmed === row.armedKey

                Layout.fillWidth: true
                implicitHeight: row.visible ? 32 : 0
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    if (row.destructive && !row.isArmed) {
                        dockWindow.menuArmed = row.armedKey;
                        return;
                    }
                    row.triggered();
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: Appearance.rounding.verysmall
                    color: row.isArmed ? Appearance.m3colors.m3errorContainer
                        : row.containsMouse ? Appearance.colors.colLayer1Hover
                        : "transparent"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 10
                    spacing: 9

                    MaterialSymbol {
                        text: row.isArmed ? "warning" : row.symbol
                        iconSize: 17
                        color: row.isArmed ? Appearance.m3colors.m3onErrorContainer
                            : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.isArmed ? Translation.tr("Click again to confirm") : row.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: row.isArmed ? Appearance.m3colors.m3onErrorContainer
                            : Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }
            }

            // ── One dock item ────────────────────────────────────
            component DockItem: Item {
                id: item
                property var entry: null
                property string symbol: ""
                // For items that are not applications and so have no appId to
                // guess from — the Trash names its icon directly.
                property string iconName: ""
                property bool isTrash: false
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
                            if (item.iconName.length > 0)
                                return Quickshell.iconPath(item.iconName, "application-x-executable");
                            if (item.appId.length === 0) return "";
                            // "image-missing" renders a broken-image glyph — a
                            // visible error in the middle of the dock. Every
                            // other module here falls back to the generic app
                            // icon, which at least looks deliberate.
                            return Quickshell.iconPath(AppSearch.guessIcon(item.appId),
                                                       "application-x-executable");
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

                    // Reordering, macOS-style: drag an icon sideways and it
                    // changes places with its neighbours as you pass them.
                    property real grabX: 0
                    property bool didReorder: false
                    readonly property bool canReorder: (item.entry?.pinned ?? false)

                    onPressed: mouse => {
                        itemArea.grabX = mouse.x;
                        itemArea.didReorder = false;
                    }

                    onPositionChanged: mouse => {
                        if (!itemArea.pressed || !itemArea.canReorder) return;
                        if (!(itemArea.pressedButtons & Qt.LeftButton)) return;

                        const pitch = root.iconSize + root.itemSpacing;
                        const slots = Math.round((mouse.x - itemArea.grabX) / pitch);
                        if (slots === 0) return;

                        const list = dockWindow.pinnedList();
                        const from = list.indexOf(item.appId);
                        if (from < 0) return;
                        if (dockWindow.movePinned(item.appId, from + slots)) {
                            itemArea.didReorder = true;
                            dockWindow.dragAppId = item.appId;
                            // The row re-lays out under the pointer, so the
                            // grab origin has to follow or every further pixel
                            // would count from a position that no longer exists.
                            itemArea.grabX = mouse.x;
                        }
                    }

                    onReleased: {
                        dockWindow.dragAppId = "";
                    }

                    onClicked: mouse => {
                        // A drag that reordered is not also a click; without
                        // this, letting go would launch or focus the app you
                        // were only trying to move.
                        if (itemArea.didReorder) {
                            itemArea.didReorder = false;
                            return;
                        }
                        if (mouse.button === Qt.RightButton) {
                            // Used to toggle the pin outright — a silent,
                            // unlabelled, easily mis-aimed way to lose an icon.
                            dockWindow.openMenu(item, item.centerX);
                            return;
                        }
                        if (item.entry === null) {
                            item.activated();
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
