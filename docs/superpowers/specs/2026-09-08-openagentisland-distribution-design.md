# Design — Turning openagentisland into a distributable desktop

**Date:** 2026-09-08
**Status:** Approved, in implementation
**Scope:** CachyOS / Arch only. Ubuntu is explicitly deferred to its own cycle.

---

## 1. The problem

The repo ships a Quickshell config. The desktop people actually want is larger
than that, and most of it lives outside the repo on one machine:

| Outside the repo | Where it lives |
|---|---|
| Hyprland keybinds, rules, execs, window behaviour | `~/.config/hypr/custom/*.lua` |
| Traffic-light dispatch scripts, finder, hyprbars | `~/.config/hypr/custom/scripts/` |
| Fonts | `~/.local/share/fonts/` |
| WhiteSur icon theme | `~/.local/share/icons/` |
| MatugenGlass GTK theme | `~/.local/share/themes/` |
| Nautilus glass (shadow `XDG_CONFIG_HOME`) | `~/.config/nautilus-glass/` |
| Terminal and launcher config | `~/.config/{kitty,fish,foot,fuzzel}/` |
| Tuned shell settings | `~/.config/illogical-impulse/config.json` |

Someone cloning the repo today gets the islands and none of the desktop. The
goal is one clone plus one script producing the whole thing.

A second, quieter problem: the repo had drifted 61 commits and 23 dirty files
behind the machine. Any distribution story built on that state would have been
built on something nobody could reproduce.

## 2. Decisions

Each was taken deliberately; the rationale matters more than the choice.

**2.1 — Grow this repo rather than create an umbrella.** The alternative was a
meta-repo vendoring the island as a component. Rejected: two repos to keep in
step, submodule overhead, and an installer that must bootstrap an inner repo
before it can act.

**2.2 — The name stays `openagentisland`.** The string is already load-bearing
in eight places — the config directory, the `qsConfig` env value,
`~/.local/share/openagentisland-backups`, `~/.local/state/openagentisland`, the
runtime symlink, the launch command, the installer and the docs. Renaming means
rewriting all of it and breaking the install path for anyone already running it,
in exchange for nothing the name does not already do. The GitHub repo was
renamed from `Dynamic-island-for-arch`; stars and redirects survive.

**2.3 — The live machine is disconnected from the repo, with one exception.**
Nothing propagates between the repo checkout and the running desktop unless
explicitly moved. The exception is `~/.config/quickshell/openagentisland`, which
stays a symlink into the main checkout because it *is* the shell edit-reload
loop; breaking it makes shell development miserable and removes the dogfooding
that has kept the project honest.

The asymmetry has a cost that must stay visible: **a `git checkout`, `pull` or
rebase on `main` can change the running shell.** Worktrees are therefore the
rule for anything non-trivial, and `quickshell/` must never move within the repo
(§3).

**2.4 — Everything ships; hardware tweaks do not.** Fonts, icons, cursors,
themes and wallpapers are vendored in full. Machine-specific work — the Acer EC
fan service, the 80% battery limiter, the Plymouth `quit-wait` workaround, the
Chrome `--gtk-version=4` fix, the Electron keyring flag, the three-output
PipeWire sink, `monitors.conf` — does not ship in any form.

The repo stays public. Vendoring Apple-licensed fonts (SF Pro Display, and a
Nerd-Font-patched SF Mono) into a public repo is redistribution their licence
does not grant. This was raised, understood and accepted by the owner; it is
recorded here so the decision is not mistaken for an oversight.

**2.5 — CachyOS/Arch reaches v1 before Ubuntu starts.** Ubuntu gets its own
brainstorm → spec → plan cycle. The installer is nonetheless built so distro
differences are isolated to manifest columns rather than scattered through
imperative phases, so the later port is an extension rather than a rewrite.

**2.6 — Docs are Mintlify.** MDX in-repo, auto-deployed from `main`.

## 3. Repo layout

```
openagentisland/
├── install.sh              thin wrapper over the engine
├── manifest.toml           the declarative artifact table
├── quickshell/             the shell — STAYS AT REPO ROOT
├── bridge/                 Claude Code agent hooks (unchanged)
├── install/
│   ├── engine.py           manifest walker
│   ├── packages/arch.txt   pacman + AUR list
│   └── traffic-lights/     CSS injection payloads
├── config/                 destined for ~/.config
│   ├── hypr/custom/
│   ├── kitty/ fish/ foot/ fuzzel/
│   ├── nautilus-glass/
│   └── illogical-impulse/config.json
├── assets/
│   ├── fonts/
│   ├── icons/*.tar.zst
│   ├── themes/MatugenGlass/
│   └── wallpapers/
├── docs/                   Mintlify
└── dev/                    worktree + nested-session harness
```

**`quickshell/` stays at the repo root** rather than moving under `config/`,
which would be tidier. The live symlink points at it and tracks `main`; moving
the directory means the next pull silently breaks the running desktop. The wart
is deliberate and is documented in `manifest.toml` beside the row.

## 4. The manifest and engine

Every installable artifact is one row. Adding a config layer is a row, not new
bash in three places.

```toml
[[artifact]]
id      = "shell"
src     = "quickshell"
dest    = "~/.config/quickshell/openagentisland"
mode    = "symlink"
profile = ["island", "full"]
```

### 4.0 Row schema

| field | required | meaning |
|---|---|---|
| `id` | yes | stable identifier; used by `--status` output and test assertions |
| `src` | yes | path within the repo |
| `dest` | yes | destination, `~` expanded against `$HOME` |
| `mode` | yes | one of §4.1 |
| `profile` | no | which profiles include this row; default `["full"]` |
| `post` | no | command to run after this row lands (e.g. `fc-cache -f`) |
| `keys` | `merge-json` only | the key paths this rice owns and may write |
| `distro` | no | reserved. Absent means every distro. The Ubuntu port (§2.5) adds values here rather than branching the engine. |

`distro` is specified now and unused now. Defining the field costs nothing and
means the later port adds rows and values instead of introducing a concept.

### 4.1 Modes

| mode | behaviour |
|---|---|
| `symlink` | dest becomes a link to the repo path |
| `copy` | recursive copy, backed up first |
| `inject` | fenced-marker block into a file shared with another project |
| `setting` | a single key into an ini / gsettings / kdeglobals |
| `extract` | tarball unpacked into dest |
| `merge-json` | deep-merge into an existing JSON document |

`merge-json` is the one that carries real risk if omitted.
`illogical-impulse/config.json` is 17 KB of rice settings mixed with end-4
defaults and per-machine values — wallpaper path, monitor layout, personal
preferences. Copying it over someone's file destroys their configuration. Only
the keys the rice owns may be written.

### 4.2 Commands

Derived from the manifest rather than hand-maintained:

- `./install.sh` — install
- `--dry-run` — print every action, mutate nothing
- `--uninstall` — walk the manifest in reverse, restore from the backup manifest
- `--status` — diff every live destination against the repo
- `--profile island|full` — the notch alone, or the whole desktop

`--status` is what makes the disconnected model in §2.3 workable. It never
syncs; it only reports. It is the answer to "the repo silently falls behind"
that does not require anything automatic.

### 4.3 Preserved machinery

The existing `install.sh` already implements backup-with-manifest, fenced-marker
injection, Zen profile detection, Hyprland config-style detection (Lua vs
legacy), and a `run()` wrapper that makes `--dry-run` honest by construction.
These become engine primitives. None of it is rewritten.

## 5. What gets vendored

Measured, not assumed. The rice references **three** font families; the other
eight installed on the machine are leftovers from a font comparison and are not
referenced by any config.

| Asset | Size | Form |
|---|---|---|
| Google Sans Flex — shell UI | 4 MB | loose |
| SF Pro Display — GTK/system font | 1.9 MB | loose |
| Liga SF Mono Nerd Font — terminal | 17 MB | loose |
| WhiteSur + WhiteSur-dark icons | ~95 MB raw | **zstd tarball, ~30 MB** |
| MatugenGlass theme | 12 KB | loose |
| nautilus-glass config | 12 KB | loose |
| Wallpapers | ~33 MB | loose |

Icons ship as a tarball because the theme is roughly 60,000 small files.
Committing them loose makes `git clone` and even `git status` slow for every
user, forever, to save one `tar` call at install time.

Bibata cursors are **not** vendored — they are a pacman package, and so belong
in `install/packages/arch.txt` as a dependency.

Excluded per §2.4: Iosevka, Caskaydia, Monaspace, Victor Mono, Maple Mono,
Geist Mono, CommitMono, 0xProto (122 MB, unreferenced), and every
hardware-specific script.

## 6. Dev and test harness

The rule is that nothing is developed against the running system. This enforces
it rather than relying on memory.

**`dev/nested.sh <branch>`**

1. Creates a git worktree at `.worktrees/<branch>`. The live symlink keeps
   pointing at `main`.
2. Builds a shadow XDG tree inside the worktree — `XDG_CONFIG_HOME`,
   `XDG_STATE_HOME`, `XDG_CACHE_HOME` — with
   `quickshell/openagentisland` linked to the *worktree's* QML. The nested shell
   cannot read or write the live `~/.config`. Same technique already proven for
   the frosted Nautilus setup.
3. Launches nested Hyprland with `dev/hypr-nested.conf` (moved in from
   `~/.config/hypr-nested/`): wildcard monitor, animations and blur off,
   `exec-once = qs -c openagentisland`.
4. Pins the nested window to **workspace 1** at a fixed size, so captures are
   comparable across runs.

**`dev/shot.sh <name>`** — reads the nested window geometry from
`hyprctl clients`, captures with `grim -g`, writes
`docs/screenshots/<name>.png`.

**`dev/test-install.sh`** — the part a nested compositor cannot provide. A
nested session tests the *shell*; it says nothing about the *installer*, and the
installer cannot be tested against a real home directory. So: run `install.sh`
with `HOME` pointed at a scratch directory, walk the manifest asserting every
destination landed, then `--uninstall` and assert the scratch home is clean
again.

The assertions are generated from the manifest, so every row added is covered
automatically. This is the round-trip proof that `--uninstall` works — the
promise the entire installer rests on, and currently the least-exercised path in
the codebase.

## 7. Documentation

Mintlify, `docs/docs.json` plus MDX, deployed from `main`.

Home · Quickstart · Requirements · Install · What it installs · Configuring
(notch, dock, widgets, keybinds) · Agent Island · Uninstall & troubleshooting.

**"What it installs" is generated from `manifest.toml` at build time.** Every
file the installer touches, listed from the same table the installer reads.
Documentation that cannot structurally drift from behaviour.

## 8. Sequence

| Phase | Work | State |
|---|---|---|
| 0 | Land the 61 unpushed commits; rename the repo | done |
| 1 | Engine, manifest, `test-install.sh`; port existing phases to rows | |
| 2 | Vendor assets and configs | |
| 3 | Dev harness — `nested.sh`, `shot.sh`, workspace 1 | |
| 4 | Mintlify docs; screenshots captured from the nested session | |
| 5 | Round-trip verification; cut v1 | |

Phase 3 could precede phase 2. It does not, because phases 1 and 2 are both
fully testable with `test-install.sh` alone — the nested compositor only earns
its cost once there is visual output to check.

## 9. Risks

- **The symlink asymmetry (§2.3).** Git operations on `main` change the running
  shell. Mitigated by the worktree workflow and by `quickshell/` never moving;
  not eliminated.
- **`merge-json` correctness.** The one mode that can destroy a user's existing
  configuration. Needs tests against a populated `config.json`, not just an
  empty one.
- **Uninstall fidelity.** Backups are per-run and timestamped; a user who
  installs twice and uninstalls once restores to the wrong point. The engine must
  reuse the first backup rather than the most recent.
- **end-4 base updates.** The upstream installer rewrites files this rice also
  writes. `inject` and `merge-json` survive that; `copy` does not. Rows must be
  assigned modes with upstream churn in mind.

## 10. Out of scope

Ubuntu support, NixOS, X11, any display manager or greeter theming, and the
hardware-specific scripts of §2.4.
