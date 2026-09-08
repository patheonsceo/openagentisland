-- ============================================================
-- User overrides. Loaded AFTER hyprland/general.lua, so these win.
-- Backups: ~/.config/hypr/.backups/
-- ============================================================

hl.monitor({ output = "eDP-1", mode = "2880x1800@90", position = "0x0", scale = 1.5 })

-- ------------------------------------------------------------
-- INPUT / POINTER FEEL
-- Touchpad measured at 147 Hz, 0.32 ms jitter -> hardware is clean.
-- These are feel knobs, not smoothness fixes.
-- ------------------------------------------------------------
hl.config({
    input = {
        accel_profile = "adaptive",  -- explicit; macOS-style accel (flat feels dead on a trackpad)
        sensitivity   = 0.12,        -- slight lift; 2880x1800@1.5 makes stock feel sluggish

        touchpad = {
            natural_scroll       = true,
            scroll_factor        = 0.7,
            clickfinger_behavior = true,
            -- was true: libinput was firing "palm: keyboard timeout" constantly,
            -- freezing the pointer for ~400ms after every keystroke. That dead
            -- zone reads as "jittery". libinput's size/pressure palm detection
            -- still runs without this.
            disable_while_typing = false,
        },
    },

    misc = {
        middle_click_paste = false,
    },

    cursor = {
        hotspot_padding  = 1,
        inactive_timeout = 0,   -- never hide; hiding/showing forces a KMS cursor re-import
    },
})

-- ------------------------------------------------------------
-- MOTION — Apple restraint, a touch quicker than macOS.
--
--   stiffness  = how fast        dampening = how much bounce
--   damping ratio  z = dampening / (2*sqrt(stiffness))
--   overshoot %    = exp(-pi*z / sqrt(1-z^2))
--     z = 1.00 -> 0%    (dead, reads as sluggish)
--     z = 0.76 -> 2.4%  (subtle settle -- what we want)
--     z = 0.57 -> 11.5% (cartoon bounce)
--   `speed` is IGNORED on springs; it only applies to bezier curves (ds, 1.6=160ms).
-- ------------------------------------------------------------
hl.curve("spaceGlide", { type = "spring", mass = 1, stiffness = 380, dampening = 32 }) -- z .82, 1.1% overshoot
hl.curve("winPop",     { type = "spring", mass = 1, stiffness = 445, dampening = 35 }) -- z .83, 0.9% overshoot
hl.curve("menuSnap",   { type = "spring", mass = 1, stiffness = 520, dampening = 40 }) -- z .88, ~200ms, no bounce
hl.curve("dragTrack",  { type = "spring", mass = 1, stiffness = 600, dampening = 44 }) -- z .90, ~180ms, tight

-- Exits: macOS dismisses in ~200ms, smooth, never bouncy.
hl.curve("outEase",  { type = "bezier", points = { {0.4, 0.0},  {0.7, 1.0}  } })
hl.curve("outSharp", { type = "bezier", points = { {0.3, 0.0},  {0.8, 0.15} } })

-- workspaces — the one you flagged
hl.animation({ leaf = "workspaces",          enabled = true, speed = 3,   spring = "spaceGlide", style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 3,   spring = "winPop",     style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.6, bezier = "outEase",    style = "slidevert" })

-- windows
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 3,   spring = "winPop",    style = "popin 90%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 1.6, bezier = "outEase",   style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3,   spring = "dragTrack", style = "slide" })
hl.animation({ leaf = "border",      enabled = true, speed = 3,   spring = "menuSnap" })

-- fades
hl.animation({ leaf = "fadeIn",  enabled = true, speed = 3,   spring = "menuSnap" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.4, bezier = "outSharp" })

-- layers (menubar, dock, notch, launcher) — crisp, effectively no bounce
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3,   spring = "menuSnap", style = "popin 92%" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.2, bezier = "outEase",  style = "popin 95%" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 3,   spring = "menuSnap" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.4, bezier = "outSharp" })
