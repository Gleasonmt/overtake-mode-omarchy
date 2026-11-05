# Reviewing Overtake Mode

Notes for marketplace reviewers: what the automated baseline will report, where
to find each thing it points at, and how to check the rest quickly. Line numbers
are for release v0.1.7.

## Shape

- **Root plugin** `manifest.json` → `Setup.qml` (`gleasonmt.overtake-mode`, a
  service). It only checks for `~/.local/bin/overtake` and, if it's missing,
  sends one notification saying where to run `./install.sh`. Nothing else.
- **The suite**, set up by `./install.sh`: its own plugins (`plugins/overtake.*`,
  manifests two folders down, copied into `~/.config/omarchy/plugins`), patched
  copies of five Omarchy plugins built from the installed Omarchy
  (`patches/apply.py`), the `overtake` command (`bin/overtake`, bash), Hyprland
  Lua (`hypr/`) and an Omarchy menu extension (`menu/`).
- Because `omarchy plugin add` alone can't set it up, we're asking for
  `manual-setup`, like [Omarchy to Windows #13475](https://github.com/omacom/omarchy-plugin-marketplace/issues/13475).

## Capabilities the baseline reports

| Capability | Where | What it is |
| --- | --- | --- |
| `installer` | `install.sh`, `uninstall.sh`, `Setup.qml` (by file name) | The installer and uninstaller described below; `Setup.qml` is the reminder above. No sudo, no package installs, nothing downloaded. |
| `remote-build` | `README.md:29` (and the same fenced block) | The README's install steps clone this repository and run its own `./install.sh`. Nothing outside the repository is fetched or built. |

There is no `systemctl`, `systemd-run`, `sudo` or `pkexec` anywhere. Sleep runs
Omarchy's own Suspend menu entry by its route (`omarchy-menu summon
system.suspend`), or opens Omarchy's system menu instead if the user has turned
Suspend off there (Toggle > Suspend). Restart and Shut Down use Omarchy's
`omarchy-system-reboot` / `omarchy-system-shutdown` or its system menu, and
links open through `omarchy-launch-browser`.

Precedents: [macOS Dock #13499](https://github.com/omacom/omarchy-plugin-marketplace/issues/13499)
(`installer` + `remote-build`), [Omarchy to Windows #13475](https://github.com/omacom/omarchy-plugin-marketplace/issues/13475)
(thin root plugin + installer + `manual-setup`), [StartBar #10918](https://github.com/omacom/omarchy-plugin-marketplace/issues/10918)
(a Start-menu taskbar desktop).

## Install and uninstall

- `install.sh`: `plan()` (line 117) prints every file it will add and every
  existing file it will change; nothing is written before the prompt (line 190)
  or `--yes`, and it refuses without a terminal. `--dry-run` only prints.
- **Optional extras are off unless chosen** (asked one by one in a terminal, or
  `--link-handler`, `--image-viewer`, `--style-menus`, `--name-tags`): the
  link handler (`omarchy-browser.desktop`), the default image viewer
  (`xdg-mime`), Overtake's Style > Background / Theme in the Omarchy menu, and
  the Claude Code name tags (`~/.claude/sessions`, Super+Alt+N). Without them
  Overtake changes nothing outside its own files, its marked blocks, and the
  two `shell.json` plugin entries below. An update keeps earlier choices;
  `--no-…` takes one back out exactly.
- Edits to existing files are between `>>> overtake` / `<<< overtake` markers
  (`bindings.lua`, `autostart.lua`, `omarchy-menu.jsonc`). The README's
  [What it installs](README.md#what-it-installs) table lists every path.
- `uninstall.sh` (also `overtake uninstall`, from a copy in
  `~/.local/share/overtake`) prints what it will do and asks (line 62). It
  switches back to Omarchy first (also if a switch failed halfway), removes the
  marked blocks, re-enables Omarchy's notifications/battery unless the user had
  turned them off before installing (recorded at `install.sh:324`), restores
  the exact earlier `mimeapps.list` lines (recorded per type, `uninstall.sh:142`)
  and the link handler, and deletes its own files. `--purge` also removes
  settings and wallpapers.
- **Why patched copies of Omarchy's notifications and battery services:**
  the notification center needs every notification kept in Omarchy's history
  with a close button and per-app quiet/off settings, and Overtake's battery
  alerts cover each device instead of Omarchy's single 10% warning. The copies
  are built at install time from the installed Omarchy by exact replacements
  (`patches/apply.py`): if Omarchy's code has changed, that copy isn't
  installed and Omarchy's own stays. While Overtake Mode is off they behave
  exactly like Omarchy's own (so switching modes needs no shell restart).
  Uninstall hands Omarchy's own back, leaving off any the user had turned off.
- While a mode is on, `overtake` swaps the bar layout in `shell.json`, adds a
  marked block to `shell.toml` and sets GTK's `button-layout`; all of it is put
  back when switching to Omarchy. Both files are replaced whole through a temp
  file next to them and a rename (`replace_with`, `bin/overtake:179`), as
  Omarchy's own `omarchy-shell-config` does.

## Untrusted input and private data

- **Rich text:** every `Text` item (138) uses
  `textFormat: Text.PlainText`; there are no `ToolTip`, `Label` or `TextEdit`.
- **Process arguments:** window titles, window names, Claude Code session ids
  and notification text never go into another process's argv:
  - jq gets them through `--slurpfile`/`--rawfile` from `<(printf …)`
    (`remember_layout` :775, `relayout` :797, `claude_windows` :1147,
    `sync_session_names` :1172, `set_name` :1208);
  - names and notification text reach `overtake` on stdin (`name … -` :1742,
    `notification-open … -` :1715; QML: `session-names/Service.qml:232`,
    `notification-center/Panel.qml:208`);
  - Copy URL passes the page title in the environment (`copy_url` :1074) and
    reads browser history read-only in place;
  - Spotlight lists the home folder once per opening and matches typed text
    in-process (`Spotlight.qml:178`); its calculator is a small parser
    (`Spotlight.qml:104`), no eval.
- **What still goes into process arguments**, and why: file paths a click
  opens (`xdg-open` needs the path); a notification's app name and plain icon
  name (`overtake notification-open`, to find its window or launcher; the
  message text itself goes on stdin); a device's name in a battery alert
  (`notify-send`'s title); and `overtake name here "<name>"` when a user types
  it that way on purpose (`echo name | overtake name here -` keeps it out).
- **Shell and Lua:** window addresses must match `^0x[0-9a-f]+$` before any
  command runs (`bin/overtake:1673`); workspace names with quotes or
  backslashes are refused before reaching Hyprland's Lua (`lua_safe` :675);
  Settings shell-quotes font and theme names (`Settings.qml:47`).
- **Opening things from other apps' text:** clicking a notification in the
  notification center runs the notification's own action exactly as Omarchy's
  toasts do (`notification-center/Panel.qml`, the same checks as Omarchy's
  `parseExecArgv`, run through `bash -lc 'exec "$@"'`). Without one, it opens a
  folder or file the message names only if it's under `$HOME`, not
  executable, and (for a file) both its extension and its content are a
  picture, video, sound, PDF or plain text
  (`notification_open` :946); app names are matched only as plain desktop-file
  names. `open-url` (:912) drops option-like arguments.
- **Images:** notification icons and album art load local files only
  (`Panel.qml:265`, `ControlCenter.qml:256`).
- **Network:** one request, `wttr.in` for sunrise/sunset, only in the optional
  Day & Night wallpaper mode (`sun_times` :310); documented in the README.
- **Local reads** (browser history for Copy URL, `~/.claude/sessions` for name
  tags, recent files, files under home for search) are listed in the README's
  Privacy section and never leave the machine.
- **Files:** state lives in `~/.local/state/overtake`, created 0700; no `/tmp`
  state; the slideshow's saved pid is checked against `/proc/<pid>/cmdline`
  before it's stopped (`stop_slideshow` :355).
- **Background work:** the mode, Claude Code sessions and the Trash are
  watched, not polled (`session-names/Service.qml:83`), and Hyprland window
  events trigger at most one refresh per 100 ms (title changes are ignored).
  Process spawns that remain: `overtake sessions` every 15 s while Claude Code
  runs (and when a window opens or closes then), and `overtake remember`
  every 5 s while Classic or Studio is on. In-process Hyprland IPC polling
  that remains: window geometry every 1.5 s while a window has a name tag;
  in Classic and Studio every 400 ms (Hyprland sends no event for resizes),
  and while a floating window has focus every 250 ms, 80 ms once it's
  moving (to follow an app dragging its own window).

## Trying it without touching your desktop

```bash
git clone https://github.com/Gleasonmt/overtake-mode-omarchy.git && cd overtake-mode-omarchy
./install.sh --dry-run                     # the full change list; writes nothing
scratch=$(mktemp -d)      # a private, empty home to install into
mkdir -p "$scratch/.config/omarchy" && echo '{}' > "$scratch/.config/omarchy/shell.json"
HOME=$scratch OVERTAKE_NO_RELOAD=1 ./install.sh --yes     # installs into the scratch home
HOME=$scratch OVERTAKE_NO_RELOAD=1 ./uninstall.sh --yes   # and removes it again
```

`OVERTAKE_NO_RELOAD=1` skips reloading Hyprland and the shell. (Unset the
`XDG_*` variables too if your session sets them.)

## Credits

Omarchy's MIT notice for the patched copies and excerpts is in
[NOTICE.md](NOTICE.md); each patched copy gets one. The wallpapers were made for
this project with an AI image model.
