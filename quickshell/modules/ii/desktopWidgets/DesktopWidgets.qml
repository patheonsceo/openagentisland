pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services
import qs.modules.ii.desktopWidgets.todo
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Host surface for widgets that live on the wallpaper.
 *
 * Sits on WlrLayer.Bottom: above the wallpaper, below every normal window, so a
 * widget is visible whenever the desktop is and never in the way when it isn't.
 *
 * This is a separate surface from Background.qml on purpose. Two reasons:
 *   - Blur. Hyprland already runs blur with xray on, so a `blur` layerrule
 *     against this namespace frosts the wallpaper for free on the GPU. Doing it
 *     inside the background window would mean decoding the wallpaper a second
 *     time into a Qt effect.
 *   - Keyboard. Background.qml takes no keyboard focus, so a text field there
 *     could never be typed into. Here focus is raised on demand and dropped the
 *     moment the field loses it, so it never steals keys from an app.
 *
 * Input is masked to the widget itself, so the rest of the desktop stays
 * clickable straight through.
 */
Scope {
    id: root

    readonly property var todoConfig: Config.options.background.widgets.todo

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: widgetWindow
            required property var modelData

            // One list across three monitors would just be three copies of itself.
            readonly property bool isTargetScreen: root.todoConfig.screenName.length === 0
                ? (Quickshell.screens.length > 0 && modelData.name === Quickshell.screens[0].name)
                : modelData.name === root.todoConfig.screenName

            screen: modelData
            visible: Config.ready
                && root.todoConfig.enable
                && widgetWindow.isTargetScreen
                && !GlobalStates.screenLocked

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:desktopWidgets"
            WlrLayershell.layer: WlrLayer.Bottom
            // Only ask for keys while a field is actually focused.
            WlrLayershell.keyboardFocus: todoCard.inputActive
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Everything outside the card stays clickable through to the desktop —
            // EXCEPT while the settings menu is open, when the whole surface has to
            // accept input or the menu (which extends past the card) gets no clicks
            // at all and the click-away catcher never fires.
            mask: todoCard.menuOpen ? null : cardOnlyRegion
            Region { id: cardOnlyRegion; item: todoCard }

            function restorePosition() {
                if (!Config.ready) return;
                todoCard.x = Math.max(0, Math.min(root.todoConfig.x,
                    widgetWindow.width - todoCard.width));
                todoCard.y = Math.max(0, Math.min(root.todoConfig.y,
                    widgetWindow.height - todoCard.height));
            }

            Component.onCompleted: widgetWindow.restorePosition()
            onWidthChanged: widgetWindow.restorePosition()
            onHeightChanged: widgetWindow.restorePosition()

            Connections {
                target: Config
                function onReadyChanged() { widgetWindow.restorePosition(); }
            }

            // Position lives in config, but nothing re-applied it when the value
            // changed — so editing it (or the menu's "Reset position") moved the
            // number and left the widget where it was.
            Connections {
                target: root.todoConfig
                function onXChanged() { widgetWindow.restorePosition(); }
                function onYChanged() { widgetWindow.restorePosition(); }
            }

            TodoCard {
                id: todoCard
                screenWidth: widgetWindow.width
                screenHeight: widgetWindow.height
            }
        }
    }
}
