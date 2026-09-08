#!/usr/bin/env bash
#
# OpenAgentIsland installer.
#
# Sets up the whole desktop in one run: the end-4 base (delegated to end-4's own
# installer rather than reimplemented — theirs is maintained, a copy here would
# rot), then every artifact listed in manifest.toml.
#
# This script is the front door: argument parsing, preflight, and the end-4
# base. WHAT gets installed and WHERE lives in manifest.toml, and the work is
# done by install/engine.py. Adding a config layer is a row in that table, not
# a change here.
#
# Everything it writes is backed up before the first change, so --uninstall puts
# the machine back and re-running is safe.
#
#   ./install.sh                    full install
#   ./install.sh --profile island   just the notch and shell
#   ./install.sh --skip-base        you already run end-4
#   ./install.sh --dry-run          print every action, change nothing
#   ./install.sh --status           show how the live system differs from the repo
#   ./install.sh --uninstall        restore the original backup
#   ./install.sh --help
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$REPO_DIR/install/engine.py"

PROFILE="full"
DRY_RUN=0
SKIP_BASE=0
DO_UNINSTALL=0
DO_STATUS=0
WITH_AGENT=0
WITH_VOICE=0
ASSUME_YES=0

# ── output ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
    C_RESET=""; C_DIM=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi
step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '  %s·%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '\n%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

confirm() {
    (( ASSUME_YES )) && return 0
    (( DRY_RUN )) && return 0
    local reply
    read -r -p "  $1 [y/N] " reply < /dev/tty || return 1
    [[ "$reply" =~ ^[Yy]$ ]]
}

usage() {
    sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'
    cat <<'USAGE_EOF'

Options:
  --profile P          full (default) or island
  --skip-base          Don't touch the end-4 base; assume it is already working
  --agent-hooks        Enable the Claude Code agent bridge hooks
  --voice              Print voice-dictation setup instructions
  --dry-run            Show every action without performing any of them
  --status             Report how the live system differs from the repo
  -y, --yes            Assume yes for all prompts (non-interactive)
  --uninstall          Restore the original backup
  -h, --help           This text
USAGE_EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)     PROFILE="${2:?--profile needs a value}"; shift ;;
        --profile=*)   PROFILE="${1#*=}" ;;
        --skip-base)   SKIP_BASE=1 ;;
        --agent-hooks) WITH_AGENT=1 ;;
        --voice)       WITH_VOICE=1 ;;
        --dry-run)     DRY_RUN=1 ;;
        --status)      DO_STATUS=1 ;;
        -y|--yes)      ASSUME_YES=1 ;;
        --uninstall)   DO_UNINSTALL=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) die "unknown option: $1  (try --help)" ;;
    esac
    shift
done

case "$PROFILE" in
    full|island) ;;
    *) die "unknown profile '$PROFILE' (expected: full, island)" ;;
esac

engine() {
    local cmd="$1"; shift
    local args=("$cmd" --repo "$REPO_DIR" "$@")
    (( DRY_RUN )) && args+=(--dry-run)
    python3 "$ENGINE" "${args[@]}"
}

# ── preflight ─────────────────────────────────────────────────────────
preflight() {
    step "Preflight"

    [[ "$(uname -s)" == "Linux" ]] || die "this installer is Linux-only"
    command -v pacman >/dev/null 2>&1 \
        || warn "pacman not found — this targets Arch-based systems (CachyOS, EndeavourOS, …). Continuing, but the base install will not work."

    local missing=()
    for c in git python3 tar zstd; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    (( ${#missing[@]} )) && die "missing required commands: ${missing[*]}"
    ok "git, python3, tar, zstd"

    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
        || die "python 3.11+ required (tomllib is used to read manifest.toml)"
    ok "python $(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"

    if command -v hyprctl >/dev/null 2>&1; then
        ok "hyprland $(hyprctl version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo present)"
    else
        info "hyprland not detected (fine if the base is about to be installed)"
    fi

    if command -v qs >/dev/null 2>&1; then
        ok "quickshell present"
    else
        info "quickshell not detected (installed by the end-4 base)"
    fi

    command -v matugen >/dev/null 2>&1 && ok "matugen present" \
        || info "matugen not detected (installed by the end-4 base; needed for traffic-light theming)"
}

base_present() {
    [[ -d "$HOME/.config/quickshell/ii" ]] || [[ -f "$HOME/.config/hypr/hyprland/variables.lua" ]]
}

install_base() {
    step "end-4 base"
    if base_present; then
        ok "already present — skipping"
        return 0
    fi
    warn "The end-4 / illogical-impulse base is not installed."
    warn "This installs Hyprland, Quickshell, fonts and dependencies, needs sudo,"
    warn "and takes a while. It runs end-4's OWN installer, not a copy."
    confirm "Clone and run end-4's installer now?" \
        || die "base required — install it yourself, then rerun with --skip-base"

    if (( DRY_RUN )); then
        info "would clone end-4/dots-hyprland and run its installer"
        return 0
    fi
    local tmp="${TMPDIR:-/tmp}/dots-hyprland-$$"
    git clone --depth 1 https://github.com/end-4/dots-hyprland.git "$tmp"
    info "handing over to end-4's installer; follow its prompts"
    ( cd "$tmp" && ./install.sh )
    ok "base installed"
}

install_agent_hooks() {
    (( WITH_AGENT )) || return 0
    step "Claude Code agent bridge"
    if command -v claude >/dev/null 2>&1 || [[ -f "$HOME/.claude/settings.json" ]]; then
        if (( DRY_RUN )); then
            info "would enable Claude Code hooks"
        else
            python3 "$REPO_DIR/bridge/install-hooks.py" enable
            ok "hooks enabled (disable with: python3 bridge/install-hooks.py disable)"
        fi
    else
        warn "Claude Code not detected — skipping hooks"
    fi
}

show_voice() {
    (( WITH_VOICE )) || return 0
    step "Voice dictation"
    info "Needs the external hyprvoice daemon + a Groq key."
    info "Full setup: $REPO_DIR/docs/voice-dictation.md"
}

# ── main ──────────────────────────────────────────────────────────────
main() {
    printf '%s\n' "${C_BOLD}OpenAgentIsland installer${C_RESET}"

    if (( DO_STATUS )); then
        engine status --profile "$PROFILE"
        exit 0
    fi

    if (( DO_UNINSTALL )); then
        engine uninstall
        ok "Restart your shell and Zen to see the change."
        exit 0
    fi

    (( DRY_RUN )) && warn "DRY RUN — nothing will be modified"

    preflight
    if (( SKIP_BASE )); then info "base skipped (--skip-base)"; else install_base; fi

    engine install --profile "$PROFILE"

    install_agent_hooks
    show_voice

    step "Done"
    info "Undo everything:  ./install.sh --uninstall"
    info "See what changed: ./install.sh --status"
    printf '\n  %sReload the shell:%s  pkill -x qs; setsid -f qs -c openagentisland\n' "$C_BOLD" "$C_RESET"
    printf '  %sRestart Zen%s to pick up its traffic lights.\n\n' "$C_BOLD" "$C_RESET"
}

main "$@"
