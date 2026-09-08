hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Vicinae: Raycast/Spotlight-style launcher (added 2026-06-07)
hl.bind("SUPER + Space", hl.dsp.exec_cmd("vicinae toggle"), {description = "Launch Vicinae launcher"})

-- Super+E now opens the Yazi "Finder" via the fileManager override (see custom/variables.lua).
-- Dolphin (GUI files) kept on Super+Shift+E. Added 2026-06-07.
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("dolphin"), {description = "App: Dolphin (GUI files)"})

-- Fix: "Send window to workspace" (Super+Alt+N) was moving ALL windows, not just
-- the active one. Upstream keybinds.lua registers BOTH a keysym bind ("SUPER+ALT+3")
-- AND a keycode bind ("SUPER+ALT+code:12") for the same physical key. On this layout
-- both match one press, so hl.dsp.window.move fires twice: it moves the active window,
-- focus falls to the next window, and the second fire moves that one too.
-- Drop the redundant keysym variant; the layout-robust keycode binds (number row +
-- numpad) still fire exactly once. Added 2026-06-08.
for i = 0, 9 do
    hl.unbind("SUPER + ALT + " .. i)
end

-- Hyprvoice push-to-talk: HOLD Right Ctrl to dictate, release to transcribe →
-- text types at the cursor. Fn is EC/firmware-level on this laptop (emits no
-- keycode), so Right Ctrl is the hold key. The island's Hyprvoice service owns
-- `hyprvoice toggle` (via the hyprvoicePtt global shortcut) so the notch
-- animates instantly; the exec fallbacks keep dictation working headless if
-- quickshell is down. Right Ctrl is consumed — use Left Ctrl for shortcuts.
-- Added 2026-07-07.
local qsIsAlive = "qs -c $qsConfig ipc call TEST_ALIVE"
hl.bind("Control_R", hl.dsp.global("quickshell:hyprvoicePtt"),
    { ignore_mods = true, description = "Hyprvoice: push-to-talk (hold to dictate)" })
hl.bind("Control_R", hl.dsp.global("quickshell:hyprvoicePtt"),
    { ignore_mods = true, release = true })
hl.bind("Control_R", hl.dsp.exec_cmd(qsIsAlive .. " || hyprvoice toggle"), { ignore_mods = true })
hl.bind("Control_R", hl.dsp.exec_cmd(qsIsAlive .. " || hyprvoice toggle"),
    { ignore_mods = true, release = true })

-- ============================================================================
-- FLOAT/TILE TOGGLE — shrink + center on the way out. Added 2026-08-31.
--
-- Stock SUPER+ALT+Space pops a window out to floating at full size, so it
-- covers the screen and there is no desktop showing to aim at. This shrinks it
-- to a fraction of the usable area and drops it in the middle, so there is
-- always an edge to grab.
--   SUPER + drag LMB = move        SUPER + drag RMB = resize
--
-- Floating -> tiled is untouched: plain toggle, no resizing.
--
-- Only *big* windows get shrunk. Hyprland floats a window at roughly full size
-- when it has no floating geometry for it yet, but restores the smaller size
-- once you have resized one by hand -- so the size test below is what keeps
-- your own sizes from being overwritten on every toggle. Set keep_manual=false
-- to always force the size below instead.
-- ============================================================================
local FLOAT = {
    -- <= 1 means "fraction of the usable area" (screen minus menubar + dock).
    -- >  1 means exact logical pixels.  0.55 = 55% of the width; 900 = 900px.
    width  = 0.55,
    height = 0.62,

    center       = true, -- put it in the middle of the screen
    keep_manual  = true, -- keep a floating size you set by hand
    big_if_over  = 0.80, -- counts as "big" at >= this much of the usable area
    min_size     = 240,  -- never shrink below this many px

    -- Per-app sizes. Key is the window class: hyprctl activewindow -j | jq -r .class
    per_class = {
        -- ["kitty"]                      = { width = 0.45, height = 0.55 },
        -- ["zen"]                        = { width = 0.72, height = 0.80 },
        -- ["org.pulseaudio.pavucontrol"] = { width = 600,  height = 500  },
    },
}

local function float_px(value, basis)
    if value <= 1 then value = basis * value end
    return math.max(FLOAT.min_size, math.floor(value + 0.5))
end

local function float_toggle()
    local w = hl.get_active_window()
    if not w then return end

    -- Floating -> tiled, or a fullscreen window: just toggle, touch nothing else.
    if w.floating or w.fullscreen ~= 0 then
        hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
        return
    end

    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    w = hl.get_active_window()
    if not w or not w.floating then return end

    -- m.size is the raw mode, before rotation; transforms 1/3/5/7 are the
    -- 90/270-degree ones, which swap the axes (matters on DP-3).
    local m = w.monitor
    local mw, mh = m.width, m.height
    if m.transform % 2 == 1 then mw, mh = mh, mw end
    local usable_x = mw / m.scale - m.reserved.left - m.reserved.right
    local usable_y = mh / m.scale - m.reserved.top - m.reserved.bottom

    -- Came back small => that is a size you picked. Leave it.
    if FLOAT.keep_manual
        and w.size.x < usable_x * FLOAT.big_if_over
        and w.size.y < usable_y * FLOAT.big_if_over then
        return
    end

    local size = FLOAT.per_class[w.class] or FLOAT
    hl.dispatch(hl.dsp.window.resize({
        x = float_px(size.width, usable_x),
        y = float_px(size.height, usable_y),
        "exact",
    }))
    if FLOAT.center then hl.dispatch(hl.dsp.window.center()) end
end

-- Replace the upstream bind rather than adding a second one on the same key:
-- both would fire on one press (same trap as the SUPER+ALT+number binds above).
hl.unbind("SUPER + ALT + Space")
hl.bind("SUPER + ALT + Space", float_toggle, { description = "Window: Float/Tile" })

-- Restore the macOS traffic lights after a `hyprctl reload`.
--
-- A reload wipes hyprbars' config, window rules AND its button list. Neither a
-- top-level exec_cmd nor an hl.on("config.reloaded") handler reliably re-runs
-- afterwards - both were tried and both fired only sometimes. Rather than
-- leave it to chance, this is the explicit one-key fix. Boot is handled by
-- the hyprland.start hook in custom/execs.lua and needs no key press.
hl.bind("SUPER + SHIFT + B",
    hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/hyprbars-setup.sh"),
    { description = "Restore window traffic lights (after hyprctl reload)" })
