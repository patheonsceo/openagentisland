pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Headless listener for the Claude Code agent bridge. Hosts the Unix socket that
// the hook client (bridge/oai_hook.py) connects to. Maintains per-session status
// and a queue of pending permission requests, and writes Allow/Deny decisions
// back on the held connection. The notch agent UI (later) reads `sessions` /
// `pendingPermissions` and calls allow()/deny(). See bridge/ + NOTES.md §5.
//
// Safety lives on the HOOK side (timeout + fallback). This side just needs to not
// crash on bad input — every parse is guarded; a dropped connection clears its
// pending request so the queue can't wedge.
Singleton {
    id: root

    readonly property string socketPath: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        return (xdg && xdg.length > 0 ? xdg : "/tmp") + "/openagentisland.sock";
    }
    property bool debug: false  // set true to log every received line to the qs log

    // session_id → { project, cwd, tool, summary, message, lastEvent, status, ts }
    property var sessions: ({})
    // [{ request_id, session_id, project, cwd, tool, summary, ts }]
    property var pendingPermissions: []
    property var _conns: ({})          // request_id → Socket (held open until decided)
    property var _sessionBypass: ({})  // session_id → true (Bypass: allow ALL tools)
    property var _toolAllow: ({})       // "session|tool" → true (Allow All: this tool)

    // --- derived: what the compact notch shows (most-urgent session) ---
    readonly property var sessionList: {
        const rank = { "permission": 0, "waiting": 1, "working": 2, "running": 3, "idle": 3, "done": 4 };
        const out = [];
        for (const k in root.sessions)
            out.push(Object.assign({ "id": k }, root.sessions[k]));
        out.sort((a, b) => {
            const ra = rank[a.status] ?? 5, rb = rank[b.status] ?? 5;
            if (ra !== rb)
                return ra - rb;
            return (b.ts || 0) - (a.ts || 0); // most recent first within a rank
        });
        return out;
    }
    readonly property int sessionCount: root.sessionList.length
    readonly property string headlineMode: {
        if (root.pendingPermissions.length > 0)
            return "permission";
        let working = false, done = false;
        for (let i = 0; i < root.sessionList.length; i++) {
            const s = root.sessionList[i];
            if (s.status === "waiting")
                return "waiting";
            if (s.status === "working" || s.status === "running")
                working = true;
            if (s.status === "done")
                done = true;
        }
        if (working)
            return "working";
        // nothing active: a just-finished session shows "Done" (until pruned),
        // otherwise resting sessions show the brand label.
        if (done)
            return "done";
        if (root.sessionList.length > 0)
            return "idle";
        return "";
    }
    readonly property var headlineSession: {
        if (root.pendingPermissions.length > 0) {
            const sid = root.pendingPermissions[0].session_id;
            return root.sessions[sid] ? Object.assign({ "id": sid }, root.sessions[sid]) : null;
        }
        for (let i = 0; i < root.sessionList.length; i++)
            if (root.sessionList[i].status === "waiting")
                return root.sessionList[i];
        for (let i = 0; i < root.sessionList.length; i++)
            if (root.sessionList[i].status === "working")
                return root.sessionList[i];
        return null;
    }
    readonly property bool active: root.headlineMode !== ""

    // no-op so shell.qml can force-instantiate this singleton (→ server goes active)
    function load() {}

    function statusFor(event, prev) {
        switch (event) {
        case "SessionStart": return "idle";
        case "UserPromptSubmit": return "working";
        case "PreToolUse": return "working";
        case "PostToolUse": return "working";
        case "Notification": return "waiting";
        case "Stop": return "done";
        default: return prev || "idle";
        }
    }

    function applyEvent(obj) {
        const sid = obj.session_id || "default";
        const prev = root.sessions[sid] || {};
        const st = statusFor(obj.event, prev.status);
        const next = Object.assign({}, root.sessions);
        next[sid] = {
            "project": obj.project || prev.project || "",
            "cwd": obj.cwd || prev.cwd || "",
            "tool": obj.tool || "",
            "summary": obj.summary || "",
            "message": obj.message || "",
            // the actual user prompt (only from UserPromptSubmit; persists)
            "prompt": obj.event === "UserPromptSubmit" ? (obj.message || prev.prompt || "") : (prev.prompt || ""),
            "lastEvent": obj.event || "",
            "status": st,
            // process-ancestor PIDs (terminal window is one of them) — for jump-to-terminal
            "pids": (obj.pids && obj.pids.length > 0) ? obj.pids : (prev.pids || []),
            // terminal's permission mode (default|acceptEdits|plan|bypassPermissions)
            "mode": (obj.mode && obj.mode.length > 0) ? obj.mode : (prev.mode || "default"),
            "ts": obj.ts || 0,
            "doneTick": st === "done" ? root._tick : 0,
            "waitTick": st === "waiting" ? (prev.status === "waiting" ? (prev.waitTick || root._tick) : root._tick) : 0,
            "seenTick": root._tick,
        };
        root.sessions = next;
    }

    // Prune finished sessions a few seconds after Stop so the notch returns to
    // State 1 (base) when nothing is running. Tick-based to avoid Date.
    property int _tick: 0
    property double now: Math.floor(Date.now() / 1000)  // live epoch seconds (for relative time)
    readonly property int _doneLingerTicks: 5     // finished session lingers ~5s then collapses
    readonly property int _waitDemoteTicks: 60    // "waiting" → calm resting after ~1 min
    readonly property int _stalenessTicks: 300    // no events for ~5 min → ghost session, prune
    Timer {
        // Only tick while there's at least one session to age/prune. With no
        // sessions this loop did nothing useful but still rewrote `now` every
        // second, invalidating every relative-time binding downstream. The last
        // session's own pruning keeps sessionCount > 0 until it's removed, then
        // the timer goes quiet.
        interval: 1000
        running: root.sessionCount > 0
        repeat: true
        onTriggered: {
            root._tick++;
            root.now = Math.floor(Date.now() / 1000);
            let changed = false;
            const next = Object.assign({}, root.sessions);
            for (const k in next) {
                const s = next[k];
                if (s.status === "done" && (root._tick - (s.doneTick || 0)) >= root._doneLingerTicks) {
                    delete next[k];
                    changed = true;
                } else if (s.status === "waiting" && (root._tick - (s.waitTick || 0)) >= root._waitDemoteTicks) {
                    // idle-waiting for ~1 min → drop the "Waiting…" back to calm resting
                    next[k] = Object.assign({}, s, { "status": "idle" });
                    changed = true;
                } else if (s.status !== "permission" && (root._tick - (s.seenTick || 0)) >= root._stalenessTicks) {
                    // ghost (crashed terminal / killed claude with no Stop) — clean up.
                    delete next[k];
                    changed = true;
                }
            }
            if (changed)
                root.sessions = next;
        }
    }

    function _autoAllowed(sid, tool) {
        return root._sessionBypass[sid] === true || root._toolAllow[sid + "|" + tool] === true;
    }

    // --- island-side auto-rule state (for display) ---
    function isBypassed(sid) {
        return root._sessionBypass[sid] === true;
    }
    function allowedToolsFor(sid) {
        const out = [];
        const pfx = sid + "|";
        for (const k in root._toolAllow)
            if (root._toolAllow[k] === true && k.indexOf(pfx) === 0)
                out.push(k.slice(pfx.length));
        return out;
    }

    function addPermission(obj, conn) {
        const sid = obj.session_id || "";
        const tool = obj.tool || "";
        // Honour an earlier "Allow All" / "Bypass" rule → auto-allow, no UI.
        if (root._autoAllowed(sid, tool)) {
            try {
                conn.write(JSON.stringify({ "type": "permission_decision", "request_id": obj.request_id, "decision": "allow", "reason": "auto-allowed" }) + "\n");
                conn.flush();
            } catch (e) {}
            root.applyEvent({ "session_id": sid, "cwd": obj.cwd, "project": obj.project, "event": "PreToolUse", "tool": tool, "summary": obj.summary });
            return;
        }
        conn.reqId = obj.request_id;
        root._conns[obj.request_id] = conn;
        const list = root.pendingPermissions.slice();
        list.push({
            "request_id": obj.request_id,
            "session_id": sid,
            "project": obj.project || "",
            "cwd": obj.cwd || "",
            "tool": tool,
            "summary": obj.summary || "",
            "preview": obj.preview || null,
            "ts": obj.ts || 0,
        });
        root.pendingPermissions = list;
        const prev = root.sessions[sid || "default"] || {};
        const next = Object.assign({}, root.sessions);
        next[sid || "default"] = Object.assign({}, prev, {
            "project": obj.project || prev.project || "",
            "cwd": obj.cwd || prev.cwd || "",
            "tool": tool,
            "summary": obj.summary || "",
            "status": "permission",
            "seenTick": root._tick,
        });
        root.sessions = next;
    }

    // Remove a session outright (its terminal closed / it exited). Also clears any
    // of its bypass/allow rules and pending permission rows so nothing lingers.
    function endSession(sid) {
        if (root.sessions[sid]) {
            const next = Object.assign({}, root.sessions);
            delete next[sid];
            root.sessions = next;
        }
        const remaining = root.pendingPermissions.filter(p => (p.session_id || "default") !== sid);
        if (remaining.length !== root.pendingPermissions.length)
            root.pendingPermissions = remaining;
        if (root._sessionBypass[sid]) {
            const b = Object.assign({}, root._sessionBypass);
            delete b[sid];
            root._sessionBypass = b;
        }
    }

    function dropPending(reqId) {
        const p = root.pendingPermissions.find(x => x.request_id === reqId);
        delete root._conns[reqId];
        root.pendingPermissions = root.pendingPermissions.filter(x => x.request_id !== reqId);
        // The request is gone (decided or timed out) — don't leave the session
        // stuck showing "permission"; revert it to working.
        if (p) {
            const sid = p.session_id || "default";
            const prev = root.sessions[sid];
            if (prev && prev.status === "permission") {
                const next = Object.assign({}, root.sessions);
                next[sid] = Object.assign({}, prev, { "status": "working" });
                root.sessions = next;
            }
        }
    }

    function decide(reqId, decision, reason) {
        const conn = root._conns[reqId];
        if (conn) {
            try {
                conn.write(JSON.stringify({
                    "type": "permission_decision",
                    "request_id": reqId,
                    "decision": decision,
                    "reason": reason || "",
                }) + "\n");
                conn.flush();
            } catch (e) {}
        }
        dropPending(reqId);
    }
    function _pending(reqId) {
        return root.pendingPermissions.find(p => p.request_id === reqId) || null;
    }
    function deny(reqId) { root.decide(reqId, "deny", "Denied from the island"); }
    function allowOnce(reqId) { root.decide(reqId, "allow", "Allowed once"); }
    function allow(reqId) { root.allowOnce(reqId); }  // alias
    function allowAll(reqId) {
        const p = root._pending(reqId);
        if (p) {
            const m = Object.assign({}, root._toolAllow);
            m[(p.session_id || "") + "|" + (p.tool || "")] = true;
            root._toolAllow = m;
            root._toast("Allow " + (p.tool || "tool") + " ✓");
        }
        root.decide(reqId, "allow", "Allow all (this tool, this session)");
    }
    function bypass(reqId) {
        const p = root._pending(reqId);
        if (p) {
            const m = Object.assign({}, root._sessionBypass);
            m[p.session_id || ""] = true;
            root._sessionBypass = m;
            root._toast("Bypass ✓");
        }
        root.decide(reqId, "allow", "Bypass (all tools, this session)");
    }

    // brief confirmation toast shown in the compact notch
    property string toast: ""
    Timer { id: toastTimer; interval: 2600; onTriggered: root.toast = "" }
    function _toast(t) { root.toast = t; toastTimer.restart(); }

    function onLine(conn, line) {
        if (!line || line.trim().length === 0)
            return;
        if (root.debug)
            console.log("[agent] recv:", line);
        let obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (obj.type === "permission_request" && obj.request_id) {
            root.addPermission(obj, conn);
        } else if (obj.event === "SessionEnd") {
            // Session actually closed (exit / terminal closed) — remove it now
            // instead of leaving a ghost "idle"/"waiting" row until staleness.
            root.endSession(obj.session_id || "default");
        } else {
            root.applyEvent(obj);
        }
    }

    // Manual control / test hook: `qs -c openagentisland ipc call agent <fn>`.
    // Acts on the oldest pending permission. Useful for testing the round-trip
    // and as a keyboard-free fallback.
    IpcHandler {
        target: "agent"
        function status(): string {
            return JSON.stringify({
                "sessions": Object.keys(root.sessions).length,
                "pending": root.pendingPermissions.length
            });
        }
        function dump(): string {
            return JSON.stringify({
                "active": root.active,
                "headlineMode": root.headlineMode,
                "sessionCount": root.sessionCount,
                "statuses": root.sessionList.map(s => s.id + ":" + s.status)
            });
        }
        function allowOldest(): string {
            if (root.pendingPermissions.length === 0)
                return "none";
            const r = root.pendingPermissions[0].request_id;
            root.allowOnce(r);
            return "allowOnce " + r;
        }
        function denyOldest(): string {
            if (root.pendingPermissions.length === 0)
                return "none";
            const r = root.pendingPermissions[0].request_id;
            root.deny(r);
            return "deny " + r;
        }
        function allowAllOldest(): string {
            if (root.pendingPermissions.length === 0)
                return "none";
            const r = root.pendingPermissions[0].request_id;
            root.allowAll(r);
            return "allowAll " + r;
        }
        function bypassOldest(): string {
            if (root.pendingPermissions.length === 0)
                return "none";
            const r = root.pendingPermissions[0].request_id;
            root.bypass(r);
            return "bypass " + r;
        }
    }

    SocketServer {
        active: true
        path: root.socketPath
        handler: Component {
            Socket {
                id: conn
                property string reqId: ""
                parser: SplitParser {
                    onRead: line => root.onLine(conn, line)
                }
                onConnectedChanged: {
                    if (!conn.connected && conn.reqId.length > 0) {
                        root.dropPending(conn.reqId);
                        conn.reqId = "";
                    }
                }
            }
        }
    }
}
