# PROGRESS.md — OpenAgentIsland work log

Chronological log. Newest first within each section. Architecture/design rationale
lives in `NOTES.md`.

---

## 2026-08-30 — Desktop widget: resize, settings menu, undo. STATE OF PLAY

Everything below is committed and live. `qs -c openagentisland` is running the
macOS-style shell: menubar + notch + dock, desktop todo widget, traffic lights.

### Shipped this session

- **Desktop todo widget** on its own `WlrLayer.Bottom` surface
  (`modules/ii/desktopWidgets/`) — frosted card, per-task countdown timer with a
  fullscreen focus screen and a draggable pill, resizable, numbered list,
  right-click settings menu, undo for every removal.
- **Menubar** (`modules/ii/menubar/`) replaced IslandLeft/IslandRight. Scrim
  gradient, logo + app name + workspaces, status cluster where every item does
  something distinct, plus a **Control Centre** panel.
- **Dock rebuilt from scratch** (`modules/ii/macDock/`) with magnification.
  The original dock is still present behind `dock.macStyleDock`.
- **Traffic lights** — config only, outside this repo. See NOTES §8.
- **Idle CPU 25.9% -> ~13%** as a side effect of retiring the two islands.

### Outstanding

1. **`install.sh` is written but UNCOMMITTED and untested.** ~430 lines at the
   repo root, plus `install/traffic-lights/*.css` which ARE committed. The user
   wants to discuss scope before it lands. It delegates the end-4 base to end-4's
   own installer. **Its base-install path has never been run** — running it would
   reinstall the user's desktop.
2. **README still describes the old three-island design** and its screenshots are
   stale. Agreed to update it alongside the installer.
3. **This machine has no removal markers** in the matugen templates / Zen
   userChrome, because the CSS was appended by hand before the installer existed.
   Re-running the installer here would duplicate the block.
4. Zen traffic lights are not leftmost (Zen's sidebar toggle still precedes
   them). `order: -1` would fix it; left alone deliberately.
5. Remaining idle CPU (~13%) is unexplained. The notch is ~8% of it with zero
   visual change. Needs the QML profiler, not more guessing.

### DO NOT TOUCH

The working tree carries the user's own uncommitted work — acKeepAwake
(`GlobalStates`, `Idle.qml`, `shell.qml`, quickToggles, Config) and
regionSelector (`RegionSelection.qml`, Config, Persistent). Every commit this
session staged ONLY its own hunks, via a python hunk filter, and verified with
`git diff --cached | grep -cE "acKeepAwake|rememberLastRegion|Idle.load"`
returning 0. Keep doing that.

---

## 2026-08-26 (evening) — traffic lights

Config only, nothing in this repo; see NOTES.md section 8. GTK + Qt button layout
moved left, macOS traffic-light CSS added to the **Matugen templates** so a
wallpaper change cannot wipe it (verified across five regenerations).

- Works fully on GTK4/libadwaita (Nautilus): circles, correct colours, hover
  reveals all three glyphs, backdrop greys them out.
- **Zen moves its buttons left but keeps its own styling** — Firefox draws its own
  window controls, so GTK CSS does not reach them. Would need userChrome.css.
- kitty / Warp / Discord unchanged by design (no titlebar to decorate).

Gotchas: `all: unset` is required or libadwaita leaves them oval and the amber one
muddy; GTK CSS has no `max-height`, so vertical `margin` is the only way to get a
circle out of a button that stretches to the headerbar height.

---

## 2026-08-26 (evening) — menubar items made functional + Control Centre

- Every menubar item now does something specific rather than all opening the same
  sidebar. Volume: scroll to change, click to mute, right click for the mixer.
  Wi-Fi / Bluetooth: click toggles the radio, right click opens settings. Clock:
  click drops a calendar.
- **Control Centre** (`modules/ii/menubar/ControlCentre.qml`): power-mode chips,
  live CPU / memory / swap / GPU / battery, volume + brightness sliders, Wi-Fi and
  Bluetooth tiles. GPU is reported as a *clock*, not load — Intel integrated
  graphics expose no busy-percent, so calling it load would be a guess.
- `ResourceUsage` gained Intel GPU clock (globs for the card dir; index varies).

### Gotchas

- **`FileView.reload()` is async** — `text()` on the next line returns the previous
  contents or empty. CPU temp and GPU clock read as 0 until `blockLoading: true`.
- **`Hyprland` requires `import Quickshell.Hyprland`** — without it the reference
  fails as a runtime ReferenceError, which is why the menubar always showed
  "Desktop" instead of the focused app's name.
- **Do not derive a ShellScreen from `QsWindow` inside a popup** — it resolves to
  the popup's window, and `Brightness.getMonitorForScreen` matches by identity.
- Not a bug: the brightness slider reading near-zero was correct. The backlight
  really was at 1/400.

---

## 2026-08-26 (later) — macOS menubar + dock magnification, and idle CPU halved

- **Menubar replaces IslandLeft/IslandRight** (`modules/ii/menubar/`). Full width,
  scrim gradient, no outline, no island. Left: logo + focused app name +
  workspaces. Right: tray, volume, bluetooth, wifi, battery %, clock — monochrome
  glyphs, no pills. Notch untouched; `islandReserve` still carries the exclusive
  zone so the menubar claims none.
- **Dock rebuilt from scratch** (`modules/ii/macDock/`). 42px icons on the bottom
  baseline rising out of the container, magnification at peak 1.28 / spread 2.9
  with a raised-cosine falloff, running dot below each running app, hairline
  separator, name label on hover. Reserves its own strip via `exclusiveZone` so
  maximised windows rest above it. The old dock is still present, gated behind
  `dock.macStyleDock`.
  - *Jitter:* growing item width as well as scale fed the result back into its own
    input (widths move centres, centres decide widths). The easing Behaviour only
    made the oscillation prettier. Width is now fixed; scale alone is stable.
  - *Cropped tooltip:* the window clips its contents, so the label has to be
    budgeted into `implicitHeight` along with the magnification headroom.
  - *Stray line:* a full-width 1px top "highlight" crosses inside the rounded
    corners and reads as a bug. Removed.
- **Idle CPU halved: 25.9% -> 13.9%.** Busy render threads 4 -> 1, main thread
  9.8% -> 5.9%, surfaces 17 -> 15. IslandLeft + IslandRight were ~11% of a core at
  rest while nothing on screen changed. This was the CPU bug — the earlier
  config-flag bisect (cava, floatStyleShadow, extraBackgroundTint) found nothing
  because none of them were it.

### Gotchas

- **`hyprctl keyword` and `hyprctl dispatch` do not work here.** Hyprland is
  configured through the Lua parser. Use `hyprctl eval` + the `hl` API. Any code
  shelling out to `hyprctl keyword` (GameMode.qml) is silently a no-op.
- **Do not bisect by editing and reloading on a short timer.** Reloading every 7s
  never lets the shell settle and reports garbage (99% CPU). Full restart, ~20s
  settle, then measure.
- Dock pointer position cannot come from a `HoverHandler` on the row — delegate
  MouseAreas swallow hover first.
- **A hot reload can log "Configuration Loaded" and still be running the OLD code.**
  Edits to `TodoCard.qml` produced a reload in the log, but a
  `Component.onCompleted: console.log(...)` added to that file never printed until
  the shell was **cold-restarted** — at which point it printed immediately. This is
  the atomic-write watch problem: editors that save by writing a temp file and
  renaming it replace the inode, so the watch fires but the component is not
  rebuilt. Consequence: **any behavioural test after editing a nested component is
  meaningless without a cold restart.** Several hours went into "the fix does not
  work" results that were measuring the unfixed code. Restart with
  `kill -TERM $(pgrep -x qs)` then
  `setsid nohup qs -c openagentisland > /tmp/qs.log 2>&1 &` — logging to a file you
  control beats `qs log`, which streams from the beginning and gets cut off.
  (`pgrep -f "qs -c openagentisland"` matches your own shell command and kills it —
  use `pgrep -x qs`.)

### Next

- Traffic lights: toolkit settings only. GTK CSS must go in
  `~/.config/matugen/templates/gtk-4.0/gtk.css`, not the generated `gtk.css`.
- Remaining ~14% idle CPU is unexplained; the notch is ~8% of it with zero visual
  change. Needs the QML profiler, not more guessing.
- RSS still ~710MB (was 375MB this morning) and survives restarts. Unexplained.

---

## 2026-08-26 — Desktop todo widget + per-task focus timer

First piece of the macOS conversion. Designed visually and approved before any
code was written; see NOTES.md §6 for architecture and gotchas.

- **Desktop todo card** on its own `WlrLayer.Bottom` surface
  (`modules/ii/desktopWidgets/`). macOS Reminders anatomy — count-led header,
  accent list name, hairline rule, hollow circle checkboxes, 40px rows, hover-only
  start button — painted entirely from `Appearance` tokens, so it retints with the
  wallpaper. Material is 10% `colPrimary` over **compositor** blur, not a Qt
  effect. Drags from the header, position persists to
  `background.widgets.todo`. Input masked to the card so the desktop stays
  clickable. Shows on one monitor (`screenName`, empty = first screen).
- **Per-task focus timer** (`services/FocusTimer.qml`,
  `modules/ii/focusTimer/`). Start a task, pick a duration (presets + a -/+
  stepper, pre-armed with whatever that task was last run with), then a fullscreen
  take-over on the overlay layer with progress ring, or a draggable pill. Wall-clock
  based, so it survives suspend and shell reloads. Notifies and plays a sound at
  zero, logs the session onto the task, and the running task shows a live countdown
  inline in the card.
- **`Todo.qml` schema extended** with `id`, `createdAt`, `doneAt`, `lastDuration`
  and `sessions`, migrated on read so existing `todo.json` files keep working.
  Added `watchChanges` — with the sidebar and the desktop card both showing one
  list, they were drifting apart until the next reload.
- Verified in the nested session: rows, ellipsis, estimate badges, collapsible
  Completed, countdown, ring, pill, and blur (confirmed on the pill over wallpaper).

### Next

- Menubar + dock (flatten the three islands). Drafts approved: scrim gradient,
  no outline, logo + app name + workspaces on the left; dock magnification
  1.28x peak / 2.9 icon-width spread, raised-cosine falloff.
- Traffic lights via toolkit settings only. **GTK CSS must go in
  `~/.config/matugen/templates/gtk-4.0/gtk.css`** — the `gtk.css` in
  `~/.config/gtk-4.0/` is generated output and gets overwritten on retheme.

### Open

- **`qs` idles at ~24-30% CPU and RSS grew 375MB -> 609MB across this session's
  hot reloads.** The reload growth is Quickshell accumulating across ~15 reloads
  and clears on restart. The idle CPU does not: it is not the islands (flattening
  only takes 17 layer surfaces to 10). Untested suspects: `cava` running
  continuously for the notch visualiser, `bar.floatStyleShadow` re-rasterising a
  Qt drop shadow per frame, `appearance.extraBackgroundTint`. Bisect by toggling
  each and re-measuring.

---

## 2026-07-13 — Notch on laptop screen only (config-driven) + perf tuning

Investigating "YouTube lags on CachyOS": hardware video decode in Zen verified
fine (RDD process shows `drm-engine-video` activity); real causes were thermals
(package at 92–96°C, power profile pinned to `performance`) and constant repaint
overhead — the notch animates on ALL monitors (agent shimmer, cava, morphs), and
freezing qs dropped Hyprland CPU 13.5%→7%.

- **New config option `island.notchScreenList`** (Config.qml, default `[]` = all
  screens, same pattern as `bar.screenList`). `IslandNotch.qml` filters its
  `Variants` model through it; the user's machine sets `["eDP-1"]` in
  `~/.config/illogical-impulse/config.json` → notch only on the laptop screen.
  Left/right islands and the `islandReserve` strip stay on every monitor.
- Safety: if none of the listed outputs are connected (lid closed), falls back
  to all screens — the notch carries agent permissions and must never vanish.
  `focusedScreenName()` now clamps auto-open routing (permission arrivals) to
  screens that actually have a notch; click-to-open was already safe (a click
  can only come from an existing notch).
- Perf: cava visualizer 60fps→30fps, 50→36 bars (`scripts/cava/raw_output_config.txt`).
  Outside the repo: Hyprland shadows range 20→12 / render_power→2, power profile
  performance→balanced.
- Verified live via `hyprctl layers`: notch layer only on eDP-1; left/right/reserve
  on all three monitors; hot reload clean, no QML errors.

## 2026-07-09 — Right island clock: hover popup with IST + SF time, click to switch

Hovering the clock pill (`IslandRight.qml`) shows an `IslandPopup` with two
rows: **IST** (local, `h:mm AP`) and **SF** (US Pacific, 12-hour). Clicking a
row switches which zone the pill itself displays (SF mode shows "SF 9:11 AM");
choice persists via new `time.islandClockZone` config option ("ist"|"sf",
written through Config's JsonAdapter). Active row is accent-tinted with a
check; rows tint on hover, pointer cursor.

- SF time computed in JS from UTC with the US DST rule (2nd Sun Mar 10:00 UTC
  → 1st Sun Nov 9:00 UTC → UTC-7, else UTC-8) — no subprocess, reactive off
  `DateTime.clock.date`. When SF's calendar day differs from local (most IST
  mornings), the row appends the SF weekday, e.g. "9:11 PM (Tue)".
- `IslandPopup` gained opt-in `interactive: true`: a HoverHandler on the popup
  body keeps it open while the cursor is over it (`effectiveShow =
  shouldShow || contentHovered`), so content can take clicks; the existing
  220ms keep-alive timer covers the anchor→popup gap traversal. Stats pill
  popup unchanged (only user of IslandPopup besides the clock).
- Verified: live shell hot-reloaded clean (no QML errors in `qs log`).

## 2026-07-09 — Ghost dictation activations: tap-guard + stuck-press cancel

User reported random "Listening" pills with no key press. Journal showed
press-only Control_R events starting runs (pttHeld stuck true), later aborted
mid-upload. RCTRL-capable devices on this box: AT keyboard, **2.4G wireless
dongle (top suspect)**, ydotoold virtual, vicinae-snippet-virtual-keyboard —
virtual keyboards + flaky dongles can synthesize Control_R. Defenses
(`f23d265`): daemon toggle only after **200ms hold** (synthetic taps do
nothing — verified: 34ms tap ignored, no pill, no daemon call), **120s
stuck-press auto-cancel** (ghost hold can no longer inject hallucinated
"Thank you"-style text), PTT event log at `/tmp/hyprvoice-ptt.log`, and a
detached per-device RCTRL monitor (`/tmp/rctrl-monitor.py` →
`/tmp/rctrl-events.log`, relaunch after reboot) to name the culprit device on
next occurrence. E2E re-verified: arm at +202ms, hold-release transcribed,
no aborts.

## 2026-07-07 — Voice dictation in the notch (hyprvoice push-to-talk)

New notch surface: hold **Right Ctrl** → notch morphs into a dictation pill
(pulsing coral mic badge + LIVE mic waveform + "Listening"), release → shimmering
"Transcribing…" → "Typing…" → green "Done" flash → collapse. Click the pill
mid-run to cancel.

- `services/Hyprvoice.qml` (new): singleton owning the PTT flow. `hyprvoicePtt`
  GlobalShortcut (press+release binds in `custom/keybinds.lua`) fires
  `hyprvoice toggle` via execDetached; polls `hyprvoice status` at 200ms while
  active. **Gotcha:** the daemon reports `transcribing` from the FIRST AUDIO
  FRAME (streaming design) — `pttHeld`, not daemon state, decides the
  "listening" phase (`phase` derived property). `idleGrace` swallows stale
  idle reads during toggle handshakes; `failCount` bails out if the daemon
  dies mid-run. IPC-testable: `qs -c openagentisland ipc call hyprvoice
  pttPress/pttRelease/cancel`.
- Mic waveform: second cava instance on `@DEFAULT_SOURCE@` (libpulse magic
  name — no shell/sed needed; `scripts/cava/mic_raw_config.txt`, 18 bars,
  middle 16 shown). PipeWire multiplexes the mic fine alongside pw-record.
- `IslandNotch.qml`: `dictation` displaySource at TOP precedence (user is
  actively speaking — nothing steals the notch); dictationUI RowLayout
  (sonar pulse ring, waveform, AgentStatusText shimmer reuse); pill click =
  cancel while active; hyprvoice's own notify-send chatter is filtered from
  the notification OSD (appName "Hyprvoice", errors still pop; history keeps
  everything).
- Verified live on eDP-1 via IPC + grim screenshots: listening pill renders
  (flat dotted waveform in silence — expected), cancel collapses and hands
  the notch back to the agent state correctly. Real-voice end-to-end
  (release → Groq → text injection) pending user test.
- Keybind rationale: Fn is EC/firmware-level on the Swift Go 14 (no keycode),
  so Right Ctrl is the hold key (consumed; use Left Ctrl for shortcuts).
  Headless fallback binds (`qs ipc TEST_ALIVE || hyprvoice toggle`) keep
  dictation alive if quickshell is down.
- **Gotcha (fixed, `7764bb9`):** Hyprland delivers DUPLICATE release events for
  the global shortcut (press-bind key tracking + explicit release bind). The
  second release sent a second `toggle` µs after the first → daemon treats
  toggle-while-injecting as ABORT → "context canceled" on the Groq POST.
  `pttPressed`/`pttReleased` are now idempotent (guarded on `pttHeld`/idle).
  Upstream's `workspaceNumber` never hit this because its handler is an
  idempotent bool.
- **Gotcha:** a quickshell hot reload can silently NOT apply (old code keeps
  running, no visible panel) — PROBE behavior after service edits (e.g. lone
  `ipc call hyprvoice pttRelease` must leave the daemon idle) instead of
  trusting the reload. Restart fallback: `setsid -f qs -c openagentisland
  </dev/null >/tmp/oai.log 2>&1`. Careful: `pkill -f "qs -c openagentisland"`
  from an agent shell can match the AGENT'S OWN wrapper cmdline and
  self-terminate — use a self-safe pattern like `[q]s -c openagentisland`.
- Full E2E verified after fix: forced duplicate release via IPC → single
  inject action, "transcription completed", "Text injection completed
  successfully", daemon idle. Real mic audio transcribed and typed into a
  scratch window.

## Current phase & status

**FEATURE-COMPLETE; multi-monitor blanking FIXED + VERIFIED on the scaled built-in
monitor; now running LIVE on `openagentisland` (2026-06-06).** All features built +
polished + validated. The headline feature (live Claude Code agent + permission
Allow/Deny from the notch) is safety-proven (13/13, never hangs Claude). The
multi-monitor blanking bug (below) is root-caused + fixed, and the fix was
**verified live on `eDP-1` (scale 1.5)** — the exact monitor that blanked before
now renders wallpaper + all three islands + dock correctly.

**Live state right now:** OpenAgentIsland is the PERMANENT desktop — `variables.lua`
is `hl.env("qsConfig", "openagentisland")` (backup: `variables.lua.bak-preisland`),
so it loads on every boot/relogin. **hooks ENABLED**; socket listener up at
`$XDG_RUNTIME_DIR/openagentisland.sock`. **Still UNVERIFIED on real hardware:** the
rotated vertical monitor (`DP-3`, transform 1) and the full 3-monitor combo (all
testing so far was on `eDP-1` 1.5× only, user mobile) — the logical-anchor fix
should handle rotation, but confirm on reconnect. **Rollback if multi-monitor
misbehaves:** set `variables.lua` → `hl.env("qsConfig", "ii")` (or restore the
.bak) and relog; or live-revert with
`pkill -f "qs -c openagentisland"; hyprctl dispatch exec "qs -c ii"`.

Re-test / swap commands:
- Hot-swap to island: `pkill -f "qs -c ii"; setsid qs -c openagentisland </dev/null >/tmp/oai.log 2>&1 &`
  (NOTE: `hyprctl dispatch exec "qs -c openagentisland"` did NOT keep it alive this
   session — use `setsid` to detach it from the launching shell.)
- Revert to ii: `pkill -f "qs -c openagentisland"; hyprctl dispatch exec "qs -c ii"`
- Hooks: `python3 ~/Projects/openagentisland/bridge/install-hooks.py enable|disable|status`

### ✅ PERF OVERHAUL (2026-07-07) — idle/working CPU cut ~4×, laptop was cooking at 92°C
**Symptom:** shell + compositor burned ~1.1 cores 24/7 (qs 58% + Hyprland 56% of a
core); package temp pinned at 92°C. **Root cause:** smooth `Infinite` animations on
always-visible island content re-rendered the full-screen notch layer at panel
refresh rate (90–100 fps) on ALL THREE monitors whenever any agent session existed —
mascot resting bob, shimmer sweep (an OpacityMask shader pass per frame), and the
working-bars `Behavior` tween retriggered every 170ms. **Fix — stepped pixel-art
motion:** bob = 850ms discrete hop (Timer), bars snap (no tween), shimmer = 8
timer-driven hops + parked hold, dots+shimmer share ONE ticker, spinner frame+bars
share ONE tick (each unsynced timer forced its own compositor pass across all
monitors). Launcher logo/sparkle/StarField animations gated on `win.visible`.
**Measured: qs 58.4→13.6%, Hyprland 55.8→17.4% (working state; true idle ≈0).**
Permission shake + done-hop stay smooth on purpose (brief, attention-grabbing).

**Reload icon-vanish bug (dock showed blank buttons after hot-reload):** root-caused
to Qt's in-process NEGATIVE icon cache — a hot reload re-queries dock icons while
MaterialThemeLoader rewrites kdeglobals; lookups that land in that window fail and
the failure is cached for the process lifetime (retries useless). Old icons (btop
etc.) unaffected, only icons queried during the window (kitty, zen-browser).
**Fix:** restart the shell (fresh process = clean cache); added a bounded retry in
DockAppButton for genuinely transient races. Also: NotificationAppIcon now blanks
dead `image://qsimage` handles on Image.Error (they die on every reload and
otherwise retry-spam the log/CPU forever); new IPCs — `notifs clearAll` and
`debug guessIcon/iconPath <name>` for live icon diagnosis; `?.` guard on
notifications.forceMonitor (TypeError churn).

**System side (not repo) — SOLVED same day:** the 92°C/throttling turned out to be
the Acer EC's fan-mode register (0x45) sitting UNINITIALIZED on Linux (AcerSense
writes 1/2/3 on Windows; 0 = no fan curve at all → fans never ramp). Fixed with
`acer-fanmode.service` (+2min re-assert timer) writing 0x45=3 via ec_probe
(nbfc-linux). Fan tach now ramps 3700→6250 RPM with heat; 92→66°C in 5s post-load;
boost 1.9→3.4+ GHz. Power profile set to performance per user preference. Red
herrings ruled out: acpitz=27.8°C is a firmware stub, paste/fans hardware fine,
EC reset + DPTF active-policy UUID both no-ops. Full story in the memory file
`laptop-fan-ec-quirk.md`.

### ✅ MULTI-MONITOR BLANKING — root cause found + fixed
**Symptom (Path A switch, 3 monitors):** only the main external monitor worked;
the laptop built-in and the vertical monitor went COMPLETELY BLANK (no wallpaper /
dock / islands), plus wrong sizing. Confirmed by photos + `monitors.lua`:
- `HDMI-A-1` 2560×1440 **scale 1.0, no transform** → logical == physical → **worked**.
- `eDP-1` 2880×1800 **scale 1.5** → logical 1920×1200 → **blank**.
- `DP-3` 1920×1080 **transform 1 (rotated)** → logical 1080×1920 → **blank**.

**Root cause:** `IslandNotch.qml` sized its PanelWindow with PHYSICAL pixels —
`implicitWidth: screen.width; implicitHeight: screen.height`. Layer-shell surfaces
use LOGICAL coords, so on any monitor with scale≠1 or a rotation the full-screen
Top-layer surface was oversized/mis-axed and **broke compositing for the whole
output** (everything on it went black, wallpaper included). The one scale-1.0,
unrotated monitor was the only one where physical==logical, so it alone rendered.
The notch was the SOLE violator — every other panel (Background, Dock, left/right
islands) is content-/edge-sized and survived; their disappearance on the dead
monitors was collateral from the broken output, not their own bug.

**Fix (commit `c94a7b9`):** anchor the notch window `top+left+right` (logical
full-width per monitor) + fixed `implicitHeight: maxHeight+60`; removed both
`screen.width/height`. `exclusiveZone` (40) still honored (anchored top + both
perpendicular edges). This matches the framework's `Background`/`Dock` pattern,
which is already proven on all 3 of the user's monitors under `ii`. Trade-off: the
outside-click-to-close catcher now covers the top ~460px instead of the full
screen (Esc / re-click the pill still close); fine since surfaces hang from the top.

**VERIFIED (2026-06-06):** live hot-swap on `eDP-1` (scale 1.5) — wallpaper +
all three islands + dock render correctly; no blanking. The scaled-monitor failure
mode is fixed. STILL TO VERIFY: rotated `DP-3` (transform 1) + the full 3-monitor
combo (only `eDP-1` connected during the test). If a secondary monitor's wallpaper
ever looks mis-scaled, that's a separate `Background` parallax tweak (also uses
`screen.width` in its zoom math) — but it renders fine under `ii`, so likely moot.

Toggle hooks for real Claude work (currently DISABLED):
  python3 ~/Projects/openagentisland/bridge/install-hooks.py enable|disable|status

---

## Done (newest first)

- **2026-06-30 — Agent Island v3: radial menu, window chrome, new-project, Theo.**
  Big interaction/feature pass (all loaded clean + screenshot-verified):
  - `FolderRadialMenu.qml` (NEW): click a folder → it lifts to focus, the bg blurs
    (contentRoot layer.effect MultiEffect, animated `blurAmt`), and 5 actions fan
    out in a wave-staggered RING around it — Launch (primary), Launch from…, Open,
    Settings, Remove. "Launch from…" swaps the ring for a subfolder picker
    (store.loadSubdirs via find) so you choose the session's working dir.
  - Window chrome: fullscreen toggle (FloatingWindow.fullscreen) + close (Qt.quit)
    top-right. NOTE: minimize is NOT exposed by Quickshell's FloatingWindow API, so
    it's omitted (only title/fullscreen/visible/color/minimumSize exist).
  - New project: a "＋ New" tile → sheet to Create new (name + optional `git init`,
    under ~/Projects) or Add existing (kdialog folder picker; stored as an "added"
    flag in settings and merged into the grid via store.extraDirs).
  - Theo = "just the voice": greeting + a "✦ Theo" line with rotating quips + live
    session count; launch overlay now says "Theo's spinning up <x>…".
  - FolderTile click now emits `activated()` (opens the menu) instead of launching;
    gear removed (settings live in the ring). Store gained openFolder/removeRecent/
    launchFrom/createProject/addExisting/addPath/loadSubdirs.

- **2026-06-30 — SEVERE BUG FIXED: clicking a folder launched nothing.**
  Symptom: click a project → animation plays, no terminal opens. Root cause:
  Quickshell serves QML from a virtual qrc-like FS, so in ProjectsStore.qml
  `Qt.resolvedUrl("../../../../bridge/launch-project.sh")` resolved to the bogus
  `qrc:/qs-blackhole` (verified via a startup debug log) — `execDetached` ran a
  nonexistent path and silently no-op'd while the QML launch overlay still played.
  FIX: resolve the launcher from `Quickshell.shellDir` (the REAL on-disk config
  dir) → `<shellDir>/../bridge/launch-project.sh`. Verified end-to-end: kitty
  opens, tmux session created, exit 0. Hardening also added: launch-project.sh now
  exports a sane PATH (GUI launchers hand a minimal one — claude lives in
  ~/.npm-global/bin) and logs every invoke+exit to
  $XDG_RUNTIME_DIR/agentisland-launch.log; ProjectsStore re-scans ~/Projects every
  20s so deleted folders (e.g. geoscalar) don't linger as dead tiles.
  Bug 2 (closed app → dead dock icon): Quickshell locks app_id to org.quickshell
  and a qs --path app has no .desktop, so the dock can't relaunch a closed
  instance. Added `bridge/install-app.sh` (installs agentisland.desktop + themed
  icon) so it's launchable from the app grid / a keybind; documented the dock
  limitation.

- **2026-06-30 — Agent Island dock icon fix (custom logo in the dock).**
  Quickshell locks every window's app_id to "org.quickshell" (FloatingWindow has no
  icon/appId/startupClass prop; ShellId pragma doesn't change it either — verified),
  so the island dock resolved our launcher to Quickshell's default green icon.
  Fix in `modules/ii/dock/DockAppButton.qml`: `customIconSource` matches app_id
  "org.quickshell" + a toplevel title containing "Agent Island" → uses bundled
  `modules/ii/agentIsland/assets/logo-256.png`. VERIFIED in the live DP-3 dock.
  NOTE: scoped to our dock only; alt-tab / external taskbars would still show the
  default (would need a global org.quickshell.desktop icon override to fix).

- **2026-06-30 — "Agent Island" v2 REDESIGN: welcoming full-screen launchpad.**
  User feedback: v1 "mid"; wants a high-quality welcoming app (Claude-web vibe).
  Rebuilt AgentIslandWindow.qml into a launchpad + added components & assets:
  - Brand assets from ~/Downloads: `assets/icon*.png` (transparent A+star, header),
    `assets/logo*.png` (black-square app icon), `assets/sparkle.png` (4-pt star,
    SVG→PNG) for the live star animation.
  - `StarField.qml` — live twinkling/rotating/drifting sparkles (GPU Image insts).
  - `FolderTile.qml` — macOS folder (blue gradient + tab + gloss), soft drop
    shadow (layer.effect MultiEffect), blurred aurora hover glow, live-session
    dot, hover/press spring (OutBack), settings gear on hover.
  - Window: aurora blob background (blue/green/magenta, MultiEffect blur) +
    StarField; welcome header = floating logo + time-aware greeting "{greeting},
    Kartik" + animated sparkle + rotating quirky subline + search; Recents row +
    Projects Flow grid; centered settings sheet (sessions/mode/host) opened from
    the gear; refined launch overlay (spinning sparkle + "Launching …").
  - Name "Kartik" from GECOS. VERIFIED loads clean (no QML errors) + screenshot
    looks premium. KNOWN: Lua-Hyprland tiles the toplevel (628px); hyprctl
    keyword/dispatch no-op ("non-legacy parser, use eval") → needs a Lua
    windowrule, OR convert to a fullscreen layer-shell overlay (pending decision).

- **2026-06-30 — "Agent Island" app v1: mission-control launcher built + loads live.**
  Standalone Quickshell app (decided: standalone native app via `qs --path`, which
  reuses the shell's theme/widgets — verified `qs.` imports resolve under --path).
  Run: `qs --path ~/Projects/openagentisland/quickshell/agentIsland.qml`.
  - Files: `quickshell/agentIsland.qml` (entry, ShellRoot+FloatingWindow),
    `modules/ii/agentIsland/AgentIslandWindow.qml` (mission-control UI),
    `modules/ii/agentIsland/ProjectsStore.qml` (scan + tmux-live + persistence).
  - UI: left = project list scanned from ~/Projects (avatars, live green tmux
    dots, session-count chips, search filter); right = settings card (sessions
    stepper 1-6, mode segmented bypass/default/plan/acceptEdits, host segmented
    kitty/alacritty/warp) + big Launch button (→ Re-attach when live). Palette:
    near-black + Material-You accent (Appearance.m3colors.m3primary), reuses
    StyledText/MaterialSymbol.
  - Settings persist to ~/.local/state/quickshell/user/agentisland-projects.json
    (never re-prompted). "Running" state decoupled from the agent socket — read
    from tmux (`tmux list-sessions`) polled every 4s, so it never contends with
    the island shell that owns the socket. launch() shells to launch-project.sh.
  - VERIFIED: loads clean (Configuration Loaded, no QML/type errors; only the
    expected first-run FileNotFound → creates {}), window present in Hyprland.
  - NEXT: new-project folder picker (add dirs outside ~/Projects), jump/focus a
    running session's terminal, keybind + .desktop entry, real-app QA pass.

- **2026-06-30 — "Agent Island" launcher: tmux session engine built + verified.**
  New feature track (beyond phases 0-8): a project launcher that spins up
  pre-configured Claude Code sessions per project. Engine-first per project ethos.
  - `bridge/launch-project.sh` — parameterized: `--dir --name --sessions --mode
    (bypass|default|plan|acceptEdits) --model --host (warp|kitty|alacritty|none)
    --setup --claude-bin --dry-run`. tmux is the engine (persistence + tiled
    panes + idempotent reattach); host terminal just runs `tmux attach`.
  - Verified standalone (fake claude=sleep): N tiled panes each running the
    command (pane_pid→child confirmed), idempotent re-run re-attaches without
    duplicating panes, mode/model/setup flow through. Gotcha fixed: `send-keys`
    races shell-rc load and drops keys → switched to pane START command
    `claude …; exec $SHELL` (no race; pane drops to a shell if claude exits).
  - Warp reality: Warp is single-instance, so `-e`/env don't propagate; only
    Launch Configurations + `warp://` deeplinks route reliably. Script generates
    `~/.warp/launch_configurations/agentisland-<name>.yaml` (pane runs tmux
    attach); kitty/alacritty are the guaranteed one-click hosts. Binary probe
    confirmed launch-config schema `windows→tabs→layout{cwd,split_direction,
    panes,commands[exec]}` and `.yaml` dir.
  - DECIDED: delivery = standalone native app (not an island surface); multi-
    session layout = tiled panes; project source = all ~/Projects subfolders.
    OPEN: app GUI tech stack.

- **2026-06-30 — Right-island stats: CPU temperature + matching/clear icons.**
  User reported the collapsed stats pill and its hover popup used MISMATCHED icons
  and that the panel felt static ("values don't move"). Fixes:
  - `ResourceUsage.qml`: added live CPU package temperature. `findTempProc` runs
    ONCE at startup to discover the best sysfs file (Intel coretemp "Package id 0",
    AMD k10temp/zenpower Tctl/Tdie, ARM cpu_thermal, then x86_pkg_temp/acpitz
    thermal-zone fallbacks) → `cpuTempPath`; `fileTemp` FileView is re-read each
    poll tick (no per-tick process spawn). `cpuTemperature` in °C, 0 = unsupported.
    Verified discovery resolves to `/sys/class/hwmon/hwmon5/temp1_input` here.
  - `IslandRight.qml`: new `device_thermostat` MetricRing in the stats pill (fills
    toward 100°C; tints #FFB454 ≥70°C, #FF6B6B ≥85°C), plus a "Temp:" row in the
    CPU popup column. Unified pill↔popup icons: CPU now `speed` in both (was
    `speed`/`planner_review`), Battery now `battery_full` in both (was
    `battery_full`/`battery_android_full`). Clarified value-row icons: Used →
    `data_usage`, Total → `database` (were `clock_loader_60`/`empty_dashboard`).
  - SWAP "frozen numbers" bug: this box runs zram swap with ~4 MB used, but the
    popup formatted everything as GB@1-decimal → `4304 kB → "0.0 GB"`, so swap
    Used never appeared to change. Added `ResourceUsage.kbToSizeString(kb)`
    (adaptive MB<1GB / GB) and switched all RAM+Swap Used/Free/Total rows to it,
    so sub-GB swap usage is shown in MB and visibly moves.

- **2026-06-07 — CRITICAL GOTCHA: real desktop is a LUA-config Hyprland.** The
  standard dispatch form `Hyprland.dispatch("focuswindow address:…")` /
  `"workspace N"` SILENTLY NO-OPS on the user's real desktop (verified live:
  workspace didn't change). It only works in the nested dev window (vanilla
  Hyprland) — which is why island workspace/window dispatches "worked" in dev but
  not live. The correct form is the LUA API: `hl.dsp.focus({window = "address:…"})`,
  `hl.dsp.focus({workspace = N})`, `hl.dsp.window.move({…})`, `hl.dsp.window.close({…})`
  (same forms the upstream end-4 OverviewWidget uses). ✅ FIXED everywhere: all
  island `Hyprland.dispatch` callers now use `hl.dsp.*` — `AgentSurface` (jump),
  `IslandWorkspaces` (scroll+click; relative e±1 computed as absolute from
  `activeWs`), `OverviewSurface` (workspace switch, window focus/move/close).
  `grep Hyprland.dispatch modules/ii/island/` → all hl.dsp. (`LauncherSearch`
  already used `hl.dsp.global`.) The end-4 `OverviewWidget` (old overview, not our
  island) already used hl.dsp. NOTE: verify on the real desktop — proven live that
  `hl.dsp.focus({workspace=N})` and `{window="address:…"}` work.

- **2026-06-07 — Session permission-mode shown + live-synced.** Hook reports
  `permission_mode`; a colored ModeChip on each session row / permission card shows
  Bypass / Auto-edit / Plan (live from the terminal, updates on Shift+Tab) and
  island-side Auto:<tool> / Bypass from notch Allow-All/Bypass. (A hook cannot SET
  the terminal's mode — the notch reflects/augments, can't flip it.) Verified the
  notch Allow-All auto-rule DOES work (next same-tool request auto-allowed, no UI).

- **2026-06-07 — Jump-to-terminal fixed (Lua dispatch + Warp disambiguation).**
  Was broken because it used the standard dispatch form (see gotcha above) and
  because Warp shares one PID across all its windows. Now uses `hl.dsp.focus` and,
  when multiple windows share a PID, picks the one whose title best matches the
  session prompt/summary.

- **2026-06-06 — Jump-to-terminal (the previously-skipped feature).** Each session
  row in the agent list has an `open_in_new` button → focuses the terminal running
  that Claude session (switches workspace if needed). Mechanism: `oai_hook.py` sends
  its process-ancestor PIDs (`ancestor_pids()`); the terminal is always an ancestor
  of `claude`, so `AgentService` stores them and `AgentSurface.findWindow()` matches
  a PID against `HyprlandData.windowList`, then `Hyprland.dispatch("focuswindow
  address:…")`. Verified the ancestor chain includes the real window pid. Caveat:
  single-process multi-window terminals (Warp) share one pid across windows, so it
  focuses *a* Warp window, not the exact tab; per-process terminals (foot/kitty/
  alacritty) are precise. Button hidden when no window matches.

- **2026-06-06 — Per-monitor open + full-screen close-catcher + clean agent surface
  + restored top-strip reservation.** (3 reported bugs.) Island bus tracks
  `openScreen` so a surface opens only on the clicked monitor; notch window anchors
  all-4 (logical full-screen, multi-monitor safe) for a click-anywhere-to-close
  catcher; a separate stable strip window re-reserves the top 40px so windows sit
  below the islands; agent surface re-laid-out (title=project, prompt up to 2 lines,
  command = dimmed monospace tail).

- **2026-06-06 — Ghost sessions fixed via `SessionEnd` hook.** Closing a Claude
  session left a ghost row (`idle`/`waiting`) until the 5-min staleness timer,
  because `Stop` = "turn finished", not "session closed". Added Claude Code's
  `SessionEnd` hook (`install-hooks.py` STATUS_EVENTS) → `AgentService.endSession()`
  removes the session immediately (+ clears its pending rows & bypass rule).
  Verified: injection test (SessionStart→Notification/waiting→SessionEnd→removed)
  and a real `claude -p` one-shot leaving no ghost. Caveat: a hard kill (SIGKILL /
  crash) won't fire `SessionEnd` — the 5-min staleness backstop still cleans those.

- **2026-06-06 — Multi-monitor blanking ROOT-CAUSED, FIXED, and VERIFIED live.**
  Root cause: `IslandNotch.qml` sized its PanelWindow in PHYSICAL pixels
  (`implicitWidth/Height: screen.width/height`); layer-shell uses LOGICAL coords,
  so any monitor with scale≠1 or rotation got an oversized/mis-axed full-screen
  Top-layer surface that broke compositing for the whole output → blank. Confirmed
  with `monitors.lua` + photos: `HDMI-A-1` (1.0, no transform) worked; `eDP-1`
  (1.5×) + `DP-3` (transform 1) blanked. Fix (`c94a7b9`): edge-anchor the notch
  window `top+left+right` + fixed height, drop `screen.width/height`; matches the
  framework's `Background`/`Dock` sizing. Verified by hot-swapping the real desktop
  to `openagentisland` on the `eDP-1` 1.5× built-in — wallpaper, all 3 islands, and
  the dock render correctly (previously fully blank). Re-enabled hooks; agent
  feature ready to test live. Pending: rotated `DP-3` + full 3-monitor verification
  (user was mobile, single screen connected).

- **2026-06-06 — Phase 6+7 agent feature VALIDATED end-to-end (real Claude Code).**
  Ran a real `claude` session in `~/agent-island-test/` (project-level hooks,
  isolated from the dev session): notch showed SessionStart → Working… → the
  orange permission card with the real Write preview; approved from the island;
  Claude Code wrote hello.txt and continued. Full UI built + user-approved:
  AgentSpinner (4-frame running pixel mascot, state-tinted), AgentStatusText
  (shimmer + cycling dots, fixed width), compact State 2 (DI spread, fixed 224w,
  auto-collapse via 5s done-prune), AgentSurface State 3 (session list +
  permission card with write/edit/bash preview + Deny/Allow Once/Allow All/Bypass
  w/ 2-click confirm). Permission auto-opens the surface and auto-closes on
  resolve. Bugs fixed live: status string mismatch (running vs working), stale
  "permission" status after resolve/timeout (dropPending reverts to working).

- **2026-06-05 — Phase 6 agent bridge BACKEND (safety-first).** Built the riskiest
  piece first and proved it before any UI. `bridge/oai_hook.py` (Python — no
  socat/nc on this box) forwards Claude Code hook events to a unix socket; for
  PreToolUse it blocks for an Allow/Deny decision with a hard timeout. **Safety
  contract:** any failure (no socket / refused / timeout / frozen / exception) →
  exit 0, no stdout → Claude falls back to its normal prompt; never hangs, never
  auto-approves. `bridge/test_safety.py` proves it (13/13: down, allow, deny,
  frozen→bounded fallback, delivery). Quickshell side `services/AgentService.qml`
  hosts a `SocketServer`, keeps per-session status + a pending-permission queue,
  writes decisions back on the held connection, and drops a pending request if
  its connection closes (queue can't wedge). Verified END-TO-END through the real
  Quickshell listener: status events received with correct project/tool/summary;
  full allow + deny round-trip via the `agent` IPC target; disconnect cleanup.
  Gotchas: Quickshell `SocketServer.handler` is a `QQmlComponent` (one `Socket`
  per connection); `Socket` has `write()`/`flush()`/`connected`; new singleton
  needed a fresh `qs` start to register (imported-module quirk) — socket appeared
  after restart. Hooks documented but NOT yet wired into live `~/.claude/`.

- **2026-06-05 — Expansion phases A–H (notch surfaces + side islands).** Built the
  whole reference feature set ahead of the agent work; each phase compiled clean
  (verified via reload log + force-opening each surface) and committed separately
  (commits Phase A `45c8fe8` → Phase H). New files under `modules/ii/island/`:
  `Island` (bus singleton), `DashboardSurface`/`DashboardPlaceholder`,
  `WidgetsPane`/`WidgetCalendar`, `KanbanStore`/`KanbanPane`, `PowerSurface`,
  `ToolsSurface`, `LauncherSurface`, `OverviewSurface`, `IslandWeatherPill`,
  `IslandNetworkPill`. `IslandNotch` open state → Loader surface-host; `IslandLeft`
  rebuilt to 5 pills (title dropped); `IslandRight` gained pencil pill + power→surface.
  Gotchas hit:
  - **New-file reload race:** adding a new surface file + editing IslandNotch to
    reference it in the SAME reload nudge yields a transient `X is not a type`
    "Failed to load" pass, immediately followed by a successful "Configuration
    Loaded". The `Component { X {} }` wrapper forces X to be a valid type for the
    config to load at all, so a trailing `Configuration Loaded` proves it resolved
    — trust the LAST line; the interleaved error is stale (its line:col often no
    longer even points at the Component after later edits).
  - **PowerProfilesDaemon not running** on this box → mode selector shows default
    and `powerprofilesctl set` is a harmless no-op (env, not a bug).
  - **end-4 `hl.dsp.*` dispatchers are plugin-only** (invalid in vanilla Hyprland)
    — OverviewSurface uses standard `focuswindow`/`closewindow`/
    `movetoworkspacesilent`/`workspace` instead.
  - **Cross-cell/column drag** (kanban + overview): avoided Repeater-delegate
    reparenting; instead arm after 8px, show a floating proxy, and on release map
    cursor position → target cell/column. Robust without z-order fighting.

- **2026-06-05 — Phase 5 media + cava visualizer (notch).**
  - One shared cava `Process` at the `Scope` root runs `cava -p scripts/cava/
    raw_output_config.txt` (50 bars, `;`-sep stdout) only while `mediaActive` →
    `visualizerPoints`. Downsampled to 22 **equalizer bars** (center-anchored
    Rectangles) — NOT the `WaveVisualizer` (user wanted bars).
  - Minimal media UI (reference-style): small album art · bars · play/pause. NO
    title/artist. Compact (~40px). `MprisController.activePlayer`.
  - `mediaActive = isPlaying` → pausing/no-playback collapses back to idle (user choice).
  - **Album-art flicker fix:** binding straight to `trackArtUrl` made art vanish when the
    player rewrote/cleared the URL. Fix = download to a stable local cache
    (`Directories.coverArt/Qt.md5(url)` via a curl `Process`) AND only clear `displayedArt`
    on an actual track change (`trackKey`=trackTitle), set only on curl exit 0. Persists.
- **2026-06-04 — Phase 4 notch brightness + notification.** Generalized to one
  `expandedSource` + shared hide-timer; reusable `OsdBar`/`OsdPercent`. NOTE: brightness
  only fires when changed THROUGH the shell service (`Brightness.brightnessChanged`;
  test via `qs -c openagentisland ipc call brightness increment`), and notifications
  CANNOT be tested in the nested session — the real `ii` already owns the
  `org.freedesktop.Notifications` D-Bus name, so the nested shell gets none. Both wired
  correctly; verify on real desktop.
- **2026-06-04 — Phase 3 notch idle + volume + the morphing framework.**
  - Top-attached notch: square top corners flush with screen edge, rounded bottom,
    concave `RoundCorner` shoulders (left=TopRight, right=TopLeft, overlap −1px) blending
    into the top edge. Borderless (a border drew seam lines). Window fixed at max size +
    `mask: Region{item:notch}` (click-through elsewhere) so size animates smoothly
    Qt-side (no janky per-frame compositor resize).
  - Goey morph: `easing.bezierCurve` from the reference's notch.css
    (`cubic-bezier(0.175,0.885,0.32,1.275)`), softened to **[0.34,1.22,0.64,1,1,1]**
    (1.275 made the open→idle shrink collapse violently; user still wanted bounce).
  - **Constant 18px bottom radius** (≤ idle-height/2 so Qt never clamps it) — animating
    the radius read as corners "rounding in", which the user rejected. idle height = 36.
  - Volume triggers off `Audio.sink.audio` VALUE (not `GlobalStates.osdVolumeOpen`).

- **2026-06-04 — Phase 2 RIGHT island + sidebar slide-in.**
  - `IslandRight.qml`: pills = stats (CPU/RAM/SWAP/battery as `CircularProgress` rings,
    hover → combined RAM/Swap/CPU/Battery tooltip) · tray (hidden when empty) ·
    perf-toggle + settings-gear · clock (12h `h:mm AP`, small) · circular power button.
    Smooth `Behavior on color` hovers on gear/perf/power.
  - `IslandPopup.qml` (new): hover tooltip anchored BELOW via `PopupWindow` (the bar's
    `StyledPopup` is hard-coded for the full-width bar → lands top-left on our island).
    Loader-based + keep-alive timer = crash-safe (an always-mapped PopupWindow triggered
    a Wayland popup protocol error → killed qs). Content passed as a `Component`
    (instantiated fresh inside; reparenting a shared Item rendered empty boxes). Slides
    in from the right + fades, both ways.
  - `IslandWorkspaces.qml`: fixed dispatch — end-4's `hl.dsp.focus({...})` is invalid in
    vanilla Hyprland ("Invalid dispatcher"); switched to standard `workspace N` / `e±1`.
  - `SidebarRight.qml`: top margin 44 (opens below the island strip) + slides in from the
    right screen edge (Translate on content, window kept mapped through slide-out).
  - Gotchas: brace-balance bugs are easy to misdiagnose because `${}` template literals
    and reload-race stale reads show contradictory errors — verify with a string/comment/
    template-aware brace counter, not `grep -c {`.

- **2026-06-03 — Phase 2 LEFT island.** Built the left island iteratively with the user:
  - `IslandWorkspaces.qml` (custom): a `Row` of uniform-spaced dots where the CURRENT
    workspace is a capsule (same height as dots) that **expands and pushes neighbours**
    apart → genuinely uniform gaps + fluid 280ms animation. Reuses end-4's Hyprland
    dispatch (`hl.dsp.focus`) + occupancy logic. Used dots = white, unused = faint,
    current = blue-tint. Scroll = switch ws, right-click = overview, left-click = focus.
    (Earlier tried bending the reused end-4 `Workspaces.qml` via override props, but
    fixed slots can't give uniform spacing around an elongated capsule — reverted that
    file to pristine and went custom.)
  - `ActiveWindow.qml`: added `compact` mode (single-line title, short "Desktop" idle
    label) — default off, so the disabled bar is unaffected.
  - `IslandStyle.qml` (singleton): shared tokens — solid space-black `#0B0B0E` pill,
    white text, `#8AB4F8` blue accent, 4px edge margin, 32px height, full radius. ALL
    islands use this for consistency.
  - Left-click pill → `sidebarLeftOpen`. Verified by user across several rounds of
    color/spacing/size tuning.

- **2026-06-03 — Phase 0 orientation.**
  - Read `~/Projects/island-reference/hyprfabricated/modules/notch.py` (995 lines) and
    `utils/animator.py`. Key finding: their notch "morph" is a GTK `Stack` with
    `set_interpolate_size(True)` swapping fixed-size children, NOT a width/height tween;
    the functional left/right clusters live in a separate full-width bar (we split those
    into two floating islands); single-window, no multi-monitor. animator.py is a
    hand-rolled cubic-bezier tick tween → replaced by native Qt `Behavior`/`easing`.
  - Wrote `NOTES.md` and `PROGRESS.md`.
  - **Surveyed current repo state:**
    - `panelFamilies/IllogicalImpulseFamily.qml`: full-width `Bar` PanelLoader ACTIVE;
      `// PanelLoader { component: Island {} }` commented out; `qs.modules.ii.island`
      already imported.
    - `modules/ii/island/` already contains a **prior-session sketch**:
      `Island.qml` (static 220×32 "island" pill, single `PanelWindow` in `Variants`,
      anchored top-center) and `IslandContent.qml` (volume-only state machine where
      `idle` is *invisible* and the trigger is `GlobalStates.osdVolumeOpen`). Both
      diverge from the target design (idle should be a minimal clock; trigger off the
      `Audio` value, not the flickering flag). Treat as a sketch to rewrite in Phase 3.
  - **Dev env confirmed present:**
    - Runtime symlink OK: `~/.config/quickshell/openagentisland` →
      `~/Projects/openagentisland/quickshell`.
    - Nested Hyprland config OK: `~/.config/hypr-nested/hyprland.conf`
      (monitor `WL-1 2560x1440@60`, `exec-once = qs -c openagentisland`,
      animations/blur disabled).
    - The live `ii` config is untouched (hard rule).

---

## Next

1. **Notch `open` (fully-expanded) state content** — the `open` state (click-toggled,
   480×300) currently has the shape/morph but NO content. Design + build what it shows
   (likely the agent view + media controls + a dashboard-ish surface). User wants to
   iterate on the expanded/open notch.
2. **Phase 6 — agent bridge (status only), safety-first.** Build `bridge/` (NOT created
   yet): Unix socket at `$XDG_RUNTIME_DIR/openagentisland.sock`, Claude Code hooks →
   socket, a listener → notch `agent` state. Build the timeout/failure-safety FIRST so a
   down/broken island can NEVER hang real Claude Code. Confirm `Quickshell.Io` 0.2.1
   socket support (or external daemon). See NOTES.md §4.
3. Phase 7 permission round-trip, Phase 8 multi-session + polish.

Dev: launch nested window with
`WLR_BACKENDS=wayland WLR_NO_HARDWARE_CURSORS=1 HYPRLAND_INSTANCE_SIGNATURE= Hyprland --config ~/.config/hypr-nested/hyprland.conf`

---

## Blockers / open questions

- (Phase 6) Confirm `Quickshell.Io` 0.2.1 supports a listening socket +
  bidirectional/blocking writes from QML; if awkward, propose an external listener
  daemon to the user before building.
- Memory file `project_openagentland.md` describes this as a "fork of dynisland" —
  that is **stale/incorrect**; the actual project is Quickshell/QML on end-4 per
  `CLAUDE.md`. Trusting `CLAUDE.md` + the repo.

---

## Gotchas hit

- **⚠ NESTED MONITOR NAME VARIES PER SESSION → broke scaling.** The nested output is
  sometimes `WL-1`, sometimes `WAYLAND-1` (changes after a laptop reboot). A
  `monitor=WL-1,...` line silently stops matching → nested falls back to scale 1.5 +
  letterboxed wallpaper. FIX (in `~/.config/hypr-nested/hyprland.conf`): use a wildcard
  `monitor=,preferred,auto,1.0` (empty name = all outputs). Monitor changes need a
  nested-session restart. Check actual name/scale with
  `HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl monitors` (find the nested instance under
  `$XDG_RUNTIME_DIR/hypr/`).
- **ConflictKiller "Kill conflicting programs? kded6" dialog** appears in the nested
  session (`ConflictKiller.load()` in shell.qml). Click **No** — `kded6` is shared with
  the real desktop; killing it would break the real session's KDE integration.
- **Brace-balance is easy to misdiagnose:** `${...}` template literals contain `{`/`}`,
  so `grep -c '{'` lies. Use a string/comment/template-aware counter (a small python
  walker). Also, the reload race shows CONTRADICTORY stale errors ("Expected }" then
  "Unexpected }") from different in-flight file states — trust the LAST
  `Configuration Loaded` line, not transient errors.
- **`exclusiveZone` for "windows below the islands":** set
  `exclusionMode: ExclusionMode.Normal; exclusiveZone: 40` on the (top-anchored) notch
  to reserve the top strip so maximized windows don't get covered. Wallpaper (Background,
  layer Bottom, `ExclusionMode.Ignore`) still fills the whole screen.
- **Notifications can't be tested in the nested session** (real `ii` owns the D-Bus
  notification server). **Brightness** only triggers when changed through the shell
  service. Verify both on the real desktop. **Volume/media ARE testable** (shared
  PipeWire / MPRIS).
- **WaveVisualizer / any self-anchoring widget inside a Layout** → "anchors on an item
  managed by a layout" warning; wrap it in a plain `Item` with `Layout.preferredWidth/
  Height` and let the widget `anchors.fill: parent`.

- **⚠ HOT-RELOAD DOESN'T FIRE FROM CLAUDE'S FILE WRITES (critical, every phase).**
  Claude's Write/Edit tools save *atomically* (write temp + rename → new inode), and
  Quickshell's file watcher is on the old inode, so it never sees the change. Symptom:
  you edit a `.qml`, nothing updates in the nested window, and there's NO red error
  panel (suppressed by `//@ pragma Env QS_NO_RELOAD_POPUP=1` in `shell.qml`). Diagnosed
  via `qs -c openagentisland log` (shows "Configuration Loaded" only at launch, no
  reload). Also: a **plain `touch` does NOT reload** (mtime/IN_ATTRIB ignored); only a
  real content change (IN_MODIFY) does, and it must *persist* (append+immediate-truncate
  nets zero and gets coalesced → no reload).
  **Reliable reload nudge after editing QML** (in-place, then restore so git stays clean):
  ```bash
  bash -c "printf '%s\n' '// reload-nudge' >> ~/Projects/openagentisland/quickshell/shell.qml"
  sleep 2   # let Quickshell reload from current disk state
  cd ~/Projects/openagentisland/quickshell && git checkout shell.qml   # remove the nudge line
  ```
  When the **user** saves from their own editor, normal hot-reload works fine — this
  only affects Claude's tool-writes. `qs -c openagentisland log` is the way to read
  silenced QML errors (note the log/"Configuration Loaded" counter appears capped, so
  trust the screenshot + error lines, not the reload count).
- User shell is **fish** — no `<<EOF` heredocs; write files with tools or
  `printf`/`cat` inside `bash -c '...'`. (A chained `ls A B && find …` failed because
  fish/`ls` returned exit 2 when one path was missing and short-circuited the `&&`.)
- A prior session already scaffolded `modules/ii/island/` — check existing files before
  creating, to avoid clobbering or duplicating.
