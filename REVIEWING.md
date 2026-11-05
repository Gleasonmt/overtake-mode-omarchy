# Reviewing Overtake Mode

Notes for marketplace reviewers: what the automated baseline will report, where
to find each thing it points at, and how to check the rest quickly. Line numbers
are for release v0.1.10.

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
| `remote-build` | `README.md:29` (the bot also shows `README.md:1`: it numbers lines inside each fenced shell block) | The README's install steps clone this repository and run its own `./install.sh`. Nothing outside the repository is fetched or built. |

There is no `systemctl`, `systemd-run`, `sudo` or `pkexec` anywhere. Sleep runs
Omarchy's own Suspend menu entry by its route (`omarchy-menu summon
system.suspend`), or opens Omarchy's system menu instead if the user has turned
Suspend off there (Toggle > Suspend) or Omarchy has turned sleep off on this
machine (`omarchy-sleep-disabled`). Restart and Shut Down use Omarchy's
`omarchy-system reboot` / `omarchy-system shutdown` or its system menu, and
links open through `omarchy-launch-browser`.

Not a baseline capability, but listed for review: `install.sh` adds one
Omarchy hook, `~/.config/omarchy/hooks/post-update.d/overtake.hook` (three
lines). Omarchy runs it as the user near the end of `omarchy update`; it runs
`~/.local/bin/overtake build-copies update`, which never calls `sudo`,
downloads nothing, and only rebuilds Overtake's own
`~/.config/omarchy/plugins/overtake.*` copies from the installed Omarchy.
`overtake resume` (at login) runs the same check, for updates made another
way. `./uninstall.sh` removes the hook.

Precedents: [macOS Dock #13499](https://github.com/omacom/omarchy-plugin-marketplace/issues/13499)
(`installer` + `remote-build`), [Omarchy to Windows #13475](https://github.com/omacom/omarchy-plugin-marketplace/issues/13475)
(thin root plugin + installer + `manual-setup`), [StartBar #10918](https://github.com/omacom/omarchy-plugin-marketplace/issues/10918)
(a Start-menu taskbar desktop).

## Install and uninstall

- `install.sh`: `plan()` (line 127) prints every file it will add and every
  existing file it will change; nothing is written before the prompt (line 209)
  or `--yes`, and it refuses without a terminal. `--dry-run` only prints.
- **Optional extras are off unless chosen** (asked one by one in a terminal, or
  `--link-handler`, `--image-viewer`, `--style-menus`, `--name-tags`): the
  link handler (`omarchy-browser.desktop`), the default image viewer
  (`xdg-mime`), Overtake's Appearance > Background / Theme in the Omarchy menu, and
  the Claude Code name tags (`~/.claude/sessions`, Super+Alt+N; without them
  `~/.claude` is never read). Without them Overtake changes nothing outside its
  own files, its marked blocks, its post-update hook, and `shell.json`'s plugin
  list, where its copies of Omarchy's notifications and battery are enabled in
  place of Omarchy's own (switched off in every mode while the copy is on). An update keeps earlier choices;
  `--no-…` takes one back out exactly.
- Edits to existing files are between `>>> overtake` / `<<< overtake` markers
  (`bindings.lua`, `autostart.lua`, `omarchy-menu.jsonc`). The README's
  [What it installs](README.md#what-it-installs) table lists every path.
- `uninstall.sh` (also `overtake uninstall`, from a copy in
  `~/.local/share/overtake`) prints what it will do and asks (line 63). It
  switches back to Omarchy first (also if a switch failed halfway), removes the
  marked blocks, re-enables Omarchy's notifications/battery unless the user had
  turned them off before installing (recorded at `install.sh:325`), restores
  the exact earlier `mimeapps.list` lines (recorded per type, `uninstall.sh:147`)
  and the link handler, and deletes its own files. `--purge` also removes
  settings and wallpapers.
- **Why patched copies of Omarchy's notifications and battery services:**
  Omarchy's history is its notifications service's own file, so only the
  service can take entries out (the notification center's remove and Clear
  all); per-app Show / Quiet / Off and the 15-second critical toasts hook into
  its delivery code; and Overtake's battery alerts cover each device instead
  of Omarchy's single 10% warning. The notifications patch changes one file,
  `Service.qml`. The copies
  are built from the installed Omarchy by exact replacements
  (`patches/apply.py`, `build_copies` in `bin/overtake:199`), at install and
  again after every `omarchy update` (the hook above; the shell reloads a
  changed plugin folder by itself) and at login, so they never fall behind
  Omarchy's code. If
  a patch no longer fits, that copy is removed, Omarchy's own is switched back
  on, and a notification says so. While Overtake Mode is off they behave like
  Omarchy's own (Omarchy's timings, low-battery warning and Do Not Disturb
  exceptions unchanged), so switching modes needs no shell
  restart.
  Uninstall hands Omarchy's own back, leaving off any the user had turned off.
- While a mode is on, `overtake` swaps the bar layout in `shell.json`, adds a
  marked block to `shell.toml`, sets GTK's `button-layout`, and tiles any
  workspace set to Omarchy 4.5's floating layout in Omarchy's own record
  (`~/.local/state/omarchy/workspace-layouts`; Overtake floats every window
  itself, with its own title bars and Dock); all of it is put back when
  switching to Omarchy, a layout you changed meanwhile excepted. Both files are replaced whole through a temp
  file next to them and a rename (`replace_with`, `bin/overtake:286`), as
  Omarchy's own `omarchy-shell-config` does.

## Untrusted input and private data

- **Rich text:** every `Text` item (138) uses
  `textFormat: Text.PlainText`; there are no `ToolTip`, `Label` or `TextEdit`.
- **Process arguments:** window titles, window names, Claude Code session ids
  and notification text never go into another process's argv:
  - jq gets them through `--slurpfile`/`--rawfile` from `<(printf …)`
    (`remember_layout` :931, `relayout` :953, `claude_windows` :1275,
    `sync_session_names` :1302, `set_name` :1338);
  - battery alerts (which name the device) go to `overtake notify-stdin` on
    stdin and from there over D-Bus, never through `notify-send`'s arguments;
  - the bar's settings (which can name your cities) reach jq through a file
    descriptor, not the command line;
  - names reach `overtake` on stdin (`name … -` :1877; QML:
    `session-names/Service.qml:235`); notification text never leaves the
    shell (the notification center doesn't pass it to anything);
  - Copy URL passes the page title in the environment (`copy_url` :1202) and
    reads browser history read-only in place;
  - Spotlight lists the home folder once per opening and matches typed text
    in-process (`Spotlight.qml:180`); its calculator is a small parser
    (`Spotlight.qml:104`), no eval.
- **What still goes into process arguments**, and why: file paths a click
  opens (`xdg-open` needs the path); a notification's app name
  (`overtake notification-open`, to find its window, as Omarchy's toasts do
  with `omarchy-hyprland-focus-app`); a web notification's site address
  when it's opened (`https://<host>/`, as Omarchy's toasts open it); and
  `overtake name here "<name>"` when a user types it that way on purpose (the documented form, `echo name | overtake name here
  -`, keeps it out).
- **Shell and Lua:** window addresses must match `^0x[0-9a-fA-F]+$` before any
  command runs (`bin/overtake:1808`); workspace names with quotes,
  backslashes, `;` (which `hyprctl --batch` splits on) or control characters
  are refused before reaching Hyprland's Lua (`lua_safe` :829);
  Settings shell-quotes font and theme names (`Settings.qml:47`).
- **Opening things from other apps' text:** clicking a notification in the
  notification center runs the notification's own action exactly as Omarchy's
  toasts do (`notification-center/Panel.qml`, the same checks as Omarchy's
  `parseExecArgv`, run through `bash -lc 'exec "$@"'`). Without one, it
  does what Omarchy's own toasts do: the sender's open window comes forward
  (`notification_open` :1101); failing that, a browser's web notification
  (Omarchy's `web:<host>` group, a plain hostname only) opens
  `https://<host>/` through `Qt.openUrlExternally`, as Omarchy does. Nothing is opened
  or launched from the message text. `open-url` (:1068) drops
  option-like arguments.
- **Images:** notification icons, and icons looked up from an app's window
  class, are theme icons by plain name only (never a path the app chose).
  The Control Center shows no album art: decoding a player's picture would
  happen inside the shell.
- **Network:** one request, `wttr.in` for sunrise/sunset, only in the optional
  Day & Night wallpaper mode (`sun_times` :417); documented in the README.
- **Local reads** (browser history for Copy URL, `~/.claude/sessions` for name
  tags, recent files, files under home for search) are listed in the README's
  Privacy section and never leave the machine.
- **Files:** Overtake's folders (`~/.local/state/overtake`,
  `~/.config/overtake`, `~/.cache/overtake`) are 0700, created that way
  before anything is written, and tightened at install and at every start if
  an older version left them open; edits to existing files keep their mode
  (temp file next to them, then a rename); no `/tmp` state; the slideshow's saved pid is checked against `/proc/<pid>/cmdline`
  before it's stopped (`stop_slideshow` :462).
- **Background work:** the mode, Claude Code sessions, the Trash and Do Not
  Disturb (Omarchy's `notifications/history.json` and `quiet.json`) are watched, not polled
  (`session-names/Service.qml:82`), and Hyprland window events trigger at
  most one refresh per 100 ms (title changes are ignored). Process spawns
  that remain: `overtake sessions` every 15 s while Claude Code runs (and
  when a window opens or closes then), `overtake remember` while Classic or
  Studio is on, only when a window has moved, resized, opened or closed
  (checked in-process every 5 s), and one status probe (Wi-Fi, Bluetooth, night
  light…) every 2 s only while the Control Center is open. Battery alerts
  read UPower in-process (on its change events, and every 30 s). In-process Hyprland IPC polling
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
sandbox="env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME HOME=$scratch OVERTAKE_NO_RELOAD=1"
$sandbox ./install.sh --yes     # installs into the scratch home
$sandbox ./uninstall.sh --yes   # and removes it again
```

`OVERTAKE_NO_RELOAD=1` skips reloading Hyprland and the shell, and unsetting
the `XDG_*` variables (Omarchy's session sets them) keeps every path inside
the scratch home.

## Credits

Omarchy's MIT notice for the patched copies and excerpts is in
[NOTICE.md](NOTICE.md); each patched copy gets one. The wallpapers were made for
this project with an AI image model.
