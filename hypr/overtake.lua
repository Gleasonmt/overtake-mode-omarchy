-- Familiar desktop shortcuts, loaded from bindings.lua only while Overtake Mode is
-- on (`overtake on`). Turning the mode off removes them on the next reload,
-- which brings Omarchy's own SUPER+L and SUPER+V back.

o.bind("ALT + F4", "Close window", hl.dsp.window.close())
o.bind("SUPER + E", "File Explorer", { omarchy = "nautilus" })
o.bind("SUPER + R", "Run", "omarchy-menu toggle apps")
o.bind("SUPER + I", "Settings", "overtake settings")
o.bind("SUPER + D", "Show desktop", "overtake show-desktop")
o.bind("SUPER + PERIOD", "Emojis", "omarchy-shell shell toggle omarchy.emojis")
o.bind("CTRL + SHIFT + ESCAPE", "Task Manager", { tui = "btop" })
o.bind("SUPER + CTRL + ALT + SPACE", "Next Overtake wallpaper", "overtake next-wallpaper")

-- New windows open floating (centered); the title bar's snap layouts and
-- Super+arrows place them. `overtake off` tiles them again.
o.window(".*", { float = true, center = true })

-- Snap Layouts (Super+Z), and Super+Left/Right snap to a half.
-- Was: focus the window left/right.
o.bind("SUPER + Z", "Snap layouts", "overtake snap-layouts")
hl.unbind("SUPER + LEFT")
o.bind("SUPER + LEFT", "Snap window left", "overtake snap left")
hl.unbind("SUPER + RIGHT")
o.bind("SUPER + RIGHT", "Snap window right", "overtake snap right")

-- Was: focus the window below/above. Here they minimize/maximize.
hl.unbind("SUPER + DOWN")
o.bind("SUPER + DOWN", "Minimize window", "overtake minimize")
hl.unbind("SUPER + UP")
o.bind("SUPER + UP", "Maximize window", "overtake maximize")

-- Was: toggle workspace layout (no shortcut while Overtake Mode is on; use
-- `omarchy hyprland workspace layout toggle`).
hl.unbind("SUPER + L")
o.bind("SUPER + L", "Lock", "omarchy-system-lock")

-- Was: universal paste. SUPER+V opens clipboard history instead.
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard history", "omarchy-shell shell toggle omarchy.clipboard")

-- Omarchy suppresses every app's own maximize request. Overtake Mode honours them,
-- so replace that suppression with a harmless one (later rules win).
o.window(".*", { suppress_event = "fullscreenoutput" })

-- Start menu search (Super+S) and the quick-link menu (Super+X).
-- Were: toggle the scratchpad, and universal cut (Ctrl+X still cuts).
hl.unbind("SUPER + S")
o.bind("SUPER + S", "Start menu search", "overtake start")
hl.unbind("SUPER + X")
o.bind("SUPER + X", "Quick link menu", "overtake start quick")

-- Tapping the Super key on its own opens Start.
o.bind("SUPER + SUPER_L", "Start menu", "overtake start", { release = true })

-- Resize windows by dragging their edges and corners.
hl.config({ general = { resize_on_border = true } })
