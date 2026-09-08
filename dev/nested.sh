#!/usr/bin/env bash
#
# Launch a nested Hyprland running this repo's shell from a git worktree,
# pinned to workspace 8.
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
WORKSPACE=8
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
[[ -f "$CONF/illogical-impulse/config.json" ]] \
    || cp "$WT/config/illogical-impulse/config.json" "$CONF/illogical-impulse/config.json"

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

env -u HYPRLAND_INSTANCE_SIGNATURE \
    XDG_CONFIG_HOME="$CONF" \
    XDG_STATE_HOME="$SHADOW/state" \
    XDG_CACHE_HOME="$SHADOW/cache" \
    WLR_BACKENDS=wayland \
    WLR_NO_HARDWARE_CURSORS=1 \
    Hyprland --config "$WT/dev/hypr-nested.conf" >"$LOG" 2>&1 &

NESTED_PID=$!
echo "$NESTED_PID" > "$STATE/pid"
info "pid $NESTED_PID, log $LOG"

# ── pin to workspace 8 ────────────────────────────────────────────────
# Matched by address rather than by a windowrule on class: the nested
# compositor's app_id varies between wlroots versions, and an address is exact.
step "Pinning to workspace $WORKSPACE"
before="$(hyprctl clients -j | jq -r '.[].address' | sort)"
addr=""
for _ in $(seq 1 60); do
    sleep 0.5
    kill -0 "$NESTED_PID" 2>/dev/null || { cat "$LOG" >&2; die "nested Hyprland exited — see log above"; }
    after="$(hyprctl clients -j | jq -r '.[].address' | sort)"
    addr="$(comm -13 <(echo "$before") <(echo "$after") | head -1)"
    [[ -n "$addr" ]] && break
done
[[ -n "$addr" ]] || die "nested window never appeared (30s); see $LOG"

hyprctl dispatch movetoworkspacesilent "$WORKSPACE,address:$addr" >/dev/null
echo "$addr" > "$STATE/address"
ok "window $addr -> workspace $WORKSPACE"

step "Ready"
info "look:      hyprctl dispatch workspace $WORKSPACE"
info "screenshot: dev/shot.sh <name>"
info "stop:       dev/nested.sh --stop"
