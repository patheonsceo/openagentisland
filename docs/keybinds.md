# Keybinds

_What this rice binds on top of the end-4 defaults._

The end-4 base brings its own keybinds and this rice keeps them. What follows is
what `config/hypr/custom/keybinds.lua` adds or changes.

| Keys | Action |
| --- | --- |
| `Super + Space` | Vicinae launcher (Raycast/Spotlight style) |
| `Super + E` | Yazi file manager |
| `Super + Shift + E` | Dolphin |
| `Super + Shift + S` | Region snip — reopens with your last selection drawn |
| `Enter` in snip | Accept the restored region |
| `Shift + Enter` in snip | Accept, and send it to the annotation editor |
| `Right Ctrl` (hold) | Push-to-talk dictation — see [Voice dictation](voice-dictation.md) |
| `Ctrl + Super + Alt + /` | Open this keybinds file |

## Two things worth knowing

**Right Ctrl is consumed by dictation.** Use Left Ctrl for shortcuts. Right Ctrl
was chosen because Fn is handled in firmware on the machine this was built on and
emits no keycode at all.

**Send-window-to-workspace was fixed.** Upstream registers both a keysym bind
(`SUPER+ALT+3`) and a keycode bind (`SUPER+ALT+code:12`) for the same physical
key. On some layouts both match a single press, so the dispatcher fired twice: it
moved the active window, focus fell to the next window, and the second firing
moved that one too. The redundant keysym variants are unbound; the layout-robust
keycode binds still fire exactly once.
