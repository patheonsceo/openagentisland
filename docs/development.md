# Development

_Working on the shell without putting your own desktop at risk._

## The rule

Your live desktop's config symlink follows the **main** checkout. So work on the
shell happens in a git worktree, rendered by a nested compositor, never against
the running session.

```bash
dev/nested.sh              # worktree for nested/<current-branch>
dev/nested.sh my-feature   # worktree for my-feature
dev/nested.sh --stop
```

This opens a nested Hyprland as an ordinary window on your desktop, pinned to
**workspace 1** at a fixed 1600×900, running the shell from the worktree.

Edit files under `.worktrees/<branch>/quickshell/` and Quickshell hot-reloads on
save. No restart for QML changes.

## How the isolation works

The nested session gets `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME`
pointed inside the worktree, with its Quickshell config linked to the worktree's
own `quickshell/`. It cannot read or write the real `~/.config`. It is the same
shadow-XDG technique the rice uses to give Nautilus a GTK4 theme nothing else
gets.

Generated colours are **copied** into the shadow tree rather than linked, so the
nested shell has a palette to render with and still cannot write back into live
state.

## Screenshots

```bash
dev/shot.sh notch-idle          # -> dev/shots/ (scratch, gitignored)
dev/shot.sh notch-idle --docs   # -> docs/screenshots/
```

Geometry comes from the recorded window address, so every capture of a given
state is identical and two runs compare pixel for pixel. Publishing to
`docs/screenshots` refuses to overwrite an existing file without `--force`,
because that directory holds the curated README assets.

## Tests

```bash
python3 install/test_engine.py   # engine logic, no filesystem
bash dev/test-install.sh         # full install/uninstall round trip in a scratch HOME
python3 bridge/test_safety.py    # the agent bridge can never hang Claude Code
```

## Adding something to the installer

Add a row to `manifest.toml`. That is the whole change — install, `--dry-run`,
`--uninstall`, `--status` and the round-trip test all derive from that table, and
`docs/what-it-installs.md` regenerates from it:

```bash
python3 install/gen_docs.py
```

If a row uses `merge-json` it must declare the key paths it owns. The loader
refuses a row without them, because an empty list would mean "change nothing" —
which reads as a working install while doing nothing at all.
