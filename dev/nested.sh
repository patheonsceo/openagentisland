#!/usr/bin/env bash
#
# Launch a nested Hyprland running this repo's shell from a git worktree,
# pinned to workspace 1.
#
#   dev/nested.sh                 worktree for the current branch
#   dev/nested.sh my-feature      worktree for branch my-feature (created if new)
#   dev/nested.sh --stop          kill the running nested session
#
# The point is isolation. The live desktop's ~/.config/quickshell/openagentisland
# symlink tracks the MAIN checkout, so anything developed here must not be able
# to reach it. This builds a shadow XDG tree inside the worktree and points
# XDG_CONFIG_HOME, XDG_STATE_HOME and XDG_CACHE_HOME at it. The nested shell
# physically cannot read or write the real ~/.config.
#
# Same technique the rice already uses to give Nautilus its own GTK4 theme.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE=1
# Fixed window size so every screenshot has identical geometry and two runs
# compare pixel for pixel. The nested compositor adapts its output to
# whatever size the host window is, so setting it here is enough.
NESTED_W=1600
NESTED_H=900
STATE="${XDG_RUNTIME_DIR:-/tmp}/openagentisland-nested"

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
step() { printf '\n%s %s\n' "$(c 34 '==>')" "$(c 1 "$*")"; }
ok()   { printf '  %s %s\n' "$(c 32 '✓')" "$*"; }
info() { printf '  %s %s\n' "$(c 2 '·')" "$*"; }
die()  { printf '\n%s %s\n' "$(c 31 'error:')" "$*" >&2; exit 1; }

if [[ "${1:-}" == "--stop" ]]; then
    [[ -f "$STATE/pid" ]] || die "no nested session recorded"
    pid="$(cat "$STATE/pid")"
    kill "$pid" 2>/dev/null && ok "stopped nested session (pid $pid)" || info "pid $pid already gone"
    rm -rf "$STATE"
    exit 0
fi

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
    # A branch checked out in the main working tree cannot also be checked out
    # in a worktree, and the whole point here is not to develop on the branch
    # the live symlink is following. So default to a sibling branch.
    CURRENT="$(git -C "$REPO" branch --show-current)"
    [[ -n "$CURRENT" ]] || die "detached HEAD; pass a branch name explicitly"
    BRANCH="nested/$CURRENT"
fi

command -v Hyprland >/dev/null || die "Hyprland not found"
command -v qs        >/dev/null || die "quickshell (qs) not found"
[[ -n "${WAYLAND_DISPLAY:-}" ]] || die "no WAYLAND_DISPLAY — this must run from inside your Wayland session"

# ── worktree ──────────────────────────────────────────────────────────
step "Worktree"
WT="$REPO/.worktrees/$BRANCH"
if [[ -d "$WT" ]]; then
    ok "reusing $WT"
elif git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$REPO" worktree add "$WT" "$BRANCH" >/dev/null
    ok "worktree for existing branch $BRANCH"
else
    git -C "$REPO" worktree add -b "$BRANCH" "$WT" >/dev/null
    ok "worktree for NEW branch $BRANCH"
fi

# ── shadow XDG tree ───────────────────────────────────────────────────
step "Shadow XDG tree"
SHADOW="$WT/.nested"
CONF="$SHADOW/config"
mkdir -p "$CONF/quickshell" "$CONF/illogical-impulse" \
         "$SHADOW/state/quickshell/user/generated" "$SHADOW/cache"

# The shell, from THIS worktree — never from the main checkout.
ln -sfn "$WT/quickshell" "$CONF/quickshell/openagentisland"
ok "quickshell -> $(realpath --relative-to="$REPO" "$WT")/quickshell"

# Seed the shell's settings from the repo's shipped overlay, so the nested
# session shows what a new user would get rather than this machine's tuning.
if [[ ! -f "$CONF/illogical-impulse/config.json" ]]; then
    # The shipped overlay carries no wallpaperPath on purpose — that value
    # belongs to a machine, not to the rice. The nested session needs one
    # anyway or it renders onto black, so point it at a vendored wallpaper.
    WALL="$(find "$WT/assets/wallpapers" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) | sort | head -1)"
    python3 - "$WT/config/illogical-impulse/config.json" \
              "$CONF/illogical-impulse/config.json" "$WALL" <<'SEED'
import json, sys
src, dst, wall = sys.argv[1:4]
cfg = json.load(open(src))
if wall:
    cfg.setdefault("background", {})["wallpaperPath"] = wall
json.dump(cfg, open(dst, "w"), indent=2)
SEED
    ok "seeded shell config${WALL:+ (wallpaper: $(basename "$WALL"))}"
fi

# Mark the shell as already greeted. Without this the first-run welcome dialog
# covers the whole desktop on every single launch, because the shadow state
# tree starts empty each time a worktree is created.
FIRST_RUN="$SHADOW/state/quickshell/user/first_run.txt"
mkdir -p "$(dirname "$FIRST_RUN")"
[[ -f "$FIRST_RUN" ]] || echo "greeted by dev/nested.sh" > "$FIRST_RUN"

# Generated colours are produced by matugen against a wallpaper. Copying them
# rather than linking means the nested shell has a palette to render with and
# still cannot write back into the live state directory.
LIVE_GEN="$HOME/.local/state/quickshell/user/generated"
if [[ -d "$LIVE_GEN" ]]; then
    cp -rn "$LIVE_GEN/." "$SHADOW/state/quickshell/user/generated/" 2>/dev/null || true
    ok "seeded generated colours (copy, not link)"
else
    info "no generated colours found — the shell may render with defaults"
fi

# ── launch ────────────────────────────────────────────────────────────
step "Launching nested Hyprland"
mkdir -p "$STATE"
LOG="$STATE/hyprland.log"

# Snapshot BEFORE starting: the nested window can appear in well under a
# second, and a snapshot taken afterwards would already contain it.
WINDOWS_BEFORE="$(hyprctl clients -j | jq -r '.[].address' | sort)"

env -u HYPRLAND_INSTANCE_SIGNATURE \
    XDG_CONFIG_HOME="$CONF" \
    XDG_STATE_HOME="$SHADOW/state" \
    XDG_CACHE_HOME="$SHADOW/cache" \
    WLR_BACKENDS=wayland \
    WLR_NO_HARDWARE_CURSORS=1 \
    Hyprland --config "$WT/dev/hypr-nested.lua" >"$LOG" 2>&1 &

NESTED_PID=$!
echo "$NESTED_PID" > "$STATE/pid"
info "pid $NESTED_PID, log $LOG"

# ── pin to workspace 1 ────────────────────────────────────────────────
# Matched by address rather than by a windowrule on class: the nested
# compositor's app_id varies between wlroots versions, and an address is exact.
step "Pinning to workspace $WORKSPACE"
addr=""
for _ in $(seq 1 60); do
    sleep 0.5
    kill -0 "$NESTED_PID" 2>/dev/null || { cat "$LOG" >&2; die "nested Hyprland exited — see log above"; }
    after="$(hyprctl clients -j | jq -r '.[].address' | sort)"
    addr="$(comm -13 <(echo "$WINDOWS_BEFORE") <(echo "$after") | head -1)"
    [[ -n "$addr" ]] && break
done

# Fallback: Hyprland's nested window is drawn by its wayland backend, which
# reports class "aquamarine". Used only if the diff came up empty, e.g. because
# a leftover session is already running.
if [[ -z "$addr" ]]; then
    addr="$(hyprctl clients -j | jq -r '.[] | select(.class == "aquamarine") | .address' | head -1)"
    [[ -n "$addr" ]] && info "matched by class (aquamarine) rather than by diff"
fi

[[ -n "$addr" ]] || die "nested window never appeared (30s); see $LOG"

# Hyprland 0.56 replaced the string dispatchers with a Lua API: `hyprctl
# dispatch movetoworkspacesilent 8,address:0x..` now fails to parse, because
# the arguments are spliced into a Lua call unquoted. Try the Lua form first
# and fall back to the classic one for older Hyprland.
if hyprctl eval "hl.dispatch(hl.dsp.window.move({workspace='$WORKSPACE', silent=true, window='address:$addr'}))" 2>/dev/null | grep -q '^ok'; then
    :
elif ! hyprctl dispatch movetoworkspacesilent "$WORKSPACE,address:$addr" >/dev/null 2>&1; then
    die "could not move the nested window to workspace $WORKSPACE"
fi

# Confirm rather than assume: a dispatcher that silently no-ops would otherwise
# leave the window sitting on top of whatever you were doing.
sleep 0.3
landed="$(hyprctl clients -j | jq -r --arg a "$addr" '.[] | select(.address == $a) | .workspace.id')"
[[ "$landed" == "$WORKSPACE" ]] || die "window is on workspace $landed, expected $WORKSPACE"

# Float and pin the size. Tiled, the host stretches the window to fill its
# slot and the capture size depends on whatever else is on the workspace.
hyprctl eval "hl.dispatch(hl.dsp.window.float({window='address:$addr', state='on'}))" >/dev/null 2>&1 || true
sleep 0.3
hyprctl eval "hl.dispatch(hl.dsp.window.resize({window='address:$addr', x=$NESTED_W, y=$NESTED_H}))" >/dev/null 2>&1 || true
sleep 0.4
size="$(hyprctl clients -j | jq -r --arg a "$addr" '.[] | select(.address == $a) | "\(.size[0])x\(.size[1])"')"
[[ "$size" == "${NESTED_W}x${NESTED_H}" ]] \
    && ok "sized ${NESTED_W}x${NESTED_H}" \
    || info "size is $size, wanted ${NESTED_W}x${NESTED_H} — screenshots will still work, just not at the canonical size"

echo "$addr" > "$STATE/address"
ok "window $addr -> workspace $WORKSPACE"

step "Ready"
info "look:      hyprctl dispatch workspace $WORKSPACE"
info "screenshot: dev/shot.sh <name>"
info "stop:       dev/nested.sh --stop"
