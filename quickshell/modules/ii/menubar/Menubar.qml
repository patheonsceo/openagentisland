pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.modules.ii.island
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Wayland as QsWayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Bluetooth

/**
 * macOS-style menubar. Replaces IslandLeft and IslandRight.
 *
 * No island, no outline, no container. The only thing standing between the text
 * and the wallpaper is a scrim: opaque at the very top, gone by 46px. Drafted
 * against three treatments over the worst part of the wallpaper — a bare
 * text-shadow could not hold the right-hand cluster over the sun shaft, and a
 * glass strip reintroduced exactly the bottom edge this was meant to remove.
 *
 * The left side is deliberately NOT File / Edit / View. macOS can draw those
 * because every app publishes its menu to the system; on Wayland there is no
 * equivalent that covers Electron, so Zen, Cursor, Warp and Discord — most of
 * what actually runs here — would leave it empty. App name plus workspaces is
 * always populated and always does something.
 *
 * The notch keeps its own surface and is untouched; this sits under it, and the
 * centre is left empty so they never collide. Space at the top is already
 * reserved by islandReserve inside IslandNotch, so this claims none of its own.
 */
Scope {
    id: root

    readonly property int barHeight: 30
    readonly property int scrimHeight: 46
    // Which dropdown is open, if any. One string rather than a flag each: it
    // makes "only one at a time" structural instead of something every handler
    // has to remember to enforce, and the click-away catcher needs a single
    // thing to watch.
    property string openMenu: ""

    readonly property string material: Config.options?.bar?.menubarMaterial ?? "bar"
    readonly property real materialOpacity: Config.options?.bar?.menubarOpacity ?? 0.55
    readonly property int sideMargin: 13

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:menubar"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            // islandReserve (in IslandNotch) already reserves the top strip.
            // Claiming it again would push every window down twice.
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: root.scrimHeight

            // Clicks land on the two clusters only; the empty middle stays
            // click-through so the notch and the desktop below keep working.
            mask: Region {
                item: leftCluster
                regions: [
                    Region { item: rightCluster }
                ]
            }

            // The bar is "persistent": part of the grab so clicking it is not
            // treated as clicking away, but never closed by a dismiss itself.
            Component.onCompleted: GlobalFocusGrab.addPersistent(barWindow)
            Component.onDestruction: GlobalFocusGrab.removePersistent(barWindow)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    root.openMenu = "";
                    barWindow.controlCentreOpen = false;
                    barWindow.calendarOpen = false;
                }
            }

            // Dropdown state. Only one of these is ever open at a time.
            property bool calendarOpen: false
            property bool controlCentreOpen: false

            readonly property bool focusedHere:
                (Hyprland.focusedMonitor?.name ?? "") === (barWindow.screen.name ?? "")

            // A flat translucent bar, matching the dock's material. The notch
            // then reads as a cutout in a real bar rather than a pill floating
            // in a gradient — which is what a MacBook actually looks like.
            Rectangle {
                visible: root.material === "bar"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.barHeight
                color: Qt.rgba(Appearance.colors.colLayer0.r,
                               Appearance.colors.colLayer0.g,
                               Appearance.colors.colLayer0.b,
                               root.materialOpacity)

                // Only a bottom edge: the bar runs to the screen edges, so a
                // full border would draw three lines that are not there.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.07)
                }
            }

            // Scrim. Opaque at the top edge, nothing by the bottom — so there is
            // ground under the text but never a visible border.
            Rectangle {
                visible: root.material === "scrim"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.scrimHeight
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(Appearance.colors.colLayer0.r,
                                       Appearance.colors.colLayer0.g,
                                       Appearance.colors.colLayer0.b, 0.74)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.rgba(Appearance.colors.colLayer0.r,
                                       Appearance.colors.colLayer0.g,
                                       Appearance.colors.colLayer0.b, 0.32)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(Appearance.colors.colLayer0.r,
                                       Appearance.colors.colLayer0.g,
                                       Appearance.colors.colLayer0.b, 0.0)
                    }
                }
            }

            // ── Left: menu titles, then workspaces ───────────────
            RowLayout {
                id: leftCluster
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: root.sideMargin
                height: root.barHeight
                spacing: 2

                MenuTitle {
                    id: systemTitle
                    menuId: "system"
                    symbol: Config.options.bar.topLeftIcon === "spark" ? "auto_awesome" : "linux"
                    IslandPopup {
                        anchorItem: systemTitle
                        shouldShow: root.openMenu === "system"
                        interactive: true
                        contentComponent: Component {
                            SystemMenu {
                                open: root.openMenu === "system"
                                onRequestClose: root.openMenu = ""
                            }
                        }
                    }
                }

                MenuTitle {
                    id: windowTitle
                    menuId: "window"
                    label: Translation.tr("Window")
                    IslandPopup {
                        anchorItem: windowTitle
                        shouldShow: root.openMenu === "window"
                        interactive: true
                        contentComponent: Component {
                            AppMenu {
                                open: root.openMenu === "window"
                                appName: barWindow.appName
                                onRequestClose: root.openMenu = ""
                            }
                        }
                    }
                }

                MenuTitle {
                    id: goTitle
                    menuId: "go"
                    label: Translation.tr("Go")
                    IslandPopup {
                        anchorItem: goTitle
                        shouldShow: root.openMenu === "go"
                        interactive: true
                        contentComponent: Component {
                            GoMenu { open: root.openMenu === "go"; onRequestClose: root.openMenu = "" }
                        }
                    }
                }

                MenuTitle {
                    id: captureTitle
                    menuId: "capture"
                    label: Translation.tr("Capture")
                    IslandPopup {
                        anchorItem: captureTitle
                        shouldShow: root.openMenu === "capture"
                        interactive: true
                        contentComponent: Component {
                            CaptureMenu { open: root.openMenu === "capture"; onRequestClose: root.openMenu = "" }
                        }
                    }
                }

                MenuTitle {
                    id: focusTitle
                    menuId: "focus"
                    label: Translation.tr("Focus")
                    IslandPopup {
                        anchorItem: focusTitle
                        shouldShow: root.openMenu === "focus"
                        interactive: true
                        contentComponent: Component {
                            FocusMenu { open: root.openMenu === "focus"; onRequestClose: root.openMenu = "" }
                        }
                    }
                }

                // Workspaces sit at the right end of the menu titles, compact —
                // they are an indicator, not a menu, so they read better after
                // the things that are.
                BarWorkspaces {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 10
                }
            }

            // Focused app, prettified. appId is a desktop-entry id, so it arrives
            // as "dev.warp.Warp" or "org.gnome.Nautilus" more often than a name.
            readonly property string appName: {
                const toplevel = ToplevelManager.activeToplevel;
                if (!toplevel?.activated || !barWindow.focusedHere)
                    return Translation.tr("Desktop");
                const id = toplevel.appId ?? "";
                if (id.length === 0)
                    return Translation.tr("Desktop");
                const last = id.split(".").pop().replace(/[-_]/g, " ");
                return last.charAt(0).toUpperCase() + last.slice(1);
            }

            // ── Right: status cluster ────────────────────────────
            RowLayout {
                id: rightCluster
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: root.sideMargin
                height: root.barHeight
                spacing: 14

                SysTray {
                    Layout.alignment: Qt.AlignVCenter
                    visible: SystemTray.items.values.length > 0
                    showSeparator: false
                }

                // Scroll to change volume, click to mute, right click for the mixer.
                MenuItem {
                    symbol: Audio.sink?.audio?.muted ? "volume_off"
                        : (Audio.sink?.audio?.volume ?? 0) > 0.5 ? "volume_up"
                        : (Audio.sink?.audio?.volume ?? 0) > 0 ? "volume_down" : "volume_mute"
                    active: !(Audio.sink?.audio?.muted ?? false)
                    scrollable: true
                    onTriggered: if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted
                    onSecondary: Quickshell.execDetached(["bash", "-c", Config.options.apps.volumeMixer])
                    onScrolled: delta => {
                        if (!Audio.sink?.audio) return;
                        Audio.sink.audio.volume = Math.max(0, Math.min(1,
                            Audio.sink.audio.volume + delta * 0.05));
                    }
                }

                // Click toggles the adapter, right click opens the full settings.
                MenuItem {
                    visible: BluetoothStatus.available
                    symbol: BluetoothStatus.connected ? "bluetooth_connected"
                        : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                    active: BluetoothStatus.enabled
                    onTriggered: {
                        if (Bluetooth.defaultAdapter)
                            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                    }
                    onSecondary: Quickshell.execDetached(["bash", "-c", Config.options.apps.bluetooth])
                }

                // Click toggles wifi, right click opens network settings.
                MenuItem {
                    symbol: Network.ethernet ? "lan"
                        : !Network.wifiEnabled ? "wifi_off"
                        : Network.wifi ? "wifi" : "wifi_find"
                    active: Network.ethernet || Network.wifiEnabled
                    onTriggered: Network.toggleWifi()
                    onSecondary: Quickshell.execDetached(["bash", "-c", Config.options.apps.network])
                }

                // Control Centre — the sliders/toggles panel, like macOS.
                MenuItem {
                    id: ccItem
                    symbol: "tune"
                    active: barWindow.controlCentreOpen
                    onTriggered: {
                        barWindow.controlCentreOpen = !barWindow.controlCentreOpen;
                        barWindow.calendarOpen = false;
                        root.openMenu = "";
                    }
                    onSecondary: Quickshell.execDetached(["bash", "-c", Config.options.apps.taskManager])

                    IslandPopup {
                        anchorItem: ccItem
                        shouldShow: barWindow.controlCentreOpen
                        interactive: true
                        contentComponent: Component {
                            ControlCentre { targetScreen: barWindow.screen }
                        }
                    }
                }

                // Percentage then glyph, the way macOS orders it.
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    visible: Battery.available
                    // Time remaining beside the percentage while on battery —
                    // the number you actually want is "how long", not "how full".
                    text: Battery.timeRemaining > 0
                        ? `${Math.round(Battery.percentage * 100)}%  ${Battery.formatRemaining(Battery.timeRemaining)}`
                        : `${Math.round(Battery.percentage * 100)}%`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: (Battery.isLow && !Battery.isCharging)
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colOnLayer0
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: Battery.available
                    text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                    iconSize: 17
                    fill: 1
                    color: (Battery.isLow && !Battery.isCharging)
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colOnLayer0
                }

                // Click drops a real calendar, not another sidebar toggle.
                StyledText {
                    id: clockText
                    Layout.alignment: Qt.AlignVCenter
                    text: `${DateTime.collapsedCalendarFormat}  ${DateTime.time}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: clockArea.containsMouse
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnLayer0

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MouseArea {
                        id: clockArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                            else {
                                barWindow.calendarOpen = !barWindow.calendarOpen;
                                barWindow.controlCentreOpen = false;
                            }
                        }
                    }

                    IslandPopup {
                        anchorItem: clockText
                        shouldShow: barWindow.calendarOpen
                        interactive: true
                        contentComponent: Component {
                            CalendarView {}
                        }
                    }
                }
            }
        }
    }

    // Monochrome glyph, no pill behind it. The whole point of the menubar is
    // that nothing has a container.
    //
    // Every item does something specific rather than all opening the same
    // sidebar: left click is the primary action, right click opens the full
    // application for it, and scrolling adjusts where adjusting makes sense.
    // A menubar menu title: text (or a symbol for the system menu), with the
    // filled highlight an open menu gets on macOS. Hovering a sibling while a
    // menu is already open switches to it without a second click, which is how
    // a real menu bar behaves.
    component MenuTitle: Item {
        id: title
        required property string menuId
        property string label: ""
        property string symbol: ""
        readonly property bool isOpen: root.openMenu === title.menuId

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: title.symbol.length > 0 ? 28 : titleText.implicitWidth + 18
        implicitHeight: root.barHeight - 6

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.verysmall
            color: title.isOpen ? Appearance.colors.colPrimary
                : titleArea.containsMouse ? Appearance.colors.colLayer1Hover
                : "transparent"
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: title.symbol.length > 0
            text: title.symbol
            iconSize: 17
            color: title.isOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }

        StyledText {
            id: titleText
            anchors.centerIn: parent
            visible: title.symbol.length === 0
            text: title.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: title.isOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }

        MouseArea {
            id: titleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.openMenu = title.isOpen ? "" : title.menuId;
                barWindow.controlCentreOpen = false;
                barWindow.calendarOpen = false;
            }
            onEntered: if (root.openMenu !== "" && !title.isOpen) root.openMenu = title.menuId;
        }
    }

    component MenuItem: MaterialSymbol {
        id: menuItem
        required property string symbol
        property bool active: true          // false = "off", dimmed
        property bool scrollable: false
        signal triggered()
        signal secondary()
        signal scrolled(int delta)          // +1 up, -1 down

        Layout.alignment: Qt.AlignVCenter
        text: menuItem.symbol
        iconSize: 17
        fill: 1
        opacity: menuItem.active ? 1 : 0.45
        color: itemArea.containsMouse
            ? Appearance.colors.colPrimary
            : Appearance.colors.colOnLayer0

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MouseArea {
            id: itemArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) menuItem.secondary();
                else menuItem.triggered();
            }
            onWheel: wheel => {
                if (!menuItem.scrollable) return;
                menuItem.scrolled(wheel.angleDelta.y > 0 ? 1 : -1);
            }
        }
    }
}
