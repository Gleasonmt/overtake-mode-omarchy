-- Overtake Mode, Classic look: familiar desktop shortcuts for the taskbar and
-- Start menu. Loaded by overtake.lua.

o.bind("ALT + F4", "Close window", hl.dsp.window.close())
o.bind("SUPER + E", "File Explorer", { omarchy = "nautilus" })
o.bind("SUPER + R", "Run", "omarchy-menu toggle apps")
hl.unbind("SUPER + I")   -- (Omarchy 4.5: input-language switching)
o.bind("SUPER + I", "Settings", "overtake settings")
o.bind("SUPER + D", "Show desktop", "overtake show-desktop")
hl.unbind("SUPER + M")   -- (Omarchy 4.5's minimize works only on its floating workspaces)
o.bind("SUPER + M", "Minimize window", "overtake minimize")
o.bind("SUPER + PERIOD", "Emojis", "omarchy-shell shell toggle omarchy.emojis")
o.bind("CTRL + SHIFT + ESCAPE", "Task Manager", { tui = "btop" })

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

-- Was: cycle workspace layout. Omarchy's layouts bring their own title bars and
-- Dock, which don't mix with Overtake's, so neither shortcut does that here.
hl.unbind("SUPER + ALT + L")
hl.unbind("SUPER + L")
o.bind("SUPER + L", "Lock", "omarchy-system-lock")

-- Was: universal paste. SUPER+V opens clipboard history instead.
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard history", "omarchy-shell shell toggle omarchy.clipboard")

-- Start menu search (Super+S) and the quick-link menu (Super+X).
-- Were: toggle the scratchpad, and universal cut (Ctrl+X still cuts).
hl.unbind("SUPER + S")
o.bind("SUPER + S", "Start menu search", "overtake start")
hl.unbind("SUPER + X")
o.bind("SUPER + X", "Quick link menu", "overtake start quick")

-- Tapping the Super key on its own opens Start.
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + ALT + SPACE", "All apps", "overtake start all")
o.bind("SUPER + SUPER_L", "Start menu", "overtake start", { release = true })
