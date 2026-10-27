-- Overtake Mode, Studio look: Super works as a Command key. Loaded by
-- overtake.lua.
--
--  - App shortcuts: Super+<key> reaches the focused app as Ctrl+<key>
--    (Super+S saves, Super+T opens a tab, Super+Z undoes, ...). Super+C/V/X
--    are Omarchy's universal copy/paste/cut, which already work this way.
--  - Desktop shortcuts: Super+Space Spotlight, Super+Tab switch apps,
--    Super+Q quit, Super+H hide, Super+M minimize, Ctrl+Up Mission Control.
--  - Workspaces stay on Super+1-9 (as in Omarchy) and also answer
--    Ctrl+Left/Right. Alt+Left/Right jump a word, as Option does.

-- ---------- Sending keys to the focused app ----------
-- The same down/up split Omarchy's universal copy uses (Hyprland's
-- send_shortcut can leave a key stuck), sent to the focused surface.
local function send(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local function has_tag(window, wanted)
  for _, tag in ipairs((window and window.tags) or {}) do
    if tag:gsub("%*$", "") == wanted then return true end
  end
  return false
end

local function active_class()
  local window = hl.get_active_window()
  return window and window.class or "", window
end

-- Terminals take their app shortcuts with Ctrl+Shift (Ctrl alone sends
-- control codes: Ctrl+Z would suspend, Ctrl+S freeze output). Keys a
-- terminal has no use for (save, print, ...) aren't sent to it at all.
local function app_key(key, terminal_ok)
  return function()
    local _, window = active_class()
    if has_tag(window, "terminal") then
      if terminal_ok then send("CTRL + SHIFT", key) end
    else
      send("CTRL", key)
    end
  end
end

local function app_shortcut(combo, label, key, terminal_ok)
  hl.unbind(combo)
  o.bind(combo, label, app_key(key, terminal_ok))
end

app_shortcut("SUPER + A", "Select all", "A", true)
app_shortcut("SUPER + Z", "Undo", "Z", false)
hl.unbind("SUPER + SHIFT + Z")
o.bind("SUPER + SHIFT + Z", "Redo", function()
  local _, window = active_class()
  if not has_tag(window, "terminal") then send("CTRL + SHIFT", "Z") end
end)
app_shortcut("SUPER + S", "Save", "S", false)
app_shortcut("SUPER + F", "Find", "F", true)
app_shortcut("SUPER + G", "Find next", "G", false)
app_shortcut("SUPER + T", "New tab", "T", true)
app_shortcut("SUPER + N", "New window", "N", true)
app_shortcut("SUPER + O", "Open", "O", false)
app_shortcut("SUPER + P", "Print", "P", false)
app_shortcut("SUPER + R", "Reload", "R", false)
app_shortcut("SUPER + L", "Address bar", "L", false)
app_shortcut("SUPER + B", "Bold", "B", false)
app_shortcut("SUPER + I", "Italic", "I", false)
app_shortcut("SUPER + U", "Underline", "U", false)
app_shortcut("SUPER + J", "Downloads", "J", false)
app_shortcut("SUPER + Y", "History", "H", false)
hl.unbind("SUPER + SHIFT + T")
o.bind("SUPER + SHIFT + T", "Reopen closed tab", function()
  local _, window = active_class()
  if not has_tag(window, "terminal") then send("CTRL + SHIFT", "T") end
end)
-- Zoom: Ctrl +/-/0 in apps and terminals alike. (Were: resize window.)
-- (Super+0 stays workspace 10.)
for combo, key in pairs({ ["SUPER + equal"] = "equal", ["SUPER + minus"] = "minus" }) do
  hl.unbind(combo)
  o.bind(combo, "Zoom", function() send("CTRL", key) end)
end
hl.unbind("SUPER + code:20")
hl.unbind("SUPER + code:21")

-- Text navigation: Super+Left/Right go to the start/end of the line,
-- Super+Up/Down to the top/bottom, Super+Backspace deletes to the line start.
-- (Were: move focus between tiled windows; Studio's windows float.)
local function nav(combo, label, mods, key)
  hl.unbind(combo)
  o.bind(combo, label, function() send(mods, key) end)
end
nav("SUPER + LEFT", "Line start", "", "Home")
nav("SUPER + RIGHT", "Line end", "", "End")
nav("SUPER + UP", "Document start", "CTRL", "Home")
nav("SUPER + DOWN", "Document end", "CTRL", "End")
nav("SUPER + SHIFT + LEFT", "Select to line start", "SHIFT", "Home")
nav("SUPER + SHIFT + RIGHT", "Select to line end", "SHIFT", "End")
nav("SUPER + SHIFT + UP", "Select to document start", "CTRL + SHIFT", "Home")
nav("SUPER + SHIFT + DOWN", "Select to document end", "CTRL + SHIFT", "End")
nav("ALT + LEFT", "Word left", "CTRL", "Left")
nav("ALT + RIGHT", "Word right", "CTRL", "Right")
nav("ALT + SHIFT + LEFT", "Select word left", "CTRL + SHIFT", "Left")
nav("ALT + SHIFT + RIGHT", "Select word right", "CTRL + SHIFT", "Right")
nav("ALT + BACKSPACE", "Delete word", "CTRL", "BackSpace")
-- Back and forward (browsers, Files).
nav("SUPER + bracketleft", "Back", "ALT", "Left")
nav("SUPER + bracketright", "Forward", "ALT", "Right")
hl.unbind("SUPER + BACKSPACE")
o.bind("SUPER + BACKSPACE", "Delete to line start", function() send("SHIFT", "Home"); hl.timer(function() send("", "BackSpace") end, { timeout = 80, type = "oneshot" }) end)

-- ---------- Windows and apps ----------
-- Super+W closes the tab in a browser (its last tab closes the window), the
-- window anywhere else. Super+Shift+W always closes the window.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close tab or window", function()
  local class = active_class()
  if class:match("^chromium") or class:match("^chrome%-") or class:match("^google%-chrome") or class:match("^brave") or class:match("^firefox") then
    send("CTRL", "W")
  else
    hl.dispatch(hl.dsp.window.close())
  end
end)
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "Close window", hl.dsp.window.close())
hl.unbind("SUPER + Q")
o.bind("SUPER + Q", "Quit app", "overtake quit-app")
hl.unbind("SUPER + M")
o.bind("SUPER + M", "Minimize window", "overtake minimize")
hl.unbind("SUPER + H")
o.bind("SUPER + H", "Hide app", "overtake hide-app")
hl.unbind("SUPER + ALT + H")
o.bind("SUPER + ALT + H", "Hide other apps", "overtake hide-others")
hl.unbind("SUPER + CTRL + F")
o.bind("SUPER + CTRL + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind("ALT + F4", "Close window", hl.dsp.window.close())

-- Tiling (the green button's choices): Super+Ctrl+arrows put the window in a
-- half or fill the screen; Down gives back its size from before.
-- (Were: grouped-window focus.)
local function tile(combo, label, command)
  hl.unbind(combo)
  o.bind(combo, label, command)
end
tile("SUPER + CTRL + LEFT", "Tile left", "overtake snap left")
tile("SUPER + CTRL + RIGHT", "Tile right", "overtake snap right")
tile("SUPER + CTRL + UP", "Fill screen", "overtake snap full")
tile("SUPER + CTRL + DOWN", "Return to previous size", "overtake unsnap-active")
tile("SUPER + CTRL + C", "Center window", "overtake snap center")

-- App switcher: hold Super, tap Tab (Shift+Tab goes back); let go to switch.
-- Super+` cycles the focused app's own windows.
hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Switch apps", "overtake ui switcher")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + SHIFT + TAB", "Switch apps (back)", "overtake ui switcher-back")
-- Letting go of Super switches (the switcher also sees the release itself,
-- unless Super came up before it had the keyboard).
o.bind("SUPER + SUPER_L", "Switch to the picked app", "overtake ui switcher-commit", { release = true })
hl.unbind("SUPER + grave")
o.bind("SUPER + grave", "Next window of this app", "overtake ui app-windows")

-- ---------- Desktop ----------
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Spotlight", "overtake ui spotlight")
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + ALT + SPACE", "Omarchy menu", "omarchy-menu toggle")
hl.unbind("SUPER + comma")
o.bind("SUPER + comma", "Settings", "overtake settings")
hl.unbind("SUPER + CTRL + Q")
o.bind("SUPER + CTRL + Q", "Lock screen", "omarchy-system-lock")
hl.unbind("SUPER + ALT + ESCAPE")
o.bind("SUPER + ALT + ESCAPE", "Force Quit", "overtake ui force-quit")
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Emoji & symbols", "omarchy-shell shell toggle omarchy.emojis")
o.bind("SUPER + F3", "Show desktop", "overtake show-desktop")
o.bind("CTRL + SHIFT + ESCAPE", "Activity monitor", { tui = "btop" })
hl.unbind("SUPER + E")
o.bind("SUPER + E", "Files", { omarchy = "nautilus" })

-- Screenshots: Super+Shift+3 the whole screen, 4 a region, 5 the capture
-- menu (the keys by position, as Omarchy binds them; were: move the window
-- to workspace 3/4/5, which dragging it onto a workspace box still does).
for code, binding in pairs({
  [12] = { "Screenshot of the screen", "omarchy-capture-screenshot fullscreen" },
  [13] = { "Screenshot of a region", "omarchy-capture-screenshot region" },
  [14] = { "Capture menu", "omarchy-menu toggle capture" },
}) do
  hl.unbind("SUPER + SHIFT + code:" .. code)
  o.bind("SUPER + SHIFT + code:" .. code, binding[1], binding[2])
end

-- Mission Control (Ctrl+Up) and the next/previous workspace (Ctrl+Left/Right).
o.bind("CTRL + UP", "Mission Control", "overtake ui mission-control")
o.bind("CTRL + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "r-1" }))
o.bind("CTRL + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "r+1" }))
