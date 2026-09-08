-- User exec-once commands (survives dotfile updates)

hl.on("hyprland.start", function ()
    -- Vicinae launcher daemon — launched by Hyprland so it always has the
    -- live Wayland env (the shipped systemd unit needs graphical-session.target,
    -- which plain Hyprland never starts). Added 2026-06-07.
    hl.exec_cmd("vicinae server")

end)

-- ─────────────────────────────────────────────────────────────────────
-- DISABLED 2026-08-31: hyprbars crashed the compositor.
--
-- Hyprland aborted with SIGABRT inside CHyprAnimationManager::tick() on a
-- __dynamic_cast - an animated variable whose owning object had already been
-- freed. hyprbars registers animated vars per titlebar, and opening a new
-- window (Zen) tripped it. The whole session went down.
--
-- Plugins run INSIDE the compositor process, so this is not recoverable from
-- and not worth an auto-load. The package and the setup script are still on
-- disk: run the script by hand, or SUPER+SHIFT+B, if you want bars for a
-- session and accept the crash risk.
-- ─────────────────────────────────────────────────────────────────────
-- macOS traffic lights (hyprbars).
--
-- Registered on BOTH events on purpose:
--   hyprland.start   - boot
--   config.reloaded  - `hyprctl reload` wipes plugin config, window rules AND
--                      the button list, so it has to be rebuilt afterwards.
--
-- A plain top-level hl.exec_cmd was tried first and is NOT reliable here: it
-- re-ran on some reloads and not others, leaving bars stripped at random.
-- The script itself is flock-guarded, so overlapping events queue instead of
-- racing (racing is what once produced a titlebar with forty buttons).
-- hl.on("hyprland.start", function()
--     hl.exec_cmd("$HOME/.config/hypr/custom/scripts/hyprbars-setup.sh")
-- end)

-- hl.on("config.reloaded", function()
--     hl.exec_cmd("$HOME/.config/hypr/custom/scripts/hyprbars-setup.sh")
-- end)
