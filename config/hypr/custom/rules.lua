-- macOS-like "Finder" window: Yazi in a floating kitty (class=Finder). Added 2026-06-07.
hl.window_rule({match = {class = "^(Finder)$"}, float = true})
hl.window_rule({match = {class = "^(Finder)$"}, center = true})
hl.window_rule({match = {class = "^(Finder)$"}, size = "1280 820"})
hl.window_rule({match = {class = "^(Finder)$"}, no_blur = false}) -- re-enable blur (global rule disables it) for frosted glass

-- Daily kitty: re-enable blur (the global rule in hyprland/rules.lua disables it
-- for every window) so background_opacity 0.88 reads as frosted glass. Added 2026-08-31.
hl.window_rule({match = {class = "^(kitty)$"}, no_blur = false})

-- Nautilus frosted glass: re-enable blur (the global rule in hyprland/rules.lua
-- disables it for every window) so the alpha set in
-- ~/.config/nautilus-glass/gtk-4.0/gtk.css reads as frosted glass. Added 2026-08-31.
hl.window_rule({match = {class = "^(org\\.gnome\\.Nautilus)$"}, no_blur = false})
