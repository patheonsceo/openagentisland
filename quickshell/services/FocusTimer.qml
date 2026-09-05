pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Per-task focus countdown, driven by the desktop todo widget.
 *
 * Distinct from TimerService's pomodoro: that one cycles work/break forever and
 * belongs to nobody, this one counts a single chosen duration down against one
 * specific task and logs the time onto it when the session ends.
 *
 * Time is wall-clock, not tick-counted. `start` is a unix timestamp that gets
 * shifted forward on resume to absorb the pause, so the countdown stays honest
 * across suspend, and across a shell reload — Quickshell restarts the singleton
 * but Persistent still holds the timestamp, so a running session picks straight
 * back up where it was.
 */
Singleton {
    id: root

    readonly property string taskId: Persistent.states.timer.focus.taskId
    readonly property string taskContent: Persistent.states.timer.focus.taskContent
    readonly property bool running: Persistent.states.timer.focus.running
    readonly property bool minimized: Persistent.states.timer.focus.minimized
    readonly property int duration: Persistent.states.timer.focus.duration

    // A session exists (running or paused) whenever a task is attached.
    readonly property bool active: root.taskId.length > 0

    property int secondsLeft: 0
    readonly property int secondsElapsed: Math.max(0, root.duration - root.secondsLeft)
    readonly property real progress: root.duration > 0
        ? Math.max(0, Math.min(1, root.secondsElapsed / root.duration))
        : 0

    signal finished(string taskId)

    function getCurrentTimeInSeconds() {
        return Math.floor(Date.now() / 1000);
    }

    function formatDuration(totalSeconds) {
        const s = Math.max(0, Math.round(totalSeconds));
        const hours = Math.floor(s / 3600);
        const minutes = Math.floor((s % 3600) / 60);
        const seconds = s % 60;
        if (hours > 0)
            return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
        return `${minutes}:${String(seconds).padStart(2, "0")}`;
    }

    // Compact form for "1h 05m logged", not the countdown readout.
    function formatLogged(totalSeconds) {
        const s = Math.max(0, Math.round(totalSeconds));
        const hours = Math.floor(s / 3600);
        const minutes = Math.floor((s % 3600) / 60);
        if (hours > 0) return `${hours}h ${String(minutes).padStart(2, "0")}m`;
        if (minutes > 0) return `${minutes}m`;
        return `${s}s`;
    }

    function start(taskId, taskContent, seconds) {
        if (!taskId || seconds <= 0) return;
        const state = Persistent.states.timer.focus;
        state.taskId = taskId;
        state.taskContent = taskContent ?? "";
        state.duration = Math.round(seconds);
        state.start = root.getCurrentTimeInSeconds();
        state.pausedLeft = 0;
        state.minimized = false;
        state.running = true;
        // Cleared here, not set — the overlay knows which monitor is focused
        // and pins it on the first frame it is shown.
        state.screenName = "";
        Todo.rememberDuration(taskId, Math.round(seconds));
        root.refresh();
    }

    function pause() {
        if (!root.running) return;
        const state = Persistent.states.timer.focus;
        state.pausedLeft = root.secondsLeft;
        state.running = false;
    }

    function resume() {
        if (root.running || !root.active) return;
        const state = Persistent.states.timer.focus;
        // Shift the start point so the remaining time is preserved exactly.
        state.start = root.getCurrentTimeInSeconds() - (state.duration - state.pausedLeft);
        state.running = true;
        root.refresh();
    }

    function toggle() {
        if (root.running) root.pause();
        else root.resume();
    }

    function setMinimized(value) {
        Persistent.states.timer.focus.minimized = value;
    }

    function toggleMinimized() {
        root.setMinimized(!root.minimized);
    }

    // Writes whatever time was actually spent onto the task, then clears the session.
    function logAndClear() {
        const state = Persistent.states.timer.focus;
        const elapsed = root.secondsElapsed;
        if (state.taskId.length > 0 && elapsed > 0)
            Todo.logSession(state.taskId, state.start, elapsed);
        state.taskId = "";
        state.taskContent = "";
        state.running = false;
        state.minimized = false;
        state.duration = 0;
        state.start = 0;
        state.pausedLeft = 0;
        root.secondsLeft = 0;
    }

    // Give up on the session. Time already spent is still credited.
    function stop() {
        root.logAndClear();
    }

    // Finished the work early: credit the time and tick the task off.
    function complete() {
        const id = Persistent.states.timer.focus.taskId;
        root.logAndClear();
        if (id.length > 0) Todo.toggleDoneById(id);
    }

    function refresh() {
        const state = Persistent.states.timer.focus;
        if (!root.active) {
            root.secondsLeft = 0;
            return;
        }
        if (!state.running) {
            root.secondsLeft = state.pausedLeft;
            return;
        }

        const left = state.duration - (root.getCurrentTimeInSeconds() - state.start);
        if (left > 0) {
            root.secondsLeft = left;
            return;
        }

        // Ran out. Credit the full duration, notify, and clear.
        root.secondsLeft = 0;
        const finishedId = state.taskId;
        const label = state.taskContent.length > 0 ? state.taskContent : Translation.tr("your task");
        Todo.logSession(finishedId, state.start, state.duration);

        state.taskId = "";
        state.taskContent = "";
        state.running = false;
        state.minimized = false;
        state.duration = 0;
        state.start = 0;
        state.pausedLeft = 0;

        Quickshell.execDetached(["notify-send",
            Translation.tr("Focus complete"),
            Translation.tr("Finished: %1").arg(label),
            "-a", "Shell", "-u", "normal"]);
        if (Config.options.sounds.focus)
            Audio.playSystemSound("alarm-clock-elapsed");

        root.finished(finishedId);
    }

    Timer {
        id: focusTicker
        interval: 200
        running: root.running
        repeat: true
        onTriggered: root.refresh()
    }

    // A shell reload restarts this singleton with Persistent already populated,
    // so recompute once rather than waiting for the first tick.
    Component.onCompleted: root.refresh()

    Connections {
        target: Persistent
        function onReadyChanged() { root.refresh(); }
    }
}
