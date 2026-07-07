#!/usr/bin/env bash
# Install (or remove) a desktop entry + themed icon for the Agent Island launcher,
# so it shows up in your app launcher/grid with the right icon and can be opened
# without a terminal. Reversible:  install-app.sh        (install)
#                                  install-app.sh --uninstall
#
# NOTE: Quickshell hardcodes every window's app_id to "org.quickshell", so the
# island dock can't relaunch a *closed* qs --path app from a pinned icon. Launch
# Agent Island from the app grid (this entry) or a keybind instead. The dock shows
# the correct icon while it's running (handled in DockAppButton.qml).
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ENTRY="$REPO/quickshell/agentIsland.qml"
SRC_ICON="$REPO/quickshell/modules/ii/agentIsland/assets/logo-256.png"

APPS="$HOME/.local/share/applications"
DESKTOP="$APPS/agentisland.desktop"
ICONROOT="$HOME/.local/share/icons/hicolor"

uninstall() {
    rm -f "$DESKTOP"
    rm -f "$ICONROOT"/256x256/apps/agentisland.png "$ICONROOT"/128x128/apps/agentisland.png
    update-desktop-database "$APPS" 2>/dev/null || true
    echo "Removed Agent Island desktop entry + icon."
}

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "-u" ]]; then
    uninstall; exit 0
fi

[[ -f "$ENTRY" ]] || { echo "error: entry not found: $ENTRY" >&2; exit 1; }
[[ -f "$SRC_ICON" ]] || { echo "error: icon not found: $SRC_ICON" >&2; exit 1; }
command -v qs >/dev/null || echo "warning: 'qs' (quickshell) not on PATH; the entry's Exec assumes it is."

# install icon into the hicolor theme (256 + a 128 downscale if possible)
mkdir -p "$ICONROOT/256x256/apps" "$ICONROOT/128x128/apps"
cp "$SRC_ICON" "$ICONROOT/256x256/apps/agentisland.png"
if command -v magick >/dev/null; then
    magick "$SRC_ICON" -resize 128x128 "$ICONROOT/128x128/apps/agentisland.png"
else
    cp "$SRC_ICON" "$ICONROOT/128x128/apps/agentisland.png"
fi

# write the desktop entry (absolute Exec so it works from any launcher)
mkdir -p "$APPS"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Agent Island
GenericName=Project Session Launcher
Comment=Launch and manage Claude Code sessions per project
Exec=qs --path $ENTRY
Icon=agentisland
Terminal=false
Categories=Development;Utility;
Keywords=claude;agent;tmux;sessions;island;
StartupWMClass=org.quickshell
EOF

update-desktop-database "$APPS" 2>/dev/null || true
gtk-update-icon-cache -f -t "$ICONROOT" 2>/dev/null || true

echo "Installed Agent Island:"
echo "  desktop entry : $DESKTOP"
echo "  icon          : $ICONROOT/256x256/apps/agentisland.png"
echo "  launches      : qs --path $ENTRY"
echo "Search 'Agent Island' in your app launcher. (Undo: $0 --uninstall)"
