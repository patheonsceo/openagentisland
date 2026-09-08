pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import QtQuick.Effects
import Quickshell

/**
 * One item on the desktop: icon, label, drag, open.
 *
 * Drag semantics are the interesting part. While dragging we move a floating
 * copy, not the real position — the real position only changes if `dropped`
 * accepts the landing spot. A drop onto a widget is refused, and the icon
 * animates back to where it started. Nothing is written on a refused drop, so
 * a mis-drop can never cost you a placement you meant to keep.
 */
Item {
    id: root

    required property string itemName
    required property string itemPath
    required property bool isDir
    property int iconSize: 64
    property real boardWidth: 0
    property real boardHeight: 0

    // Owned by the board: a delegate cannot know that you clicked
    // somewhere else, so it must not latch its own highlight.
    property bool selected: false
    signal selectRequested()

    // Return true to accept the drop; false snaps the icon home.
    signal dropped(real nx, real ny)
    signal activated()
    signal contextRequested(real gx, real gy)

    // Freedesktop icon name for this item. WhiteSur ships these itself under
    // mimes/ (3000+ of them), so files get proper macOS icons, not a fallback.
    // Extension mapping rather than spawning `xdg-mime` per file — one process
    // per desktop item would be absurd.
    readonly property string iconName: {
        if (root.isDir) return "folder";
        const n = root.itemName.toLowerCase();
        const ext = n.indexOf(".") >= 0 ? n.slice(n.lastIndexOf(".") + 1) : "";
        switch (ext) {
        case "pdf":  return "application-pdf";
        case "zip": case "gz": case "xz": case "tar": case "7z": case "rar":
            return "application-zip";
        case "png": case "jpg": case "jpeg": case "gif": case "webp": case "svg": case "bmp":
            return "image-x-generic";
        case "mp4": case "mkv": case "webm": case "mov": case "avi":
            return "video-x-generic";
        case "mp3": case "flac": case "wav": case "ogg": case "m4a":
            return "audio-x-generic";
        case "sh": case "bash": case "fish": case "zsh":
            return "text-x-script";
        case "py":   return "text-x-python";
        case "js": case "ts": case "jsx": case "tsx": case "qml":
            return "text-x-javascript";
        case "json": case "yaml": case "yml": case "toml": case "conf": case "ini":
            return "text-x-generic";
        case "md": case "txt": case "log":
            return "text-x-generic";
        case "desktop": return "application-x-executable";
        default: return "text-x-generic";
        }
    }

    // ── Drag state ────────────────────────────────────────────
    property real homeX: root.x
    property real homeY: root.y
    property bool dragging: false

    Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !root.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    // Selection / hover plate, sized to the cell so the hit area matches what
    // you see.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 10
        color: root.selected ? "#552f6fed"
             : (hoverArea.containsMouse ? "#22ffffff" : "transparent")
        border.width: root.selected ? 1 : 0
        border.color: "#882f6fed"
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 8
        spacing: 4

        Image {
            id: iconImage
            width: root.iconSize
            height: root.iconSize
            anchors.horizontalCenter: parent.horizontalCenter
            source: Quickshell.iconPath(root.iconName, root.isDir ? "folder" : "text-x-generic")
            sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)  // crisp on 1.5x
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: root.dragging ? 0.55 : 1.0
            Behavior on opacity { NumberAnimation { duration: 90 } }
        }

        Text {
            width: root.width - 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.itemName
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            // Wallpapers are arbitrary; without a shadow a light photo makes
            // white labels unreadable.
            style: Text.Outline
            styleColor: "#cc000000"
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real pressX: 0
        property real pressY: 0
        property bool moved: false

        onPressed: event => {
            if (event.button === Qt.RightButton) return;
            hoverArea.pressX = event.x;
            hoverArea.pressY = event.y;
            hoverArea.moved = false;
            root.homeX = root.x;
            root.homeY = root.y;
            root.selectRequested();
        }

        onPositionChanged: event => {
            if (!(event.buttons & Qt.LeftButton)) return;
            const dx = event.x - hoverArea.pressX;
            const dy = event.y - hoverArea.pressY;
            if (!hoverArea.moved && Math.abs(dx) + Math.abs(dy) < 6) return;   // deadzone
            if (!hoverArea.moved) {
                hoverArea.moved = true;
                root.dragging = true;
                DesktopLayout.iconDragActive = true;   // widgets draw their tint
            }
            root.x = Math.max(0, Math.min(root.boardWidth - root.width, root.x + dx));
            root.y = Math.max(0, Math.min(root.boardHeight - root.height, root.y + dy));
        }

        onReleased: event => {
            if (event.button === Qt.RightButton) return;
            if (!hoverArea.moved) return;
            root.dragging = false;
            DesktopLayout.iconDragActive = false;
            // Refused drops animate home via the Behaviors above.
            if (DesktopLayout.collides(root.x, root.y, root.width, root.height)) {
                root.x = root.homeX;
                root.y = root.homeY;
            } else {
                root.dropped(root.x, root.y);
            }
            hoverArea.moved = false;
        }

        onDoubleClicked: event => {
            if (event.button === Qt.LeftButton) root.activated();
        }

        onClicked: event => {
            if (event.button === Qt.RightButton) {
                root.selectRequested();
                root.contextRequested(root.x + event.x, root.y + event.y);
            }
        }
    }
}
