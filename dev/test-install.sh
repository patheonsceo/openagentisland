#!/usr/bin/env bash
#
# Round-trip the installer against a scratch HOME.
#
# A nested compositor tests the SHELL; it says nothing about whether the
# installer works, and the installer cannot be tested against a real home
# directory without installing into it. So this points HOME at a throwaway
# directory and exercises install -> verify -> uninstall end to end.
#
# The assertions come from the manifest, so every row added is covered here
# automatically. This is the round-trip proof that --uninstall works, which is
# the promise the whole installer rests on.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d -t oai-testinstall-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

# gsettings goes through dconf over D-Bus, which is scoped to the SESSION and
# not to $HOME. Without this the test would reconfigure the real desktop it is
# running on, scratch HOME or not. The memory backend keeps it contained.
export GSETTINGS_BACKEND=memory

echo "repo:         $REPO"
echo "scratch HOME: $SCRATCH"
echo

# A pre-existing config the installer must merge into rather than clobber.
# These two values stand in for everything that belongs to the machine and not
# to the rice: where their wallpaper is, and anything personal.
mkdir -p "$SCRATCH/.config/illogical-impulse"
cat > "$SCRATCH/.config/illogical-impulse/config.json" <<'JSON'
{
  "background": { "wallpaperPath": "/their/wallpaper.jpg" },
  "personal": { "keep": "me" },
  "dock": { "enable": false }
}
JSON

# A file we inject into that already has unrelated content, to prove the fence
# does not eat what surrounds it.
mkdir -p "$SCRATCH/.config/matugen/templates/gtk-3.0"
printf '/* their own css */\n.custom { color: red; }\n' \
    > "$SCRATCH/.config/matugen/templates/gtk-3.0/gtk.css"

step() { printf '\n\033[34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

step "install --profile full"
HOME="$SCRATCH" python3 "$REPO/install/engine.py" install --repo "$REPO" --profile full

step "verify"
HOME="$SCRATCH" python3 "$REPO/install/engine.py" verify --repo "$REPO" --profile full

step "install again (idempotency)"
HOME="$SCRATCH" python3 "$REPO/install/engine.py" install --repo "$REPO" --profile full
cp "$SCRATCH/.config/matugen/templates/gtk-3.0/gtk.css" "$SCRATCH/.after-second-install"

step "assertions"
python3 - "$SCRATCH" <<'PY'
import json, os, sys
home = sys.argv[1]
failed = []
def check(name, cond):
    print(f"  {'ok  ' if cond else 'FAIL'} {name}")
    if not cond:
        failed.append(name)

cfg = json.load(open(f"{home}/.config/illogical-impulse/config.json"))
check("their wallpaper survived the merge",
      cfg["background"]["wallpaperPath"] == "/their/wallpaper.jpg")
check("their personal settings survived",
      cfg.get("personal", {}).get("keep") == "me")
check("an owned key was actually written",
      cfg.get("dock", {}).get("enable") is True)

css = open(f"{home}/.config/matugen/templates/gtk-3.0/gtk.css").read()
check("injection kept their existing css", ".custom { color: red; }" in css)
check("injection added our block", "openagentisland" in css)
check("exactly one block after two installs",
      css.count(">>> openagentisland") == 1)

link = f"{home}/.config/quickshell/openagentisland"
check("shell symlink exists", os.path.islink(link))

check("fonts landed", os.path.isdir(f"{home}/.local/share/fonts"))

gtk3 = open(f"{home}/.config/gtk-3.0/settings.ini").read()
check("gtk decoration layout set", "close,minimize,maximize:" in gtk3)

sys.exit(1 if failed else 0)
PY

step "uninstall"
HOME="$SCRATCH" python3 "$REPO/install/engine.py" uninstall --repo "$REPO"

step "post-uninstall assertions"
python3 - "$SCRATCH" <<'PY'
import json, os, sys
home = sys.argv[1]
failed = []
def check(name, cond):
    print(f"  {'ok  ' if cond else 'FAIL'} {name}")
    if not cond:
        failed.append(name)

cfg = json.load(open(f"{home}/.config/illogical-impulse/config.json"))
check("config.json restored exactly",
      cfg == {"background": {"wallpaperPath": "/their/wallpaper.jpg"},
              "personal": {"keep": "me"},
              "dock": {"enable": False}})

css = open(f"{home}/.config/matugen/templates/gtk-3.0/gtk.css").read()
check("our block is gone", "openagentisland" not in css)
check("their css survived uninstall", ".custom { color: red; }" in css)

check("shell symlink removed",
      not os.path.lexists(f"{home}/.config/quickshell/openagentisland"))

sys.exit(1 if failed else 0)
PY

printf '\n\033[32mround-trip PASSED\033[0m\n'
