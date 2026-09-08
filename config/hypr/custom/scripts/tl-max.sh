#!/usr/bin/env bash
# Traffic light: green. Toggles maximized (not true fullscreen).
exec hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })'
