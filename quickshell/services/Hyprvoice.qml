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
        doneFlash = false;
        state = "recording"; // optimistic — poll confirms
        sawInjecting = false;
        idleGrace = 4;
        Quickshell.execDetached(["hyprvoice", "toggle"]);
    }

    function pttReleased() {
        if (!pttHeld)
            return; // duplicate release (or release of an ignored press)
        pttHeld = false;
        if (state === "recording")
            state = "transcribing"; // optimistic
        idleGrace = 4;
        Quickshell.execDetached(["hyprvoice", "toggle"]);
    }

    function cancel() {
        Quickshell.execDetached(["hyprvoice", "cancel"]);
        pttHeld = false;
        idleGrace = 0;
        doneFlash = false;
        state = "idle";
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
