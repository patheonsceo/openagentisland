pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

/**
 * Shared desktop geometry.
 *
 * DesktopWidgets and DesktopIcons are two separate layer surfaces, so neither
 * can see the other's items directly. The widget board publishes the rects its
 * widgets occupy here; the icon board reads them so an icon can step aside
 * instead of hiding underneath a widget.
 *
 * Deliberately a plain `property var` on a Singleton, NOT a JsonAdapter list —
 * JsonAdapter list properties are known to crash this shell. Nothing here is
 * persisted; it is live geometry, rebuilt whenever a widget moves.
 */
Singleton {
    id: root

    // [{ x, y, width, height }] in board (screen) coordinates.
    property var widgetRects: []

    // True only while a desktop icon is mid-drag. The widget board reads this
    // to draw its no-drop tint, so the tint lives with the thing it covers.
    property bool iconDragActive: false

    function publishRects(rects) {
        root.widgetRects = rects || [];
    }

    // Does a proposed icon rect overlap any widget? Used both to reject a drop
    // and to push an icon aside at render time, so the two can never disagree.
    function collides(x, y, w, h) {
        const pad = 8;   // breathing room so icons never kiss a widget edge
        for (let i = 0; i < root.widgetRects.length; i++) {
            const r = root.widgetRects[i];
            if (!r) continue;
            if (x < r.x + r.width + pad && x + w > r.x - pad
             && y < r.y + r.height + pad && y + h > r.y - pad)
                return true;
        }
        return false;
    }
}
