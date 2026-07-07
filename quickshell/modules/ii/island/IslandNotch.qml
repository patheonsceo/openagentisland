pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.Mpris

// Center notch — top-attached, morphing. THE STAR.
//
// Shape: hangs from top-center; square top corners flush with the screen edge,
// rounded bottom (constant radius), concave RoundCorner shoulders. Borderless fill.
// Reserves a top strip (exclusiveZone) so maximized windows sit BELOW the islands.
//
// State machine (precedence: agent > media > volume/brightness > notification > idle).
// Transient OSDs auto-hide; media shows only while PLAYING. `open` is click-toggled.
// Goey overshoot morph (cubic-bezier 0.34,1.22,0.64,1).
Scope {
    id: root

    readonly property list<real> goeyCurve: [0.34, 1.22, 0.64, 1, 1, 1]
    readonly property int morphDuration: 330
    readonly property int shoulderSize: 20
    readonly property int cornerRadius: 18
    readonly property int maxWidth: 1100          // widest open surface (overview) — also sizes the window
    readonly property int maxHeight: 400
    readonly property int expandedMaxWidth: 480   // cap for transient OSDs (volume/brightness/media/notif)
    readonly property int reservedStrip: 40       // top space reserved for the island strip

    // Open-state surface sizes — notch body w×h per named surface (Island.openSurface).
    readonly property var surfaceSizes: ({
            "dashboard": { "w": 1040, "h": 360 },
            "overview":  { "w": 1100, "h": 300 },
            "launcher":  { "w": 560,  "h": 380 },
            "power":     { "w": 320,  "h": 92  },
            "tools":     { "w": 440,  "h": 84  },
            "agent":     { "w": 460,  "h": 300 }
        })

    // Media (shared across monitors). Show only while actively playing.
    readonly property var activePlayer: MprisController.activePlayer
    readonly property bool mediaActive: activePlayer?.isPlaying ?? false
    property list<real> visualizerPoints: []

    // Cover art: download the (often remote / flickery) trackArtUrl to a stable local
    // cache file so the art doesn't vanish when the player rewrites/clears the URL.
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property string artFilePath: artUrl.length > 0 ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
    // Persisted local art path. Only cleared on an actual TRACK change — NOT when the
    // player momentarily rewrites/clears artUrl (which made the art vanish). Set only
    // once the cache file is confirmed present (exit 0).
    property string displayedArt: ""
    readonly property string trackKey: activePlayer?.trackTitle ?? ""
    onTrackKeyChanged: displayedArt = ""
    onArtFilePathChanged: {
        if (artFilePath.length === 0)
            return; // transient empty URL — keep the current art
        coverArtDownloader.outFile = artFilePath;
        coverArtDownloader.targetUrl = artUrl;
        coverArtDownloader.running = true;
    }
    Process {
        id: coverArtDownloader
        property string targetUrl: ""
        property string outFile: ""
        command: ["bash", "-c", `[ -f '${outFile}' ] || curl -4 -sSL '${targetUrl}' -o '${outFile}'`]
        onExited: (code, status) => {
            if (code === 0)
                root.displayedArt = Qt.resolvedUrl(coverArtDownloader.outFile);
        }
    }

    Process {
        id: cavaProc
        running: root.mediaActive
        onRunningChanged: {
            if (!cavaProc.running)
                root.visualizerPoints = [];
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                root.visualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }

    // The monitor that currently has keyboard focus — where auto-opened surfaces
    // (e.g. an incoming permission) should appear. Falls back to the first screen.
    function focusedScreenName() {
        const n = Hyprland.focusedMonitor?.name ?? "";
        if (n.length > 0)
            return n;
        return Quickshell.screens.length > 0 ? (Quickshell.screens[0].name ?? "") : "";
    }

    // Permission is top-priority + sticky: auto-open the agent surface when a
    // request arrives (if nothing else is open) on the FOCUSED monitor, and close
    // back to compact when the last one is resolved.
    Connections {
        target: AgentService
        function onPendingPermissionsChanged() {
            if (AgentService.pendingPermissions.length > 0 && Island.openSurface === "")
                Island.open("agent", root.focusedScreenName());
            else if (AgentService.pendingPermissions.length === 0 && Island.openSurface === "agent")
                Island.close();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notchWindow
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:islandNotch"
            WlrLayershell.layer: WlrLayer.Top
            // Grab keyboard only while THIS monitor's surface is open (Esc / search typing).
            WlrLayershell.keyboardFocus: notchWindow.ownsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            // Floating island — don't reserve a strip; windows pass under it like the
            // left/right islands (wallpaper breathes through the gaps).
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            // ALL FOUR edges anchored → the window fills the monitor in LOGICAL
            // coordinates (like the framework's Background), correct on scaled
            // (eDP-1 @1.5) and rotated (DP-3) outputs. (Sizing via screen.width/height
            // — PHYSICAL pixels — is what blanked those monitors before.) Being
            // full-screen restores the click-anywhere-to-close catcher. It's
            // transparent and masked to just the notch body normally (rest is
            // click-through), to the whole screen while THIS monitor's surface is open.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // This monitor owns the open surface? Only ONE monitor shows a surface at
            // a time (see Island.qml) — so opening on this screen doesn't expand the
            // notch on the others.
            readonly property bool ownsOpen: Island.openSurface !== "" && Island.openScreen === (notchWindow.screen.name ?? "")

            mask: Region {
                item: notchWindow.ownsOpen ? fullMaskItem : notch
            }
            Item { id: fullMaskItem; anchors.fill: parent }

            // --- state machine ---
            property string expandedSource: ""  // transient OSD: volume|brightness|notification|""
            // Agent-forward: an active agent outranks media for the notch display
            // (precedence: dictation > transient OSD > agent > media). Music keeps
            // playing. Dictation is the user actively SPEAKING — nothing steals it.
            property string displaySource: Hyprvoice.active ? "dictation"
                : expandedSource !== "" ? expandedSource
                : (AgentService.active ? "agent"
                : (root.mediaActive ? "media" : ""))
            // open (a named surface is up ON THIS MONITOR) outranks transient OSDs,
            // which outrank idle.
            property string islandState: notchWindow.ownsOpen ? "open"
                : (displaySource !== "" ? "expanded" : "idle")

            Timer {
                id: hideTimer
                onTriggered: notchWindow.expandedSource = ""
            }
            function trigger(src, ms) {
                expandedSource = src;
                hideTimer.interval = ms;
                hideTimer.restart();
            }

            property string notifApp: ""
            property string notifSummary: ""
            property string notifIcon: ""
            readonly property var brightnessMonitor: Brightness.getMonitorForScreen(notchWindow.screen)

            // attention flash when a NEW permission arrives
            property int _lastPending: 0
            property real permFlash: 0
            Connections {
                target: AgentService
                function onPendingPermissionsChanged() {
                    if (AgentService.pendingPermissions.length > notchWindow._lastPending)
                        permFlashAnim.restart();
                    notchWindow._lastPending = AgentService.pendingPermissions.length;
                }
            }
            SequentialAnimation {
                id: permFlashAnim
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 1; duration: 90; easing.type: Easing.OutQuad }
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 0.35; duration: 220; easing.type: Easing.InOutQuad }
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 1; duration: 130; easing.type: Easing.OutQuad }
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 0; duration: 650; easing.type: Easing.InQuad }
            }

            // Downsampled equalizer bars from the cava points (0..1).
            readonly property int barCount: 22
            property var barValues: {
                const pts = root.visualizerPoints;
                const n = barCount;
                let out = [];
                for (let i = 0; i < n; i++) {
                    if (pts && pts.length > 0) {
                        const idx = Math.floor(i * pts.length / n);
                        out.push(Math.max(0, Math.min(1, (pts[idx] ?? 0) / 1000)));
                    } else {
                        out.push(0);
                    }
                }
                return out;
            }

            Connections {
                target: Audio.sink?.audio ?? null
                function onVolumeChanged() {
                    if (Audio.ready)
                        notchWindow.trigger("volume", 2000);
                }
                function onMutedChanged() {
                    if (Audio.ready)
                        notchWindow.trigger("volume", 2000);
                }
            }
            Connections {
                target: Brightness
                function onBrightnessChanged() {
                    notchWindow.trigger("brightness", 2000);
                }
            }
            Connections {
                target: Notifications
                function onNotify(notification) {
                    // The dictation pill IS the hyprvoice status UX — don't also pop
                    // its notify-send chatter (still lands in history). Errors pop.
                    const app = notification.appName ?? "";
                    const summary = notification.summary ?? "";
                    if (app === "Hyprvoice" && !summary.includes("Error"))
                        return;
                    notchWindow.notifApp = app;
                    notchWindow.notifSummary = summary;
                    notchWindow.notifIcon = notification.appIcon ?? "";
                    notchWindow.trigger("notification", 4000);
                }
            }

            property real contentWidth: {
                switch (displaySource) {
                case "volume":
                    return volumeUI.implicitWidth;
                case "brightness":
                    return brightnessUI.implicitWidth;
                case "notification":
                    return notifUI.implicitWidth;
                case "media":
                    return mediaUI.implicitWidth;
                case "agent":
                    return agentUI.implicitWidth;
                case "dictation":
                    return dictationUI.implicitWidth;
                default:
                    return 0;
                }
            }
            property real targetWidth: islandState === "open" ? (root.surfaceSizes[Island.openSurface]?.w ?? root.maxWidth)
                : islandState === "expanded" ? (displaySource === "agent" ? (root.mediaActive ? 264 : 224) : Math.min(root.expandedMaxWidth, contentWidth + 36))
                : 180
            property real targetHeight: islandState === "open" ? (root.surfaceSizes[Island.openSurface]?.h ?? root.maxHeight)
                : islandState === "expanded" ? (displaySource === "media" || displaySource === "agent" || displaySource === "dictation" ? 40 : 54)
                : 36

            // Full-screen click-catcher (only while open). Sits BEHIND the notch
            // body — which absorbs its own clicks — so only clicks OUTSIDE the
            // notch close the surface. Same window → z-order is guaranteed.
            MouseArea {
                anchors.fill: parent
                enabled: notchWindow.islandState === "open"
                visible: enabled
                acceptedButtons: Qt.AllButtons
                onPressed: Island.close()
            }

            RoundCorner {
                corner: RoundCorner.CornerEnum.TopRight
                color: IslandStyle.pillColor
                implicitSize: root.shoulderSize
                anchors.right: notch.left
                anchors.rightMargin: -1
                anchors.top: parent.top
            }
            RoundCorner {
                corner: RoundCorner.CornerEnum.TopLeft
                color: IslandStyle.pillColor
                implicitSize: root.shoulderSize
                anchors.left: notch.right
                anchors.leftMargin: -1
                anchors.top: parent.top
            }

            Rectangle {
                id: notch
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter

                width: notchWindow.targetWidth
                height: notchWindow.targetHeight

                color: IslandStyle.pillColor
                clip: true
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: root.cornerRadius
                bottomRightRadius: root.cornerRadius
                border.width: notchWindow.permFlash * 3
                border.color: Qt.rgba(0.91, 0.64, 0.24, notchWindow.permFlash)

                Behavior on width {
                    NumberAnimation { duration: root.morphDuration; easing.bezierCurve: root.goeyCurve }
                }
                Behavior on height {
                    NumberAnimation { duration: root.morphDuration; easing.bezierCurve: root.goeyCurve }
                }

                MouseArea {
                    anchors.fill: parent
                    // Click the notch body from idle/OSD → open the dashboard. When a
                    // surface is open, surfaceHost's absorber catches clicks (no
                    // accidental close); close via Esc or re-clicking the trigger pill.
                    onClicked: {
                        // mid-dictation the pill is a cancel button
                        if (notchWindow.displaySource === "dictation") {
                            if (Hyprvoice.state !== "idle")
                                Hyprvoice.cancel();
                            return;
                        }
                        // open on THIS monitor (moves the surface here if another had it)
                        Island.open(notchWindow.displaySource === "agent" ? "agent" : "dashboard",
                                    notchWindow.screen.name);
                    }
                }

                // ---- volume ----
                RowLayout {
                    id: volumeUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "volume" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 20
                        fill: 1
                        color: IslandStyle.textColor
                        text: {
                            const a = Audio.sink?.audio;
                            if (!a || a.muted)
                                return "volume_off";
                            if (a.volume <= 0.0001)
                                return "volume_mute";
                            if (a.volume < 0.5)
                                return "volume_down";
                            return "volume_up";
                        }
                    }
                    OsdBar {
                        value: Audio.sink?.audio?.volume ?? 0
                        accent: (Audio.sink?.audio?.muted ?? false) ? Qt.rgba(1, 1, 1, 0.4) : IslandStyle.accent
                    }
                    OsdPercent { value: Audio.sink?.audio?.volume ?? 0 }
                }

                // ---- brightness ----
                RowLayout {
                    id: brightnessUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "brightness" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 20
                        fill: 1
                        color: IslandStyle.textColor
                        text: (notchWindow.brightnessMonitor?.brightness ?? 1) < 0.5 ? "brightness_low" : "brightness_high"
                    }
                    OsdBar {
                        value: notchWindow.brightnessMonitor?.brightness ?? 0
                        accent: "#FFD479"
                    }
                    OsdPercent { value: notchWindow.brightnessMonitor?.brightness ?? 0 }
                }

                // ---- notification ----
                RowLayout {
                    id: notifUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "notification" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    Loader {
                        Layout.alignment: Qt.AlignVCenter
                        active: notchWindow.notifIcon !== ""
                        visible: active
                        sourceComponent: IconImage {
                            implicitSize: 22
                            source: Quickshell.iconPath(notchWindow.notifIcon, "dialog-information-symbolic")
                        }
                    }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: notchWindow.notifIcon === ""
                        iconSize: 20
                        fill: 1
                        color: IslandStyle.textColor
                        text: "notifications"
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2
                        StyledText {
                            Layout.maximumWidth: 280
                            visible: notchWindow.notifApp !== ""
                            text: notchWindow.notifApp
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: IslandStyle.subtextColor
                        }
                        StyledText {
                            Layout.maximumWidth: 280
                            text: notchWindow.notifSummary
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: IslandStyle.textColor
                        }
                    }
                }

                // ---- dictation (hyprvoice push-to-talk): pulsing mic · live mic waveform · status ----
                RowLayout {
                    id: dictationUI
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "dictation" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    readonly property bool listening: Hyprvoice.phase === "listening"
                    readonly property bool working: Hyprvoice.phase === "transcribing" || Hyprvoice.phase === "polishing"
                    readonly property bool typing: Hyprvoice.phase === "typing"
                    readonly property bool done: Hyprvoice.phase === "done"
                    // muted island accent (blue) — user preference over recording-red
                    readonly property color recColor: IslandStyle.accent
                    readonly property color okColor: "#7EE787"

                    // mic badge — filled while listening, with a sonar pulse ring
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 26
                        implicitHeight: 26
                        Rectangle {
                            id: pulseRing
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            radius: 13
                            color: "transparent"
                            border.width: 2
                            border.color: dictationUI.recColor
                            opacity: 0
                        }
                        ParallelAnimation {
                            running: dictationUI.listening && dictationUI.visible
                            loops: Animation.Infinite
                            onRunningChanged: {
                                if (!running) {
                                    pulseRing.opacity = 0;
                                    pulseRing.scale = 1;
                                }
                            }
                            NumberAnimation { target: pulseRing; property: "scale"; from: 1; to: 1.65; duration: 1100; easing.type: Easing.OutQuad }
                            NumberAnimation { target: pulseRing; property: "opacity"; from: 0.85; to: 0; duration: 1100; easing.type: Easing.OutQuad }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 13
                            color: dictationUI.listening ? dictationUI.recColor
                                : dictationUI.done ? Qt.rgba(0.49, 0.91, 0.53, 0.18)
                                : Qt.rgba(1, 1, 1, 0.10)
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 16
                            fill: 1
                            color: dictationUI.listening ? "#10131C"
                                : dictationUI.done ? dictationUI.okColor
                                : IslandStyle.textColor
                            text: dictationUI.done ? "check"
                                : dictationUI.typing ? "keyboard"
                                : dictationUI.working ? "graphic_eq"
                                : "mic"
                        }
                    }

                    // waveform — procedural traveling wave, always alive while
                    // listening (mic-level cava looked dead at low gain). Stepped
                    // ticker + Behavior smoothing, same perf pattern as the shimmer.
                    // Collapses away for a clean width morph into the transcribing pill.
                    Item {
                        id: dictationWave
                        Layout.alignment: Qt.AlignVCenter
                        visible: dictationUI.listening
                        implicitWidth: 96
                        implicitHeight: 24
                        property real phase: 0
                        Timer {
                            interval: 90
                            repeat: true
                            running: dictationWave.visible && dictationUI.visible
                            onTriggered: dictationWave.phase += 0.55
                        }
                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater {
                                model: 16
                                delegate: Item {
                                    id: micBarCell
                                    required property int index
                                    width: 3
                                    height: 24
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 3
                                        radius: 1.5
                                        color: dictationUI.recColor
                                        // two offset sines → organic, non-robotic wave
                                        height: {
                                            const w = 0.62 * Math.sin(dictationWave.phase + micBarCell.index * 0.8)
                                                    + 0.38 * Math.sin(1.7 - dictationWave.phase * 1.3 + micBarCell.index * 0.45);
                                            return 12.5 + 9.5 * w;
                                        }
                                        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                                    }
                                }
                            }
                        }
                    }

                    AgentStatusText {
                        Layout.alignment: Qt.AlignVCenter
                        word: dictationUI.done ? "Done"
                            : dictationUI.typing ? "Typing"
                            : Hyprvoice.phase === "polishing" ? "Polishing"
                            : dictationUI.working ? "Transcribing"
                            : "Listening"
                        animateDots: dictationUI.working || dictationUI.typing
                        shimmer: dictationUI.working || dictationUI.typing
                        baseColor: dictationUI.done ? dictationUI.okColor : IslandStyle.textColor
                        pixelSize: Appearance.font.pixelSize.small
                    }
                }

                // ---- media: art · equalizer bars · play/pause (minimal, reference-style) ----
                RowLayout {
                    id: mediaUI
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "media" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 7
                        color: Qt.rgba(1, 1, 1, 0.08)
                        StyledImage {
                            id: artImg
                            anchors.fill: parent
                            source: root.displayedArt
                            fillMode: Image.PreserveAspectCrop
                            visible: root.displayedArt !== "" && status === Image.Ready
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: artImg.width
                                    height: artImg.height
                                    radius: 7
                                }
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !artImg.visible
                            text: "music_note"
                            iconSize: 16
                            color: IslandStyle.textColor
                        }
                    }

                    // Equalizer bars
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 112
                        implicitHeight: 24
                        Row {
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: notchWindow.barCount
                                delegate: Item {
                                    id: barCell
                                    required property int index
                                    width: 3
                                    height: 24
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 3
                                        radius: 1.5
                                        color: IslandStyle.accent
                                        height: Math.max(3, (notchWindow.barValues[barCell.index] ?? 0) * 22)
                                        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                                    }
                                }
                            }
                        }
                    }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 24
                        fill: 1
                        color: IslandStyle.textColor
                        text: root.mediaActive ? "pause" : "play_arrow"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.activePlayer?.togglePlaying()
                        }
                    }
                }

                // ---- agent (compact): pixel mascot + status ----
                RowLayout {
                    id: agentUI
                    anchors.fill: parent
                    anchors.leftMargin: 16   // breathing room to the LEFT of the mascot
                    anchors.rightMargin: 14
                    spacing: 11              // gap between the mascot cluster and the text area
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "agent" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    AgentSpinner {
                        Layout.alignment: Qt.AlignVCenter
                        // resting presence → green "running" mascot (alive, no bars)
                        mode: AgentService.headlineMode === "idle" ? "running" : (AgentService.headlineMode === "" ? "idle" : AgentService.headlineMode)
                        pixel: 2
                    }
                    // Fills the remaining estate; status text centered IN it (true
                    // midpoint of the right-hand space). Count rides the far right.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        AgentStatusText {
                            anchors.centerIn: parent
                            readonly property string m: AgentService.headlineMode
                            readonly property string t: AgentService.toast
                            word: t !== "" ? t
                                : m === "permission" ? "Needs you" : m === "waiting" ? "Waiting"
                                : m === "working" ? "Working" : m === "done" ? "Done" : "Agent Island"
                            animateDots: t === "" && (m === "working" || m === "waiting")
                            shimmer: t === "" && (m === "working" || m === "waiting" || m === "permission")
                            baseColor: (t !== "" || m === "done") ? "#7EE787" : IslandStyle.textColor
                            pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: AgentService.sessionCount > 1
                            text: AgentService.sessionCount
                            color: IslandStyle.subtextColor
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    // now-playing indicator — coexists when media plays while an agent is active
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.mediaActive
                        implicitWidth: 20
                        implicitHeight: 20
                        Rectangle { anchors.fill: parent; radius: 5; color: Qt.rgba(1, 1, 1, 0.08) }
                        StyledImage {
                            id: miniArt
                            anchors.fill: parent
                            source: root.displayedArt
                            fillMode: Image.PreserveAspectCrop
                            visible: root.displayedArt !== "" && status === Image.Ready
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: miniArt.width; height: miniArt.height; radius: 5 }
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !miniArt.visible
                            text: "music_note"
                            iconSize: 13
                            color: IslandStyle.subtextColor
                        }
                    }
                }

                // ---- open-state surface host (dashboard / power / tools / launcher / overview) ----
                FocusScope {
                    id: surfaceHost
                    anchors.fill: parent
                    visible: notchWindow.islandState === "open"
                    focus: visible
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                    // Absorb clicks on empty surface padding so they don't fall through
                    // to the notch background (which would close the surface).
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                    }

                    Loader {
                        id: surfaceLoader
                        anchors.fill: parent
                        active: surfaceHost.visible
                        focus: true
                        sourceComponent: {
                            switch (Island.openSurface) {
                            case "dashboard":
                                return dashboardComp;
                            case "power":
                                return powerComp;
                            case "tools":
                                return toolsComp;
                            case "launcher":
                                return launcherComp;
                            case "overview":
                                return overviewComp;
                            case "agent":
                                return agentComp;
                            default:
                                return null;
                            }
                        }
                    }
                    Component { id: dashboardComp; DashboardSurface { focus: true } }
                    Component { id: powerComp; PowerSurface { focus: true } }
                    Component { id: toolsComp; ToolsSurface { focus: true } }
                    Component { id: launcherComp; LauncherSurface { focus: true } }
                    Component { id: overviewComp; OverviewSurface { focus: true } }
                    Component { id: agentComp; AgentSurface { focus: true } }
                }
            }
        }
    }

    // Dedicated top-strip reservation. A stable, empty, full-width, click-through
    // window that reserves `reservedStrip` px at the top so maximized windows open
    // BELOW the island row (like the bar used to). Kept SEPARATE from the notch
    // window — the notch is full-screen (all-4-anchored) so its click-anywhere
    // catcher works, which would forfeit exclusiveZone; this tiny strip carries the
    // reservation instead, and never resizes so windows never jump.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "quickshell:islandReserve"
            WlrLayershell.layer: WlrLayer.Bottom
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.reservedStrip
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: root.reservedStrip
            mask: Region {}   // fully click-through — purely a spacer
        }
    }

    // Small reusable OSD bits.
    component OsdBar: Rectangle {
        id: bar
        property real value: 0
        property color accent: IslandStyle.accent
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 110
        implicitHeight: 6
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.18)
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: bar.height
            width: bar.width * Math.max(0, Math.min(1, bar.value))
            radius: height / 2
            color: bar.accent
            Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
        }
    }
    component OsdPercent: StyledText {
        property real value: 0
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 26
        horizontalAlignment: Text.AlignRight
        text: `${Math.round(Math.max(0, Math.min(1, value)) * 100)}`
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: IslandStyle.textColor
    }
}
