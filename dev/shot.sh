#!/usr/bin/env bash
#
# Capture the nested session's window.
#
#   dev/shot.sh notch-idle          -> dev/shots/notch-idle.png   (scratch)
#   dev/shot.sh notch-idle --docs   -> docs/screenshots/notch-idle.png
#
# Reads the window address recorded by dev/nested.sh rather than asking for a
# selection, so every capture of a given state has identical geometry and two
# runs can be compared pixel for pixel.
#
# Scratch by default, and --docs will not clobber an existing file without
# --force. docs/screenshots holds the curated README assets; a dev capture that
# happens to be called "desktop" would otherwise quietly destroy one of them.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${XDG_RUNTIME_DIR:-/tmp}/openagentisland-nested"
OUTDIR="$REPO/dev/shots"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

NAME="${1:-}"
[[ -n "$NAME" ]] || die "usage: dev/shot.sh <name> [--docs] [--force]"
shift || true

PUBLISH=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --docs)  PUBLISH=1 ;;
        --force) FORCE=1 ;;
        *) die "unknown option: $arg" ;;
    esac
done
(( PUBLISH )) && OUTDIR="$REPO/docs/screenshots"
command -v grim >/dev/null || die "grim not found"
command -v jq   >/dev/null || die "jq not found"
[[ -f "$STATE/address" ]] || die "no nested session running (start one: dev/nested.sh)"

ADDR="$(cat "$STATE/address")"
GEO="$(hyprctl clients -j | jq -r --arg a "$ADDR" \
    '.[] | select(.address == $a) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
[[ -n "$GEO" ]] || die "window $ADDR is gone — is the nested session still up?"

# The window must be on a visible workspace for the compositor to have pixels
# for it. Switching there and back is cheaper than compositing offscreen.
WS="$(hyprctl clients -j | jq -r --arg a "$ADDR" '.[] | select(.address == $a) | .workspace.id')"
CUR="$(hyprctl activeworkspace -j | jq -r '.id')"

mkdir -p "$OUTDIR"
OUT="$OUTDIR/$NAME.png"

if (( PUBLISH )) && [[ -e "$OUT" ]] && (( ! FORCE )); then
    die "$OUT already exists. It is probably a README asset. Pass --force if you really mean to replace it."
fi

if [[ "$WS" != "$CUR" ]]; then
    hyprctl dispatch workspace "$WS" >/dev/null
    sleep 0.4
fi
grim -g "$GEO" "$OUT"
if [[ "$WS" != "$CUR" ]]; then
    hyprctl dispatch workspace "$CUR" >/dev/null
fi

printf '\033[32m✓\033[0m %s  (%s)\n' "${OUT#"$REPO"/}" "$GEO"
