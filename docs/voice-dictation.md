# Voice Dictation — hold-to-talk in the notch

Hold **Right Ctrl** → the notch morphs into a dictation pill with a live
waveform. Speak, release, and the transcript is typed into whatever window has
focus. It's push-to-talk speech-to-text, driven from the island.

This is powered by **[hyprvoice](https://github.com/leonardotrapani/hyprvoice)**
(an external MIT-licensed daemon) with **Groq Whisper** for transcription.
OpenAgentIsland does **not** bundle hyprvoice — you install it separately and
this shell drives it. The integration lives in
`quickshell/services/Hyprvoice.qml` and the pill UI in
`quickshell/modules/ii/island/IslandNotch.qml`.

> ⚠️ **Never commit your hyprvoice config.** `~/.config/hyprvoice/config.toml`
> stores your Groq API key in plaintext. It is a per-user secret — generate your
> own with the wizard (below); do not copy anyone else's or check it into git.

---

## Dependencies

| Component | Role | Install |
|---|---|---|
| `hyprvoice-bin` | the daemon + CLI (records → STT → injects text) | AUR: `yay -S hyprvoice-bin` |
| `pipewire`, `pipewire-pulse`, `pipewire-audio` | microphone capture | official repos |
| **Groq API key** | speech-to-text (`whisper-large-v3`), free tier is fine | [console.groq.com](https://console.groq.com) |
| `wtype`, `wl-clipboard` | text injection into the focused window | pulled in by `hyprvoice-bin` |
| `ydotool` + `ydotoold` *(optional)* | injection fallback for Chromium/Electron apps | `sudo pacman -S ydotool` |
| `libnotify` | hyprvoice's desktop notifications | pulled in by `hyprvoice-bin` |
| Hyprland + Quickshell built with `Quickshell.Hyprland` | provides the global-shortcut used for push-to-talk | already required by OpenAgentIsland |

Tested against `hyprvoice-bin` **v1.0.2**. The current setup uses cloud STT
(Groq); hyprvoice can also run a local Whisper model (`hyprvoice model`), which
this integration does not require.

---

## Setup

1. **Install hyprvoice** (pulls pipewire, wtype, wl-clipboard, libnotify):
   ```sh
   yay -S hyprvoice-bin      # or: paru -S hyprvoice-bin
   ```
2. **Optional — better injection in Chromium/Electron:**
   ```sh
   sudo pacman -S ydotool
   systemctl --user enable --now ydotool   # the unit is named ydotool.service; it launches ydotoold
   ```
3. **Get a Groq API key** at <https://console.groq.com>.
4. **Configure hyprvoice** — this writes `~/.config/hyprvoice/config.toml`
   (with your key) interactively. Never commit that file.
   ```sh
   hyprvoice onboarding      # or: hyprvoice configure  (full wizard)
   ```
5. **Enable the daemon** (ships its own user unit, gated on pipewire + Wayland):
   ```sh
   systemctl --user enable --now hyprvoice
   ```
6. **Bind the push-to-talk key** — see below.

---

## The push-to-talk keybind

OpenAgentIsland registers a Quickshell global shortcut named
`quickshell:hyprvoicePtt` (`Hyprvoice.qml` → `GlobalShortcut { name: "hyprvoicePtt" }`).
You bind a key to it in your Hyprland config — **both press and release**, so the
shell knows when you let go.

**Stock Hyprland** (`~/.config/hypr/hyprland.conf`), Right Ctrl as the PTT key:
```ini
bind  = , Control_R, global, quickshell:hyprvoicePtt
bindr = , Control_R, global, quickshell:hyprvoicePtt
```
The `quickshell:` namespace is your shell's `-c` config name; the above assumes
you run `qs -c openagentisland`.

**Optional headless fallback** — dictate even when the shell isn't running:
```ini
bind  = , Control_R, exec, qs -c openagentisland ipc call TEST_ALIVE || hyprvoice toggle
bindr = , Control_R, exec, qs -c openagentisland ipc call TEST_ALIVE || hyprvoice toggle
```
`TEST_ALIVE` is **not** a real IPC target you need to implement — it's a liveness
probe. Any successful `qs` call exits `0`, so `hyprvoice toggle` only fires when
Quickshell isn't up. If the shell is running, the `global` shortcut above handles
everything.

> **Author-machine caveat:** this repo's live config uses a Lua-wrapped Hyprland
> (`hl.bind` / `hl.dsp.global(...)`), which is **not** stock Hyprland syntax. The
> `bind = …, global, …` form above is the portable translation for stock Hyprland.

---

## How it works

- On a hold of **≥ 200 ms**, `Hyprvoice.qml` runs `hyprvoice toggle` (idempotent)
  and starts polling `hyprvoice status` every 200 ms, mapping
  `status=recording|transcribing|processing|injecting|idle` onto the notch pill.
- **Ghost-press defenses:** a 200 ms tap-guard drops synthetic `Control_R` taps
  (flaky 2.4 GHz dongles / virtual keyboards can inject them); a 120 s stuck-press
  auto-cancel prevents a wedged key from hallucinating text; if the daemon dies
  mid-run, the pill falls back to idle after ~2 s of unparseable status.
- The waveform in the pill is a **procedural animation, not real mic level** — a
  real cava mic feed was tried and dropped because it looked dead at low gain. So
  there is no mic/cava config to set up for dictation.

## Troubleshooting

- Pipeline state: `hyprvoice status` and `journalctl --user -u hyprvoice`.
- Shell-side log: `/tmp/hyprvoice-ptt.log`.
- Exercise it without a keybind:
  ```sh
  qs -c openagentisland ipc call hyprvoice pttPress
  qs -c openagentisland ipc call hyprvoice pttRelease
  ```
