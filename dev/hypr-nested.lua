-- Nested Hyprland for openagentisland development.
--
-- Runs as a Wayland CLIENT of the host compositor, so it appears as an ordinary
-- window on the real desktop. dev/nested.sh pins that window to workspace 1.
--
-- Everything it reads comes from the shadow XDG tree nested.sh builds inside the
-- worktree, so this session cannot see or write the live ~/.config.
--
-- Lua, not .conf: Hyprland 0.56 warns that .conf support is removed in 0.57.

-- Wildcard output (empty name) so it applies whatever the nested output is
-- called — WL-1 / WAYLAND-1 vary between sessions. The nested compositor sizes
-- its output to the host window, so nested.sh setting the window size is what
-- actually determines the resolution.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})

hl.env("qsConfig", "openagentisland")

-- Former exec-once commands go inside this handler. This is what actually
-- starts the shell; without it the nested session is an empty compositor.
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c openagentisland")
end)

hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0
    },

    -- Off so screenshots are deterministic and the nested session stays cheap:
    -- it shares a GPU with the real desktop, which is still doing its job.
    animations = {
        enabled = false
    },

    decoration = {
        blur = {
            enabled = false
        },
        shadow = {
            enabled = false
        }
    },

    input = {
        kb_layout = "us",
        follow_mouse = 1
    }
})

-- Escape hatch: the nested session grabs input while focused.
-- Key strings are joined with "+", not commas. "SUPER SHIFT, Q" fails to parse
-- and takes every other bind down with it into emergency mode.
hl.bind("SUPER + SHIFT + Q", hl.dsp.exit(), { description = "Quit the nested session" })
