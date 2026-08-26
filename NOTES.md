# NOTES.md — OpenAgentIsland design & architecture

The "how it works and why" reference. Read this first to understand the project.
Stable-ish: update on architecture decisions, not every edit. Chronological work
log lives in `PROGRESS.md`.

---

## 1. Reference findings — Hyprfabricated (Fabric/Python+GTK)

Studied READ-ONLY in `~/Projects/island-reference/hyprfabricated/`. We translate the
*technique*, not the Python.

### 1.1 `modules/notch.py` — notch state model

**Key insight: Hyprfabricated's notch is NOT a width/height tween state machine.**
It's a **GTK `Stack`** that swaps full-size child widgets and *interpolates its own
size* to fit whichever child is showing. The "morph" is an emergent effect of:

```python
self.stack = Stack(name="notch-content", transition_type="crossfade",
                   transition_duration=250, children=[compact, launcher, dashboard,
                   overview, emoji, power, tools, tmux, cliphist])
self.stack.set_interpolate_size(True)   # <-- animates size between children
self.stack.set_homogeneous(False)       # <-- children keep their own size
```

Each child has an explicit fixed size (`set_size_request`), e.g. compact `260×40`,
dashboard `1093×472`, launcher `480×244`. Switching child → Stack animates from the
old size to the new size over 250 ms (crossfade). That's the whole morph.

**Composition (left / notch / right):** the notch window itself is a single
horizontal `CenterBox` (`notch-box`):
- `start_children = corner_left`  — a `MyCorner("top-right")` drawing the rounded
  notch shoulder on the left.
- `center_children = stack`       — the morphing content Stack.
- `end_children = corner_right`   — `MyCorner("top-left")` rounded shoulder on the right.

So Hyprfabricated's "left/right" pieces around the notch are just **decorative
rounded corners**, not functional islands. The functional left/right clusters
(workspaces, metrics, tray, clock) live in a *separate* full-width **bar**
(`modules/bar.py`), which our design discards. **We split the bar's clusters into two
independent floating islands** (`IslandLeft`, `IslandRight`) — a structural change,
not a port.

**Idle ("compact") state:** itself a nested `Stack` (`compact_stack`,
slide-up-down, 100 ms) cycling three children:
- `user_label` → `username@hostname`
- `active_window_box` → app icon + active window title (default visible child)
- `player_small` → tiny media widget

Triggers that switch the compact sub-state:
- **Scroll** on the compact area cycles the three children (`_on_compact_scroll`,
  250 ms debounce via `_scrolling` flag + timeout).
- MPRIS `player-appeared` → show `player_small`; `player-vanished` → back to
  `active_window_box`. **(Reactive to the actual player signal, not a UI flag.)**

**Show / hide (reveal):** a `Revealer` (`slide-down`, 250 ms) wraps the notch box.
Visibility is driven by **occlusion checking** (`utils/occlusion.py`): every 250 ms,
if the top 40 px of the screen is covered by a window AND the notch isn't hovered /
open / temporarily-pinned, the revealer collapses. On active-window-class change the
notch is briefly force-revealed for 500 ms (`on_active_window_changed` →
`_prevent_occlusion`). **Single window, no multi-monitor `Variants` — only renders on
one output. This is the gap we beat.**

**Open / expand:** `open_notch(widget_name)` sets keyboard mode exclusive, swaps the
Stack's visible child to the requested big widget (dashboard/launcher/etc.), and
toggles bar revealers. `close_notch()` returns to `compact`. Lots of
toggle-if-already-open logic; not relevant to our morph-OSD model.

### 1.2 `utils/animator.py` — tween technique

A hand-rolled `Animator` service: ticks a float `value` from `min_value`→`max_value`
across `duration` using a **cubic-bezier ease**, at ~60 fps (`GLib.timeout_add(16,…)`
or a widget tick callback), emitting `finished` at the end.

```python
def do_interpolate_cubic_bezier(self, t):           # only Y control points used
    y = (0, bezier[1], bezier[3], 1)
    return (1-t)**3*y[0] + 3*(1-t)**2*t*y[1] + 3*(1-t)*t**2*y[2] + t**3*y[3]
def do_ease(self, t):  return lerp(min, max, interp_cubic_bezier(t))
```

It only uses the Y components of the bezier (a simplified 1-D ease curve), lerps the
target range, and drives any float property (size, opacity).

**Quickshell equivalent is strictly simpler and better:** Qt has native bezier
easing, so we never reimplement a tick loop. Use:

```qml
Behavior on width  { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
// or the exact reference curve:
Behavior on height { NumberAnimation { duration: 350; easing.bezierCurve: [0.34,1.56,0.64,1, ...] } }
```

The "goey/spring" feel = `Easing.OutBack` with overshoot (or a custom bezier).

### 1.3 Fabric → Quickshell mapping table

| Hyprfabricated (Fabric/GTK) concept | Our Quickshell/QML equivalent |
|---|---|
| `Window(layer, anchor, margin, exclusivity)` | `PanelWindow { WlrLayershell.layer; anchors; margins; exclusiveZone }` |
| GTK `Stack` + `set_interpolate_size` (morph) | state property (`islandState`) driving `width/height` + `Behavior … NumberAnimation` |
| `Revealer` (slide-down show/hide) | `opacity`/`implicitHeight` driven by state + `Behavior`, or `Revealer` widget (`qs.modules.common.widgets`) |
| `utils/animator.py` cubic-bezier tween | native `easing.bezierCurve` / `Easing.OutBack` on `NumberAnimation` |
| `compact_stack` scroll-cycle of idle widgets | optional: `StackLayout`/state index, scroll handler on idle pill |
| `occlusion.py` + per-frame occlusion reveal | **dropped** — we float with gaps, always visible; multi-monitor via `Variants` |
| `MyCorner` rounded notch shoulders | `Rectangle { radius }` on the pill; optional `screenCorners` module already in end-4 |
| `ActiveWindow` formatter (win title) | end-4 `Hyprland`/`ActiveWindow.qml` already in `modules/ii/bar/` |
| `PlayerSmall` / `modules/player.py` | `MprisController` service + end-4 `mediaControls/` |
| `modules/metrics.py` (CPU/RAM/SWAP) | `ResourceUsage` service + `bar/Resources.qml` |
| `modules/cavalcade.py` (cava) | `scripts/cava` + end-4 cava in `mediaControls/` |
| `modules/bar.py` left/right clusters | split into `IslandLeft.qml` / `IslandRight.qml` |
| single-window notch (no multimon) | every island wrapped in `Variants { model: Quickshell.screens }` |

---

## 2. Architecture — three floating islands

**No full-width bar.** Three independent rounded `PanelWindow`s, transparent
background, always visible, on **every** monitor (each wrapped in
`Variants { model: Quickshell.screens; PanelWindow { required property var modelData; screen: modelData } }`).
Wallpaper breathes through the gaps.

```
┌─ IslandLeft ─┐        ┌──── IslandNotch ────┐        ┌─ IslandRight ─┐
│ workspaces · │        │  morphing OSD/clock │        │ cpu·clk·bat·  │
│ window title │        │  + AGENT status     │        │ tray·net·bt   │
└──────────────┘        └─────────────────────┘        └───────────────┘
        top-left                 top-center                    top-right
```

### 2.1 IslandLeft — `modules/ii/island/IslandLeft.qml`
Workspace dots (expand for active, Hyprfabricated-style) + active window title.
- Left-click → toggle `GlobalStates.sidebarLeftOpen`.
- Right-click workspaces → `GlobalStates.overviewOpen`.

### 2.2 IslandNotch — `modules/ii/island/IslandNotch.qml` (the star)
`property string islandState`. State machine:

| State | Content | Trigger | Exit |
|---|---|---|---|
| `idle` | minimal clock / small info (**NOT invisible**) | default | — |
| `volume` | volume icon + level bar | `Audio.sink.audio.volume` **value** change | ~2 s timer |
| `brightness` | brightness icon + level bar | `Brightness` value change | ~2 s timer |
| `media` | art + title + cava visualizer + controls | media playing (MPRIS) | media stops |
| `notification` | brief notification preview | incoming `Notifications` | short timer |
| `agent` | Claude session status; permission Allow/Deny | bridge socket event | session ends / decision made |

**Morph:** `implicitWidth`/`implicitHeight` reflect the active state so layout
reserves space; `Behavior on width/height` with `Easing.OutBack` overshoot for goey
spring. Content per state in a `Loader`/state-keyed visibility.

**State precedence (highest → lowest):**
`agent-permission` > `agent-status` > `media` > `volume`/`brightness` >
`notification` > `idle`. Implement as a computed `islandState` that picks the
highest-priority active source, not a free-for-all of timers stomping each other.

> Existing `IslandContent.qml` (prior session) has `idle` = *invisible* and triggers
> volume off `GlobalStates.osdVolumeOpen`. **Both must change** in Phase 3: idle =
> minimal clock; trigger off the `Audio` value (the flag flickers during scroll — see
> CLAUDE.md). Treat the existing file as a sketch, not the design.

### 2.3 IslandRight — `modules/ii/island/IslandRight.qml`
Left→right: Resources (CPU/RAM/SWAP via `ResourceUsage`) · clock · battery · system
tray · wifi/bt. Left-click → toggle `GlobalStates.sidebarRightOpen`. Keep ONLY the
performance toggle from `UtilButtons` (user removed keyboard/brightness/darkmode).

### 2.4 Bar removal
In `panelFamilies/IllogicalImpulseFamily.qml`: comment the full-width `Bar`
PanelLoader; add three island PanelLoaders. Keep ALL other panels (sidebars,
overview, lock, notifications, dock, screenCorners, polkit, etc.).

### 2.5 AS-BUILT details (Phases 1–5, user-approved)

**Shared style — `IslandStyle.qml` (singleton, `pragma Singleton` + `Singleton{}`, no
qmldir needed):** `margin 4`, `pillHeight 32`, `hPadding 10`, `radius full`,
`pillColor "#0B0B0E"` (solid space-black — NOT translucent `colLayer0`), `textColor
"#FFFFFF"`, `accent "#8AB4F8"`, `subtextColor`, `inactiveOpacity 0.45`. Every island
uses it.

**`IslandWorkspaces.qml` (left):** custom (NOT end-4 `Workspaces` — fixed slots can't do
the reference's uniform-gap look). A `Row` of dots; the CURRENT workspace is a capsule
the same height as the dots that EXPANDS and pushes neighbours apart (uniform gaps +
fluid). Used=white, unused=faint, current=blue. Dispatch = standard `workspace N` /
`workspace e±1` (end-4's `hl.dsp.focus` is INVALID in vanilla Hyprland).

**`IslandPopup.qml` (right-island tooltips):** the bar's `StyledPopup` is hard-coded to
the full-width bar → lands top-left on our island. So: a `PopupWindow` anchored BELOW
the hovered item (`anchor.window/item/edges:Bottom/gravity:Bottom`). Loader + keep-alive
timer (NOT always-mapped — an always-mapped PopupWindow triggered a Wayland popup
protocol error that CRASHED qs). Content passed as a `Component` (instantiated fresh
inside; reparenting a shared `Item` rendered empty boxes). Drive `shouldShow` from a
`HoverHandler` (composes over MouseAreas; the battery's tiny target + a competing base
MouseArea made plain MouseArea hover unreliable). Slide-in-from-right + fade.

**`IslandNotch.qml` (THE STAR) — top-attached morphing notch:**
- Hangs from top-center: square top corners flush with the screen edge, **rounded
  bottom**, concave `RoundCorner` shoulders (left=`TopRight`, right=`TopLeft`,
  `anchors.*Margin:-1` overlap) that blend it into the top edge. **Borderless** (a
  border drew seam lines).
- Window fixed at MAX size (`maxWidth+2*shoulder` × `maxHeight`); `mask: Region{item:
  notch}` so input passes through everywhere but the notch and the inner notch
  Rectangle animates size smoothly Qt-side (no janky per-frame compositor resize).
- **States:** `idle` (180×36 empty) · `expanded` (fits the active content) · `open`
  (480×300, click-toggled, NO content yet). `targetWidth`/`targetHeight`/`displaySource`
  computed by precedence.
- **Goey morph:** `Behavior on width/height { NumberAnimation { easing.bezierCurve:
  [0.34,1.22,0.64,1,1,1] } }` (reference was 1.275 → too violent on the shrink).
- **Constant 18px bottom radius** (≤ idle-height/2 so Qt never clamps) — animating it
  read as corners "rounding in", rejected. NO radius Behavior.
- **Reserves a 40px top strip** (`exclusionMode: Normal; exclusiveZone: 40`) so
  maximized windows open below the islands.
- **Sources & precedence** (computed `displaySource`): transient OSDs (volume /
  brightness / notification, one `expandedSource` + shared hide-timer, auto-hide) win
  over persistent **media**; `agent` (Phase 6) will be highest. Triggers use the service
  VALUE/signal, never the flicker-prone OSD flags.
- **Media:** shared cava `Process` at the `Scope` root → `visualizerPoints`, downsampled
  to 22 center-anchored **equalizer bars**. Minimal UI = art · bars · play/pause (no
  title). `mediaActive = isPlaying`. Album art downloaded to a stable local cache
  (`Directories.coverArt/Qt.md5(url)`) and only reset on track change (see PROGRESS
  gotcha — fixes the mid-song art vanish).

---

## 3. Quickshell / end-4 facts in use

- **Quickshell 0.2.1.** Panels = `PanelWindow` (Wayland layer-shell) wrapped in
  `Variants` for multi-monitor. Family = a `Scope` of `PanelLoader { component }` in
  `IllogicalImpulseFamily.qml`.
- **Panel module pattern:** folder `modules/ii/<name>/`, imported `qs.modules.ii.<name>`.
  Study `modules/ii/bar/` (ActiveWindow, Workspaces, Resources, SysTray, Media,
  BatteryIndicator, UtilButtons, ClockWidget) — most island content can be reused.
- **Theme tokens (always use, never hardcode):** `Appearance.colors.colLayer0/1/2`,
  `colOnLayer0/1/2`, `colLayer0Border`; `Appearance.rounding.windowRounding (18)` /
  `.full`; `Appearance.sizes.baseBarHeight (40)`; `Appearance.font.pixelSize.*`;
  `Appearance.animation.elementMoveFast.*`.
- **Widgets** (`qs.modules.common.widgets`): `StyledText`, `MaterialSymbol`,
  `RippleButton`, `Revealer`. Must import or "X is not a type".
- **Services (reuse):** `Audio` (`Audio.sink.audio.volume/.muted`), `Brightness`
  (`Brightness.getMonitorForScreen(screen)`), `MprisController`, `Notifications`
  (`.unread/.silent`), `Battery`, `Network`, `BluetoothStatus`, `ResourceUsage`,
  `TimerService`, `DateTime`.
- **GlobalStates** (`GlobalStates.qml`): `sidebarLeftOpen`, `sidebarRightOpen`,
  `osdVolumeOpen` (⚠ flickers on scroll — don't trigger notch from it), `overviewOpen`.
- **Hot reload** on `.qml` save; QML errors show a red panel with `file:line`.

---

## 4. Agent bridge design (Phases 6–8)

Live Claude Code session status in the notch, with Allow/Deny permission approval.
All bridge code in `~/Projects/openagentisland/bridge/` (hook scripts + listener).

### 4.1 Transport — Unix domain socket (mandated)
- Socket path: `$XDG_RUNTIME_DIR/openagentisland.sock`, fallback `/tmp/openagentisland.sock`.
- Claude Code **hooks** in `~/.claude/settings.json` fire on events and send one JSON
  line to the socket. A listener (Quickshell `Quickshell.Io` `Socket`/`SocketServer`,
  or a small helper process) reads lines → updates notch agent state.

### 4.2 Hook events → socket
`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`,
`Stop`, plus the permission/approval event.

### 4.3 JSON schema (line-delimited, one object per message) — *draft, finalize in Phase 6*
```json
{
  "event": "PreToolUse",          // hook event name
  "session_id": "abc123",          // Claude session id (key for multi-session)
  "cwd": "/home/topg/Projects/x",  // project dir; notch shows basename
  "tool": "Bash",                  // tool name when relevant
  "message": "running tests",      // human summary / Notification text
  "needs_permission": false,        // true → blocking round-trip
  "request_id": "uuid",            // correlates a permission ask with its reply
  "ts": 0                           // epoch ms
}
```
Notch-side per-session state: `running | idle | waiting-for-input | waiting-for-permission`.

### 4.4 Blocking permission protocol
1. Permission hook writes a `needs_permission:true` message with a `request_id`,
   then **blocks reading the socket** for a reply.
2. Notch enters `agent`/permission state → shows request + Allow/Deny.
3. User click sends `{request_id, decision: "allow"|"deny"}` back over the socket.
4. Hook matches `request_id`, returns the matching **exit code** to Claude Code.

### 4.5 CRITICAL safety (build FIRST, in Phase 6)
A blocking hook can **hang real Claude Code** if the listener is down/crashed. Mandatory:
- **Timeout:** hook waits at most *N* seconds (e.g. 5–10 s); on timeout it falls back
  to Claude Code's **default** behavior (does not block, does not auto-allow unsafely).
- **Graceful absence:** if the socket doesn't exist / connect fails, the hook returns
  immediately with default behavior. Never block on a missing listener.
- **A broken island must NEVER make real Claude Code unusable.** Test this failure
  mode explicitly (listener down, listener crashes mid-wait, slow listener) before
  Phase 7 is "done".

### 4.6 Quickshell IO caveat
Confirm `Quickshell.Io` in 0.2.1 supports a listening socket + bidirectional writes.
If bidirectional/blocking is awkward from QML, a tiny external listener daemon
(socket server) that the QML side talks to via a simpler channel is the fallback —
**flag to the user before committing to an approach.**

### 4.7 Scope ramp
Claude Code only (not Codex/Gemini). One session status → permission approval →
multiple sessions (count / cycle / stack).

---

## 5. Key decisions & rationale

- **Morph via state-driven size + `Behavior`, not a GTK-Stack size-interpolate port.**
  Qt animates property changes natively; cleaner, no tick loop, exact-curve control.
- **Trigger volume/brightness from the *service value*, not `osdVolumeOpen`.** The flag
  flickers during scroll (CLAUDE.md); value changes are the real signal.
- **Split the reference bar into two floating islands.** Hyprfabricated keeps a
  full-width bar + decorative notch corners; our look is three independent islands
  with wallpaper gaps — a deliberate structural divergence.
- **Multi-monitor via `Variants` on every island.** Hyprfabricated renders the notch
  on one output only; `Variants { model: Quickshell.screens }` is our headline
  reliability win.
- **`islandState` is computed by precedence**, so higher-priority sources (agent
  permission) can't be stomped by a volume auto-hide timer.
- **Safety before features in the agent phase.** The timeout/fallback path is built
  and tested before any status rendering, so a broken island can never brick real
  Claude Code.

---

## 3. REFERENCE TECHNIQUE NOTES — expansion features (Hyprfabricated)

Technique-level extract from `~/Projects/island-reference/hyprfabricated/` for the
ROADMAP A–H expansion. We translate to Quickshell — commands/services below are
the reusable facts.

**Dashboard tabs** (`modules/dashboard.py`, `widgets.py`, `kanban.py`): a
`Gtk.Stack` + `StackSwitcher`, slide-left-right 500ms; tabs widgets/pins/kanban/
wallpapers/mixer (we keep **widgets/kanban/coming-soon** only). Ctrl+Tab /
Ctrl+Shift+Tab switch. Widgets tab panes: media (MPRIS), calendar (locale +
datetime, refresh at midnight), notification history, quick-toggles 2×2
(Network/BT/NightMode/Caffeine), volume+mic sliders (Audio), system-profile
selector (`powerprofilesctl list/get/set`), live stats (psutil 1s; GPU `nvtop -s`).
Kanban: 3 cols + DnD (`Gtk.DragAction.MOVE`), JSON at `~/.kanban.json`, inline
editor (Shift+Enter newline, Return save).

**Power** (`modules/power.py`): Lock `loginctl lock-session`; Suspend
`systemctl suspend`; Logout `loginctl terminate-user ""`; Reboot `systemctl
reboot`; Poweroff `systemctl poweroff`. Buttons Tab-navigable, Return/Space fire.

**Capture** (`modules/tools.py` + `scripts/screenshot.sh`): screenshots via
`hyprshot -z -s -m {output|region|window} -o DIR -f FILE`; clipboard `wl-copy`;
mockup via ImageMagick `magick`. Record: `gpu-screen-recorder -w screen -ac opus
-cr full -a default_output -f 60 -o FILE`; state `pgrep -f gpu-screen-recorder`;
stop = SIGINT. Save `$XDG_PICTURES_DIR/Screenshots`, `$XDG_VIDEOS_DIR/Recordings`.
(We may substitute `grim`+`slurp`/`wf-recorder` if hyprshot/gpu-screen-recorder
absent — detect at build.)

**Launcher** (`modules/launcher.py`): apps from `get_desktop_applications()`
(.desktop), casefold substring on display+name+generic; lazy `idle_add`; arrows
move, Return `app.launch()`, Esc close, auto-scroll to selection. Prefixes
`=`/`;`/`:w`/`:d`/`:p`. (Quickshell equiv: `DesktopEntries` service.)

**Overview** (`modules/overview.py`): Hyprland IPC `j/monitors` + `j/clients`
(JSON); per client address/initialClass/title/workspace/at/size; window button
icon via DesktopApp/IconResolver; SCALE 0.1 in `Gtk.Fixed`. Left-click
`focuswindow address:`, right-click `closewindow address:`, DnD →
`movetoworkspacesilent {wsid},address:{addr}`; rebuild on openwindow/closewindow/
movewindow. (Quickshell equiv: `Hyprland` service `workspaces`/`toplevels` +
`Hyprland.dispatch`.)

**Weather** (`modules/weather.py`): location via `https://ipinfo.io/json`, data
`https://wttr.in/{loc}?format=%c+%t`; poll 600s; threaded fetch; cloud-off icon on
failure. (We force metric/°C with `&m`.)

**Network** (`modules/metrics.py` NetworkApplet): `psutil.net_io_counters()`
delta / elapsed, poll 1000ms; format B/s · KB/s · MB/s; Revealer shows speed on
hover; wifi strength icon. (Quickshell equiv: read `/proc/net/dev`.)

See ROADMAP.md for the phased build plan (A–H) that consumes these.

---

## 4. OPEN-STATE SURFACE HOST (expansion A–H, as-built)

The notch `open` state is a **named-surface host** (mirrors the reference's
`notch.stack` + `open_notch(name)`).

- **`Island` singleton** (`modules/ii/island/Island.qml`): `property string
  openSurface` (`"" | dashboard | power | tools | launcher | overview`) +
  `open()/close()/toggle()`. Side-island pills (separate PanelWindows) call it to
  drive the centre notch.
- **`IslandNotch`**: `islandState = openSurface!=="" ? "open" : (transient OSD ?
  "expanded" : "idle")`. Per-surface sizes in `surfaceSizes`; window sized to the
  widest (`maxWidth 1100 × maxHeight 400`), notch masked so only its body is
  interactive. Open content = a `FocusScope` "surfaceHost" with a click-absorber
  MouseArea + a `Loader` switching `sourceComponent` on `openSurface`
  (`Component { DashboardSurface{} }` etc.). `keyboardFocus: OnDemand` while open
  → Esc closes; transient OSDs gated to `expanded` so they don't overlap surfaces.
- **Surfaces** (all `FocusScope`, same dir, auto-resolved by filename):
  - `DashboardSurface` → tab bar (Widgets/Kanban/Coming-soon) hosting `WidgetsPane`
    (`WidgetCalendar` + inline toggles/sliders/media/notifs/mode/stat-bars) and
    `KanbanPane` (+ `KanbanStore` singleton, JSON at `<state>/user/kanban.json`).
  - `PowerSurface`, `ToolsSurface`, `LauncherSurface`, `OverviewSurface`.
- **Close paths:** Esc (keyboard focus), re-clicking the originating side pill
  (`Island.toggle`), or taking an action. Clicks inside an open surface are
  absorbed (no accidental close); the notch background only OPENS (dashboard) from
  idle.
- **Services reused:** Audio (sink+source), Network, BluetoothStatus +
  `Bluetooth.defaultAdapter`, Hyprsunset, Idle (caffeine), ResourceUsage,
  Notifications, DateTime, MprisController, AppSearch/DesktopEntries, HyprlandData
  + `Hyprland.dispatch`. Weather/network pills self-fetch (wttr.in / /proc/net/dev).

See ROADMAP.md for the phase→task breakdown and PROGRESS.md for gotchas.

---

## 5. AGENT BRIDGE (Phase 6 — backend, as-built)

Live Claude Code in the notch + Allow/Deny from the island. Code in `bridge/`
(hook client + tests) and `quickshell/services/AgentService.qml` (listener).

**Transport:** Unix socket `$XDG_RUNTIME_DIR/openagentisland.sock` (fallback
`/tmp`). Newline-delimited JSON, one message per connection. Quickshell hosts a
`SocketServer` (handler = one `Socket` per connection); the hook (`oai_hook.py`)
is the client. Full schema in `bridge/README.md`.

**Hooks** (`bridge/hooks.settings.json`, NOT yet installed into live
`~/.claude/settings.json`): status events (SessionStart/UserPromptSubmit/
PostToolUse/Notification/Stop) call `oai_hook.py status` (fire-and-forget);
PreToolUse on mutating tools (Bash|Write|Edit|…) calls `oai_hook.py permission`
(blocking).

**Permission protocol:** hook opens a connection, sends `permission_request`,
keeps it open, blocks reading for `OAI_PERMISSION_TIMEOUT` (20s). Island shows UI
(future) / IPC; on decision it `write()`s `permission_decision` back on that same
connection → hook emits PreToolUse `permissionDecision` allow/deny. Per-connection
correlation (no id matching needed); `request_id` carried for logging.

**SAFETY (built + proven FIRST, `bridge/test_safety.py` 13/13):** the hook never
hangs/auto-approves. No socket / refused / timeout / frozen island / exception →
exit 0, no stdout → Claude falls back to its normal prompt. Island side drops a
pending request when its connection closes, so a timed-out request can't wedge
the queue. Verified end-to-end against the REAL Quickshell listener: status
delivery, allow, deny, and disconnect-cleanup.

**AgentService state:** `sessions` (session_id → {project, cwd, tool, summary,
lastEvent, status, ts}; status = idle|running|waiting|permission) and
`pendingPermissions[]`. `allow(reqId)`/`deny(reqId)` write back. IPC target
`agent` (`status`/`allowOldest`/`denyOldest`) for manual control + testing.
Forced to instantiate via `AgentService.load()` in `shell.qml`.

**Next:** notch `agent` UI (status + permission Allow/Deny) — waiting on the
user's visual references. State precedence: agent-permission > agent-status >
media > volume/brightness > notification > idle.

---

## 6. DESKTOP WIDGETS — todo card + focus timer (as-built)

First piece of the macOS conversion. Design was drafted and approved visually
before any code: material weight, card anatomy and the start flow were compared
against the real wallpaper rather than decided in the abstract.

### 6.1 Why a separate layer surface, not `Background.qml`

`Background.qml` already runs a `WidgetCanvas` on `WlrLayer.Bottom` and
`AbstractBackgroundWidget` already gives free-drag, persisted position and
wallpaper parallax. Putting the card there would have cost zero new surfaces,
and it was the original plan. Two things ruled it out:

- **Blur.** Hyprland runs blur with `xray` on, so a `blur` layerrule against our
  own namespace frosts the *wallpaper* on the GPU for free. Inside the background
  window there is nothing behind us to blur — we would have had to decode the
  wallpaper a second time into a Qt `MultiEffect`, i.e. a second full-resolution
  texture, purely for looks.
- **Keyboard.** `Background.qml` never takes keyboard focus, so the "Add a task"
  field could not be typed into. A separate surface sets
  `WlrKeyboardFocus.OnDemand` only while a field is focused, and drops back to
  `None` the moment it isn't, so it never steals keys from an app.

Cost is one surface on one monitor. `mask: Region { item: card }` keeps the rest
of the desktop clickable straight through.

### 6.2 Layer rules at runtime, not in `~/.config/hypr`

This project may not edit the user's Hyprland config. `DesktopWidgets.qml` and
`FocusOverlay.qml` each push their own `layerrule blur` + `ignorealpha` via
`hyprctl --batch` on completion. Idempotent, so re-applying on every reload is
harmless, and losing them only costs the frost, never function.

### 6.3 Card anatomy

macOS Reminders proportions, Material You colour. 16px content margin and 11px
minimum type are Apple's published widget numbers; corner radii are concentric
(inner = outer − padding), which `StyledOverlayWidget` already expresses as
`contentRadius`. Count-led header, accent list name, hairline rule, hollow 20px
circle checkboxes that fill on completion, 40px row rhythm, single-line elide so
card height stays predictable, start button revealed on hover only.

Material is **10% `colPrimary` over compositor blur**. Drafted at 5 / 10 / 62
percent against a wallpaper with both near-black and blown-out regions; 5% could
not hold text over the bright one, 62% stopped reading as glass.

### 6.4 Timer is wall-clock, like `TimerService`

`Persistent.states.timer.focus` stores a unix `start`, shifted forward on resume
to absorb pauses, rather than counting ticks. Survives suspend, and survives a
shell reload: Quickshell rebuilds the singleton but Persistent still holds the
timestamp, so a running session picks up where it was.

Maximised is a take-over on `WlrLayer.Overlay` so it covers fullscreen apps.
Minimised is a masked pill, also Overlay. Clicking the backdrop minimises rather
than cancels — losing a running session to a stray click would be hostile.

### 6.5 Gotchas hit

- **Binding loop → zero size.** `root.implicitHeight` ← `card.implicitHeight` ←
  `column.implicitHeight` while the column was `anchors.fill`-ed back to the
  card puts height on both sides of one binding. QML resolves that to zero and
  the widget renders nothing, silently — no error, the surface still exists in
  `hyprctl layers`. Fixed by anchoring the column left/right/top only, so its
  height stays its own `implicitHeight`. Same class of bug in `TodoRow`, which
  read `parent.width` inside a layout; use `Layout.fillWidth` instead.
- **`touch` does not trigger Quickshell's reloader.** Only real content changes
  do. Cost some confusing minutes reading stale log output.
- **`Todo.qml` had no `watchChanges`.** With two views on one list (sidebar and
  desktop card) they drifted apart until the next reload. Now watched.
- **Diagnosing an invisible widget:** raise it to `WlrLayer.Top` briefly. If it
  is still invisible it is a sizing bug, not occlusion. Note the temporary change
  applies to every running instance, including the host shell, which will then
  paint over a nested session and look like a double render.
- **Capture the nested session natively** with `WAYLAND_DISPLAY=wayland-2 grim`.
  Screenshotting the nested window's rectangle on the host catches host overlays
  sitting on top of it.

---

## 7. MENUBAR + DOCK MAGNIFICATION (as-built)

### 7.1 Menubar replaces IslandLeft / IslandRight

`modules/ii/menubar/Menubar.qml`. Full width, no island, no outline. The only
thing between the text and the wallpaper is a scrim — opaque at the very top,
gone by 46px — so text always has ground under it but there is never an edge.
Drafted against three treatments over the worst part of the wallpaper: a bare
text-shadow could not hold the right-hand cluster over the sun shaft, and a glass
strip reintroduced exactly the bottom edge the design was meant to remove.

Left is logo + focused app name + workspaces, deliberately NOT File/Edit/View.
macOS can draw those because every app publishes its menu to the system; on
Wayland nothing covers Electron, so Zen, Cursor, Warp and Discord — most of what
runs here — would leave it empty.

The notch keeps its own surface and is untouched. `islandReserve` (inside
IslandNotch) still reserves the top strip, so the menubar claims no exclusive
zone of its own — claiming it twice would push every window down twice.

**This halved idle CPU.** 25.9% -> 13.9%, busy render threads 4 -> 1, main thread
9.8% -> 5.9%. IslandLeft and IslandRight together were ~11% of a core at rest,
with nothing changing on screen. Retiring them did what a day of config-flag
bisecting could not.

### 7.2 Dock, rebuilt from scratch

`modules/ii/macDock/MacDock.qml`. The first attempt patched magnification into
the existing dock and worked, but the old dock's shape (pin button, hover-to-
reveal, window previews) is not the shape of a macOS dock, so it was rebuilt.
The original is still there, gated behind `dock.macStyleDock`.

42px icons on the bottom baseline, `transformOrigin: Item.Bottom` so they rise
out of the container rather than swelling from their centres. 4px running dot
below each running app, hairline separator before the trailing group, name label
above on hover. Reserves its own strip via `exclusiveZone` (container height plus
its gap) so maximised windows rest above it — deliberately NOT including the
magnification headroom, so growing icons rise into free space instead of pushing
every window down.

Magnification is a raised cosine — 1 under the cursor, 0 at the edge of the
falloff, flat tangent at both ends. A squared cosine peaks too sharply and reads
as a snap. Peak 1.28 / spread 2.9, tuned live against the draft.

**Item width is fixed; only `scale` changes.** Growing width as well made
neighbours slide apart like the real dock, but it fed the result back into its
own input — widths move centres, centres decide widths. The easing Behaviour did
not damp that oscillation, it only gave it a nicer curve, and it read as visible
jitter. Scale alone is stable and at this peak the icons stay clear anyway.

Two more things that bit:
- The window **clips its own contents**. Anything not budgeted into
  `implicitHeight` is cut off, which is what cropped the name label until the
  height accounted for label + magnification headroom.
- A full-width 1px "inset highlight" across the top of the container reads as a
  stray line where it crosses inside the rounded corners. Removed.

### 7.3 hyprctl on a Lua-configured Hyprland

Worth writing down because it cost real time twice. This machine configures
Hyprland with the Lua parser, where `hyprctl keyword` and `hyprctl dispatch` do
not work — the former answers "keyword can't work with non-legacy parsers", the
latter tries to parse arguments as Lua. Use `hyprctl eval` with the `hl` API:
`hl.layer_rule({ match = { namespace = "..." }, blur = true })`,
`hl.dsp.cursor.move({x=..., y=...})`. Anything in this repo shelling out to
`hyprctl keyword` (e.g. GameMode.qml) is silently a no-op here.

### 7.4 Menubar items do real work; Control Centre

Every menubar item has a distinct action instead of all opening the same
sidebar: left click is the primary action, right click opens the full
application for it, scroll adjusts where that makes sense.

- volume: scroll changes it, click mutes, right click opens the mixer
- wifi / bluetooth: click toggles the radio, right click opens its settings
- clock: click drops a calendar
- Control Centre (`ControlCentre.qml`): power-mode chips, live CPU / memory /
  swap / GPU / battery, volume and brightness sliders, Wi-Fi and Bluetooth tiles

GPU is labelled **GPU clock**, not load. Intel integrated graphics expose
`gt_act_freq_mhz` and no busy-percent at all, so anything called "GPU load" here
would be a guess dressed as a measurement. `ResourceUsage` discovers the card
directory once by globbing — the index varies (card1 here, card0 elsewhere).

Gotchas:
- **`FileView.reload()` is asynchronous.** Calling `text()` on the next line
  returns the *previous* contents, or empty on the first tick. That is why CPU
  temperature and GPU clock read as zero. `blockLoading: true` makes the
  /proc and sysfs reads synchronous, which is what this polling loop wants.
- **`Hyprland` needs `import Quickshell.Hyprland`.** Without it the reference
  fails silently at runtime as a ReferenceError in the log, and every binding
  that depended on it fell back — which is why the menubar always said "Desktop"
  instead of the focused app.
- **Do not derive a `ShellScreen` from `QsWindow` inside a popup.** It resolves
  to the popup's own window, whose screen is a different object, and
  `Brightness.getMonitorForScreen` matches by identity — so it silently finds
  nothing. Pass the screen in from the panel that owns it.

### 7.5 Why CPU read 0%

Two causes stacked, both silent.

`ResourceUsage` is a QML singleton, and QML singletons are **lazy** — nothing
constructs one until something references it. `IslandRight` used to hold CPU
rings, which kept it alive and polling from startup. Retiring the islands removed
that reference, so the service now only wakes when something like Control Centre
opens. (Part of the 25.9% -> 13.9% idle CPU win is exactly this: a poller that had
been running forever stopped.)

On top of that, a CPU figure is a **delta** — the first sample can only seed a
baseline and must read 0%. Combined with lazy construction, that first 0% is
precisely what a user sees the moment the panel opens. Fixed by scheduling the
second sample 400ms after the first and only then settling to the configured
interval, so a real figure appears almost immediately.

Verify readings against the system, not against the code: `/proc/stat` deltas said
9.6% while the panel said 0%, which is what proved the panel wrong.

---

## 8. TRAFFIC LIGHTS (config only, outside this repo)

No code in this repo. Everything lives in the user's config, so it is recorded
here rather than committed. Backups of every file touched were taken first.

Files changed:
- `~/.config/gtk-3.0/settings.ini`, `~/.config/gtk-4.0/settings.ini` (created) —
  `gtk-decoration-layout=close,minimize,maximize:`. The trailing colon is the
  left/right split, so everything before it sits left and nothing sits right.
- `gsettings org.gnome.desktop.wm.preferences button-layout` — set to match,
  because apps that read gsettings ignore settings.ini.
- `~/.config/kdeglobals` — `[org.kde.kdecoration2] ButtonsOnLeft=XIA`
  (X close, I minimize, A maximize) for server-decorated Qt apps.
- `~/.config/matugen/templates/gtk-{3,4}.0/gtk.css` — the traffic-light CSS.

**The CSS must go in the Matugen TEMPLATE.** `~/.config/gtk-4.0/gtk.css` is
generated output; anything written there survives only until the next wallpaper
change. Verified by re-running matugen five times during development — the rules
came through every time.

Colours are hardcoded `#ff5f57 / #febc2e / #28c840` rather than themed: a traffic
light that is not red/amber/green is not a traffic light.

### Gotchas

- **`all: unset` first.** libadwaita sizes and paints these buttons from several
  rules at once. Setting `padding` and `min-*` alone left them as ovals AND let
  its own background bleed through the amber one, which came out muddy olive.
- **GTK CSS has no `max-height`,** and the button stretches to the headerbar's
  height, so `min-height` cannot make a circle. Vertical `margin` is the only
  lever — `margin: 11px 5px` lands a 13px circle on a standard libadwaita
  headerbar. It is headerbar-height dependent, so it is a tuning value, not a law.
- **Hovering one reveals all three glyphs** via `windowcontrols:hover > button
  image`, which is the single most recognisable detail of the real thing.

### Coverage, as actually observed

- Nautilus / GTK4 / libadwaita: full traffic lights, correct colours, hover
  glyphs, backdrop greying. Works.
- **Zen: buttons moved left, but NOT restyled.** Firefox draws its own window
  controls in its chrome, so GTK CSS never reaches them. Restyling those needs
  `userChrome.css` in the Zen profile — a separate surface, deliberately not
  done here.
- kitty, Warp, Discord: unchanged, as designed. They draw no titlebar (or their
  own), and covering them needs the `hyprbars` plugin, which was declined for the
  rebuild-on-every-Hyprland-update cost.
