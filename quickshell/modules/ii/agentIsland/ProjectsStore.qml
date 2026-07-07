pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

// Backing store for the Agent Island launcher.
//  - Scans ~/Projects/* for project folders (all subfolders).
//  - Tracks which projects have a LIVE tmux session (the engine's source of
//    truth for "running" — decoupled from the agent socket, which the island
//    shell owns; two listeners on one socket would conflict).
//  - Persists per-project settings (sessions / mode / host) as JSON so they are
//    editable but never re-prompted.
//  - launch() shells out to bridge/launch-project.sh.
Item {
    id: store

    // path → { sessions, mode, host }  (only non-default overrides are stored)
    property var settings: ({})
    // sanitized tmux session name → true, for the live "running" badge
    property var live: ({})
    // [{ name, path }] discovered under ~/Projects
    property var dirs: []

    readonly property string statePath: FileUtils.trimFileProtocol(`${Directories.state}/user/agentisland-projects.json`)
    // bridge/launch-project.sh. NOTE: Quickshell loads QML from a virtual (qrc-like)
    // FS, so Qt.resolvedUrl("../bridge/…") yields a bogus "qrc:/…" path that
    // execDetached can't run. Quickshell.shellDir is the REAL on-disk config dir
    // (…/quickshell), so go up one to the repo root and into bridge/.
    readonly property string launcher: FileUtils.trimFileProtocol(Quickshell.shellDir + "/../bridge/launch-project.sh")

    readonly property var modeOptions: ["bypass", "default", "plan", "acceptEdits"]
    readonly property var hostOptions: ["kitty", "alacritty", "warp"]

    // Same sanitization the bash launcher applies, so the names we test against
    // tmux match the sessions it creates.
    function sanitize(name) {
        return name.replace(/[ .:/]/g, "_").replace(/[^A-Za-z0-9_-]/g, "") || "project";
    }

    function settingFor(path) {
        const s = store.settings[path] || {};
        return {
            sessions: s.sessions ?? 1,
            mode: s.mode ?? "bypass",
            host: s.host ?? "kitty"
        };
    }

    function setSetting(path, key, val) {
        const next = Object.assign({}, store.settings);
        next[path] = Object.assign(store.settingFor(path), next[path] || {});
        next[path][key] = val;
        store.settings = next; // reassign → notify bindings
        stateFile.setText(JSON.stringify(store.settings));
    }

    // Projects added from outside ~/Projects, stored as settings keys flagged added.
    readonly property var extraDirs: {
        const out = [];
        for (const path in store.settings) {
            if (store.settings[path] && store.settings[path].added) {
                const name = path.split("/").filter(s => s.length > 0).pop() || path;
                out.push({ name: name, path: path });
            }
        }
        return out;
    }

    // Computed view the UI binds to: dirs + extras + settings + live, running-first.
    readonly property var projects: {
        const out = [];
        const seen = {};
        for (const d of store.dirs.concat(store.extraDirs)) {
            if (seen[d.path]) continue;
            seen[d.path] = true;
            const s = store.settingFor(d.path);
            out.push({
                name: d.name,
                path: d.path,
                sessions: s.sessions,
                mode: s.mode,
                host: s.host,
                lastOpened: (store.settings[d.path] && store.settings[d.path].lastOpened) || 0,
                running: store.live[store.sanitize(d.name)] === true
            });
        }
        out.sort((a, b) => (b.running - a.running) || a.name.localeCompare(b.name));
        return out;
    }

    // Most-recently-launched projects, newest first (for the Recents row).
    readonly property var recents: {
        const out = store.projects.filter(p => p.lastOpened > 0);
        out.sort((a, b) => b.lastOpened - a.lastOpened);
        return out.slice(0, 6);
    }

    function launch(p) {
        const s = store.settingFor(p.path);
        Quickshell.execDetached([
            store.launcher,
            "--dir", p.path,
            "--name", store.sanitize(p.name),
            "--sessions", String(s.sessions),
            "--mode", s.mode,
            "--host", s.host
        ]);
        store.setSetting(p.path, "lastOpened", Date.now()); // for Recents
        // give the session a beat to register, then refresh the live badges
        liveDelay.restart();
    }

    // Launch using an explicit working dir (a subfolder picked via "Launch from…").
    function launchFrom(p, dir) {
        const s = store.settingFor(p.path);
        const base = dir.split("/").filter(x => x.length > 0).pop() || p.name;
        Quickshell.execDetached([
            store.launcher,
            "--dir", dir,
            "--name", store.sanitize(base),
            "--sessions", String(s.sessions),
            "--mode", s.mode,
            "--host", s.host
        ]);
        store.setSetting(p.path, "lastOpened", Date.now());
        liveDelay.restart();
    }

    function openFolder(path) { Quickshell.execDetached(["xdg-open", path]); }

    function removeRecent(path) { store.setSetting(path, "lastOpened", 0); }

    // Add an existing folder from anywhere as a project (flagged added).
    function addPath(path) {
        if (!path || path.length === 0) return;
        const next = Object.assign({}, store.settings);
        next[path] = Object.assign({}, next[path] || {}, { added: true });
        store.settings = next;
        stateFile.setText(JSON.stringify(store.settings));
    }
    function addExisting() { pickProc.running = true; }

    // Create a brand-new project folder under ~/Projects (optionally git init).
    function createProject(name, gitInit) {
        const safe = name.replace(/[^A-Za-z0-9 ._-]/g, "").trim();
        if (safe.length === 0) return;
        const initCmd = gitInit ? '&& git -C "$d" init -q' : "";
        Quickshell.execDetached(["bash", "-c",
            `d="$HOME/Projects/${safe}"; mkdir -p "$d" ${initCmd}`]);
        rescanDelay.restart();
    }

    // Subdir listing for "Launch from…": immediate subfolders of a project.
    property string subdirsFor: ""
    property var subdirs: []
    function loadSubdirs(path) {
        store.subdirsFor = path;
        store.subdirs = [];
        subdirProc.command = ["find", path, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-not", "-name", ".*", "-printf", "%f\t%p\n"];
        subdirProc.running = true;
    }

    function rescan() { scanProc.running = true; }
    function refreshLive() { tmuxProc.running = true; }

    Component.onCompleted: {
        stateFile.reload();
        scanProc.running = true;
        tmuxProc.running = true;
    }

    // ---- persistence ----
    FileView {
        id: stateFile
        path: Qt.resolvedUrl(store.statePath)
        onLoaded: {
            try { store.settings = JSON.parse(stateFile.text()) || {}; }
            catch (e) { store.settings = {}; }
        }
        onLoadFailed: error => {
            store.settings = {};
            if (error === FileViewError.FileNotFound)
                stateFile.setText("{}");
        }
    }

    // ---- scan ~/Projects ----
    Process {
        id: scanProc
        command: ["bash", "-c", "find \"$HOME/Projects\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\t%p\\n' | sort -f"]
        stdout: StdioCollector {
            id: scanOut
            onStreamFinished: {
                const rows = scanOut.text.split("\n").filter(l => l.length > 0);
                store.dirs = rows.map(l => {
                    const tab = l.indexOf("\t");
                    return { name: l.slice(0, tab), path: l.slice(tab + 1) };
                });
            }
        }
    }

    // ---- which tmux sessions are live ----
    Process {
        id: tmuxProc
        command: ["bash", "-c", "tmux list-sessions -F '#{session_name}' 2>/dev/null || true"]
        stdout: StdioCollector {
            id: tmuxOut
            onStreamFinished: {
                const names = tmuxOut.text.split("\n").filter(l => l.length > 0);
                const m = {};
                for (const n of names) m[n] = true;
                store.live = m;
            }
        }
    }

    // folder picker for "Add existing" (kdialog prints the chosen path)
    Process {
        id: pickProc
        command: ["bash", "-c", "kdialog --getexistingdirectory \"$HOME\" 2>/dev/null"]
        stdout: StdioCollector {
            id: pickOut
            onStreamFinished: {
                const p = pickOut.text.trim();
                if (p.length > 0) store.addPath(p);
            }
        }
    }

    // subdir listing for "Launch from…"
    Process {
        id: subdirProc
        stdout: StdioCollector {
            id: subdirOut
            onStreamFinished: {
                const rows = subdirOut.text.split("\n").filter(l => l.length > 0);
                const out = rows.map(l => {
                    const t = l.indexOf("\t");
                    return { name: l.slice(0, t), path: l.slice(t + 1) };
                });
                out.sort((a, b) => a.name.localeCompare(b.name));
                store.subdirs = out;
            }
        }
    }

    Timer { id: rescanDelay; interval: 500; onTriggered: store.rescan(); }

    // poll live sessions so badges update as sessions come and go
    Timer { interval: 4000; running: true; repeat: true; onTriggered: store.refreshLive(); }
    Timer { id: liveDelay; interval: 1200; onTriggered: store.refreshLive(); }
    // re-scan ~/Projects so added/deleted folders don't linger as stale tiles
    Timer { interval: 20000; running: true; repeat: true; onTriggered: store.rescan(); }
}
