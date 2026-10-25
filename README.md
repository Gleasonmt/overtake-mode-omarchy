# Overtake Mode (Omarchy)

A classic desktop you can switch on and off inside [Omarchy](https://omarchy.org):
a bottom taskbar with a Start menu, title bars with minimize / maximize / close,
snap layouts, desktop icons, a Settings window, and familiar shortcuts. It's an
on-ramp for people coming from other desktops: ease in with what you know, and
switch to Omarchy's own keyboard-first tiling whenever you're ready. One
shortcut switches either way, and Omarchy itself isn't changed.

> Status: early, private preview for friends to try. Tested on Omarchy 4.0.6
> (Hyprland, the Quickshell-based Omarchy shell). Feedback welcome in Issues.

## Install

```bash
git clone https://github.com/Gleasonmt/overtake-mode-omarchy.git
cd overtake-mode-omarchy
./install.sh
```

Then switch it on with **Super + Ctrl + Shift + W**, `overtake on`, or
**Omarchy menu → Overtake Mode**. The same shortcut, or the ⇄ button next to
Start, switches back to Omarchy.

Running `./install.sh` again updates it. Your own settings in `~/.config/overtake`
are never overwritten.

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
- **Windows stay put** — sections and positions survive docking, undocking,
  and switching back and forth with Omarchy mode.
- **Settings** — Super + I opens a Settings window for display, sound,
  Bluetooth, Wi-Fi, power, themes, fonts, default apps, time and updates.
- **Notification center** — toasts slide off after 10 seconds (critical ones
  after 15) into the bell at the end of the taskbar, which counts new ones.
  Its panel groups them by app, newest first; open an app to see its
  notifications, click one to act on it (runs its action or brings the app
  forward), or clear one, an app's, or all. The gear opens **Manage**, where
  each app is set to Show, Quiet (no pop-ups, still collected) or Off
  (saved in `~/.config/overtake/notifications.json`). Do Not Disturb sits at the
  bottom. Toasts on screen have an × too.
- **Battery alerts for every device** — the laptop and anything connected that
  reports a battery (Bluetooth or USB mice, keyboards, headsets, controllers)
  each get a Low and a Critical alert at levels you choose, in Settings →
  Power & battery (kept in `~/.config/overtake/battery-alerts.json`). Critical
  ones get through Do Not Disturb. They replace Omarchy's single 10% laptop
  warning while the mode is on; its `battery-low` hook still runs.
- **Desktop icons**, a **wallpaper slideshow** (rotate every 15 minutes, or
  follow sunrise and sunset), and an **Overtake Mode** entry in the Omarchy menu.

## Shortcuts (while Overtake Mode is on)

| Keys | Does |
| --- | --- |
| Super (tap) | Start |
| Super + S | Start, ready to search |
| Super + X | Quick links menu |
| Super + E / I / R | Files / Settings / Run |
| Super + D | Show desktop |
| Super + Z | Snap layouts |
| Super + ← / → | Snap left / right |
| Super + ↑ / ↓ | Maximize / minimize |
| Super + L | Lock |
| Super + V | Clipboard history |
| Ctrl + Shift + Esc | Task manager |
| Alt + F4 | Close window |
| Super + Ctrl + Shift + W | Switch between Overtake and Omarchy |

These replace a few Omarchy shortcuts only while the mode is on (for example
Super + S is normally the scratchpad); switching back restores them all.

## Customising

All in `~/.config/overtake/`:

- `start-pinned.txt` — Start menu pins (or right-click apps in Start)
- `desktop-icons.txt` — desktop icons (`trash`, `browser`, `terminal`, or any app)
- `no-controls.txt` — apps that keep their own window buttons instead of
  Overtake's title bar

`overtake` on its own lists every command (snap, minimize, wallpaper modes…).

## What it installs

| Where | What |
| --- | --- |
| `~/.local/bin/overtake` | the command |
| `~/.config/hypr/overtake.lua` | the shortcuts, loaded only while the mode is on |
| `~/.config/hypr/bindings.lua`, `autostart.lua` | a few lines between `>>> overtake` / `<<< overtake` markers |
| `~/.config/omarchy/plugins/overtake.taskbar` | taskbar, Start menu, title bars, desktop icons, Settings |
| `~/.config/omarchy/plugins/overtake.{workspaces,bluetooth,audio}` | copies of Omarchy's own widgets, made from your installed Omarchy, with small changes (no gaps in the workspace list; right-click opens the Bluetooth and sound panels instead of turning Bluetooth off or muting) |
| `~/.config/omarchy/plugins/overtake.notifications` | a copy of Omarchy's notifications with a close button on each card, critical toasts leaving after 15 s instead of never, and a 50-entry history for the notification center. Used only while the mode is on; switching restarts the shell, since Omarchy keeps its notification service loaded until then |
| `~/.config/omarchy/plugins/overtake.battery` | a copy of Omarchy's battery service without its fixed 10% warning (Overtake's battery alerts replace it); used only while the mode is on, switched together with the notifications copy |
| `~/.config/omarchy/plugins/overtake.notification-center` | the bell and its panel; it reads Omarchy's notification history folder (`~/.local/state/omarchy/notifications/history`). `omarchy-shell overtake.notification-center toggle` opens it |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | the Overtake Mode menu entry, between markers |
| `~/.config/overtake/`, `~/Pictures/overtake/` | your settings and the wallpapers |

If a future Omarchy changes one of those widgets so the change no longer
applies, the installer says so and Overtake uses Omarchy's own one.

## Uninstall

```bash
./uninstall.sh          # keeps ~/.config/overtake and the wallpapers
./uninstall.sh --purge  # removes those too
```

## Known limits

- Apps that draw their own title bar and can't hide it (Discord's desktop app,
  for one) keep their own buttons; listed in `no-controls.txt`.
- Dragging such an app by its own title area snaps when you hold still over a
  layout for half a second, since Hyprland doesn't report their mouse button.
- Network picking, Bluetooth pairing and detailed sound settings open
  Omarchy's own panels; screen resolution and keyboard layouts open the
  config file.

## Wallpapers

Original art made for this project; see `wallpapers/src` for the scripts that
draw some of them.
