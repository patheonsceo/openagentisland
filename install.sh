#!/usr/bin/env bash
#
# OpenAgentIsland installer.
#
# Sets up the whole desktop in one run: the end-4 base (delegated to end-4's own
# installer rather than reimplemented — theirs is maintained, a copy here would
# rot), the Quickshell config, and the macOS layer (traffic lights, button
# layout, Zen chrome).
#
# Everything it writes is backed up first and wrapped in removal markers, so
# `--uninstall` puts the machine back and re-running is safe.
#
#   ./install.sh                 full install
#   ./install.sh --skip-base     you already run end-4
#   ./install.sh --dry-run       print every action, change nothing
#   ./install.sh --uninstall     restore from the most recent backup
#   ./install.sh --help
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/openagentisland-backups"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/openagentisland"

# Injected blocks are fenced so they can be found again exactly — for removal on
# uninstall, and so a second run replaces rather than duplicates them.
MARK_BEGIN="/* >>> openagentisland traffic lights >>> */"
MARK_END="/* <<< openagentisland traffic lights <<< */"

DRY_RUN=0
SKIP_BASE=0
DO_UNINSTALL=0
WITH_TRAFFIC=1
WITH_ZEN=1
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

# Every mutating action goes through this, so --dry-run is honest by
# construction rather than by remembering to check a flag at each call site.
run() {
    if (( DRY_RUN )); then
        printf '  %swould run:%s %s\n' "$C_DIM" "$C_RESET" "$*"
    else
        "$@"
    fi
}

confirm() {
    (( ASSUME_YES )) && return 0
    (( DRY_RUN )) && return 0
    local reply
    read -r -p "  $1 [y/N] " reply < /dev/tty || return 1
    [[ "$reply" =~ ^[Yy]$ ]]
}

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'
    cat <<'EOF'

Options:
  --skip-base          Don't touch the end-4 base; assume it is already working
  --no-traffic-lights  Skip GTK/Qt button layout and traffic-light styling
  --no-zen             Skip the Zen userChrome.css step
  --agent-hooks        Enable the Claude Code agent bridge hooks
  --voice              Print voice-dictation setup instructions
  --dry-run            Show every action without performing any of them
  -y, --yes            Assume yes for all prompts (non-interactive)
  --uninstall          Restore the most recent backup and remove injected blocks
  -h, --help           This text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-base)         SKIP_BASE=1 ;;
        --no-traffic-lights) WITH_TRAFFIC=0 ;;
        --no-zen)            WITH_ZEN=0 ;;
        --agent-hooks)       WITH_AGENT=1 ;;
        --voice)             WITH_VOICE=1 ;;
        --dry-run)           DRY_RUN=1 ;;
        -y|--yes)            ASSUME_YES=1 ;;
        --uninstall)         DO_UNINSTALL=1 ;;
        -h|--help)           usage; exit 0 ;;
        *) die "unknown option: $1  (try --help)" ;;
    esac
    shift
done

# ── backup helpers ────────────────────────────────────────────────────
# Mirrors the file's absolute path inside the backup dir, so restoring is a
# straight copy back and the manifest is human-readable.
backup_file() {
    local src="$1"
    [[ -e "$src" ]] || { info "no existing $src (nothing to back up)"; return 0; }
    local rel="${src#"$HOME"/}"
    local dst="$BACKUP_DIR/home/$rel"
    run mkdir -p "$(dirname "$dst")"
    run cp -a "$src" "$dst"
    (( DRY_RUN )) || echo "$src" >> "$BACKUP_DIR/manifest.txt"
    info "backed up $src"
}

# Replace between markers if present, else append. Idempotent by design: running
# the installer twice must not leave two copies of the CSS.
inject_block() {
    local target="$1" content_file="$2"
    run mkdir -p "$(dirname "$target")"
    [[ -e "$target" ]] || run touch "$target"
    if (( DRY_RUN )); then
        printf '  %swould inject%s %s -> %s\n' "$C_DIM" "$C_RESET" "$content_file" "$target"
        return 0
    fi
    python3 - "$target" "$content_file" "$MARK_BEGIN" "$MARK_END" <<'PY'
import sys
target, content_file, begin, end = sys.argv[1:5]
body = open(content_file).read().rstrip() + "\n"
block = f"\n{begin}\n{body}{end}\n"
try:
    s = open(target).read()
except FileNotFoundError:
    s = ""
if begin in s and end in s:
    head, rest = s.split(begin, 1)
    _, tail = rest.split(end, 1)
    s = head.rstrip("\n") + block + tail.lstrip("\n")
else:
    s = s.rstrip("\n") + "\n" + block
open(target, "w").write(s)
PY
    ok "injected into $target"
}

remove_block() {
    local target="$1"
    [[ -e "$target" ]] || return 0
    if (( DRY_RUN )); then
        printf '  %swould strip block from%s %s\n' "$C_DIM" "$C_RESET" "$target"
        return 0
    fi
    python3 - "$target" "$MARK_BEGIN" "$MARK_END" <<'PY'
import sys
target, begin, end = sys.argv[1:4]
s = open(target).read()
if begin in s and end in s:
    head, rest = s.split(begin, 1)
    _, tail = rest.split(end, 1)
    open(target, "w").write(head.rstrip("\n") + "\n" + tail.lstrip("\n"))
    print(f"  stripped block from {target}")
PY
}

# ── preflight ─────────────────────────────────────────────────────────
HYPR_CONFIG_STYLE="unknown"   # lua | legacy
ZEN_PROFILE=""

detect_hypr_config_style() {
    if [[ -f "$HOME/.config/hypr/hyprland/variables.lua" ]]; then
        HYPR_CONFIG_STYLE="lua"
    elif [[ -f "$HOME/.config/hypr/hyprland/variables.conf" ]]; then
        HYPR_CONFIG_STYLE="legacy"
    fi
}

# Which Zen profile is actually in use. profiles.ini can list several and the
# Default= key is not always the live one; the running instance holds
# .parentlock, so prefer that and fall back to the ini.
detect_zen_profile() {
    local base="$HOME/.config/zen"
    [[ -d "$base" ]] || return 0
    local p
    for p in "$base"/*/; do
        [[ -e "$p/.parentlock" ]] && { ZEN_PROFILE="${p%/}"; return 0; }
    done
    if [[ -f "$base/profiles.ini" ]]; then
        local rel
        rel="$(awk -F= '/^\[Install/{ins=1} ins&&/^Default=/{print $2; exit}' "$base/profiles.ini" || true)"
        [[ -z "$rel" ]] && rel="$(awk -F= '/^Path=/{p=$2} /^Default=1/{print p; exit}' "$base/profiles.ini" || true)"
        [[ -n "$rel" && -d "$base/$rel" ]] && ZEN_PROFILE="$base/$rel"
    fi
}

preflight() {
    step "Preflight"

    [[ "$(uname -s)" == "Linux" ]] || die "this installer is Linux-only"
    command -v pacman >/dev/null 2>&1 \
        || warn "pacman not found — this targets Arch-based systems (CachyOS, EndeavourOS, …). Continuing, but the base install will not work."

    local missing=()
    for c in git python3; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
    (( ${#missing[@]} )) && die "missing required commands: ${missing[*]}"
    ok "git, python3"

    if command -v hyprctl >/dev/null 2>&1; then
        ok "hyprland $(hyprctl version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo present)"
    else
        info "hyprland not detected (fine if the base is about to be installed)"
    fi

    if command -v qs >/dev/null 2>&1; then
        ok "quickshell $(qs --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo present)"
    else
        info "quickshell not detected (installed by the end-4 base)"
    fi

    command -v matugen >/dev/null 2>&1 && ok "matugen $(matugen --version 2>/dev/null | awk '{print $2}')" \
        || info "matugen not detected (installed by the end-4 base; needed for traffic-light theming)"

    detect_hypr_config_style
    case "$HYPR_CONFIG_STYLE" in
        lua)    ok "hyprland config: Lua (hl.dsp.* dispatch)" ;;
        legacy) ok "hyprland config: legacy .conf" ;;
        *)      info "hyprland config style not detected yet" ;;
    esac

    detect_zen_profile
    [[ -n "$ZEN_PROFILE" ]] && ok "zen profile: ${ZEN_PROFILE/#$HOME/\~}" \
        || info "no Zen profile found (its traffic lights will be skipped)"
}

# ── phases ────────────────────────────────────────────────────────────
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
    confirm "Clone and run end-4's installer now?" || die "base required — install it yourself, then rerun with --skip-base"

    local tmp="${TMPDIR:-/tmp}/dots-hyprland-$STAMP"
    run git clone --depth 1 https://github.com/end-4/dots-hyprland.git "$tmp"
    info "handing over to end-4's installer; follow its prompts"
    if (( DRY_RUN )); then
        printf '  %swould run:%s (cd %s && ./install.sh)\n' "$C_DIM" "$C_RESET" "$tmp"
    else
        ( cd "$tmp" && ./install.sh )
    fi
    ok "base installed"
}

install_shell() {
    step "OpenAgentIsland shell"
    local link="$HOME/.config/quickshell/openagentisland"
    run mkdir -p "$HOME/.config/quickshell"

    if [[ -L "$link" ]]; then
        local cur; cur="$(readlink -f "$link" || true)"
        if [[ "$cur" == "$(readlink -f "$REPO_DIR/quickshell")" ]]; then
            ok "config symlink already points here"
        else
            backup_file "$link"
            run rm "$link"
            run ln -s "$REPO_DIR/quickshell" "$link"
            ok "repointed config symlink"
        fi
    elif [[ -e "$link" ]]; then
        backup_file "$link"
        die "$link exists and is not a symlink — backed up; move it aside and rerun"
    else
        run ln -s "$REPO_DIR/quickshell" "$link"
        ok "linked $link -> $REPO_DIR/quickshell"
    fi

    # Point end-4 at this config.
    local varfile
    if [[ "$HYPR_CONFIG_STYLE" == "lua" ]]; then
        varfile="$HOME/.config/hypr/hyprland/variables.lua"
        if [[ -f "$varfile" ]]; then
            backup_file "$varfile"
            if (( DRY_RUN )); then
                info "would set qsConfig -> openagentisland in variables.lua"
            elif grep -q 'qsConfig' "$varfile"; then
                sed -i 's|hl\.env("qsConfig",[[:space:]]*"[^"]*")|hl.env("qsConfig", "openagentisland")|' "$varfile"
                ok "qsConfig -> openagentisland"
            else
                printf '\nhl.env("qsConfig", "openagentisland")\n' >> "$varfile"
                ok "qsConfig appended"
            fi
        fi
    elif [[ "$HYPR_CONFIG_STYLE" == "legacy" ]]; then
        varfile="$HOME/.config/hypr/hyprland/variables.conf"
        if [[ -f "$varfile" ]]; then
            backup_file "$varfile"
            if (( DRY_RUN )); then
                info "would set qsConfig -> openagentisland in variables.conf"
            elif grep -q 'qsConfig' "$varfile"; then
                sed -i 's|^[[:space:]]*env[[:space:]]*=[[:space:]]*qsConfig,.*|env = qsConfig,openagentisland|' "$varfile"
                ok "qsConfig -> openagentisland"
            else
                printf '\nenv = qsConfig,openagentisland\n' >> "$varfile"
                ok "qsConfig appended"
            fi
        fi
    else
        warn "could not find variables.lua/.conf — set qsConfig to 'openagentisland' yourself"
    fi
}

install_traffic_lights() {
    (( WITH_TRAFFIC )) || { info "traffic lights skipped (--no-traffic-lights)"; return 0; }
    step "Traffic lights — button layout"

    local f
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        backup_file "$f"
        run mkdir -p "$(dirname "$f")"
        if (( DRY_RUN )); then
            info "would set gtk-decoration-layout in $f"
        else
            [[ -f "$f" ]] || printf '[Settings]\n' > "$f"
            grep -q '^\[Settings\]' "$f" || sed -i '1i [Settings]' "$f"
            if grep -q '^gtk-decoration-layout=' "$f"; then
                sed -i 's|^gtk-decoration-layout=.*|gtk-decoration-layout=close,minimize,maximize:|' "$f"
            else
                # after the [Settings] header, not blindly at EOF — the file may
                # have other sections below.
                sed -i '/^\[Settings\]/a gtk-decoration-layout=close,minimize,maximize:' "$f"
            fi
            ok "$(basename "$(dirname "$f")")/settings.ini"
        fi
    done

    # gsettings wins over settings.ini for apps that read it, so set both.
    if command -v gsettings >/dev/null 2>&1; then
        (( DRY_RUN )) || gsettings get org.gnome.desktop.wm.preferences button-layout \
            > "$BACKUP_DIR/gsettings-button-layout.txt" 2>/dev/null || true
        run gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'
        ok "gsettings button-layout"
    fi

    # Qt/KDE decorated apps: X close, I minimize, A maximize.
    local kg="$HOME/.config/kdeglobals"
    backup_file "$kg"
    if (( DRY_RUN )); then
        info "would set ButtonsOnLeft=XIA in kdeglobals"
    else
        python3 - "$kg" <<'PY'
import os, re, sys
p = sys.argv[1]
s = open(p).read() if os.path.exists(p) else ""
if '[org.kde.kdecoration2]' in s:
    def fix(m):
        blk = re.sub(r'Buttons(OnLeft|OnRight)=.*\n?', '', m.group(1))
        return blk.rstrip('\n') + '\nButtonsOnLeft=XIA\nButtonsOnRight=\n'
    s = re.sub(r'(\[org\.kde\.kdecoration2\][^\[]*)', fix, s, count=1)
else:
    s = s.rstrip('\n') + '\n\n[org.kde.kdecoration2]\nButtonsOnLeft=XIA\nButtonsOnRight=\n'
open(p, 'w').write(s)
PY
        ok "kdeglobals ButtonsOnLeft=XIA"
    fi

    step "Traffic lights — styling"
    # Into the matugen TEMPLATES. ~/.config/gtk-*/gtk.css is generated output and
    # is rewritten on every wallpaper change; anything written there is lost.
    local tpl3="$HOME/.config/matugen/templates/gtk-3.0/gtk.css"
    local tpl4="$HOME/.config/matugen/templates/gtk-4.0/gtk.css"
    if [[ -f "$tpl3" || -f "$tpl4" ]]; then
        [[ -f "$tpl3" ]] && { backup_file "$tpl3"; inject_block "$tpl3" "$REPO_DIR/install/traffic-lights/gtk-3.0.css"; }
        [[ -f "$tpl4" ]] && { backup_file "$tpl4"; inject_block "$tpl4" "$REPO_DIR/install/traffic-lights/gtk-4.0.css"; }
        if command -v matugen >/dev/null 2>&1; then
            local wall
            wall="$(python3 - <<'PY'
import json, os
try:
    d = json.load(open(os.path.expanduser('~/.config/illogical-impulse/config.json')))
    print(d.get('background', {}).get('wallpaperPath', ''))
except Exception:
    print('')
PY
)"
            if [[ -n "$wall" && -f "$wall" ]]; then
                run matugen --source-color-index 0 image "$wall"
                ok "regenerated gtk.css from templates"
            else
                warn "no wallpaper found — change your wallpaper once to regenerate gtk.css"
            fi
        fi
    else
        warn "matugen templates not found — skipping traffic-light CSS (is the end-4 base installed?)"
    fi
}

install_zen() {
    (( WITH_TRAFFIC )) || return 0
    (( WITH_ZEN )) || { info "zen skipped (--no-zen)"; return 0; }
    [[ -n "$ZEN_PROFILE" ]] || { info "no Zen profile — skipping"; return 0; }
    step "Traffic lights — Zen"

    local chrome="$ZEN_PROFILE/chrome/userChrome.css"
    local userjs="$ZEN_PROFILE/user.js"
    backup_file "$chrome"
    backup_file "$userjs"
    inject_block "$chrome" "$REPO_DIR/install/traffic-lights/zen-userChrome.css"

    if (( DRY_RUN )); then
        info "would enable toolkit.legacyUserProfileCustomizations.stylesheets"
    else
        run mkdir -p "$(dirname "$userjs")"
        touch "$userjs"
        if grep -q 'legacyUserProfileCustomizations' "$userjs"; then
            ok "userChrome pref already enabled"
        else
            printf '\n// Required for chrome/userChrome.css to be read at all. (openagentisland)\nuser_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);\n' >> "$userjs"
            ok "enabled userChrome pref"
        fi
    fi
    warn "Zen reads these only at startup — restart Zen to see the traffic lights"
}

install_agent_hooks() {
    (( WITH_AGENT )) || return 0
    step "Claude Code agent bridge"
    if command -v claude >/dev/null 2>&1 || [[ -f "$HOME/.claude/settings.json" ]]; then
        backup_file "$HOME/.claude/settings.json"
        run python3 "$REPO_DIR/bridge/install-hooks.py" enable
        ok "hooks enabled (disable with: python3 bridge/install-hooks.py disable)"
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

# ── uninstall ─────────────────────────────────────────────────────────
do_uninstall() {
    step "Uninstall"
    local latest
    latest="$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | tail -1 || true)"
    [[ -n "$latest" ]] || die "no backup found under $BACKUP_ROOT"
    latest="${latest%/}"
    info "restoring from $latest"

    # Strip injected blocks first: those files may legitimately have changed
    # since install (matugen rewrites, user edits), so surgically removing our
    # fenced block is safer than stamping the whole file back.
    remove_block "$HOME/.config/matugen/templates/gtk-3.0/gtk.css"
    remove_block "$HOME/.config/matugen/templates/gtk-4.0/gtk.css"
    detect_zen_profile
    [[ -n "$ZEN_PROFILE" ]] && remove_block "$ZEN_PROFILE/chrome/userChrome.css"

    if [[ -f "$latest/manifest.txt" ]]; then
        local f rel src
        while IFS= read -r f; do
            rel="${f#"$HOME"/}"
            src="$latest/home/$rel"
            if [[ -e "$src" ]]; then
                # Skip the two we just surgically cleaned.
                case "$f" in
                    */matugen/templates/gtk-*.0/gtk.css|*/chrome/userChrome.css) continue ;;
                esac
                run cp -a "$src" "$f"
                info "restored $f"
            fi
        done < "$latest/manifest.txt"
    fi

    if [[ -f "$latest/gsettings-button-layout.txt" ]] && command -v gsettings >/dev/null 2>&1; then
        local bl; bl="$(tr -d "'\n" < "$latest/gsettings-button-layout.txt")"
        [[ -n "$bl" ]] && { run gsettings set org.gnome.desktop.wm.preferences button-layout "$bl"; ok "gsettings restored"; }
    fi

    ok "uninstalled. Restart your shell and Zen to see the change."
    info "The Quickshell config symlink and qsConfig were restored if they were backed up."
}

# ── main ──────────────────────────────────────────────────────────────
main() {
    printf '%s\n' "${C_BOLD}OpenAgentIsland installer${C_RESET}"
    (( DRY_RUN )) && warn "DRY RUN — nothing will be modified"

    if (( DO_UNINSTALL )); then
        detect_hypr_config_style
        do_uninstall
        exit 0
    fi

    run mkdir -p "$BACKUP_DIR" "$STATE_DIR"
    (( DRY_RUN )) || : > "$BACKUP_DIR/manifest.txt"

    preflight
    (( SKIP_BASE )) && info "base skipped (--skip-base)" || install_base
    # The base install brings hyprland/matugen into existence, so re-detect.
    detect_hypr_config_style
    detect_zen_profile
    install_shell
    install_traffic_lights
    install_zen
    install_agent_hooks
    show_voice

    step "Done"
    ok "backup: ${BACKUP_DIR/#$HOME/\~}"
    info "Undo everything:  ./install.sh --uninstall"
    printf '\n  %sReload the shell:%s  pkill -x qs; setsid -f qs -c openagentisland\n' "$C_BOLD" "$C_RESET"
    printf '  %sRestart Zen%s to pick up its traffic lights.\n\n' "$C_BOLD" "$C_RESET"
}

main "$@"
