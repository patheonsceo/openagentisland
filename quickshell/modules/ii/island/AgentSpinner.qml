pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick

// Pixel-art agent mascot + state glyph — distinct frame sets AND motion per state:
//   working  → running legs (blue) + bouncing bars
//   permission/waiting → antennae-up "alert" wiggle (orange) + a periodic shake + "?"
//   done     → arms-up celebrate wave (green) + a happy hop
//   running/idle (resting) → calm bob + occasional blink (green/grey)
//   compact  → run frames (purple)
Item {
    id: root
    property string mode: "working"
    property int pixel: 2
    property bool animated: true

    readonly property color tint: {
        switch (root.mode) {
        case "working": return "#7AA2F7";    // blue
        case "running": return "#7EE787";    // green
        case "waiting": return "#9BB1C9";     // soft blue-grey — calm "waiting for you"
        case "permission": return "#E8A23D";  // orange — attention (permission only)
        case "compact": return "#B58AF8";     // purple
        case "done": return "#7EE787";        // green
        default: return "#9AA0AA";            // idle grey
        }
    }
    readonly property bool showBars: root.mode === "working" || root.mode === "compact"
    readonly property bool showQuestion: root.mode === "permission"

    // ---------- frame sets (8×8) ----------
    readonly property var runFrames: [
        [0,0,1,0,0,1,0,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 0,0,1,1,1,1,0,0, 0,1,0,0,0,0,1,0, 1,0,0,0,0,0,0,1],
        [0,0,1,0,0,1,0,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 0,0,1,1,1,1,0,0, 0,0,1,0,0,1,0,0, 0,1,0,0,0,1,0,0],
        [0,0,1,0,0,1,0,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 0,0,1,1,1,1,0,0, 0,0,0,1,1,0,0,0, 0,0,1,0,0,1,0,0],
        [0,0,1,0,0,1,0,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 0,0,1,1,1,1,0,0, 0,1,0,0,0,1,0,0, 0,0,1,0,0,0,1,0]
    ]
    readonly property var celebrateFrames: [
        [1,0,0,0,0,0,0,1, 0,0,1,1,1,1,0,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 0,1,1,1,1,1,1,0, 0,1,0,0,0,0,1,0, 1,0,0,0,0,0,0,1],
        [0,0,1,0,0,1,0,0, 1,0,1,1,1,1,0,1, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 0,1,1,1,1,1,1,0, 0,0,1,0,0,1,0,0, 0,1,0,0,0,1,0,0]
    ]
    readonly property var alertFrames: [
        [0,1,0,0,0,0,1,0, 0,0,1,0,0,1,0,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 1,0,1,0,0,1,0,1, 0,0,0,1,1,0,0,0],
        [1,0,0,0,0,0,0,1, 0,1,0,0,0,0,1,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 1,0,1,0,0,1,0,1, 0,0,0,1,1,0,0,0]
    ]
    readonly property var idleFrames: [
        [0,0,1,0,0,1,0,0, 0,1,1,1,1,1,1,0, 1,1,0,1,1,0,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 0,0,1,1,1,1,0,0, 0,1,0,0,0,0,1,0, 1,0,0,0,0,0,0,1],
        [0,0,1,0,0,1,0,0, 0,1,1,1,1,1,1,0, 1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1, 1,0,1,1,1,1,0,1, 0,0,1,1,1,1,0,0, 0,1,0,0,0,0,1,0, 1,0,0,0,0,0,0,1]
    ]
    readonly property var qFrame: [
        0,1,1,1,0, 1,0,0,0,1, 0,0,0,1,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,1,0,0]

    function framesFor(m) {
        if (m === "done") return root.celebrateFrames;
        if (m === "permission") return root.alertFrames;
        if (m === "running" || m === "idle" || m === "waiting") return root.idleFrames;
        return root.runFrames; // working, compact
    }
    function intervalFor(m) {
        if (m === "done") return 200;
        if (m === "permission") return 150;
        if (m === "running" || m === "idle" || m === "waiting") return 480;
        return 150;
    }

    property int frame: 0
    property int barFrame: 0
    Timer {
        interval: root.intervalFor(root.mode)
        running: root.animated
        repeat: true
        onTriggered: {
            root.frame = (root.frame + 1) % root.framesFor(root.mode).length;
            // bars advance on the SAME tick — two unsynchronized timers each force
            // their own full compositor pass across every monitor; one shared tick
            // batches them into a single damage event
            if (root.showBars) root.barFrame = (root.barFrame + 1) % 4;
        }
    }

    function barH(i) {
        const tbl = [[0.35, 0.85, 0.30], [0.85, 0.40, 0.70], [0.50, 1.00, 0.40], [1.00, 0.30, 0.80]];
        return tbl[(root.barFrame + i * 2) % tbl.length][i];
    }

    // ---------- per-state motion ----------
    // Perf: the resting bob used to be a smooth Infinite tween — that damages the
    // (blurred, full-screen) notch layer at panel refresh rate (90-100 fps) on every
    // monitor for as long as ANY session exists. A discrete pixel hop reads the same
    // in 8x8 pixel-art and costs ~1 repaint/sec instead of ~90. Done-hop and
    // permission-shake stay smooth: they're brief and meant to grab attention.
    property real motionX: 0
    property real motionY: 0
    onModeChanged: { root.motionX = 0; root.motionY = 0; }

    Timer { // gentle stepped bob (resting + calm waiting)
        interval: 850
        running: root.animated && (root.mode === "running" || root.mode === "idle" || root.mode === "waiting")
        repeat: true
        onTriggered: root.motionY = root.motionY === 0 ? -root.pixel : 0
    }
    SequentialAnimation on motionY { // celebrate hop (done) — transient (~5s linger)
        running: root.animated && root.mode === "done"
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: -5 * root.pixel; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { from: -5 * root.pixel; to: 0; duration: 260; easing.type: Easing.OutBounce }
        PauseAnimation { duration: 280 }
    }
    SequentialAnimation on motionX { // alert shake (permission only)
        running: root.animated && root.mode === "permission"
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1.5 * root.pixel; duration: 70 }
        NumberAnimation { from: 1.5 * root.pixel; to: -1.5 * root.pixel; duration: 110 }
        NumberAnimation { from: -1.5 * root.pixel; to: 0; duration: 70 }
        PauseAnimation { duration: 650 }
    }

    implicitHeight: 8 * root.pixel
    implicitWidth: glyphRow.implicitWidth

    component PixelCanvas: Canvas {
        id: pc
        property var pixels: []
        property int gw: 8
        property int gh: 8
        property int cell: 2
        property color col: "#ffffff"
        implicitWidth: gw * cell
        implicitHeight: gh * cell
        onPixelsChanged: pc.requestPaint()
        onColChanged: pc.requestPaint()
        onPaint: {
            const ctx = pc.getContext("2d");
            ctx.clearRect(0, 0, pc.width, pc.height);
            ctx.fillStyle = pc.col;
            for (let y = 0; y < pc.gh; y++)
                for (let x = 0; x < pc.gw; x++)
                    if (pc.pixels[y * pc.gw + x] === 1)
                        ctx.fillRect(x * pc.cell, y * pc.cell, pc.cell, pc.cell);
        }
    }

    Row {
        id: glyphRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pixel * 2 + 4

        PixelCanvas {
            anchors.verticalCenter: parent.verticalCenter
            gw: 8
            gh: 8
            cell: root.pixel
            col: root.tint
            pixels: root.framesFor(root.mode)[root.frame % root.framesFor(root.mode).length]
            transform: Translate { x: root.motionX; y: root.motionY }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showBars
            spacing: root.pixel
            Repeater {
                model: 3
                delegate: Item {
                    required property int index
                    width: root.pixel
                    height: 8 * root.pixel
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        radius: width / 2
                        color: root.tint
                        // Stepped on purpose (no Behavior tween): the 170ms bar timer
                        // retriggering a 160ms tween meant continuous vsync damage the
                        // whole time a session is "working" — i.e. hours. Snapping at
                        // ~6fps matches the pixel-equalizer look.
                        height: Math.max(root.pixel, parent.height * root.barH(parent.index))
                    }
                }
            }
        }

        PixelCanvas {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showQuestion
            gw: 5
            gh: 8
            cell: root.pixel
            col: root.tint
            pixels: root.qFrame
            opacity: root.frame === 0 ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }
    }
}
