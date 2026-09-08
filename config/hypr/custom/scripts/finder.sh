#!/usr/bin/env bash
# macOS-like "Finder" — Yazi in a styled floating kitty window.
# Neutral black/grey/white palette (overrides the matugen kitty theme for this window only).
# Launched via Super+E (fileManager override in custom/variables.lua). Added 2026-06-07.
exec kitty \
  --class Finder \
  --title Finder \
  -o window_padding_width=16 \
  -o confirm_os_window_close=0 \
  -o background_opacity=0.88 \
  -o background=#161616 \
  -o foreground=#dcdcdc \
  -o cursor=#dcdcdc \
  -o selection_background=#3a3a3a \
  -o selection_foreground=#ffffff \
  -o color0=#1a1a1a -o color8=#4a4a4a \
  -o color1=#8a8a8a -o color9=#9a9a9a \
  -o color2=#b0b0b0 -o color10=#c0c0c0 \
  -o color3=#cccccc -o color11=#dddddd \
  -o color4=#707070 -o color12=#808080 \
  -o color5=#9a9a9a -o color13=#aaaaaa \
  -o color6=#c0c0c0 -o color14=#cccccc \
  -o color7=#d8d8d8 -o color15=#f0f0f0 \
  -e yazi "${1:-$HOME}"
