pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// "Agent Island" — a welcoming, full-screen project launchpad.
//  - Aurora + live star background; Theo (the voice) greets you.
//  - Folder grid; click a folder → it focuses, the bg blurs, and a radial ring of
//    actions fans out (Launch / Launch from… / Open / Settings / Remove).
//  - Window chrome (fullscreen / close) + a New-project flow (create or add).
FloatingWindow {
    id: win
    implicitWidth: 1120
    implicitHeight: 760
    minimumSize: Qt.size(820, 560)
    color: pal.bg
    title: "Agent Island"

    // Edit to taste — your display name for the greeting.
    property string userName: "Kartik"

    ProjectsStore { id: store }

    QtObject {
        id: pal
        readonly property color bg: "#0A0A0D"
        readonly property color panel: "#141419"
        readonly property color panelHi: "#1E1E26"
        readonly property color border: Qt.rgba(1, 1, 1, 0.09)
        readonly property color text: "#FFFFFF"
        readonly property color subtext: "#969BA6"
        readonly property color accent: Appearance?.m3colors?.m3primary ?? "#8AB4F8"
        readonly property color good: "#34D399"
    }

    // ---- state ----
    property string filter: ""
    property var menuProject: null         // project whose radial menu is open
    property var menuShownProject: null    // persists through the close animation
    property string settingsPath: ""
    property bool newOpen: false
    property string launchingName: ""

    // animated background blur (driven by the radial menu)
    property real blurAmt: menuProject !== null ? 1 : 0
    Behavior on blurAmt { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    readonly property var filtered: {
        const f = win.filter.toLowerCase();
        if (f === "") return store.projects;
        return store.projects.filter(p => p.name.toLowerCase().indexOf(f) !== -1);
    }
    readonly property int liveCount: store.projects.filter(p => p.running).length
    readonly property var settingsProject: win.settingsPath === "" ? null : (store.projects.find(p => p.path === win.settingsPath) ?? null)

    function openMenu(p) { win.menuShownProject = p; win.menuProject = p; radial.dirMode = false; }
    function closeMenu() { win.menuProject = null; }
    function doLaunch(p) { store.launch(p); win.launchingName = p.name; launchClear.restart(); }
    Timer { id: launchClear; interval: 1600; onTriggered: win.launchingName = "" }

    // ---- Theo, the voice ----
    function greeting() {
        const h = DateTime.clock.date.getHours();
        if (h < 5) return "Still up";
        if (h < 12) return "Good morning";
        if (h < 17) return "Good afternoon";
        if (h < 21) return "Good evening";
        return "Burning the midnight oil";
    }
    readonly property var quirks: [
        "What are we building today?",
        "Point me at a project — I'll wrangle the agents.",
        "Your island. I just keep the lights on.",
        "Say the word and I'll spin one up.",
        "All quiet. Ready when you are.",
        "Let's get some agents working."
    ]
    property int quirkIndex: 0
    Timer { interval: 5600; running: true; repeat: true; onTriggered: win.quirkIndex = (win.quirkIndex + 1) % win.quirks.length }

    // ---- reusable controls ----
    component StepBtn: Rectangle {
        property string sym
        signal act
        width: 30; height: 30; radius: 9
        color: stepHover.hovered ? pal.panelHi : pal.bg
        border.width: 1; border.color: pal.border
        MaterialSymbol { anchors.centerIn: parent; text: parent.sym; iconSize: 19; color: pal.text }
        HoverHandler { id: stepHover }
        TapHandler { onTapped: parent.act() }
    }
    component SegChip: Rectangle {
        property bool active: false
        property string label: ""
        signal picked
        implicitWidth: chipText.implicitWidth + 22
        implicitHeight: 30
        radius: 9
        color: active ? pal.accent : (chipHover.hovered ? pal.panelHi : "transparent")
        border.width: 1
        border.color: active ? "transparent" : pal.border
        Behavior on color { ColorAnimation { duration: 120 } }
        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: parent.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: parent.active ? "#0A0A0D" : pal.text
        }
        HoverHandler { id: chipHover }
        TapHandler { onTapped: parent.picked() }
    }
    component ChromeBtn: Rectangle {
        property string sym
        property bool danger: false
        signal act
        width: 30; height: 30; radius: 15
        color: cHover.hovered ? (danger ? Qt.rgba(0.9, 0.3, 0.3, 0.85) : pal.panelHi) : Qt.rgba(1, 1, 1, 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }
        MaterialSymbol { anchors.centerIn: parent; text: parent.sym; iconSize: 17; color: pal.text }
        HoverHandler { id: cHover }
        TapHandler { onTapped: parent.act() }
    }
    function modeLabel(m) {
        return m === "bypass" ? "Bypass" : m === "default" ? "Default"
            : m === "plan" ? "Plan" : m === "acceptEdits" ? "Accept edits" : m;
    }

    // ====================================================================
    //  contentRoot = background + content; the radial menu blurs it.
    // ====================================================================
    Item {
        id: contentRoot
        anchors.fill: parent
        layer.enabled: win.blurAmt > 0.01
        layer.effect: MultiEffect { blurEnabled: true; blur: win.blurAmt; blurMax: 32 }

        // ---- background ----
        Rectangle { anchors.fill: parent; color: pal.bg }
        Rectangle {
            x: parent.width * 0.58; y: -300; width: 720; height: 720; radius: 360
            color: "#15306E"; opacity: 0.16
            layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
        }
        Rectangle {
            x: -280; y: parent.height * 0.5; width: 640; height: 640; radius: 320
            color: "#0F4A30"; opacity: 0.11
            layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
        }
        Rectangle {
            x: parent.width * 0.6; y: parent.height * 0.6; width: 660; height: 660; radius: 330
            color: "#5A1B3E"; opacity: 0.13
            layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 0.78; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.35) }
            }
        }
        StarField { anchors.fill: parent; count: 15; minSize: 3; maxSize: 10; intensity: 0.32 }

        // ---- content ----
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 40; anchors.rightMargin: 40
            anchors.topMargin: 34; anchors.bottomMargin: 26
            spacing: 20

            // welcome header
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: Qt.resolvedUrl("assets/icon-256.png")
                    sourceSize.width: 168; sourceSize.height: 168
                    width: 80; height: 80
                    smooth: true; mipmap: true
                    transform: Translate { id: logoFloat }
                    SequentialAnimation {
                        // gate on window visibility — an Infinite tween on a hidden
                        // window still burns CPU ticking properties every frame
                        loops: Animation.Infinite; running: win.visible
                        NumberAnimation { target: logoFloat; property: "y"; from: 0; to: -7; duration: 2600; easing.type: Easing.InOutSine }
                        NumberAnimation { target: logoFloat; property: "y"; from: -7; to: 0; duration: 2600; easing.type: Easing.InOutSine }
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: win.greeting() + ", " + win.userName
                    color: pal.text
                    font.pixelSize: 32; font.weight: Font.Bold
                }
                // Theo line
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 7
                    Image {
                        source: Qt.resolvedUrl("assets/sparkle.png")
                        sourceSize.width: 40; sourceSize.height: 40
                        width: 15; height: 15; smooth: true; mipmap: true
                        transformOrigin: Item.Center
                        RotationAnimation on rotation { from: 0; to: 360; duration: 24000; loops: Animation.Infinite; running: win.visible }
                    }
                    StyledText { text: "Theo"; color: pal.accent; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold }
                    StyledText {
                        id: subline
                        text: win.liveCount > 0
                            ? win.quirks[win.quirkIndex] + "  ·  " + win.liveCount + " live"
                            : win.quirks[win.quirkIndex]
                        color: pal.subtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                        onTextChanged: { opacity = 0; sublineFade.restart(); }
                        NumberAnimation { id: sublineFade; target: subline; property: "opacity"; from: 0; to: 1; duration: 550; easing.type: Easing.OutCubic }
                    }
                }

                // search pill
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    width: 320; height: 38; radius: 19
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: searchInput.activeFocus ? pal.accent : pal.border
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        spacing: 8
                        MaterialSymbol { text: "search"; iconSize: 18; color: pal.subtext }
                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: pal.text
                            font.pixelSize: Appearance.font.pixelSize.normal
                            clip: true
                            onTextChanged: win.filter = text
                            Keys.onEscapePressed: text = ""
                            StyledText {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                visible: searchInput.text === "" && !searchInput.activeFocus
                                text: "Search projects"
                                color: pal.subtext
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                        }
                    }
                }
            }

            // scrollable sections
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: sections.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: sections
                    width: parent.width
                    spacing: 16

                    StyledText {
                        visible: store.recents.length > 0 && win.filter === ""
                        text: "Recents"
                        color: pal.subtext; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: store.recents.length > 0 && win.filter === ""
                        spacing: 6
                        Repeater {
                            model: win.filter === "" ? store.recents : []
                            FolderTile {
                                required property var modelData
                                project: modelData
                                onActivated: win.openMenu(modelData)
                            }
                        }
                    }
                    Rectangle {
                        visible: store.recents.length > 0 && win.filter === ""
                        Layout.fillWidth: true; Layout.topMargin: 2; height: 1; color: pal.border
                    }

                    StyledText {
                        text: win.filter === "" ? "Projects" : (win.filtered.length + " result" + (win.filtered.length === 1 ? "" : "s"))
                        color: pal.subtext; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 10
                        spacing: 6
                        Repeater {
                            model: win.filtered
                            FolderTile {
                                required property var modelData
                                project: modelData
                                onActivated: win.openMenu(modelData)
                            }
                        }
                        // + New project tile
                        Item {
                            visible: win.filter === ""
                            implicitWidth: 130; implicitHeight: 132
                            Rectangle {
                                width: 92; height: 72; radius: 13
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top; anchors.topMargin: 6
                                color: newTileHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.025)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                Behavior on color { ColorAnimation { duration: 130 } }
                                MaterialSymbol { anchors.centerIn: parent; text: "add"; iconSize: 30; color: pal.subtext }
                            }
                            StyledText {
                                anchors.top: parent.top; anchors.topMargin: 88
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "New project"
                                color: newTileHover.hovered ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.7)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            HoverHandler { id: newTileHover }
                            TapHandler { onTapped: win.newOpen = true }
                        }
                    }
                    StyledText {
                        visible: store.projects.length === 0
                        text: "No folders in ~/Projects yet — hit New project."
                        color: pal.subtext; font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }
        }
    } // contentRoot

    // ============================== WINDOW CHROME ==============================
    Row {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: 12; anchors.rightMargin: 14
        spacing: 8
        z: 40
        ChromeBtn { sym: win.fullscreen ? "fullscreen_exit" : "fullscreen"; onAct: win.fullscreen = !win.fullscreen }
        ChromeBtn { sym: "close"; danger: true; onAct: Qt.quit() }
    }

    // ============================== RADIAL MENU ==============================
    FolderRadialMenu {
        id: radial
        anchors.fill: parent
        z: 30
        project: win.menuShownProject
        shown: win.menuProject !== null
        subdirs: store.subdirs
        visible: win.menuProject !== null || radial.wave > 0.01
        onLaunch: { win.doLaunch(win.menuShownProject); win.closeMenu(); }
        onLaunchFromRequested: { store.loadSubdirs(win.menuShownProject.path); radial.dirMode = true; }
        onPickDir: dir => { if (dir.length > 0) win.launchFrom(win.menuShownProject, dir); win.closeMenu(); }
        onOpenFolder: { store.openFolder(win.menuShownProject.path); win.closeMenu(); }
        onSettings: { win.settingsPath = win.menuShownProject.path; win.closeMenu(); }
        onRemoveRecent: { store.removeRecent(win.menuShownProject.path); win.closeMenu(); }
        onClosed: win.closeMenu()
    }
    function launchFrom(p, dir) { store.launchFrom(p, dir); win.launchingName = (dir.split("/").pop() || p.name); launchClear.restart(); }

    // ============================== SETTINGS SHEET ==============================
    Item {
        anchors.fill: parent
        z: 35
        visible: dim.opacity > 0.01
        Rectangle {
            id: dim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            opacity: win.settingsProject ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            TapHandler { onTapped: win.settingsPath = "" }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 460; radius: 20
            color: pal.panel; border.width: 1; border.color: pal.border
            implicitHeight: sheetCol.implicitHeight + 36
            opacity: win.settingsProject ? 1 : 0
            scale: win.settingsProject ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

            ColumnLayout {
                id: sheetCol
                anchors.fill: parent; anchors.margins: 22
                spacing: 18
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    StyledText {
                        Layout.fillWidth: true
                        text: win.settingsProject ? win.settingsProject.name : ""
                        color: pal.text; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        width: 30; height: 30; radius: 15
                        color: closeHover.hovered ? pal.panelHi : "transparent"
                        MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 18; color: pal.subtext }
                        HoverHandler { id: closeHover }
                        TapHandler { onTapped: win.settingsPath = "" }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol { text: "dashboard"; iconSize: 19; color: pal.subtext }
                    StyledText { text: "Sessions"; color: pal.text; font.pixelSize: Appearance.font.pixelSize.normal; Layout.fillWidth: true }
                    StepBtn { sym: "remove"; onAct: if (win.settingsProject) store.setSetting(win.settingsProject.path, "sessions", Math.max(1, win.settingsProject.sessions - 1)) }
                    StyledText {
                        text: win.settingsProject ? String(win.settingsProject.sessions) : "1"
                        color: pal.text; font.pixelSize: Appearance.font.pixelSize.large
                        horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 30
                    }
                    StepBtn { sym: "add"; onAct: if (win.settingsProject) store.setSetting(win.settingsProject.path, "sessions", Math.min(6, win.settingsProject.sessions + 1)) }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: pal.border }
                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol { text: "verified_user"; iconSize: 19; color: pal.subtext }
                    StyledText { text: "Mode"; color: pal.text; font.pixelSize: Appearance.font.pixelSize.normal; Layout.fillWidth: true }
                    Repeater {
                        model: store.modeOptions
                        SegChip {
                            required property var modelData
                            label: win.modeLabel(modelData)
                            active: win.settingsProject && win.settingsProject.mode === modelData
                            onPicked: if (win.settingsProject) store.setSetting(win.settingsProject.path, "mode", modelData)
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: pal.border }
                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol { text: "terminal"; iconSize: 19; color: pal.subtext }
                    StyledText { text: "Host"; color: pal.text; font.pixelSize: Appearance.font.pixelSize.normal; Layout.fillWidth: true }
                    Repeater {
                        model: store.hostOptions
                        SegChip {
                            required property var modelData
                            label: modelData
                            active: win.settingsProject && win.settingsProject.host === modelData
                            onPicked: if (win.settingsProject) store.setSetting(win.settingsProject.path, "host", modelData)
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.topMargin: 4
                    height: 48; radius: 13
                    color: sheetLaunchHover.hovered ? Qt.lighter(pal.accent, 1.08) : pal.accent
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.centerIn: parent; spacing: 9
                        MaterialSymbol { text: win.settingsProject && win.settingsProject.running ? "open_in_new" : "play_arrow"; iconSize: 21; fill: 1; color: "#0A0A0D" }
                        StyledText {
                            text: !win.settingsProject ? "" : win.settingsProject.running ? "Re-attach"
                                : "Launch " + win.settingsProject.sessions + (win.settingsProject.sessions > 1 ? " sessions" : " session")
                            color: "#0A0A0D"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold
                        }
                    }
                    HoverHandler { id: sheetLaunchHover }
                    TapHandler { onTapped: { if (win.settingsProject) { win.doLaunch(win.settingsProject); win.settingsPath = ""; } } }
                }
            }
        }
    }

    // ============================== NEW PROJECT SHEET ==============================
    Item {
        anchors.fill: parent
        z: 36
        visible: newDim.opacity > 0.01
        Rectangle {
            id: newDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            opacity: win.newOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            TapHandler { onTapped: win.newOpen = false }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 440; radius: 20
            color: pal.panel; border.width: 1; border.color: pal.border
            implicitHeight: newCol.implicitHeight + 36
            opacity: win.newOpen ? 1 : 0
            scale: win.newOpen ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

            property bool gitInit: true

            ColumnLayout {
                id: newCol
                anchors.fill: parent; anchors.margins: 22
                spacing: 16
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: "New project"; color: pal.text; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold }
                    Rectangle {
                        width: 30; height: 30; radius: 15
                        color: newCloseHover.hovered ? pal.panelHi : "transparent"
                        MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 18; color: pal.subtext }
                        HoverHandler { id: newCloseHover }
                        TapHandler { onTapped: win.newOpen = false }
                    }
                }
                StyledText { text: "Create a new folder under ~/Projects"; color: pal.subtext; font.pixelSize: Appearance.font.pixelSize.smaller }
                Rectangle {
                    Layout.fillWidth: true; height: 42; radius: 11
                    color: pal.bg; border.width: 1
                    border.color: nameInput.activeFocus ? pal.accent : pal.border
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    TextInput {
                        id: nameInput
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: pal.text; font.pixelSize: Appearance.font.pixelSize.normal; clip: true
                        Keys.onReturnPressed: { store.createProject(text, newCol.parent.gitInit); win.newOpen = false; text = ""; }
                        StyledText {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            visible: nameInput.text === "" && !nameInput.activeFocus
                            text: "project-name"; color: pal.subtext; font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Rectangle {
                        width: 22; height: 22; radius: 6
                        color: newCol.parent.gitInit ? pal.accent : "transparent"
                        border.width: 1; border.color: newCol.parent.gitInit ? "transparent" : pal.border
                        MaterialSymbol { anchors.centerIn: parent; visible: newCol.parent.gitInit; text: "check"; iconSize: 16; color: "#0A0A0D" }
                        TapHandler { onTapped: newCol.parent.gitInit = !newCol.parent.gitInit }
                    }
                    StyledText { text: "Initialize a git repository"; color: pal.text; font.pixelSize: Appearance.font.pixelSize.normal; Layout.fillWidth: true }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 46; radius: 12
                    color: nameInput.text.length > 0 ? (createHover.hovered ? Qt.lighter(pal.accent, 1.08) : pal.accent) : pal.panelHi
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.centerIn: parent; spacing: 8
                        MaterialSymbol { text: "create_new_folder"; iconSize: 20; fill: 1; color: nameInput.text.length > 0 ? "#0A0A0D" : pal.subtext }
                        StyledText { text: "Create"; color: nameInput.text.length > 0 ? "#0A0A0D" : pal.subtext; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold }
                    }
                    HoverHandler { id: createHover }
                    TapHandler { onTapped: { if (nameInput.text.length > 0) { store.createProject(nameInput.text, newCol.parent.gitInit); win.newOpen = false; nameInput.text = ""; } } }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: pal.border }
                Rectangle {
                    Layout.fillWidth: true; height: 44; radius: 12
                    color: addHover.hovered ? pal.panelHi : "transparent"
                    border.width: 1; border.color: pal.border
                    RowLayout {
                        anchors.centerIn: parent; spacing: 8
                        MaterialSymbol { text: "folder_open"; iconSize: 19; color: pal.text }
                        StyledText { text: "Add an existing folder…"; color: pal.text; font.pixelSize: Appearance.font.pixelSize.normal }
                    }
                    HoverHandler { id: addHover }
                    TapHandler { onTapped: { store.addExisting(); win.newOpen = false; } }
                }
            }
        }
    }

    // ============================== LAUNCH OVERLAY (Theo) ==============================
    Rectangle {
        anchors.fill: parent
        z: 50
        color: Qt.rgba(0.04, 0.04, 0.06, 0.82)
        opacity: win.launchingName !== "" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        ColumnLayout {
            anchors.centerIn: parent; spacing: 16
            Image {
                Layout.alignment: Qt.AlignHCenter
                source: Qt.resolvedUrl("assets/icon-256.png")
                sourceSize.width: 200; sourceSize.height: 200
                width: 92; height: 92; smooth: true; mipmap: true
                transformOrigin: Item.Center
                SequentialAnimation on scale {
                    loops: Animation.Infinite; running: win.launchingName !== ""
                    NumberAnimation { to: 1.08; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
                Image {
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("assets/sparkle.png")
                    sourceSize.width: 64; sourceSize.height: 64
                    width: 34; height: 34; smooth: true; mipmap: true
                    transformOrigin: Item.Center
                    RotationAnimation on rotation { from: 0; to: 360; duration: 2400; loops: Animation.Infinite; running: win.launchingName !== "" }
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: "Theo's spinning up " + win.launchingName + "…"
                color: pal.text; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold
            }
        }
    }
}
