# Reviewing Overtake Mode

Notes for marketplace reviewers: what the automated baseline will report, where
to find each thing it points at, and how to check the rest quickly. Line numbers
are for release v0.1.15.

## Shape

- **Root plugin** `manifest.json` → `Setup.qml` (`gleasonmt.overtake-mode`, a
  service). It only checks for `~/.local/bin/overtake` and, if it's missing,
  sends a notification at each shell start, until it's installed, saying where
  to run `./install.sh`. Nothing else.
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

Overtake itself runs no `systemctl`, `systemd-run`, `sudo` or `pkexec`. Two
Settings rows, only when clicked, call Omarchy's own `omarchy-dns` (which asks
for elevation) and `timedatectl set-ntp` (polkit). Sleep runs
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

- `install.sh`: `plan()` (line 75) prints every file it will add and every
  existing file it will change; nothing is written before the prompt (line 140)
  or `--yes`, and it refuses without a terminal. `--dry-run` only prints.
- **Omarchy mode is Omarchy as it ships.** Overtake's bar, its copies of
  Omarchy's notifications and battery services, its shortcuts, window rules
  and looks apply only while Classic or Studio is on; switching to Omarchy
  puts each one back (`turn_off`, `switch_copies off`). What stays in every
  mode: the mode shortcut and a login line (`overtake resume`, which in
  Omarchy mode only checks that the patched copies still match the installed
  Omarchy), both in marked blocks; the Overtake Mode entry in the Omarchy
  menu; the post-update hook; and a Trash entry in the app launcher. There are no
  optional extras: an update removes the link handler, image viewer,
  Appearance menus and Claude Code name tags that earlier versions offered,
  exactly.
- Edits to existing files are between `>>> overtake` / `<<< overtake` markers
  (`bindings.lua`, `autostart.lua`, `omarchy-menu.jsonc`). The README's
  [What it installs](README.md#what-it-installs) table lists every path.
- `uninstall.sh` (also `overtake uninstall`, from a copy in
  `~/.local/share/overtake`) prints what it will do and asks (line 64). It
  switches back to Omarchy first (also if a switch failed halfway), removes the
  marked blocks, re-enables Omarchy's notifications/battery unless the user had
  turned them off before installing (recorded at `install.sh:235`), restores
  anything an earlier version changed (the exact earlier `mimeapps.list`
  lines, recorded per type, `uninstall.sh:152`; the link handler), and deletes
  its own files. `--purge` also removes
  settings and wallpapers.
- **Why patched copies of Omarchy's notifications and battery services:**
  Omarchy's history is its notifications service's own file, so only the
  service can take entries out (the notification center's remove and Clear
  all); per-app Show / Quiet / Off and the 15-second critical toasts hook into
  its delivery code; and Overtake's battery alerts cover each device instead
  of Omarchy's single 10% warning. The notifications patch changes one file,
  `Service.qml`. The copies
  are built from the installed Omarchy by exact replacements
  (`patches/apply.py`, `build_copies` in `bin/overtake:204`), at install and
  again after every `omarchy update` (the hook above; the shell reloads a
  changed plugin folder by itself) and at login, so they never fall behind
  Omarchy's code. If
  a patch no longer fits, that copy is removed, Omarchy's own is switched back
  on, and a notification says so. The copies are enabled only while Classic
  or Studio is on; in Omarchy mode Omarchy's own services run. Uninstall
  leaves off any of Omarchy's own the user had turned off.
- While a mode is on, `overtake` swaps the bar layout in `shell.json`, adds a
  marked block to `shell.toml`, sets GTK's `button-layout`, and tiles any
  workspace set to Omarchy 4.5's floating layout in Omarchy's own record
  (`~/.local/state/omarchy/workspace-layouts`; Overtake floats every window
  itself, with its own title bars and Dock); all of it is put back when
  switching to Omarchy, a layout you changed meanwhile excepted. Both files are replaced whole through a temp
  file next to them and a rename (`replace_with`, `bin/overtake:292`), as
  Omarchy's own `omarchy-shell-config` does.

## Untrusted input and private data

- **Rich text:** every `Text` item (136) uses
  `textFormat: Text.PlainText`; there are no `ToolTip`, `Label` or `TextEdit`.
- **Process arguments:** window titles, window names and notification text
  never go into another process's argv:
  - jq gets them through `--slurpfile`/`--rawfile` from `<(printf …)`
    (`remember_layout` :971, `relayout` :993, `set_name` :1287);
  - battery alerts (which name the device) go to `overtake notify-stdin` on
    stdin and from there over D-Bus, never through `notify-send`'s arguments;
  - the bar's settings (which can name your cities) reach jq through a file
    descriptor, not the command line;
  - names reach `overtake` on stdin (`name … -` :1808; QML:
    `WindowControls.qml:133`); notification text never leaves the shell
    (the notification center doesn't pass it to anything);
  - Copy URL passes the page title in the environment (`copy_url` :1205) and
    reads browser history read-only in place;
  - Spotlight lists the home folder once per opening and matches typed text
    in-process (`Spotlight.qml:181`); its calculator is a small parser
    (`Spotlight.qml:104`), no eval.
- **What still goes into process arguments**, and why: file paths a click
  opens (`xdg-open` needs the path); a notification's app name
  (`overtake notification-open`, to find its window, as Omarchy's toasts do
  with `omarchy-hyprland-focus-app`); a web notification's site address
  when it's opened (`https://<host>/`, as Omarchy's toasts open it).
- **Shell and Lua:** window addresses must match `^0x[0-9a-fA-F]+$` before any
  command runs (`bin/overtake:1723`); workspace names with quotes,
  backslashes, `;` (which `hyprctl --batch` splits on) or control characters
  are refused before reaching Hyprland's Lua (`lua_safe` :869);
  Settings shell-quotes font and theme names (`Settings.qml:47`).
- **Opening things from other apps' text:** clicking a notification in the
  notification center runs the notification's own action exactly as Omarchy's
  toasts do (`notification-center/Panel.qml`, the same checks as Omarchy's
  `parseExecArgv`, run through `bash -lc 'exec "$@"'`). Without one, it
  does what Omarchy's own toasts do: the sender's open window comes forward
  (`notification_open` :1107); failing that, a browser's web notification
  (Omarchy's `web:<host>` group, a plain hostname only) opens
  `https://<host>/` through `Qt.openUrlExternally`, as Omarchy does. Nothing is opened
  or launched from the message text.
- **Images:** in the notification center, and for icons looked up from an
  app's window class, icons are theme icons by plain name only (never a path
  the app chose). Toasts are drawn by Overtake's copy of Omarchy's
  notifications service, which shows a sender's picture exactly as Omarchy's
  own does (its `Security.localImageUrl` checks, unchanged in the copy).
  The Control Center shows no album art: decoding a player's picture would
  happen inside the shell.
- **Network:** one request, `wttr.in` for sunrise/sunset, only in the optional
  Day & Night wallpaper mode (`sun_times` :429); documented in the README.
- **Local reads** (browser history for Copy URL, recent files, files under
  home for search) are listed in the README's
  Privacy section and never leave the machine.
- **Files:** Overtake's folders (`~/.local/state/overtake`,
  `~/.config/overtake`, `~/.cache/overtake`) are 0700, created that way
  before anything is written, and tightened at install and at every start if
  an older version left them open; edits to existing files keep their mode
  (temp file next to them, then a rename); no `/tmp` state; the slideshow's saved pid is checked against `/proc/<pid>/cmdline`
  before it's stopped (`stop_slideshow` :478).
- **Background work:** in Omarchy mode, none beyond one check at login that
  the patched copies match the installed Omarchy (and `overtake status` when
  the Omarchy menu opens). In Classic and Studio: the mode, the Trash and Do Not Disturb
  (Omarchy's `notifications/history.json` and `quiet.json`) are watched, not
  polled, and Hyprland window events trigger at most one refresh per 100 ms
  (title changes are ignored). Process spawns that remain: `overtake
  remember` while Classic or
  Studio is on, only when a window has moved, resized, opened or closed
  (checked in-process every 5 s), an in-process expiry check of notification history every minute and a read-back of
  the history file a second after each write, rewritten every 5 s only while it doesn't match (in Overtake's
  notifications copy, so only in Classic and Studio), and one status probe (Wi-Fi, Bluetooth, night
  light…) every 2 s only while the Control Center is open. Battery alerts
  read UPower in-process (on its change events, and every 30 s). In-process Hyprland IPC polling
  that remains: in Classic and Studio every 400 ms (Hyprland sends no event for resizes),
  and while a floating window has focus every 250 ms, 80 ms once it's
  moving (to follow an app dragging its own window).

## Threat model and the tests that check it

Overtake treats as hostile: **other local accounts** (umask 022, readable
`/proc/<pid>/cmdline`, shared `/tmp`), **text and names other programs
choose** (window titles and classes, notification fields, device names,
file names, desktop entries), and **a compromised wttr.in**. Other processes
of the same user are not a new boundary. Each claim below has a test in
`tests/`, run by GitHub Actions on every push against Omarchy 4.5.0's own
plugins (pinned commit; see the Actions tab for the run on this release).

| Boundary | How Overtake holds it | Test |
| --- | --- | --- |
| Private text vs other accounts' `ps` | stdin, `--rawfile`/`--slurpfile`, fds, the environment, D-Bus from a helper; never argv | `t-argv-privacy.sh`: a marker in window titles, classes, the bar's settings, a window name, a battery alert; every child's argv is logged and must not contain it (a planted `--argjson` leak makes it fail) |
| Private files vs other accounts | Overtake's folders 0700 before any write; older 0755 folders tightened at install and startup; edits keep the file's mode | `t-lifecycle.sh` (starts from a 0755 folder an older version would have left) |
| Names apps and devices choose | null-prototype maps and own-key lookups; `__proto__`, `constructor`, `laptop` can't reach built-ins or another device's slot | `t-qml-logic.js` (runs the real functions from the QML files) |
| Rich text and remote images | every `Text` is `Text.PlainText` (checked item by item); no Label/ToolTip/TextEdit/TextArea; no album art; icons by plain theme name | `t-plain-text.py` |
| Notification clicks | the action with Omarchy's `parseExecArgv` rules, else the sender's window, else a browser's site; nothing opened from message text | `t-qml-logic.js` (site lookup refuses app names and numeric hosts) |
| Omarchy's own files | marked blocks, mode-keeping replacements, floating layouts paused and restored, everything restored on uninstall | `t-lifecycle.sh` (byte for byte; `shell.json` by content, as jq rewrites it) |
| Omarchy updates | copies rebuilt from the new Omarchy; one whose patch no longer fits is dropped, Omarchy's own used | `t-patches.sh` |
| Omarchy mode stays stock | Overtake's notifications and battery copies switched on only with Classic/Studio, off (and the bar back) when switching to Omarchy; switched off in `shell.json` itself when no shell is running | `t-omarchy-mode.sh` |
| Upgrades from v0.1.11 | the four optional extras that release offered are taken back out exactly (`mimeapps.list` and the link line byte for byte) | `t-upgrade-extras.sh` |
| Startup repair | folders an older version left open are tightened at the next `overtake` start | `t-lifecycle.sh` |
| A compromised wttr.in | at most 256 KB read; only real times reach `date` or the cache, else 07:00/19:00 | `t-sun-times.sh` (fails if the cap is removed) |
| Notification history (the maintainer's notification-plugin checks) | Clear all and remove written at once (a shutdown right after can't lose them); every history write read back a second later and, if the file doesn't match, written again every 5 s until it does (while Classic or Studio stays on: switching to Omarchy mode before then hands over to Omarchy's own, which reads what is on disk); history past Omarchy's one day pruned every minute and never listed; nothing removed before history has loaded | `t-notifications.sh`: Omarchy's own Store.js and the copy's own functions, timers and history-file handlers, against a FileView that behaves as Quickshell 0.3 was measured to (a write refused at open emits saveFailed; one that fails at commit, e.g. disk full, only logs and emits saved; a reload inside a save signal does nothing; a repeat of the last attempted text is skipped). Both failure kinds, then room again. Fails on v0.1.14 and on a retry wired to saveFailed alone |

Run them yourself (scratch homes, stubbed desktop commands, nothing touches
your session): `tests/run.sh`.

## Trying it without touching your desktop

```bash
git clone --branch v0.1.15 https://github.com/Gleasonmt/overtake-mode-omarchy.git && cd overtake-mode-omarchy
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
