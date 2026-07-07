pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Screen-capture toolbar (USECASE 2): region / full / window screenshot,
// screen-record toggle (wf-recorder), colour picker. Opened from the right
// island pencil pill. Tools detected present: grim/slurp/hyprshot/wf-recorder/
// hyprpicker/wl-copy.
FocusScope {
    id: surf
    focus: true

    property bool recording: false
    readonly property string shotDir: FileUtils.trimFileProtocol(`${Directories.pictures}/Screenshots`)
    readonly property string recDir: FileUtils.trimFileProtocol(`${Directories.videos}/Recordings`)

    Process {
        id: recCheck
        command: ["pgrep", "-x", "wf-recorder"]
        onExited: code => surf.recording = (code === 0)
    }
    // Only poll for an externally-stopped recording while the tools surface is
    // actually on screen. When the popup is closed there's nothing to update, so
    // the always-on pgrep spawn is pure waste. (toggleRecord() also re-checks
    // immediately, so the in-surface state stays correct without constant polling.)
    Timer { interval: 1500; running: surf.visible; repeat: true; onTriggered: recCheck.running = true }
    onVisibleChanged: if (visible) recCheck.running = true
    Component.onCompleted: if (visible) recCheck.running = true

    // Close the island first (so it isn't in the shot), then capture after a beat.
    function shoot(mode) {
        Island.close();
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${surf.shotDir}'; sleep 0.4; hyprshot -m ${mode} -o '${surf.shotDir}'`]);
    }
    function toggleRecord() {
        if (surf.recording) {
            Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"]);
        } else {
            Island.close();
            Quickshell.execDetached(["bash", "-c", `mkdir -p '${surf.recDir}'; sleep 0.4; wf-recorder -f "${surf.recDir}/rec_$(date +%Y%m%d_%H%M%S).mp4"`]);
        }
        recCheck.running = true;
    }
    function pick() {
        Island.close();
        // pipe the picked hex straight to the clipboard (hyprpicker -a autocopy is
        // unreliable); strip whitespace so only the hex lands on the clipboard.
        Quickshell.execDetached(["bash", "-c", "hyprpicker -f hex | tr -d '[:space:]' | wl-copy"]);
    }

    Keys.onEscapePressed: Island.close()

    component ToolBtn: Rectangle {
        id: tb
        property string icon
        property string label
        property bool danger: false
        signal trig
        implicitWidth: 74
        implicitHeight: 60
        radius: 12
        color: tbHover.hovered ? (danger ? Qt.rgba(0.9, 0.3, 0.3, 0.22) : Qt.rgba(0.54, 0.70, 0.97, 0.18))
                               : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: danger ? "#E06A6A" : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: tb.icon
                iconSize: 23
                fill: 1
                color: tb.danger ? "#E06A6A" : IslandStyle.textColor
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: tb.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: IslandStyle.subtextColor
            }
        }
        HoverHandler { id: tbHover }
        TapHandler { onTapped: tb.trig() }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 8
        ToolBtn { icon: "crop"; label: "Region"; onTrig: surf.shoot("region") }
        ToolBtn { icon: "fullscreen"; label: "Full"; onTrig: surf.shoot("output") }
        ToolBtn { icon: "select_window"; label: "Window"; onTrig: surf.shoot("window") }
        ToolBtn {
            icon: surf.recording ? "stop_circle" : "videocam"
            label: surf.recording ? "Stop" : "Record"
            danger: surf.recording
            onTrig: surf.toggleRecord()
        }
        ToolBtn { icon: "colorize"; label: "Pick"; onTrig: surf.pick() }
    }
}
