-- Overtake Mode's Hyprland settings, loaded from bindings.lua only while the
-- mode is on (`overtake on`). Turning the mode off removes them on the next
-- reload, which brings Omarchy's own bindings back. The rules here are shared
-- by both looks; each look's shortcuts are in overtake-classic.lua (taskbar,
-- Start) or overtake-studio.lua (menu bar, Dock, Super as Command).

o.bind("SUPER + CTRL + ALT + SPACE", "Next Overtake wallpaper", "overtake next-wallpaper")

-- New windows open floating (centered); the title bar's snap layouts and
-- the snap shortcuts place them. `overtake off` tiles them again.
o.window(".*", { float = true, center = true })

-- Omarchy suppresses every app's own maximize request. Overtake Mode honours them,
-- so replace that suppression with a harmless one (later rules win).
o.window(".*", { suppress_event = "fullscreenoutput" })

-- Resize windows by dragging their edges and corners.
hl.config({ general = { resize_on_border = true } })

-- Touchpad: the bottom-right corner right-clicks, as on most laptops (Omarchy
-- uses a two-finger click, which makes the whole bottom edge a left click).
-- Two-finger click and tap still work.
hl.config({ input = { touchpad = { clickfinger_behavior = false } } })

-- Studio's glass: blur what's behind the Dock, menus and panels.
hl.layer_rule({ match = { namespace = "^overtake-(dock|spotlight|switcher|mission|forcequit)$" }, blur = true, ignore_alpha = 0.3 })

local home = os.getenv("HOME") or ""
local style = "classic"
local style_file = io.open(home .. "/.config/overtake/style", "r")
if style_file then
  if (style_file:read("*l") or ""):match("^%s*studio%s*$") then style = "studio" end
  style_file:close()
end
dofile(home .. "/.config/hypr/overtake-" .. style .. ".lua")
