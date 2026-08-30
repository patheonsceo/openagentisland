pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Simple to-do list manager.
 *
 * An item is `{ content, done }` plus, since the desktop widget landed:
 *   id            stable identifier, so a running timer survives reordering
 *   createdAt     unix seconds
 *   doneAt        unix seconds, 0 while unfinished
 *   lastDuration  seconds picked the last time this task was started
 *   sessions      [{ start, seconds }] focus sessions logged against the task
 *
 * Files written before those fields existed load fine — migrate() fills them in
 * on read, and the file is only rewritten when something else changes it.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var list: []

    function getCurrentTimeInSeconds() {
        return Math.floor(Date.now() / 1000);
    }

    function generateId() {
        return `${Date.now().toString(36)}-${Math.floor(Math.random() * 1e6).toString(36)}`;
    }

    // Fills in fields added after a file was written. Returns true if anything changed,
    // so we only rewrite the file when a migration actually happened.
    function migrate(items) {
        let changed = false;
        const now = getCurrentTimeInSeconds();
        items.forEach(item => {
            if (item.id === undefined) { item.id = root.generateId(); changed = true; }
            if (item.done === undefined) { item.done = false; changed = true; }
            if (item.createdAt === undefined) { item.createdAt = now; changed = true; }
            if (item.doneAt === undefined) { item.doneAt = item.done ? now : 0; changed = true; }
            if (item.lastDuration === undefined) { item.lastDuration = 0; changed = true; }
            if (!Array.isArray(item.sessions)) { item.sessions = []; changed = true; }
        });
        return changed;
    }

    function save() {
        // Reassign to trigger onListChanged
        root.list = root.list.slice(0);
        todoFileView.setText(JSON.stringify(root.list));
    }

    function indexOfId(id) {
        return root.list.findIndex(item => item.id === id);
    }

    function getById(id) {
        return root.list[root.indexOfId(id)];
    }

    function addItem(item) {
        root.list.push(item);
        root.save();
    }

    function addTask(desc, duration = 0) {
        const trimmed = `${desc}`.trim();
        if (trimmed.length === 0) return null;
        const item = {
            "id": root.generateId(),
            "content": trimmed,
            "done": false,
            "createdAt": root.getCurrentTimeInSeconds(),
            "doneAt": 0,
            "lastDuration": duration,
            "sessions": [],
        };
        root.addItem(item);
        return item.id;
    }

    function markDone(index) {
        if (index >= 0 && index < root.list.length) {
            root.list[index].done = true;
            root.list[index].doneAt = root.getCurrentTimeInSeconds();
            root.save();
        }
    }

    function markUnfinished(index) {
        if (index >= 0 && index < root.list.length) {
            root.list[index].done = false;
            root.list[index].doneAt = 0;
            root.save();
        }
    }

    function toggleDoneById(id) {
        const index = root.indexOfId(id);
        if (index < 0) return;
        if (root.list[index].done) root.markUnfinished(index);
        else root.markDone(index);
    }

    function deleteItem(index) {
        if (index >= 0 && index < root.list.length) {
            root.list.splice(index, 1);
            root.save();
        }
    }

    function deleteById(id) {
        root.deleteItem(root.indexOfId(id));
    }

    function setContent(id, content) {
        const index = root.indexOfId(id);
        const trimmed = `${content}`.trim();
        if (index < 0 || trimmed.length === 0) return;
        root.list[index].content = trimmed;
        root.save();
    }

    // Remembered so the second run of a task is one click instead of two.
    function rememberDuration(id, seconds) {
        const index = root.indexOfId(id);
        if (index < 0) return;
        root.list[index].lastDuration = seconds;
        root.save();
    }

    function logSession(id, startedAt, seconds) {
        const index = root.indexOfId(id);
        if (index < 0 || seconds <= 0) return;
        root.list[index].sessions.push({ "start": startedAt, "seconds": Math.round(seconds) });
        root.save();
    }

    function totalSeconds(item) {
        if (!item || !Array.isArray(item.sessions)) return 0;
        return item.sessions.reduce((sum, session) => sum + (session.seconds ?? 0), 0);
    }

    function clearAll() {
        root.list = [];
        root.save();
    }

    function clearCompleted() {
        root.list = root.list.filter(item => !item.done);
        root.save();
    }

    readonly property var unfinished: root.list.filter(item => !item.done)
    readonly property var completed: root.list.filter(item => item.done)

    function refresh() {
        todoFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        // Two views onto one list now — the sidebar and the desktop widget — plus
        // anything editing the file directly. Watching keeps them in step instead
        // of each holding its own stale copy until the next shell reload.
        watchChanges: true
        onFileChanged: todoFileView.reload()
        onLoaded: {
            const fileContents = todoFileView.text()
            let parsed;
            try {
                parsed = JSON.parse(fileContents);
            } catch (e) {
                console.log("[To Do] Could not parse file, starting empty:", e);
                parsed = [];
            }
            if (!Array.isArray(parsed)) parsed = [];
            const migrated = root.migrate(parsed);
            root.list = parsed;
            if (migrated) {
                console.log("[To Do] Migrated existing items to the extended schema");
                todoFileView.setText(JSON.stringify(root.list));
            }
            console.log("[To Do] File loaded,", root.list.length, "items")
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root.list = []
                todoFileView.setText(JSON.stringify(root.list))
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }
}
