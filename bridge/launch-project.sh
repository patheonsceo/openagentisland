#!/usr/bin/env bash
# Agent Island — project session launcher.
#
# Sets up (or re-attaches to) a per-project tmux session running N Claude Code
# panes in a chosen permission mode, then opens a host terminal attached to it.
#
# tmux is the ENGINE: it owns persistence (detach/reattach survives terminal
# restarts) and the tiled layout. The host terminal is just a viewport that runs
# `tmux attach`, which makes this terminal-agnostic — re-clicking a project that
# already has a live session simply re-attaches instead of spawning duplicates.
#
# Warp note: Warp is single-instance and ignores `-e`/env on re-invocation, so it
# can't be scripted to run a command directly. For Warp we generate a Launch
# Configuration (~/.warp/launch_configurations/) whose pane runs `tmux attach`;
# kitty/alacritty attach directly and are the guaranteed one-click path.
#
# Usage:
#   launch-project.sh --dir PATH [options]
# Options:
#   --dir PATH         Project directory (required).
#   --name NAME        tmux session name (default: sanitized basename of --dir).
#   --sessions N       Number of Claude panes, tiled (default: 1).
#   --mode MODE        bypass|default|plan|acceptEdits (default: bypass).
#   --model MODEL      Optional `claude --model MODEL`.
#   --host HOST        warp|kitty|alacritty|none (default: kitty).
#   --setup CMD        Command to run in each pane before claude (repeatable).
#   --claude-bin BIN   Override the claude command (testing; default: claude).
#   --dry-run          Print the tmux/host commands without executing.
set -euo pipefail

# --- robustness + diagnostics ---
# GUI launchers (Hyprland exec/keybind) often hand us a minimal PATH; make the
# tools findable regardless, and log every invocation + exit so "nothing opened"
# is debuggable. Log: $XDG_RUNTIME_DIR/agentisland-launch.log
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin${PATH:+:$PATH}"
_LOG="${XDG_RUNTIME_DIR:-/tmp}/agentisland-launch.log"
_log() { printf '%s\n' "$*" >>"$_LOG" 2>/dev/null || true; }
_log "── $(date '+%F %T' 2>/dev/null) invoke: $*"
trap '_log "   exit code=$? (tmux=$(command -v tmux), kitty=$(command -v kitty))"' EXIT

DIR="" NAME="" SESSIONS=1 MODE="bypass" MODEL="" HOST="kitty" CLAUDE_BIN="${AGENTISLAND_CLAUDE_BIN:-claude}" DRY=0
SETUP=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)        DIR="$2"; shift 2 ;;
    --name)       NAME="$2"; shift 2 ;;
    --sessions)   SESSIONS="$2"; shift 2 ;;
    --mode)       MODE="$2"; shift 2 ;;
    --model)      MODEL="$2"; shift 2 ;;
    --host)       HOST="$2"; shift 2 ;;
    --setup)      SETUP+=("$2"); shift 2 ;;
    --claude-bin) CLAUDE_BIN="$2"; shift 2 ;;
    --dry-run)    DRY=1; shift ;;
    *) echo "launch-project: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ -n "$DIR" ]] || { echo "launch-project: --dir is required" >&2; exit 2; }
DIR="${DIR/#\~/$HOME}"
[[ -d "$DIR" ]] || { echo "launch-project: not a directory: $DIR" >&2; exit 2; }

# tmux session names can't contain '.' or ':' and dislike spaces — sanitize.
if [[ -z "$NAME" ]]; then NAME="$(basename "$DIR")"; fi
NAME="$(printf '%s' "$NAME" | tr ' .:/' '____' | tr -cd '[:alnum:]_-')"
[[ -n "$NAME" ]] || NAME="project"

[[ "$SESSIONS" =~ ^[0-9]+$ && "$SESSIONS" -ge 1 ]] || SESSIONS=1

# Resolve the per-pane claude invocation from the permission mode.
case "$MODE" in
  bypass)                CLAUDE_ARGS="--dangerously-skip-permissions" ;;
  default|plan|acceptEdits|bypassPermissions) CLAUDE_ARGS="--permission-mode $MODE" ;;
  *)                     CLAUDE_ARGS="--dangerously-skip-permissions" ;;
esac
[[ -n "$MODEL" ]] && CLAUDE_ARGS="$CLAUDE_ARGS --model $MODEL"
PANE_CMD="$CLAUDE_BIN $CLAUDE_ARGS"

run() { if [[ "$DRY" == 1 ]]; then printf 'DRY %s\n' "$*"; else "$@"; fi; }

session_exists() { [[ "$DRY" == 1 ]] && return 1; tmux has-session -t "=$NAME" 2>/dev/null; }

build_session() {
  # Run claude as each pane's START COMMAND rather than via send-keys: send-keys
  # races the shell's rc load (keys fire before the prompt is ready and are lost).
  # A start command has no such race. We append `exec $SHELL` so the pane drops to
  # an interactive shell — in the project dir — if claude exits, instead of closing.
  local shell="${SHELL:-/bin/bash}" pane_init="" s
  for s in "${SETUP[@]:-}"; do [[ -n "$s" ]] && pane_init+="$s; "; done
  local wrap="${pane_init}${PANE_CMD}; exec $shell"

  run tmux new-session -d -s "$NAME" -c "$DIR" "$wrap"
  local i
  for ((i = 1; i < SESSIONS; i++)); do
    run tmux split-window -t "$NAME" -c "$DIR" "$wrap"
    run tmux select-layout -t "$NAME" tiled
  done
  run tmux select-layout -t "$NAME" tiled
  run tmux select-pane -t "$NAME.0"
}

write_warp_config() {
  local cfgdir="$HOME/.warp/launch_configurations"
  local cfg="$cfgdir/agentisland-$NAME.yaml"
  [[ "$DRY" == 1 ]] && { echo "DRY write $cfg"; return; }
  mkdir -p "$cfgdir"
  # One tab, one pane, attached to the tmux session we just built.
  cat > "$cfg" <<YAML
---
name: "AgentIsland: $NAME"
windows:
  - tabs:
      - title: "$NAME"
        layout:
          cwd: "$DIR"
          commands:
            - exec: tmux attach -t "$NAME"
YAML
  echo "$cfg"
}

open_host() {
  local attach="tmux attach -t $NAME"
  _log "   open_host: host=$HOST name=$NAME dir=$DIR"
  case "$HOST" in
    kitty)     run setsid -f kitty --directory "$DIR" -e tmux attach -t "$NAME" ;;
    alacritty) run setsid -f alacritty --working-directory "$DIR" -e tmux attach -t "$NAME" ;;
    warp)
      local cfg; cfg="$(write_warp_config)"
      echo "Warp launch config written: $cfg"
      echo "Open it in Warp via the Command Palette → 'Open Launch Configuration',"
      echo "or bind it to a Warp shortcut. (Warp can't be launched-with-command from CLI.)"
      # Best-effort: surface a fresh Warp window for the user to pick it.
      run setsid -f warp-terminal >/dev/null 2>&1 || true
      ;;
    none)      echo "tmux session ready. Attach with:  $attach" ;;
    *)         echo "launch-project: unknown host '$HOST'" >&2; exit 2 ;;
  esac
}

if session_exists; then
  echo "Re-attaching to existing session: $NAME"
else
  echo "Creating session: $NAME  ($SESSIONS pane(s), mode=$MODE, host=$HOST)"
  build_session
fi
open_host
