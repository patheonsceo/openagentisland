# OpenAgentIsland

_A macOS-style Dynamic Island desktop for Hyprland — with your Claude Code agents living in the notch._

![The OpenAgentIsland desktop](screenshots/desktop.png)

A slim menubar, frosted widgets on the wallpaper, and a magnifying dock. The
centrepiece is a morphing notch that shows a clock when idle and expands for
volume, brightness, media and notifications — and, the part no other rice does,
**live Claude Code agent status with Allow / Deny right from the notch**.

Built in [Quickshell](https://quickshell.outfoxxed.me/)/QML on top of
[end-4 / illogical-impulse](https://github.com/end-4/dots-hyprland).

## The headline

When a Claude Code session wants to run a command or edit a file, the request
comes to you. The notch morphs open with the tool, a preview of exactly what it
will do, and four choices: **Deny · Allow Once · Allow All · Bypass**.

![A Claude Code permission card in the notch](screenshots/permission-card.png)

The bridge is fire-and-forget. If the island is not listening, or anything goes
wrong at all, the hook falls back to Claude Code's normal prompt. It can never
hang or break your Claude Code — there are 13 safety checks that prove it, and
they run with `python3 bridge/test_safety.py`.

---

## Documentation

**Getting started**
- [Requirements](requirements.md) — what you need, and what the installer sets up
- [Install](install.md) — every flag, and how to check before you commit

**The desktop**
- [The notch](notch.md) — states, precedence, and the surfaces it opens
- [Dock and widgets](dock-and-widgets.md) — the dock, desktop widgets, desktop icons
- [Keybinds](keybinds.md) — what this rice binds on top of end-4

**Agents**
- [Agent Island](agent-island.md) — Claude Code sessions in the notch
- [Voice dictation](voice-dictation.md) — hold Right Ctrl to dictate

**Reference**
- [What it installs](what-it-installs.md) — every destination, generated from the manifest
- [Uninstall](uninstall.md) — how to put the machine back
- [Troubleshooting](troubleshooting.md) — things that go wrong, and what they mean
- [Development](development.md) — working on the shell without risking your desktop

## Install it

```bash
git clone https://github.com/patheonsceo/openagentisland.git
cd openagentisland
./install.sh
```

That is the whole thing: shell, fonts, icons, theme, wallpapers, Hyprland
config, terminal. See [Requirements](requirements.md) first — you need an
Arch-based system, and the installer will offer to set up the end-4 base if you
do not already run it.

> [!TIP]
> Run `./install.sh --dry-run` first. It prints every action it would take and
> changes nothing.


## Just the notch

Already have a rice you like? Take only the shell and leave your desktop alone:

```bash
./install.sh --profile island
```

## Undo it

```bash
./install.sh --uninstall
```

Every destination is snapshotted before the first change, and that snapshot is
never overwritten. See [Uninstall](uninstall.md).
