pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * The desktop / folder context menu.
 *
 * Deliberately parameterised by `targetDir` rather than hardwired to ~/Desktop:
 * the same component is meant to serve a Finder window later, and a menu that
 * only knows one directory would have to be rewritten to get there.
 *
 * `targetPath` empty  -> right-clicked empty space (create / open / view)
 * `targetPath` set    -> right-clicked an item (open / rename / trash)
 *
 * Every action shells out. Reimplementing copy, trash or archive semantics in
 * QML would be a worse version of what gio and xdg-open already do correctly.
 */
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 9999

    property string targetDir: ""
    property string targetPath: ""
    property real boardWidth: 0
    property real boardHeight: 0
    readonly property bool onItem: root.targetPath.length > 0

    signal refreshRequested()
    signal cleanUpRequested()
    // The board creates these, not us: only it knows a free name AND can seed
    // the new item's position at the click point.
    signal createRequested(string kind)

    function popupAt(px, py) {
        // Flip near an edge so the menu is never half off-screen.
        menu.x = Math.min(px, Math.max(0, root.boardWidth - menu.width - 8));
        menu.y = Math.min(py, Math.max(0, root.boardHeight - menu.height - 8));
        root.visible = true;
    }
    function dismiss() { root.visible = false; }

    function run(cmd) {
        Quickshell.execDetached(["bash", "-lc", cmd]);
        root.dismiss();
    }

    // Click-away catcher. Fills the board so the menu closes on any outside
    // click, the way every other menu on this desktop behaves.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.dismiss()
    }

    Rectangle {
        id: menu
        width: 250
        height: column.implicitHeight + 12
        radius: 12
        color: "#f21c1c20"
        border.width: 1
        border.color: "#33ffffff"

        // Keeps clicks on the menu itself from reaching the catcher above.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
            id: column
            anchors.fill: parent
            anchors.margins: 6
            spacing: 1

            component Row_: Rectangle {
                id: row
                property string label: ""
                property string cmd: ""
                property bool danger: false
                signal picked()
                width: column.width
                height: 30
                radius: 7
                color: rowArea.containsMouse ? (row.danger ? "#55e05c56" : "#332f6fed") : "transparent"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: row.label
                    color: row.danger ? "#ff8a84" : "#eaeaea"
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (row.cmd.length > 0) root.run(row.cmd);
                        else { row.picked(); root.dismiss(); }
                    }
                }
            }

            component Sep: Rectangle {
                width: column.width; height: 1
                color: "#22ffffff"
            }

            // ── item actions ──────────────────────────────────
            Row_ {
                visible: root.onItem
                label: "Open"
                cmd: `xdg-open ${JSON.stringify(root.targetPath)}`
            }
            Row_ {
                visible: root.onItem
                label: "Copy Path"
                cmd: `printf %s ${JSON.stringify(root.targetPath)} | wl-copy`
            }
            Row_ {
                visible: root.onItem
                label: "Duplicate"
                cmd: `cp -r ${JSON.stringify(root.targetPath)} ${JSON.stringify(root.targetPath + " copy")}`
            }
            Row_ {
                visible: root.onItem
                label: "Compress"
                cmd: `cd ${JSON.stringify(root.targetDir)} && zip -r ${JSON.stringify(root.targetPath + ".zip")} ${JSON.stringify(root.targetPath)}`
            }
            Row_ {
                visible: root.onItem
                label: "Move to Trash"
                danger: true
                cmd: `gio trash ${JSON.stringify(root.targetPath)}`
            }
            Sep { visible: root.onItem }

            // ── create ────────────────────────────────────────
            Row_ {
                label: "New Folder"
                onPicked: root.createRequested("folder")
            }
            Row_ {
                label: "New File"
                onPicked: root.createRequested("file")
            }
            Sep {}

            // ── open here ─────────────────────────────────────
            Row_ {
                label: "Open Terminal Here"
                cmd: `kitty --directory ${JSON.stringify(root.targetDir)}`
            }
            Row_ {
                label: "Claude Code Here"
                cmd: `kitty --directory ${JSON.stringify(root.targetDir)} fish -c "claude --dangerously-skip-permissions"`
            }
            Row_ {
                label: "Open in VS Code"
                cmd: `code ${JSON.stringify(root.targetDir)}`
            }
            Row_ {
                label: "Open in Cursor"
                cmd: `cursor ${JSON.stringify(root.targetDir)}`
            }
            Row_ {
                label: "Open in Warp"
                cmd: `warp-terminal --working-directory ${JSON.stringify(root.targetDir)} || warp-terminal`
            }
            Row_ {
                label: "Open in Finder"
                cmd: `${JSON.stringify(Quickshell.env("HOME") + "/.config/hypr/custom/scripts/finder.sh")} ${JSON.stringify(root.targetDir)}`
            }
            Sep {}

            // ── view / system ─────────────────────────────────
            Row_ {
                label: "Paste"
                // wl-paste writes the clipboard as a file; harmless no-op when
                // the clipboard holds no file list.
                cmd: `cd ${JSON.stringify(root.targetDir)} && wl-paste > "pasted-$(date +%s)" 2>/dev/null || true`
            }
            Row_ {
                label: "Clean Up"
                onPicked: root.cleanUpRequested()
            }
            Row_ {
                label: "Refresh"
                onPicked: root.refreshRequested()
            }
            Sep {}
            Row_ {
                label: "Change Wallpaper"
                cmd: `qs -c openagentisland ipc call wallpaperSelector toggle 2>/dev/null || ${JSON.stringify(Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/colors/switchwall.sh")}`
            }
            Row_ {
                label: "Display Settings"
                cmd: `XDG_CURRENT_DESKTOP=gnome qs -p ${JSON.stringify(Quickshell.env("HOME") + "/.config/quickshell/openagentisland/settings.qml")}`
            }
        }
    }
}
