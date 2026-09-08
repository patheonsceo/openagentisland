#!/usr/bin/env bash
# Traffic light: yellow. Hyprland has no minimize, so send to the scratchpad
# (special:special). Bring it back with SUPER + S.
exec hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:special", follow = false })'
