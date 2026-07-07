pragma ComponentBehavior: Bound
import QtQuick

// Live star animation — a field of drifting, twinkling, slowly-rotating 4-point
// sparkles referencing the AgentIsland logo star. Cheap: GPU Image instances with
// property animations only (no per-frame repaint). Purely decorative.
Item {
    id: field
    property int count: 26
    property real minSize: 3
    property real maxSize: 15
    property real intensity: 0.55   // peak opacity ceiling

    Repeater {
        model: field.count
        delegate: Image {
            id: star
            required property int index
            source: Qt.resolvedUrl("assets/sparkle.png")
            sourceSize.width: 64
            sourceSize.height: 64
            mipmap: true
            smooth: true
            transformOrigin: Item.Center

            // per-instance randomness, captured once
            readonly property real r1: Math.random()
            readonly property real r2: Math.random()
            readonly property real r3: Math.random()
            readonly property real sz: field.minSize + r1 * (field.maxSize - field.minSize)

            width: sz
            height: sz
            x: r2 * Math.max(1, field.width - width)
            y: r3 * Math.max(1, field.height - height)
            opacity: 0

            // all three gated on visibility — Infinite tweens on a hidden window
            // still burn CPU ticking property writes every animation frame
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: star.visible
                PauseAnimation { duration: Math.round(star.r1 * 3200) }
                NumberAnimation { to: field.intensity * (0.4 + star.r2 * 0.5); duration: 1900 + Math.round(star.r3 * 2400); easing.type: Easing.InOutSine }
                NumberAnimation { to: field.intensity * 0.04; duration: 1900 + Math.round(star.r1 * 2400); easing.type: Easing.InOutSine }
            }
            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: star.visible
                NumberAnimation { to: 1.1; duration: 2600 + Math.round(star.r2 * 2400); easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.92; duration: 2600 + Math.round(star.r3 * 2400); easing.type: Easing.InOutSine }
            }
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 30000 + Math.round(star.r2 * 20000)
                loops: Animation.Infinite
                running: star.visible
            }
        }
    }
}
