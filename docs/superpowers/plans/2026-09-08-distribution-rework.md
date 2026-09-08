# Distribution Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn openagentisland from a Quickshell config into a whole desktop that installs from one clone and one script.

**Architecture:** A declarative `manifest.toml` lists every installable artifact as a row (source, destination, mode). `install/engine.py` walks it. Install, dry-run, uninstall and status all derive from the same table, so they cannot disagree with each other and adding a config layer is a row rather than new imperative code in three places.

**Tech Stack:** Python 3.11+ (`tomllib` is stdlib — no TOML dependency), bash, `tar`/`zstd`, `grim`, `hyprctl`. No pytest: this repo's test convention is a standalone script of asserts that exits non-zero, per `bridge/test_safety.py`.

**Spec:** `docs/superpowers/specs/2026-09-08-openagentisland-distribution-design.md`

## Global Constraints

- **Never write outside the repo during development.** The one runtime exception is the existing `~/.config/quickshell/openagentisland` symlink. Tests write only to a scratch `$HOME`.
- **`quickshell/` must stay at the repo root.** The live symlink tracks `main`; moving the directory breaks the running desktop on the next pull.
- **Never touch `~/.config/quickshell/ii/`** — that is the user's live end-4 desktop.
- **The nested test session pins to workspace 8.**
- **Python 3.11+** for `tomllib`. Target is 3.14.7 as installed.
- **No new runtime dependencies.** `git`, `python3` and coreutils only, matching what `install.sh` already requires.
- **Every mutating action goes through one `run()`-equivalent** so `--dry-run` is honest by construction, not by remembering to check a flag.
- Vendored fonts: Google Sans Flex, SF Pro Display, Liga SF Mono Nerd Font. **Only these three.**
- Vendored icons: WhiteSur and WhiteSur-dark, as a zstd tarball, never loose.
- **No hardware-specific script ships in any form.**

---

## File Structure

| File | Responsibility |
|---|---|
| `manifest.toml` | The artifact table. Data only, no logic. |
| `install/engine.py` | Loads and validates the manifest; owns the six modes; owns backup/restore. |
| `install/paths.py` | Dotted-path get/set/has on nested dicts, and `~` expansion. Pure functions, no I/O. |
| `install/textblock.py` | Fenced-marker injection and removal. Pure string functions, no I/O. |
| `install/test_engine.py` | Unit tests for the pure logic above. No filesystem. |
| `install.sh` | Argument parsing, preflight, and the call into the engine. Keeps existing detection helpers. |
| `dev/test-install.sh` | Round-trip install/uninstall against a scratch `$HOME`. |
| `dev/nested.sh` | Worktree + shadow XDG + nested Hyprland on workspace 8. |
| `dev/shot.sh` | Deterministic capture of the nested window. |
| `dev/hypr-nested.conf` | Nested compositor config, moved in from `~/.config/hypr-nested/`. |

`paths.py` and `textblock.py` are separate from `engine.py` because they are pure and are the parts most worth testing exhaustively. Keeping them out of the module that touches the filesystem means their tests need no scratch directory and no mocking.

---

### Task 1: Dotted-path helpers

**Files:**
- Create: `install/paths.py`
- Test: `install/test_engine.py`

**Interfaces:**
- Produces: `has_path(obj: dict, path: str) -> bool`, `get_path(obj: dict, path: str)`, `set_path(obj: dict, path: str, value) -> None`, `expand_dest(dest: str, home: str) -> str`

- [ ] **Step 1: Write the failing tests**

```python
#!/usr/bin/env python3
"""Unit tests for the installer engine's pure logic. Run: python3 install/test_engine.py"""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

FAILED = []
def check(name, cond):
    if cond: print(f"  ok   {name}")
    else:    print(f"  FAIL {name}"); FAILED.append(name)

from paths import has_path, get_path, set_path, expand_dest

def test_paths():
    print("paths")
    d = {"a": {"b": {"c": 1}}, "top": 2}
    check("get nested", get_path(d, "a.b.c") == 1)
    check("get top", get_path(d, "top") == 2)
    check("has nested", has_path(d, "a.b.c") is True)
    check("has missing leaf", has_path(d, "a.b.zzz") is False)
    check("has missing branch", has_path(d, "nope.deep") is False)
    check("get missing returns None", get_path(d, "nope.deep") is None)
    # set must create intermediate dicts
    e = {}
    set_path(e, "x.y.z", 9)
    check("set creates branches", e == {"x": {"y": {"z": 9}}})
    # set must not clobber siblings
    f = {"x": {"keep": 1}}
    set_path(f, "x.new", 2)
    check("set keeps siblings", f == {"x": {"keep": 1, "new": 2}})
    # a scalar in the way must not raise
    g = {"x": 5}
    check("has through scalar is False", has_path(g, "x.y") is False)

def test_expand():
    print("expand_dest")
    check("tilde", expand_dest("~/.config/foo", "/home/u") == "/home/u/.config/foo")
    check("bare tilde", expand_dest("~", "/home/u") == "/home/u")
    check("absolute untouched", expand_dest("/etc/x", "/home/u") == "/etc/x")
    check("no mid-string expansion", expand_dest("/a/~/b", "/home/u") == "/a/~/b")

if __name__ == "__main__":
    test_paths(); test_expand()
    print(f"\n{'FAILED: ' + ', '.join(FAILED) if FAILED else 'all passed'}")
    sys.exit(1 if FAILED else 0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 install/test_engine.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'paths'`

- [ ] **Step 3: Implement**

```python
"""Pure path helpers. No filesystem access — keep it that way."""

def _walk(obj, parts):
    for p in parts:
        if not isinstance(obj, dict) or p not in obj:
            return None, False
        obj = obj[p]
    return obj, True

def has_path(obj, path):
    return _walk(obj, path.split("."))[1]

def get_path(obj, path):
    return _walk(obj, path.split("."))[0]

def set_path(obj, path, value):
    parts = path.split(".")
    for p in parts[:-1]:
        if not isinstance(obj.get(p), dict):
            obj[p] = {}
        obj = obj[p]
    obj[parts[-1]] = value

def expand_dest(dest, home):
    """Only a leading ~ expands. A ~ anywhere else is a literal directory name."""
    if dest == "~":
        return home
    if dest.startswith("~/"):
        return os.path.join(home, dest[2:])
    return dest

import os  # noqa: E402  (kept at the bottom so the pure functions read first)
```

- [ ] **Step 4: Run to verify it passes**

Run: `python3 install/test_engine.py`
Expected: PASS, all `ok`

- [ ] **Step 5: Commit**

```bash
git add install/paths.py install/test_engine.py
git commit -m "Add dotted-path helpers for the installer engine"
```

---

### Task 2: JSON merge that only writes owned keys

**Files:**
- Create: `install/jsonmerge.py`
- Modify: `install/test_engine.py`

**Interfaces:**
- Consumes: `has_path`, `get_path`, `set_path` from Task 1
- Produces: `merge_owned(base: dict, overlay: dict, keys: list[str]) -> dict`

This is the mode that can destroy someone's configuration. `illogical-impulse/config.json` is 17 KB of rice settings mixed with end-4 defaults and per-machine values. Only the key paths the rice declares ownership of may be written.

- [ ] **Step 1: Write the failing tests**

Append to `install/test_engine.py`, and add `test_merge()` to the `__main__` block:

```python
from jsonmerge import merge_owned

def test_merge():
    print("merge_owned")
    base = {"background": {"wallpaperPath": "/home/them/pic.jpg", "mode": "fill"},
            "dock": {"enable": False}, "personal": {"name": "them"}}
    overlay = {"background": {"wallpaperPath": "/repo/wall.jpg", "mode": "fit"},
               "dock": {"enable": True}, "personal": {"name": "me"}}

    out = merge_owned(base, overlay, ["dock.enable"])
    check("owned key written", out["dock"]["enable"] is True)
    check("unowned sibling kept", out["background"]["wallpaperPath"] == "/home/them/pic.jpg")
    check("unowned branch kept", out["personal"]["name"] == "them")
    check("base not mutated", base["dock"]["enable"] is False)

    out2 = merge_owned(base, overlay, ["background.mode", "dock.enable"])
    check("two owned keys", out2["background"]["mode"] == "fit" and out2["dock"]["enable"] is True)
    check("wallpaper still theirs", out2["background"]["wallpaperPath"] == "/home/them/pic.jpg")

    # A key the overlay does not define must leave base alone, not write None.
    out3 = merge_owned(base, overlay, ["dock.missingKey"])
    check("absent overlay key is a no-op", "missingKey" not in out3["dock"])

    # A key absent from base must be created.
    out4 = merge_owned({}, {"a": {"b": 1}}, ["a.b"])
    check("creates missing branch", out4 == {"a": {"b": 1}})

    # Nested values are deep-copied, not aliased.
    ov = {"x": {"list": [1, 2]}}
    out5 = merge_owned({}, ov, ["x.list"])
    out5["x"]["list"].append(3)
    check("deep copied", ov["x"]["list"] == [1, 2])
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 install/test_engine.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'jsonmerge'`

- [ ] **Step 3: Implement**

```python
"""Merge only the keys the rice declares it owns.

Copying a whole config over someone's file destroys their wallpaper path,
their monitor layout and their preferences. Ownership is explicit and narrow.
"""
import copy
from paths import has_path, get_path, set_path

def merge_owned(base, overlay, keys):
    out = copy.deepcopy(base)
    for k in keys:
        if has_path(overlay, k):
            set_path(out, k, copy.deepcopy(get_path(overlay, k)))
    return out
```

- [ ] **Step 4: Run to verify it passes**

Run: `python3 install/test_engine.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install/jsonmerge.py install/test_engine.py
git commit -m "Merge only the config keys the rice owns"
```

---

### Task 3: Fenced-block injection

**Files:**
- Create: `install/textblock.py`
- Modify: `install/test_engine.py`

**Interfaces:**
- Produces: `inject(text: str, body: str, begin: str, end: str) -> str`, `strip(text: str, begin: str, end: str) -> str`

Ports the Python already embedded as a heredoc inside `install.sh` into a tested module. Behaviour must not change: injection is idempotent, and a second run replaces rather than duplicates.

- [ ] **Step 1: Write the failing tests**

Append to `install/test_engine.py`, and add `test_textblock()` to `__main__`:

```python
from textblock import inject, strip
B, E = "/* >>> oai >>> */", "/* <<< oai <<< */"

def test_textblock():
    print("textblock")
    out = inject("body {}", "a{}", B, E)
    check("appends when absent", out.count(B) == 1 and "a{}" in out)
    check("keeps original", "body {}" in out)

    twice = inject(out, "a{}", B, E)
    check("idempotent", twice.count(B) == 1)

    replaced = inject(out, "b{}", B, E)
    check("replaces body", "b{}" in replaced and "a{}" not in replaced)
    check("still one block", replaced.count(B) == 1)

    tail = inject("head\n", "x{}", B, E) + "trailer\n"
    stripped = strip(tail, B, E)
    check("strip removes block", B not in stripped and "x{}" not in stripped)
    check("strip keeps head", "head" in stripped)
    check("strip keeps trailer", "trailer" in stripped)

    check("strip on clean text is a no-op", strip("nothing here", B, E) == "nothing here")
    check("empty input works", inject("", "z{}", B, E).count(B) == 1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 install/test_engine.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'textblock'`

- [ ] **Step 3: Implement**

```python
"""Fenced blocks in files this project shares with another.

The markers exist so the block can be found again exactly: to remove it on
uninstall, and so a second install replaces rather than duplicates it.
"""

def inject(text, body, begin, end):
    block = f"\n{begin}\n{body.rstrip()}\n{end}\n"
    if begin in text and end in text:
        head, rest = text.split(begin, 1)
        _, tail = rest.split(end, 1)
        return head.rstrip("\n") + block + tail.lstrip("\n")
    return text.rstrip("\n") + "\n" + block

def strip(text, begin, end):
    if begin not in text or end not in text:
        return text
    head, rest = text.split(begin, 1)
    _, tail = rest.split(end, 1)
    return head.rstrip("\n") + "\n" + tail.lstrip("\n")
```

- [ ] **Step 4: Run to verify it passes**

Run: `python3 install/test_engine.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install/textblock.py install/test_engine.py
git commit -m "Extract fenced-block injection into a tested module"
```

---

### Task 4: Manifest loading and validation

**Files:**
- Create: `manifest.toml`
- Create: `install/manifest.py`
- Modify: `install/test_engine.py`

**Interfaces:**
- Consumes: `expand_dest` from Task 1
- Produces: `Artifact` (dataclass: `id, src, dest, mode, profile, post, keys, distro`), `load(path: str) -> list[Artifact]`, `select(artifacts, profile: str) -> list[Artifact]`, `MODES: set[str]`

A bad manifest must fail loudly at load time, not halfway through mutating someone's home directory.

- [ ] **Step 1: Write the failing tests**

Append to `install/test_engine.py`, add `test_manifest()` to `__main__`:

```python
import tempfile
from manifest import load, select, Artifact, MODES, ManifestError

def _write(tmp, text):
    p = os.path.join(tmp, "m.toml")
    open(p, "w").write(text)
    return p

def test_manifest():
    print("manifest")
    with tempfile.TemporaryDirectory() as tmp:
        good = _write(tmp, '''
[[artifact]]
id = "shell"
src = "quickshell"
dest = "~/.config/quickshell/openagentisland"
mode = "symlink"
profile = ["island", "full"]

[[artifact]]
id = "fonts"
src = "assets/fonts"
dest = "~/.local/share/fonts"
mode = "copy"
post = "fc-cache -f"
''')
        arts = load(good)
        check("loads both rows", len(arts) == 2)
        check("id preserved", arts[0].id == "shell")
        check("profile default is full", arts[1].profile == ["full"])
        check("post captured", arts[1].post == "fc-cache -f")
        check("distro defaults empty", arts[0].distro == [])

        check("select island", [a.id for a in select(arts, "island")] == ["shell"])
        check("select full", [a.id for a in select(arts, "full")] == ["shell", "fonts"])

        dup = _write(tmp, '[[artifact]]\nid="x"\nsrc="a"\ndest="~/a"\nmode="copy"\n'
                          '[[artifact]]\nid="x"\nsrc="b"\ndest="~/b"\nmode="copy"\n')
        try:
            load(dup); check("duplicate id rejected", False)
        except ManifestError as e:
            check("duplicate id rejected", "duplicate" in str(e).lower())

        badmode = _write(tmp, '[[artifact]]\nid="x"\nsrc="a"\ndest="~/a"\nmode="teleport"\n')
        try:
            load(badmode); check("unknown mode rejected", False)
        except ManifestError as e:
            check("unknown mode rejected", "teleport" in str(e))

        missing = _write(tmp, '[[artifact]]\nid="x"\nmode="copy"\n')
        try:
            load(missing); check("missing field rejected", False)
        except ManifestError as e:
            check("missing field rejected", "src" in str(e) or "dest" in str(e))

        nokeys = _write(tmp, '[[artifact]]\nid="c"\nsrc="a"\ndest="~/a"\nmode="merge-json"\n')
        try:
            load(nokeys); check("merge-json without keys rejected", False)
        except ManifestError as e:
            check("merge-json without keys rejected", "keys" in str(e))

    check("modes are the documented six",
          MODES == {"symlink", "copy", "inject", "setting", "extract", "merge-json"})
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 install/test_engine.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'manifest'`

- [ ] **Step 3: Implement**

```python
"""The artifact table: loading, validation, and profile selection."""
import tomllib
from dataclasses import dataclass, field

MODES = {"symlink", "copy", "inject", "setting", "extract", "merge-json"}
REQUIRED = ("id", "src", "dest", "mode")

class ManifestError(Exception):
    pass

@dataclass
class Artifact:
    id: str
    src: str
    dest: str
    mode: str
    profile: list = field(default_factory=lambda: ["full"])
    post: str = ""
    keys: list = field(default_factory=list)
    distro: list = field(default_factory=list)

def load(path):
    with open(path, "rb") as fh:
        doc = tomllib.load(fh)
    rows, seen = [], set()
    for i, row in enumerate(doc.get("artifact", [])):
        where = row.get("id", f"row {i}")
        for f in REQUIRED:
            if f not in row:
                raise ManifestError(f"{where}: missing required field '{f}'")
        if row["mode"] not in MODES:
            raise ManifestError(f"{where}: unknown mode '{row['mode']}'")
        if row["mode"] == "merge-json" and not row.get("keys"):
            raise ManifestError(f"{where}: mode 'merge-json' requires 'keys' "
                                f"— it may only write keys the rice declares it owns")
        if row["id"] in seen:
            raise ManifestError(f"duplicate artifact id '{row['id']}'")
        seen.add(row["id"])
        rows.append(Artifact(**row))
    return rows

def select(artifacts, profile):
    return [a for a in artifacts if profile in a.profile]
```

- [ ] **Step 4: Run to verify it passes**

Run: `python3 install/test_engine.py`
Expected: PASS

- [ ] **Step 5: Write the real manifest**

Create `manifest.toml` with every row the current `install.sh` implements, plus the config layers. Start with the shell row carrying the comment explaining why `quickshell/` sits at the repo root:

```toml
# Every installable artifact, one row each. install/engine.py walks this;
# install, --dry-run, --uninstall and --status all derive from it.

[[artifact]]
id      = "shell"
src     = "quickshell"
dest    = "~/.config/quickshell/openagentisland"
mode    = "symlink"
profile = ["island", "full"]
# quickshell/ stays at the REPO ROOT rather than under config/. The live
# symlink points here and tracks main, so moving the directory would break the
# running desktop on the next pull. See spec section 3.
```

- [ ] **Step 6: Commit**

```bash
git add manifest.toml install/manifest.py install/test_engine.py
git commit -m "Load and validate the artifact manifest"
```

---

### Task 5: The engine — modes, backup, and the four commands

**Files:**
- Create: `install/engine.py`
- Modify: `install.sh`

**Interfaces:**
- Consumes: everything from Tasks 1–4
- Produces: `Engine(repo, home, dry_run)` with `.install(profile)`, `.uninstall()`, `.status(profile) -> list[tuple[str, str]]`

Backup semantics matter here. Per spec §9, a user who installs twice and uninstalls once must not be restored to the state after their first install. The engine writes an `original/` backup **once**, on first install, and never overwrites it; uninstall restores from `original/`.

- [ ] **Step 1: Write the failing round-trip test**

Create `dev/test-install.sh`:

```bash
#!/usr/bin/env bash
# Round-trip the installer against a scratch HOME. Touches nothing real.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
echo "scratch HOME: $SCRATCH"

# A pre-existing config the installer must merge into, not clobber.
mkdir -p "$SCRATCH/.config/illogical-impulse"
cat > "$SCRATCH/.config/illogical-impulse/config.json" <<'JSON'
{"background":{"wallpaperPath":"/their/wallpaper.jpg"},"personal":{"keep":"me"}}
JSON

HOME="$SCRATCH" python3 "$REPO/install/engine.py" install --repo "$REPO" --profile full
HOME="$SCRATCH" python3 "$REPO/install/engine.py" verify  --repo "$REPO" --profile full

python3 - "$SCRATCH" <<'PY'
import json, sys
d = json.load(open(f"{sys.argv[1]}/.config/illogical-impulse/config.json"))
assert d["background"]["wallpaperPath"] == "/their/wallpaper.jpg", "clobbered their wallpaper"
assert d["personal"]["keep"] == "me", "clobbered their settings"
print("  ok   merge preserved the user's own keys")
PY

HOME="$SCRATCH" python3 "$REPO/install/engine.py" uninstall --repo "$REPO"

python3 - "$SCRATCH" <<'PY'
import json, sys
d = json.load(open(f"{sys.argv[1]}/.config/illogical-impulse/config.json"))
assert d == {"background":{"wallpaperPath":"/their/wallpaper.jpg"},"personal":{"keep":"me"}}, \
    f"uninstall did not restore the original config: {d}"
print("  ok   uninstall restored the original config exactly")
PY
echo "round-trip PASSED"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash dev/test-install.sh`
Expected: FAIL — `install/engine.py` does not exist

- [ ] **Step 3: Implement the engine**

`install/engine.py` with: a `run()` gate every mutation passes through so `--dry-run` is honest by construction; one handler per mode; `Backup` writing `original/` once and per-run dirs thereafter; `verify` walking the manifest asserting each destination landed; `status` reporting `ok` / `missing` / `differs` per row.

- [ ] **Step 4: Run to verify it passes**

Run: `bash dev/test-install.sh`
Expected: `round-trip PASSED`

- [ ] **Step 5: Rewrite `install.sh` as a wrapper**

Keep `preflight`, `detect_hypr_config_style`, `detect_zen_profile` and the colour helpers. Replace the per-phase install functions with a single call into the engine, preserving every existing flag.

- [ ] **Step 6: Verify the flags still behave**

Run: `./install.sh --dry-run` and confirm no file is modified; `./install.sh --help` and confirm the flag list is unchanged.

- [ ] **Step 7: Commit**

```bash
git add install/engine.py install.sh dev/test-install.sh
git commit -m "Drive the installer from the manifest"
```

---

### Task 6: Vendor the assets

**Files:**
- Create: `assets/fonts/{GoogleSansFlex,SFProDisplay,SFMono}/`, `assets/icons/WhiteSur.tar.zst`, `assets/themes/MatugenGlass/`, `assets/wallpapers/`
- Create: `config/hypr/custom/`, `config/{kitty,fish,foot,fuzzel}/`, `config/nautilus-glass/`, `config/illogical-impulse/config.json`
- Modify: `manifest.toml`

Three font families only. Icons as a tarball because the theme is ~60,000 small files and committing them loose slows `git clone` and `git status` for every user forever.

- [ ] **Step 1: Copy the three referenced font families**

```bash
mkdir -p assets/fonts
cp -a ~/.local/share/fonts/illogical-impulse-google-sans-flex assets/fonts/GoogleSansFlex
cp -a ~/.local/share/fonts/SFProDisplay assets/fonts/SFProDisplay
cp -a ~/.local/share/fonts/SFMono       assets/fonts/SFMono
rm -rf assets/fonts/GoogleSansFlex/.git   # it is a checkout upstream; we vendor the files
du -sh assets/fonts
```

Expected: roughly 23 MB.

- [ ] **Step 2: Tarball the icon themes**

```bash
mkdir -p assets/icons
tar -C ~/.local/share/icons -c WhiteSur WhiteSur-dark | zstd -19 -T0 -o assets/icons/WhiteSur.tar.zst
ls -lh assets/icons/WhiteSur.tar.zst
```

Expected: roughly 30 MB from ~95 MB raw.

- [ ] **Step 3: Copy the theme, configs and wallpapers**

```bash
mkdir -p assets/themes assets/wallpapers config
cp -a ~/.local/share/themes/MatugenGlass assets/themes/
cp -a ~/Pictures/Wallpapers/. assets/wallpapers/
mkdir -p config/hypr
cp -a ~/.config/hypr/custom config/hypr/custom
cp -a ~/.config/nautilus-glass config/
for d in kitty fish foot fuzzel; do cp -a "$HOME/.config/$d" config/; done
find config -name '*.bak*' -delete
```

- [ ] **Step 4: Extract the rice-owned config keys**

Write `config/illogical-impulse/config.json` containing **only** the keys the rice owns — not the 17 KB live file, which carries the wallpaper path and monitor layout. List those same key paths in the manifest row's `keys`.

- [ ] **Step 5: Add a manifest row per artifact**

- [ ] **Step 6: Verify the round-trip still passes**

Run: `bash dev/test-install.sh`
Expected: `round-trip PASSED`

- [ ] **Step 7: Commit**

```bash
git add assets config manifest.toml
git commit -m "Vendor the fonts, icons, theme and configs the rice needs"
```

---

### Task 7: The nested development harness

**Files:**
- Create: `dev/hypr-nested.conf`, `dev/nested.sh`, `dev/shot.sh`

The nested session must be unable to read or write the live `~/.config`. That is what makes it safe to run against a worktree while the real desktop keeps running.

- [ ] **Step 1: Move the nested compositor config into the repo**

```bash
mkdir -p dev
cp ~/.config/hypr-nested/hyprland.conf dev/hypr-nested.conf
```

- [ ] **Step 2: Write `dev/nested.sh`**

Creates the worktree at `.worktrees/<branch>`; builds a shadow XDG tree inside it with `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` redirected and `quickshell/openagentisland` linked to the **worktree's** QML; launches nested Hyprland with `WLR_BACKENDS=wayland WLR_NO_HARDWARE_CURSORS=1 HYPRLAND_INSTANCE_SIGNATURE=`.

- [ ] **Step 3: Pin the nested window to workspace 8**

Add a host windowrule matching the nested Hyprland window, moving it to workspace 8 silently at a fixed size so captures are comparable between runs.

- [ ] **Step 4: Verify isolation**

Launch the nested session, then confirm the live `~/.config/quickshell/openagentisland` symlink still resolves to the main checkout and that the nested shell wrote nothing under `~/.config`.

- [ ] **Step 5: Write `dev/shot.sh`**

Reads the nested window's geometry from `hyprctl clients -j`, captures with `grim -g`, writes `docs/screenshots/<name>.png`.

- [ ] **Step 6: Commit**

```bash
git add dev/
git commit -m "Add the nested development harness"
```

---

### Task 8: Mintlify documentation

**Files:**
- Create: `docs/docs.json`, `docs/*.mdx`, `install/gen_docs.py`

- [ ] **Step 1: Write `docs/docs.json`** with the navigation from spec §7.

- [ ] **Step 2: Write the pages** — Home, Quickstart, Requirements, Install, Configuring, Agent Island, Uninstall & troubleshooting.

- [ ] **Step 3: Generate "What it installs" from the manifest**

`install/gen_docs.py` reads `manifest.toml` and emits `docs/what-it-installs.mdx` as a table of every destination. Documentation that cannot drift from behaviour.

- [ ] **Step 4: Verify the generator matches the manifest**

Run: `python3 install/gen_docs.py && git diff --exit-code docs/what-it-installs.mdx`
Expected: no diff on a second run — the generator is deterministic.

- [ ] **Step 5: Commit**

```bash
git add docs/ install/gen_docs.py
git commit -m "Document the desktop on Mintlify"
```

---

### Task 9: Verification and release

- [ ] **Step 1: Full round-trip** — `bash dev/test-install.sh`
- [ ] **Step 2: Unit tests** — `python3 install/test_engine.py`
- [ ] **Step 3: Bridge safety unchanged** — `python3 bridge/test_safety.py` (expect 13/13)
- [ ] **Step 4: Nested session renders on workspace 8**, screenshots captured
- [ ] **Step 5: `./install.sh --status`** against the live machine reports honestly
- [ ] **Step 6: Update `PROGRESS.md` and `README.md`**
- [ ] **Step 7: Commit and push**

---

## Self-Review

**Spec coverage:** §3 layout → Tasks 4–8. §4.0 schema → Task 4. §4.1 modes → Tasks 2, 3, 5. §4.2 commands → Task 5. §4.3 preserved machinery → Tasks 3, 5. §5 assets → Task 6. §6 harness → Tasks 5, 7. §7 docs → Task 8. §8 sequence → task order. §9 risks: symlink asymmetry → Task 7 step 4; `merge-json` → Task 2 and Task 5 step 1; uninstall fidelity → Task 5 `original/` backup; end-4 churn → Task 4 mode assignment.

**Placeholders:** none. Tasks 5–8 describe file responsibilities rather than quoting every line, because the engine's mode handlers are mechanical given the tested primitives in Tasks 1–4 and the existing bash they port from.

**Type consistency:** `expand_dest`, `has_path`, `get_path`, `set_path` (Task 1) are used with those names in Tasks 2 and 4. `merge_owned` (Task 2) is called by Task 5. `inject`/`strip` (Task 3) by Task 5. `Artifact`, `load`, `select`, `MODES`, `ManifestError` (Task 4) by Task 5 and Task 8.
