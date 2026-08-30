pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The focused application's menu.
 *
 * Not the app's own menu — Linux apps export those over DBus inconsistently
 * enough that a File/Edit/View strip would be empty or wrong most of the time.
 * These are window-manager actions instead, so every application gets a
 * working menu without having to cooperate. It gives the shape of a macOS app
 * menu using the only verbs that are universally available.
 */
Item {
    id: root

    property bool open: false
    property string appName: ""
    signal requestClose()

    property string armed: ""
    onOpenChanged: if (!root.open) root.armed = ""

    implicitWidth: 244
    implicitHeight: menuColumn.implicitHeight + 12

    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property string appId: root.toplevel?.appId ?? ""
    readonly property bool hasApp: root.appId.length > 0 && (root.toplevel?.activated ?? false)
    readonly property bool pinned: (Config.options?.dock?.pinnedApps ?? []).indexOf(root.appId) >= 0

    // Every window of this app, so Quit can close all of them rather than the
    // focused one — which is what Quit means everywhere else.
    readonly property var siblings: {
        const all = ToplevelManager.toplevels?.values ?? [];
        return all.filter(t => (t?.appId ?? "") === root.appId);
    }

    function pidOf(tl) {
        const c = HyprlandData.clientForToplevel(tl);
        return c?.pid ?? -1;
    }

    ColumnLayout {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: 4
            text: root.hasApp ? root.appName : Translation.tr("No window focused")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.hasApp ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
            elide: Text.ElideRight
        }

        MenuSeparator { visible: root.hasApp }

        MenuRow {
            visible: root.hasApp
            symbol: "add"
            label: Translation.tr("New Window")
            onTriggered: {
                DesktopEntries.heuristicLookup(root.appId)?.execute();
                root.requestClose();
            }
        }
        MenuRow {
            visible: root.hasApp
            symbol: "keyboard_arrow_down"
            label: Translation.tr("Hide")
            // Hyprland has no minimise. A silent move to a special workspace is
            // the closestequivalent: the window survives, leaves the screen,
            // and comes back when the workspace is toggled.
            onTriggered: {
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = "special:hidden", follow = false })`);
                root.requestClose();
            }
        }
        MenuRow {
            visible: root.hasApp
            symbol: "close"
            label: Translation.tr("Close Window")
            onTriggered: { root.toplevel?.close(); root.requestClose(); }
        }

        MenuSeparator { visible: root.hasApp }

        MenuRow {
            visible: root.hasApp
            symbol: root.pinned ? "keep_off" : "keep"
            label: root.pinned ? Translation.tr("Remove from Dock") : Translation.tr("Keep in Dock")
            onTriggered: { TaskbarApps.togglePin(root.appId); root.requestClose(); }
        }

        MenuSeparator { visible: root.hasApp }

        MenuRow {
            visible: root.hasApp
            symbol: "logout"
            label: root.siblings.length > 1
                ? Translation.tr("Quit — %1 windows").arg(root.siblings.length)
                : Translation.tr("Quit")
            destructive: true
            armedKey: "quit"
            onTriggered: {
                const tls = root.siblings.slice();
                for (let i = tls.length - 1; i >= 0; i--) tls[i]?.close();
                root.requestClose();
            }
        }
        MenuRow {
            visible: root.hasApp
            symbol: "bolt"
            label: Translation.tr("Force Quit")
            destructive: true
            armedKey: "force"
            onTriggered: {
                // SIGKILL, because Force Quit that politely asks is not force.
                for (const tl of root.siblings) {
                    const pid = root.pidOf(tl);
                    if (pid > 0) Quickshell.execDetached(["kill", "-9", `${pid}`]);
                }
                root.requestClose();
            }
        }
    }

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 3
        implicitHeight: 1
        color: Appearance.m3colors.m3outlineVariant
    }

    component MenuRow: MouseArea {
        id: row
        required property string symbol
        required property string label
        property bool destructive: false
        property string armedKey: ""
        signal triggered()

        readonly property bool isArmed: row.destructive && root.armed === row.armedKey

        Layout.fillWidth: true
        implicitHeight: row.visible ? 32 : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (row.destructive && !row.isArmed) { root.armed = row.armedKey; return; }
            row.triggered();
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: Appearance.rounding.verysmall
            color: row.isArmed ? Appearance.m3colors.m3errorContainer
                : row.containsMouse ? Appearance.colors.colLayer1Hover
                : "transparent"

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
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
}
