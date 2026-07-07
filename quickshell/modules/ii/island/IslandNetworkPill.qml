pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Network pill — status icon always; hover reveals live ↓/↑ throughput.
// Reads totals from /proc/net/dev (excluding lo) once per second and diffs.
Rectangle {
    id: root
    radius: IslandStyle.radius
    color: IslandStyle.pillColor
    border.width: IslandStyle.borderWidth
    border.color: IslandStyle.pillBorder
    // Compact (icon only) → expands inline to show rates on hover. The left-island
    // window is fixed-width + masked, so this grows into reserved space (no window
    // resize → no jitter). clip hides the rates until the pill has grown to fit.
    implicitWidth: content.implicitWidth + IslandStyle.hPadding * 2
    implicitHeight: IslandStyle.pillHeight
    clip: true
    Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    property real rxRate: 0
    property real txRate: 0
    property real lastRx: -1
    property real lastTx: -1

    function fmt(b) {
        if (b < 1024)
            return `${Math.round(b)} B/s`;
        if (b < 1048576)
            return `${(b / 1024).toFixed(1)} KB/s`;
        return `${(b / 1048576).toFixed(1)} MB/s`;
    }

    Process {
        id: netProc
        command: ["bash", "-c", "awk 'NR>2 && $1!=\"lo:\"{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev"]
        stdout: SplitParser {
            onRead: data => {
                const p = data.trim().split(/\s+/);
                if (p.length < 2)
                    return;
                const rx = parseFloat(p[0]);
                const tx = parseFloat(p[1]);
                if (root.lastRx >= 0) {
                    root.rxRate = Math.max(0, rx - root.lastRx);
                    root.txRate = Math.max(0, tx - root.lastTx);
                }
                root.lastRx = rx;
                root.lastTx = tx;
            }
        }
    }
    // Rates are only ever shown on hover, so only sample /proc/net/dev while
    // hovered. Idle cost is zero (no per-second process spawn). On un-hover we
    // reset the baseline so the first sample on the next hover re-baselines
    // instead of showing a bogus spike accumulated over the idle gap.
    Timer { interval: 1000; running: hover.hovered; repeat: true; triggeredOnStart: true; onTriggered: netProc.running = true }

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (!hovered) {
                root.lastRx = -1;
                root.lastTx = -1;
                root.rxRate = 0;
                root.txRate = 0;
            }
        }
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 6

        // Rates take their fixed slot only while hovered (so the pill is compact
        // when idle); fixed width so the live numbers don't jitter; opacity fades.
        StyledText {
            visible: hover.hovered
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
            text: `↓ ${root.fmt(root.rxRate)}`
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: IslandStyle.subtextColor
        }
        MaterialSymbol {
            text: Network.materialSymbol
            iconSize: 18
            fill: 1
            color: IslandStyle.textColor
        }
        StyledText {
            visible: hover.hovered
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignLeft
            text: `↑ ${root.fmt(root.txRate)}`
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: IslandStyle.subtextColor
        }
    }
}
