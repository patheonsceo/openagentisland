#!/usr/bin/env bash
# macOS traffic lights via hyprbars.  Added 2026-08-31.
#
# Why the wait loops: at Hyprland start this runs before the plugin has
# finished registering its `plugin:hyprbars:*` config options. Firing
# `hyprctl eval` immediately means every setting is silently rejected as an
# unknown config key - which is exactly what happened on the first reboot.
# So we poll until the options exist before configuring anything.
#
# Idempotent: the plugin is unloaded first, which clears the button list
# (buttons can only be added, never removed). Safe to re-run any time.
set -u

# Single-instance lock.
#
# Without this the script can race itself: a `hyprctl reload` fires it while a
# previous run is still between "unload" and "add buttons". Both then add three
# buttons to the same plugin instance, and buttons can only be added, never
# removed - which is how a titlebar ends up with forty traffic lights. flock
# makes a second invocation wait rather than interleave.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/hyprbars-setup.lock"
flock -w 30 9 || exit 0

SO=/usr/lib/libhyprbars.so
TL="$HOME/.config/hypr/custom/scripts"
LOG="${XDG_RUNTIME_DIR:-/tmp}/hyprbars-setup.log"
: > "$LOG"
log() { echo "[$(date +%T)] $*" >> "$LOG"; }

[ -f "$SO" ] || { log "plugin .so missing at $SO - nothing to do"; exit 0; }

# 1. wait for the Hyprland IPC socket to answer
for i in $(seq 1 50); do
  hyprctl version >/dev/null 2>&1 && break
  sleep 0.2
done
hyprctl version >/dev/null 2>&1 || { log "hyprctl never became ready"; exit 1; }
log "hyprctl ready"

# 2. Always unload then load.
#
# Tempting to skip this when the plugin is already loaded, and I tried: a
# marker file said "buttons already added, don't re-add". That was wrong.
# `hyprctl reload` clears the buttons too, so the marker caused a reload to
# leave a bar with NO buttons at all. Buttons can only be added, never
# removed, so the only way to guarantee exactly three is to start from an
# unloaded plugin every time. Costs one window resize; worth it.
hyprctl plugin unload "$SO" >/dev/null 2>&1
# Unload is asynchronous. Loading immediately after gets you
# "Cannot load a plugin twice!" and the whole setup silently no-ops.
for i in $(seq 1 40); do
  hyprctl plugin list 2>/dev/null | grep -q hyprbars || break
  sleep 0.1
done
# If it is somehow still loaded, loading again is a no-op that leaves the OLD
# button list in place and then appends three more. Refuse instead.
if hyprctl plugin list 2>/dev/null | grep -q hyprbars; then
  log "unload never completed - refusing to add buttons (would duplicate)"
  exit 1
fi
hyprctl plugin load "$SO" >>"$LOG" 2>&1 || { log "plugin load FAILED"; exit 1; }

# 3. wait for the plugin to register its config options
for i in $(seq 1 50); do
  hyprctl getoption plugin:hyprbars:bar_height 2>/dev/null | grep -q "^int:" && break
  sleep 0.2
done
hyprctl getoption plugin:hyprbars:bar_height 2>/dev/null | grep -q "^int:" \
  || { log "plugin options never registered"; exit 1; }
log "plugin options registered"

# 4. appearance
hyprctl eval "hl.config({plugin = {hyprbars = {
  bar_height                 = 26,
  bar_color                  = 'rgba(16161bee)',
  bar_text_size              = 10,
  bar_text_font              = 'SF Pro Display',
  bar_text_align             = 'center',
  bar_buttons_alignment      = 'left',
  bar_padding                = 12,
  bar_button_padding         = 7,
  bar_part_of_window         = true,
  bar_precedence_over_border = true,
  icon_on_hover              = true
}}})" >>"$LOG" 2>&1

# 5. buttons - macOS order, left to right: close / minimise / maximise
add() { hyprctl eval "hl.plugin.hyprbars.add_button({bg_color='$1', fg_color='rgba(00000000)', size=12, icon='', action='$2'})" >>"$LOG" 2>&1; }
add 'rgba(ff5f57ff)' "$TL/tl-close.sh"
add 'rgba(febc2eff)' "$TL/tl-min.sh"
add 'rgba(28c840ff)' "$TL/tl-max.sh"
log "buttons added" 

# 6. bars on chosen apps only - deny globally, then re-enable per class
hyprctl eval 'hl.window_rule({match = {class = ".*"}, ["hyprbars:no_bar"] = true})' >>"$LOG" 2>&1
for c in kitty Code Cursor dev.warp.Warp; do
  hyprctl eval "hl.window_rule({match = {class = \"^(${c})\$\"}, [\"hyprbars:no_bar\"] = false})" >>"$LOG" 2>&1
done

log "done: bar_height=$(hyprctl getoption plugin:hyprbars:bar_height 2>&1) align=$(hyprctl getoption plugin:hyprbars:bar_buttons_alignment 2>&1)"
