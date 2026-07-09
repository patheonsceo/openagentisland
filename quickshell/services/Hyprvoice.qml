pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Hyprvoice dictation state for the notch (push-to-talk).
 *
 * The `hyprvoicePtt` global shortcut (a hold key in Hyprland: press bind +
 * release bind) drives `hyprvoice toggle` from HERE — press starts recording,
 * release stops it — so the notch reacts instantly instead of waiting for a
 * poll. While a run is active the daemon is polled (`hyprvoice status` →
 * "STATUS status=<s>") to follow recording → transcribing → [processing] →
 * injecting → idle. (The waveform in the notch is procedural — a mic-cava
 * feed was tried and looked dead at low mic gain.)
 */
Singleton {
    id: root

    // Daemon pipeline state: idle | recording | transcribing | processing | injecting
    property string state: "idle"
    property bool pttHeld: false
    // Brief success flash after a run that actually injected text.
    property bool doneFlash: false
    property bool sawInjecting: false
    // Swallow stale "idle" reads right after a toggle (daemon still spinning up),
    // so the pill doesn't collapse mid-handshake.
    property int idleGrace: 0
    // Consecutive unparseable status reads (daemon down?) — bail out, don't
    // poll forever with the pill stuck open.
    property int failCount: 0
    readonly property bool active: state !== "idle" || doneFlash

    // UI phase. The daemon reports "transcribing" from the FIRST AUDIO FRAME
    // (its streaming design), so while the key is held it's really capturing —
    // pttHeld, not daemon state, decides "listening".
    readonly property string phase: {
        if (state === "idle")
            return doneFlash ? "done" : "idle";
        if (pttHeld)
            return "listening";
        if (state === "injecting")
            return "typing";
        if (state === "processing")
            return "polishing";
        return "transcribing"; // recording|transcribing after release → STT running
    }

    // Tap-guard: the daemon toggle is only sent once the key has been held
    // ARM_MS — virtual keyboards on this system (vicinae snippets, ydotoold)
    // and flaky 2.4G dongles can synthesize brief phantom Control_R events,
    // which used to start ghost "listening" runs. A sub-ARM_MS tap now does
    // NOTHING (no pill, no daemon run). See /tmp/hyprvoice-ptt.log +
    // /tmp/rctrl-events.log for the diagnostics trail.
    readonly property int armMs: 200
    // Toggle actually sent to the daemon for the current hold.
    property bool armed: false
    property double pressedAtMs: 0

    function plog(msg) {
        Quickshell.execDetached(["sh", "-c", "printf '%s %s\\n' \"$(date '+%F %T.%3N')\" \"$1\" >> /tmp/hyprvoice-ptt.log", "plog", msg]);
    }

    // IDEMPOTENT on purpose: Hyprland can deliver DUPLICATE press/release events
    // for a global shortcut (the press bind's key tracking releases it AND the
    // explicit release bind fires). A duplicate release used to send a second
    // toggle µs after the first — the daemon treats toggle-while-injecting as
    // ABORT, which context-canceled the Groq upload mid-flight.
    function pttPressed() {
        if (pttHeld)
            return; // duplicate press
        if (state !== "idle")
            return; // previous run still finishing — don't abort it
        pttHeld = true;
        pressedAtMs = Date.now();
        armed = false;
        armTimer.restart();
        plog("press");
    }

    function pttReleased() {
        if (!pttHeld)
            return; // duplicate release (or release of an ignored press)
        pttHeld = false;
        const heldMs = Math.round(Date.now() - pressedAtMs);
        if (!armed) {
            armTimer.stop();
            plog(`ghost tap ignored (${heldMs}ms)`);
            return; // never reached the daemon — nothing to undo
        }
        armed = false;
        if (state === "recording")
            state = "transcribing"; // optimistic
        idleGrace = 4;
        Quickshell.execDetached(["hyprvoice", "toggle"]);
        plog(`release -> transcribe (held ${heldMs}ms)`);
    }

    Timer {
        id: armTimer
        interval: root.armMs
        onTriggered: {
            if (!root.pttHeld || root.state !== "idle")
                return;
            root.armed = true;
            root.doneFlash = false;
            root.state = "recording"; // optimistic — poll confirms
            root.sawInjecting = false;
            root.idleGrace = 4;
            Quickshell.execDetached(["hyprvoice", "toggle"]);
            root.plog("armed -> recording");
        }
    }

    // A press that never releases (stuck virtual/wireless key) would record
    // forever and eventually inject hallucinated text — cancel it instead.
    // Legit dictations are re-pressable; hyprvoice's own cap is 5m and INJECTS.
    Timer {
        interval: 120000
        running: root.armed && root.pttHeld
        onTriggered: {
            root.plog("stuck press: auto-cancel after 120s");
            root.cancel();
        }
    }

    function cancel() {
        Quickshell.execDetached(["hyprvoice", "cancel"]);
        pttHeld = false;
        armed = false;
        armTimer.stop();
        idleGrace = 0;
        doneFlash = false;
        state = "idle";
        plog("cancel");
    }

    function applyStatus(out) {
        const m = /status=([a-z]+)/.exec(out);
        if (!m) {
            failCount++;
            if (failCount > 10) { // ~2s of dead daemon → give up
                state = "idle";
                doneFlash = false;
                failCount = 0;
            }
            return;
        }
        failCount = 0;
        const s = m[1];
        if (s === "idle") {
            if (idleGrace > 0) {
                idleGrace--;
                return;
            }
            if (state !== "idle") {
                if (sawInjecting) { // real completion, not an aborted run
                    doneFlash = true;
                    flashTimer.restart();
                }
                state = "idle";
                sawInjecting = false;
            }
        } else {
            idleGrace = 0;
            if (s === "injecting")
                sawInjecting = true;
            state = s;
        }
    }

    GlobalShortcut {
        name: "hyprvoicePtt"
        description: "Hyprvoice push-to-talk (hold to dictate)"
        onPressed: root.pttPressed()
        onReleased: root.pttReleased()
    }

    // Scriptable from the CLI: qs -c openagentisland ipc call hyprvoice pttPress
    IpcHandler {
        target: "hyprvoice"

        function pttPress(): void {
            root.pttPressed();
        }
        function pttRelease(): void {
            root.pttReleased();
        }
        function cancel(): void {
            root.cancel();
        }
    }

    Timer {
        id: flashTimer
        interval: 900
        onTriggered: root.doneFlash = false
    }

    Timer {
        interval: 200
        repeat: true
        running: root.state !== "idle"
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }

    Process {
        id: statusProc
        command: ["hyprvoice", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
    }

    // If the shell (re)starts mid-run, sync with the daemon once.
    Component.onCompleted: statusProc.running = true
}
