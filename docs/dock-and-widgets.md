# Dock and widgets

_The dock, the desktop widgets, and the desktop icons that get out of their way._

## The dock

A macOS-style dock with magnification, running app indicators, pinned apps and a
Trash that reflects whether the Trash actually has anything in it.

Configure pinned apps from **Settings → Dock**, or by editing `dock.pinnedApps`
in `~/.config/illogical-impulse/config.json`.

## Desktop widgets

Three widgets live on the wallpaper on their own layer — above the background,
below every normal window:

- **To-do** — per-task countdown timers with a fullscreen focus mode
- **Clock** — several timezones, switchable from pills on the face
- **Calendar** — a fixed six-row grid, so paging never changes the card height

Drag by the strip at the top, resize from the grips. Right-click for the menu.

### Placement modes

| Mode | Behaviour |
| --- | --- |
| Free | Stays exactly where you drop it |
| Snap (default) | Pulls to margins, centres and neighbours, with a live guide line |
| Grid | Position *and* size quantise to a grid |

## Desktop icons

`~/Desktop` renders on its own layer beside the widgets. Icons stay where you
drop them.

The interesting part is what happens when the two overlap. Icons and widgets are
separate layer surfaces and cannot see each other, so an icon would happily end
up underneath a widget and become unreachable. Instead the widget board publishes
the rectangles it occupies, and the icon board reads them.

Two positions are tracked, and they are deliberately different things:

- **Intended** — where you dropped it. Saved, and never overwritten.
- **Displayed** — intended, pushed aside if a widget now covers that spot. Worked
  out at render time, never stored.

So drag a widget over an icon and the icon steps aside; drag the widget away and
the icon goes home, because home was never lost. The same path handles a
resolution change, a widget being switched off, and a corrupt position file.
