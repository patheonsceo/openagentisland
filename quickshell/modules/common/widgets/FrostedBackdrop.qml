import qs.modules.common
import QtQuick
import QtQuick.Effects

/**
 * Frosted glass for desktop widgets.
 *
 * Compositor blur was the first choice and does not work on this setup: the
 * Hyprland config uses the Lua parser, where `hyprctl keyword` does not exist,
 * and even applied correctly as `hl.layer_rule` the blur never reached a
 * bottom-layer surface. Rather than depend on behaviour we cannot verify, the
 * frost is drawn here.
 *
 * Naively this decodes the wallpaper a second time at full size — 3840x2485 is
 * ~38MB of texture for something about to be destroyed by a 64px blur. So
 * `sourceSize` caps the decode at 640px wide: blurring a downscaled image is
 * indistinguishable from blurring a full one, and costs under a megabyte.
 *
 * Three stacked pieces, because each solves a different problem:
 *   sampled    a wallpaper copy laid out like the real one and shifted by the
 *              widget's position, oversized by `pad` so the blur has real pixels
 *              to reach for at the edges instead of bleeding in transparency
 *   frostLayer card-sized, so enabling `layer` crops the oversized blur back to
 *              the widget, then `maskSource` rounds the corners
 *   tint       what makes it read as one surface rather than smeared wallpaper
 */
Item {
    id: root

    property real radius: 22
    property real surfaceX: 0          // widget position within its layer surface
    property real surfaceY: 0
    property int screenWidth: 1920
    property int screenHeight: 1080
    property color tint: Appearance.colors.colPrimary
    property real tintOpacity: 0.10
    // Luminance floor. Blur alone tracks whatever is behind it, so the card goes
    // pale over a sunlit patch of wallpaper and text stops holding. A real macOS
    // material has a fixed floor under the blur; this is that floor.
    property color base: Appearance.colors.colLayer0
    property real baseOpacity: 0.42
    property real blurMax: 64
    // Solid skips sampling the wallpaper entirely — no blur pass, no decode —
    // so it is also the cheaper mode, not just the more opaque one.
    property bool solid: false
    readonly property real pad: root.blurMax + 16

    readonly property bool wallpaperIsVideo: {
        const path = Config.options.background.wallpaperPath ?? "";
        return [".mp4", ".webm", ".mkv", ".avi", ".mov"].some(ext => path.endsWith(ext));
    }
    readonly property string wallpaperPath: root.wallpaperIsVideo
        ? Config.options.background.thumbnailPath
        : Config.options.background.wallpaperPath

    // Oversized source. Never drawn directly.
    Item {
        id: sampled
        anchors.fill: parent
        anchors.margins: -root.pad
        visible: false
        layer.enabled: true

        Image {
            source: root.wallpaperPath
            sourceSize.width: 640          // capped decode; we blur it to mush anyway
            fillMode: Image.PreserveAspectCrop
            width: root.screenWidth
            height: root.screenHeight
            x: -root.surfaceX + root.pad
            y: -root.surfaceY + root.pad
            smooth: true
            asynchronous: true
            cache: true
        }
    }

    // Rounded alpha mask at widget size.
    Item {
        id: maskShape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "black"
        }
    }

    Item {
        id: frostLayer
        anchors.fill: parent
        // Widget-sized layer: crops the oversized blur below back to the card,
        // and gives the mask something the right shape to bite on.
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskShape
        }

        MultiEffect {
            anchors.fill: parent
            anchors.margins: -root.pad
            visible: !root.solid
            source: sampled
            blurEnabled: true
            blur: 1.0
            blurMax: root.blurMax
            saturation: 0.3
            brightness: -0.05
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.base.r, root.base.g, root.base.b,
                root.solid ? Math.max(root.baseOpacity, 0.92) : root.baseOpacity)
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tintOpacity)
        }
    }
}
