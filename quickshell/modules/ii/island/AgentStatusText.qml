pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects

// Animated agent status label: optional cycling dots ("Working" → "Working...")
// and an optional shimmer sweep across the glyphs. Width is reserved for the max
// dot count so the cycling never jitters the notch.
Item {
    id: root
    property string word: ""
    property bool animateDots: false
    property bool shimmer: false
    property int pixelSize: Appearance.font.pixelSize.small
    property color baseColor: IslandStyle.textColor

    property int dots: 0
    // One shared ticker drives BOTH the dot cycle and the shimmer sweep, so a
    // "working" notch produces a single damage event per tick instead of two
    // out-of-phase timers each forcing their own compositor pass.
    property int tick: 0
    Timer {
        interval: 200
        running: (root.animateDots || root.shimmer) && root.visible
        repeat: true
        onTriggered: {
            root.tick++;
            if (root.animateDots && root.tick % 2 === 0)
                root.dots = (root.dots + 1) % 4;
        }
    }
    readonly property string shown: root.word + (root.animateDots ? "....".substring(0, root.dots) : "")
    readonly property string maxStr: root.word + (root.animateDots ? "..." : "")

    implicitWidth: maskText.implicitWidth
    implicitHeight: maskText.implicitHeight

    // hidden, max-width copy — drives layout width + shimmer mask shape
    StyledText {
        id: maskText
        text: root.maxStr
        font.pixelSize: root.pixelSize
        font.weight: Font.Medium
        color: "white"
        visible: false
    }
    // visible (dim while shimmering) text
    StyledText {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.shown
        font.pixelSize: root.pixelSize
        font.weight: Font.Medium
        color: root.baseColor
        opacity: root.shimmer ? 0.72 : 1.0
    }
    // bright band sweeping across, clipped to the text glyphs.
    // Perf: stepped sweep (timer-driven) instead of an Infinite NumberAnimation —
    // the smooth version re-rendered this OpacityMask shader pass at panel refresh
    // rate (~90fps) for the entire time a session was working/waiting. 8 hops per
    // sweep + a parked hold between sweeps reads the same at a glance and costs
    // ~5 small repaints/sec only during the sweep, zero during the hold.
    readonly property int shimmerSweepSteps: 8
    readonly property int shimmerHoldSteps: 7
    readonly property int shimmerStep: root.tick % (root.shimmerSweepSteps + root.shimmerHoldSteps)
    Item {
        anchors.fill: maskText
        visible: root.shimmer
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: maskText }
        Rectangle {
            id: band
            height: parent.height
            width: Math.max(20, maskText.implicitWidth * 0.45)
            x: root.shimmerStep <= root.shimmerSweepSteps
               ? -band.width + (root.shimmerStep / root.shimmerSweepSteps) * (maskText.implicitWidth + 2 * band.width)
               : maskText.implicitWidth + band.width   // parked off-glyph during the hold — no repaints
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: "#FFFFFF" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
}
