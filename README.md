# Overtake Mode (Omarchy)

![Overtake Mode: Omarchy, Classic and Studio side by side](preview.png)

A classic desktop you can switch on and off inside [Omarchy](https://omarchy.org):
a bottom taskbar with a Start menu, title bars with minimize / maximize / close,
snap layouts, desktop icons, a Settings window, and familiar shortcuts. It's an
on-ramp for people coming from other desktops: ease in with what you know, and
switch to Omarchy's own keyboard-first tiling whenever you're ready. One
shortcut switches either way. Omarchy's own files aren't modified: the
changes Overtake makes to your config are listed under
[What it installs](#what-it-installs), and uninstalling reverses them.

It comes in two modes, switchable any time (`overtake style classic|studio`,
Settings → Overtake Mode, or the Omarchy menu):

- **Classic** — taskbar and Start menu along the bottom.
- **Studio** — a menu bar along the top, a Dock at the bottom, Spotlight
  search, and the Super key working as a Command key. See [Studio](#studio).

![Overtake Mode: Omarchy, Classic and Studio, one after another](media/modes.webp)

> Status: early. Tested on Omarchy 4.5.0 (Hyprland, the Quickshell-based
> Omarchy shell). Feedback and pull requests welcome in Issues.

## Install

```bash
git clone https://github.com/Gleasonmt/overtake-mode-omarchy.git
cd overtake-mode-omarchy
git checkout "$(git tag --sort=-v:refname | head -1)"  # the latest release
./install.sh
```

The installer first asks about four optional extras (each off unless you say
yes), then lists every file it will add and every file of yours it will change
(see [What it installs](#what-it-installs)), and writes nothing until you say
yes. An update keeps your earlier choices.

| Option | Does |
| --- | --- |
| `--dry-run` | only list what would change |
| `--yes` | don't ask (for scripts and updates; the extras stay as they are, off on a first install) |
| `--link-handler` | optional: links clicked in other apps open on the workspace you're on (changes `omarchy-browser.desktop`) |
| `--image-viewer` | optional: images open with their whole folder in `imv-dir` (changes your default image viewer) |
| `--style-menus` | optional: Overtake's **Appearance → Background** and **Appearance → Theme** in the Omarchy menu, in every mode |
| `--name-tags` | optional: name tags on Claude Code windows, in every mode (reads `~/.claude/sessions`), and Super+Alt+N |
| `--no-link-handler`, `--no-image-viewer`, `--no-style-menus`, `--no-name-tags` | turn one off (an update takes it back out) |

Needs Omarchy 4.5 or later (tested on 4.5.0). Everything it uses ships with Omarchy:
`jq`, `python3`, `hyprctl`, `fd`, ImageMagick (`magick`), `notify-send`,
`gtk-launch`, `wl-copy` and `file`. Optional: `imv-dir` (ships with imv) for
folder-browsing image viewing, and Nautilus for the Trash app.

Then switch it on with **Super + Ctrl + Shift + W**, `overtake on`, or
**Omarchy menu → Overtake Mode**. Each press of the shortcut goes to the next
mode: Omarchy → Classic → Studio → back to Omarchy. The ⇄ button next to
Start also switches back to Omarchy.

To update, get the newest release and run the installer again (your own
settings in `~/.config/overtake` are never overwritten):

```bash
git fetch --tags && git checkout "$(git tag --sort=-v:refname | head -1)" && ./install.sh
```

Added it with `omarchy plugin add` (or from the plugin marketplace)? That only
copies this repository into `~/.config/omarchy/plugins/gleasonmt.overtake-mode`,
whose small root plugin (`Setup.qml`) reminds you to finish with
`./install.sh` in that folder. Overtake Mode is a suite, so the installer is
what sets it up; after `omarchy plugin update`, run `./install.sh` there again.

## See it in action

**Classic:** a taskbar, desktop icons and a Start menu with your pinned apps,
folders and recent files.

![Classic: the desktop, taskbar and Start menu](media/desktop-start.webp)

**Snap windows** to halves, quarters or full screen, and back.

![Snapping windows](media/snap.webp)

**Snap layouts:** hover the maximize button, or press Super + Z.

![Snap layouts](media/snap-layouts.webp)

**Settings** for display, power and battery alerts for every device, screensaver,
themes and more (Super + I).

![Settings](media/settings.webp)

**Notification center:** notifications slide off the screen into the bell,
grouped by app, with per-app Show / Quiet / Off and Do Not Disturb.

![Notification center](media/notification-center.webp)

## What you get

- **Taskbar** — Start button, pinned apps, the apps open on this workspace
  (one taskbar per workspace, like virtual desktops), right-click menus, and
  a picker when an app has several windows. Choosing a window takes you to
  its workspace.
- **Start menu** — type to search apps, pinned apps (right-click to pin or
  unpin), All apps, Folders with a small file browser, Recommended recent
  files, and power options.
- **Title bars** — minimize, maximize and close on every window, drag to move,
  double-click to maximize, and tabs when windows share a snap section.
- **Snap layouts** — drag a window and the layouts appear right next to the
  pointer; hover the maximize button, or press Super + Z. A preview shows
  where the window will land.
- **Move to a workspace by dragging** — while you drag a window, workspaces
  1–9 show as boxes along the top of the screen (a dot marks ones with
  windows). Drop it on one to send it there; you stay where you are.
- **New windows fill the gaps** — open an app or click a link next to a
  snapped window and it lands in the half or quarter left free (Settings >
  Overtake Mode turns this off). With `--link-handler`, links open on the
  workspace you're on, in the browser window there or a new one.
- **Windows stay put** — sections and positions survive docking, undocking,
  and switching back and forth with Omarchy mode.
- **Settings** — Super + I opens a Settings window for display, sound,
  Bluetooth, Wi-Fi, power, themes, fonts, default apps, time and updates.
- **Notification center** — toasts slide off after 10 seconds (critical ones
  after 15) into the bell at the end of the taskbar, which counts new ones.
  Its panel groups them by app, newest first; open an app to see its
  notifications, click one to act on it (runs its action or brings the app
  forward), or clear one, an app's, or all. It holds what Omarchy keeps: the
  last 100, for a day. The gear opens **Manage**, where each app is set to
  Show, Quiet (no pop-ups, still collected) or Off (saved in
  `~/.config/overtake/notifications.json`). Do Not Disturb sits at the bottom.
- **Touchpad right-click in the corner** — the bottom-right of the touchpad
  right-clicks, as on most laptops (Omarchy uses a two-finger click).
- **Battery alerts for every device** — the laptop and anything connected that
  reports a battery (Bluetooth or USB mice, keyboards, headsets, controllers)
  each get a Low and a Critical alert at levels you choose, in Settings →
  Power & battery (kept in `~/.config/overtake/battery-alerts.json`). Critical
  ones get through Do Not Disturb. They replace Omarchy's single 10% laptop
  warning while the mode is on; its `battery-low` hook still runs.
- **Click the desktop to see it** — a click on empty desktop minimizes the
  windows on that workspace.
- **Screensaver & lock settings** — Settings → Screensaver & lock (or right-click
  the desktop): on/off, when it starts and when the screen locks, and what it shows:
  Omarchy's logo, your wallpaper turned into screensaver art, an image, or your own text.
- **Image folders** (optional, `--image-viewer`) — opening an image opens its
  whole folder in the image viewer, so the left and right arrow keys step
  through the others.
- **Themes in folders** — Settings → Personalization shows your themes first,
  each section foldable. With `--style-menus`, Omarchy menu → Appearance → Theme
  opens Omarchy themes, Your themes (the ones you added) or All themes, in
  plain Omarchy too.
- **Desktop with right-click menus** — right-click an icon to open, pin to
  Start, rename, move or remove it (and empty the Trash); right-click the
  desktop for icon size, sort, show/hide icons, add a shortcut (Start → right-
  click an app → Add to desktop), background, theme, Personalize and Display
  settings.
- **Desktop icons**, a **wallpaper slideshow** (rotate every 15 minutes, or
  follow sunrise and sunset), and an **Overtake Mode** entry in the Omarchy menu.
  A wallpaper you pick yourself stays put; Super+Ctrl+Alt+Space goes back to
  the slideshow.
- **Every wallpaper in Appearance → Background** (the desktop's right-click menu;
  in the Omarchy menu too with `--style-menus`), named by where it comes from: this theme's own ("Topside Mountain
  View (This Theme, Live)"), the live wallpapers of your other themes
  ("Topside Dusk (Live)"), the Classic and Studio pictures, then every other
  theme's backgrounds, Omarchy's own included ("Tokyo Night 2"). So a
  different live wallpaper doesn't mean a different theme: the theme sets
  the colours, Background sets the wallpaper.
- **Name tags on Claude Code windows** (optional, `--name-tags`), in all
  three modes (plain Omarchy too). A small tag across the top edge of each Claude Code window shows its
  name, or Claude's own title, dimmed, until you name it. Click the tag, or
  press Super+Alt+N on the focused window, type a name, then Enter (Escape
  cancels, an empty name clears it). Renaming from the taskbar or the title
  bar sets the same name. A name stays with its Claude session, so it comes
  back when the session is resumed (`claude --resume`, or after a reboot).
  Other windows get a tag once you name them. From inside a window,
  `echo "<name>" | overtake name here -` renames its own tag (so a Claude
  session can rename itself when its topic changes), without the name showing
  in the process list (`overtake name here "<name>"` works too, but the name is
  then visible there).
- **A theme and wallpaper per mode** — Omarchy (Overtake Mode off), Classic and Studio each
  remember their own theme and wallpaper. Pick a theme while in Studio and
  Studio keeps it; switching modes puts each one's back.

## Studio

The second mode, for people used to a menu bar and a Dock. Everything else
above (title bars, snapping, notifications, Settings, battery alerts,
wallpapers, dock/undock layouts) works the same in both modes.

- **Menu bar** — the Omarchy logo opens the system menu (About, System
  Settings, Force Quit, Sleep / Restart / Shut Down, Lock, Log Out, and the
  mode switch). Next to it, the focused app's name in bold, then File, Edit,
  View, Window and Help. Linux apps don't hand their own menus to the
  desktop, so these hold what works in every app: new window and tab, the
  edit keys (sent to the app), full screen, zoom, tiling, and the app's
  windows. Workspace numbers sit in the middle (click one to go there);
  status icons, Spotlight and Control Center on the right; the
  clock opens the notification center.
- **Dock** — pinned and running apps (a dot means running), then Downloads
  (click for the newest files) and Trash. Click to open or switch to an app
  (clicking the focused app minimizes it, clicking it again brings it back; an
  app with several windows lists them, with their workspaces), middle-click
  for a new window, right-click for its windows, Keep in Dock,
  Hide and Quit; drag pinned apps to reorder. Size, magnification and
  auto-hide are in Settings → Overtake Mode.
- **Title bars** — close / minimize / zoom as coloured dots on the left, the
  title in the middle. Hold the pointer on the green dot (or Super + Z) for
  the tile menu: halves, quarters, Fill, Center, full screen.
- **Tiling by dragging** — drag a window to the left or right edge of the
  screen for a half, a corner for a quarter, the menu bar to fill the screen.
  The workspace boxes still appear along the top while you drag.
- **Spotlight** (Super + Space) — apps, actions (lock, sleep, theme, Wi-Fi,
  screenshot…), files in your home folder, and quick sums (`12*4`; Enter
  copies the answer). Tab switches to **Apps**, every app in a grid (also the
  first icon in the Dock); right-click an app there to keep it in the Dock.
- **App Switcher** (hold Super, tap Tab) — apps by most recent use; let go to
  switch, Q quits the picked app, Esc cancels. Super + \` steps through the
  focused app's windows.
- **Mission Control** (Ctrl + ↑) — live previews of this workspace's windows
  and the workspaces above them; click to go, drag a window onto a workspace
  to move it.
- **Control Center** — Wi-Fi, Bluetooth, Focus (do not disturb), Night Light,
  Stay Awake, screen recording and screenshots, display and sound sliders,
  and what's playing.
- **Force Quit** (Super + Alt + Esc) — end an app that has stopped responding.
- Desktop icons sit on the right, and Studio has its own wallpaper (Day &
  Night uses the hills pair, as in Classic).

### Studio shortcuts (Super works as Command)

| Keys | Does |
| --- | --- |
| Super + Space | Spotlight |
| Super + Tab | App Switcher |
| Super + Q / H / M | Quit the app / hide it / minimize the window |
| Super + Alt + H | Hide the other apps |
| Super + W | Close the tab (browsers) or the window |
| Super + C / V / X | Copy / paste / cut (Omarchy's universal keys) |
| Super + A / Z / Shift + Z / S / F / T / N / O / P / R / L | Reach the app as Ctrl + the same key (select all, undo, redo, save, find, new tab…); terminals get Ctrl + Shift where it makes sense |
| Super + ← / → / ↑ / ↓ | Start / end of the line, top / bottom of the document |
| Alt + ← / → / Backspace | Word left / right / delete a word |
| Super + [ / ] | Back / forward |
| Super + = / − | Zoom in / out |
| Ctrl + Super + ← / → / ↑ / ↓ / C | Tile left / right, fill, previous size, center |
| Ctrl + Super + F | Full screen |
| Ctrl + ↑ | Mission Control |
| Ctrl + ← / → | Previous / next workspace (Super + 1–9 still go straight to one) |
| Super + Shift + 3 / 4 / 5 | Screenshot of the screen / a region / the capture menu |
| Super + , | Settings |
| Super + Alt + Esc | Force Quit |
| Ctrl + Super + Q | Lock |
| Ctrl + Super + Space | Emoji |
| Super + Alt + Space | Omarchy menu |
| Super + F3 | Show desktop |

Like Classic's, these replace Omarchy shortcuts only while the mode is on.
Super + Shift + 3 / 4 / 5 take over moving a window to workspace 3–5
(dragging it onto a workspace box still does that).

## Shortcuts (Classic, while Overtake Mode is on)

| Keys | Does |
| --- | --- |
| Super (tap) | Start |
| Super + S | Start, ready to search |
| Super + X | Quick links menu |
| Super + E / I / R | Files / Settings / Run |
| Super + D | Show desktop |
| Super + M | Minimize the window |
| Super + Z | Snap layouts |
| Super + ← / → | Snap left / right |
| Super + ↑ / ↓ | Maximize / minimize |
| Super + L | Lock |
| Super + V | Clipboard history |
| Super + . | Emojis |
| Super + Ctrl + Alt + Space | Next wallpaper (back to the slideshow) |
| Ctrl + Shift + Esc | Task manager |
| Alt + F4 | Close window |
| Super + Ctrl + Shift + W | Next mode: Omarchy → Classic → Studio → Omarchy |

These replace a few Omarchy shortcuts only while the mode is on (for example
Super + S is normally the scratchpad, and Super + I switches input language;
Studio also takes Super + Shift + W, Super + Shift + T, Super + Ctrl + Space
and Super + Ctrl + C); switching back restores them all. While the mode is on,
a workspace you set to Omarchy's floating layout is tiled in Omarchy's record
(Overtake floats every window itself, with its own title bars and Dock), and
turning the mode off puts your floating layouts back.

## Customising

All in `~/.config/overtake/`:

- `style` — `classic` or `studio` (`overtake style` sets it)
- `start-pinned.txt` — Start menu pins (or right-click apps in Start)
- `dock-pinned.txt` — Studio's Dock pins (or right-click apps in the Dock)
- `studio.json` — Studio's Dock size, magnification and auto-hide (Settings sets them)
- `desktop-icons.txt` — desktop icons (`trash`, `browser`, `terminal`, or any app)
- `no-controls.txt` — apps that keep their own window buttons instead of
  Overtake's title bar

`overtake` on its own lists every command (snap, minimize, wallpaper modes…).

## What it installs

| Where | What |
| --- | --- |
| `~/.local/bin/overtake` | the command |
| `~/.config/hypr/overtake.lua`, `overtake-classic.lua`, `overtake-studio.lua` | the window rules and each mode's shortcuts, loaded only while the mode is on |
| `~/.config/hypr/bindings.lua`, `autostart.lua` | a few lines between `>>> overtake` / `<<< overtake` markers: the mode shortcut, Super+Alt+N (name a window; only with `--name-tags`), loading the mode's shortcuts while it's on, and resuming the slideshow at login |
| `~/.config/omarchy/plugins/overtake.taskbar` | taskbar, Start menu, title bars, desktop icons, Settings; Studio's Dock, Spotlight, App Switcher, Mission Control and Force Quit |
| `~/.config/omarchy/plugins/overtake.menubar`, `overtake.control-center` | Studio's menu bar, and its Spotlight and Control Center buttons |
| `~/.config/omarchy/plugins/overtake.{workspaces,bluetooth,audio}` | copies of Omarchy's own widgets, made from your installed Omarchy, with small changes (no gaps in the workspace list; right-click opens the Bluetooth and sound panels instead of turning Bluetooth off or muting) |
| `~/.config/omarchy/plugins/overtake.notifications` | a copy of Omarchy's notifications (one file changed, `Service.qml`) where, while the mode is on, critical toasts leave after 15 s for the notification center instead of staying, normal ones after 10 s, each app's Show / Quiet / Off from Manage applies, and a critical battery alert gets through Do Not Disturb; it also answers the notification center's remove and Clear all (Omarchy's history is the service's own file). With Overtake Mode off it behaves like Omarchy's own, so switching needs no shell restart |
| `~/.config/omarchy/plugins/overtake.battery` | a copy of Omarchy's battery service; while the mode is on its fixed 10% warning gives way to Overtake's battery alerts, otherwise it's Omarchy's own |
| `~/.config/omarchy/plugins/overtake.notification-center` | the bell and its panel; it reads Omarchy's notification history (`~/.local/state/omarchy/notifications/history.json`) and Do Not Disturb (`quiet.json`), watched, not polled. `omarchy-shell overtake.notification-center toggle` opens it |
| `~/.config/omarchy/plugins/overtake.session-names` | only with `--name-tags`: the name tags on Claude Code windows (and named ones), loaded in every mode; names live in `~/.local/state/overtake/names.json` and, per Claude session, `session-names.json` |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | between markers: the Overtake Mode menu entry, and with `--style-menus` Overtake's own **Appearance → Background** (every theme's wallpapers, see above) and **Appearance → Theme** (Omarchy's themes and yours in separate lists). These two replace Omarchy's in every mode, Omarchy included; uninstalling brings Omarchy's back |
| `~/.config/omarchy/shell.json` | `overtake.notifications` and `overtake.battery` (and with `--name-tags` `overtake.session-names`) enabled (through `omarchy plugin enable`), in place of Omarchy's own notifications and battery, which Omarchy switches off while its copy is on, in every mode; if you had Omarchy's own notifications or battery turned off, uninstalling leaves them off |
| `~/.config/overtake/`, `~/Pictures/overtake/` | your settings and the wallpapers |
| `~/.local/state/overtake/` | its state: the mode, saved Omarchy bar and looks, window places and names (readable only by you) |
| `~/.cache/overtake/` | the lists behind Appearance → Background and Theme (links to the pictures). Their previews are made by Omarchy's own picker (`omarchy-menu-images`) in its cache, `~/.cache/omarchy/image-selector`, as for Omarchy's own Background menu; the installer makes them once in the background so the first opening doesn't wait |
| `~/.local/share/overtake/` | a copy of the uninstaller, so `overtake uninstall` works without the repository, and of the patcher (`patches/apply.py`, `NOTICE.md`) for rebuilding the copies |
| `~/.config/omarchy/hooks/post-update.d/overtake.hook` | runs `overtake build-copies update` near the end of `omarchy update`: the copies of Omarchy's plugins are rebuilt from the updated Omarchy, and the shell reloads a changed plugin folder by itself. The same check runs at login (`overtake resume`), so an Omarchy update made outside `omarchy update` is caught too |
| `~/.local/share/applications/overtake-trash.desktop` | Trash as an app, for Start, the taskbar and the desktop |
| `~/.local/share/applications/omarchy-browser.desktop` | its `Exec` line, so links from other apps open on your current workspace; only with `--link-handler`, and only if it's still Omarchy's |
| `~/.local/share/applications/overtake-image-viewer.desktop`, `xdg-mime` defaults | images open with their folder (`imv-dir`); only for types that open with imv or nothing, only with `--image-viewer`, and only if `imv-dir` is installed |

While the mode is on, `overtake` also saves your Omarchy bar layout and
swaps in its own (`~/.config/omarchy/shell.json`), adds a marked bar-size
block to `~/.config/omarchy/shell.toml` (each mode's bar height), and sets GTK apps'
title-bar buttons to none (`gsettings` `org.gnome.desktop.wm.preferences
button-layout`, since Overtake's title bars have them), and puts all of it
back when you switch to Omarchy. Your saved Omarchy layout lives in
`~/.local/state/overtake`.

`./uninstall.sh` undoes every row above, except that it keeps your settings
and wallpapers (`~/.config/overtake`, `~/Pictures/overtake`) unless you add
`--purge` (which also deletes pictures you added to those folders), and the
previews in Omarchy's own image cache stay for Omarchy to manage.

If a future Omarchy changes one of those widgets so the change no longer
applies, the installer says so and Overtake uses Omarchy's own one.

## Privacy

Overtake Mode sends nothing anywhere, with one exception: the **Day & Night**
wallpaper mode looks up today's sunrise and sunset from
[wttr.in](https://wttr.in), which estimates your location from your IP address.
The default **Rotate** mode makes no network requests. The Control Center
shows no album art (the picture comes from whichever player is playing).
Overtake's own folders (`~/.config/overtake`, `~/.local/state/overtake`,
`~/.cache/overtake`) are readable only by you.

What it reads on your machine, and keeps there:

- **Copy URL** (a browser window's title bar menu) looks the page up by its
  title in Chromium's, Chrome's or Brave's history database (read-only, in
  place) and copies the newest address with that title, so two open pages
  with the same title can give the other one's address.
- **Name tags** (optional, `--name-tags`) read `~/.claude/sessions/*.json` (just each Claude Code
  session's process id and session id), to find which window a session runs
  in and keep its name with it.
- **Start** lists your recent files from `~/.local/share/recently-used.xbel`;
  **Spotlight** lists your home folder with `fd` once each time it opens
  and matches what you type against that list in-process.
- Window names, Claude Code session ids and window places are kept in
  `~/.local/state/overtake`, readable only by you. Window titles and names
  are passed between Overtake's parts through pipes, not command lines, so
  they don't show up in the process list for other users.

## Uninstall

```bash
./uninstall.sh            # keeps ~/.config/overtake and the wallpapers
./uninstall.sh --purge    # removes those too
./uninstall.sh --dry-run  # only lists what it would do
overtake uninstall        # the same, from anywhere (takes the same options)
```

It lists what it will remove and asks first (`--yes` skips the question).
If you added the repository with `omarchy plugin add`, run `overtake uninstall`,
then `omarchy plugin remove gleasonmt.overtake-mode`.

## Known limits

- Apps that draw their own title bar and can't hide it (Discord's desktop app,
  for one) keep their own buttons; listed in `no-controls.txt`.
- Dragging such an app by its own title area snaps when you hold still over a
  layout for half a second, since Hyprland doesn't report their mouse button.
- Studio's menus are the same for every app (apps on Linux don't share
  their own menus with the desktop); app-specific commands stay in the app.
- Studio's Super-as-Command keys are sent to the app as Ctrl + key, so an app
  that uses a different key for something (say, find) won't respond to the
  usual one.
- Overtake's bar uses its own copies of Omarchy's workspaces, Bluetooth and
  sound widgets (all workspaces in use, no gaps; right-click opens the panel
  instead of turning Bluetooth off or muting). If Omarchy's originals end up
  back in the bar (disabling a copy does that), Overtake notices within a few
  seconds and swaps its copies back on its own (`overtake fix-bar` does the
  same by hand). After every `omarchy update`, Overtake rebuilds these copies
  (and its notifications and battery copies) from the new Omarchy, through a
  post-update hook; one whose changes no longer fit is removed, Omarchy's own
  is used instead, and a notification says so.
- Network picking, Bluetooth pairing and detailed sound settings open
  Omarchy's own panels; screen resolution and keyboard layouts open the
  config file.

## Wallpapers

Made for this project with an AI image model: the Classic slideshow pictures
and the Studio snow leopard. `wallpapers/src` has scripts that redraw three of
them.

Some pictures include the Omarchy logo.

## License

[MIT](LICENSE). Parts come from Omarchy (MIT); see [NOTICE.md](NOTICE.md).

Overtake Mode is an independent project, not affiliated with or endorsed by
Omarchy, 37signals, Apple or Microsoft. Names like Start menu, Dock and
Spotlight describe familiar behaviour.

Reviewing it for the plugin marketplace? See [REVIEWING.md](REVIEWING.md).
