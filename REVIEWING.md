# Reviewing Overtake Mode

Notes for marketplace reviewers: what the automated baseline will report, where
to find each thing it points at, and how to check the rest quickly. Line numbers
are for release v0.1.15.

## Shape

- **Root plugin** `manifest.json` → `Setup.qml` (`gleasonmt.overtake-mode`, a
  service). It only checks for `~/.local/bin/overtake` and its recorded version and, if it's missing or older than this folder and the plugin is enabled, sends one notification at most per shell start (not per plugin reload), and none while the installer is running, until that's done, saying where to run `./install.sh`; it also compares this folder's `bin/overtake` with the installed one when the versions match. Nothing else.
- **Everything else**, set up by `./install.sh`: its own plugins (`plugins/overtake.*`,
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
| `remote-build` | `README.md:43` and `:74`, install and update (the bot also shows `README.md:1`: it numbers lines inside each fenced shell block) | The README's install and update steps clone or fetch this repository and run its own `./install.sh`. Nothing outside the repository is fetched or built. |

Overtake itself runs no `systemctl`, `systemd-run`, `sudo` or `pkexec`. A few Settings rows, only when clicked, run Omarchy's own commands, which ask for elevation themselves: `omarchy-dns`, and in a terminal `omarchy-update`, `omarchy-update-firmware`, `omarchy-setup-security-fingerprint` and `passwd`. `timedatectl set-ntp` goes through polkit. Sleep runs
Omarchy's own Suspend menu entry by its route (`omarchy-menu summon
system.suspend`), or opens Omarchy's system menu instead if the user has turned
Suspend off there (Toggle > Suspend) or Omarchy has turned sleep off on this
machine (`omarchy-sleep-disabled`). Restart and Shut Down use Omarchy's
`omarchy-system reboot` / `omarchy-system shutdown` or its system menu, and
links open through `omarchy-launch-browser`.

Not a baseline capability, but listed for review: `install.sh` adds one
Omarchy hook, `~/.config/omarchy/hooks/post-update.d/overtake.hook` (three
lines). Omarchy runs it as the user near the end of `omarchy update`; it runs
`~/.local/bin/overtake build-copies update`, which never calls `sudo`, downloads nothing, and rebuilds Overtake's own `~/.config/omarchy/plugins/overtake.*` copies from the installed Omarchy; one whose patch no longer fits (Omarchy's own folder lacks a required file, or a patch doesn't apply) is removed, Omarchy's own is switched back on, and a notification says so. A hand-back goes through the shell only if it lists the copy; otherwise it is done in `shell.json`, and `overtake resume` repairs a stale one at login. A missing Omarchy changes nothing, and a disk problem keeps the copy.
`overtake resume` (at login) runs the same check, for updates made another
way. `./uninstall.sh` removes the hook.

Precedents: [macOS Dock #13499](https://github.com/omacom/omarchy-plugin-marketplace/issues/13499)
(`installer` + `remote-build`), [Omarchy to Windows #13475](https://github.com/omacom/omarchy-plugin-marketplace/issues/13475)
(thin root plugin + installer + `manual-setup`), [StartBar #10918](https://github.com/omacom/omarchy-plugin-marketplace/issues/10918)
(a Start-menu taskbar desktop).

## Install and uninstall

- `install.sh`: `plan()` (line 67) prints every file it will add and every
  existing file it will change; nothing is written before the prompt (line 126)
  or `--yes`, and it refuses without a terminal. `--dry-run` only prints.
- **Omarchy mode is Omarchy as it ships.** Overtake's bar, its copies of
  Omarchy's notifications and battery services, its shortcuts, window rules
  and looks apply only while Classic or Studio is on; switching to Omarchy
  puts each one back (`turn_off`, `switch_copies off`). What stays in every
  mode: the mode shortcut and a login line (`overtake resume`, which in every mode checks the patched copies against the installed Omarchy and rebuilds them if needed; in Omarchy mode that is all it does, apart from retrying a notice the shell wasn't up for), both in marked blocks; the Overtake Mode entry in the Omarchy
  menu; the post-update hook; and a Recycle Bin entry in the app launcher. There are no optional extras.
- Edits to existing files are between `>>> overtake` / `<<< overtake` markers
  (`bindings.lua`, `autostart.lua`, `omarchy-menu.jsonc`). The README's
  [What it installs](README.md#what-it-installs) table lists every path.
- `uninstall.sh` (also `overtake uninstall`, from a copy in
  `~/.local/share/overtake`) prints what it will do and asks (line 64). It
  switches back to Omarchy first (also if a switch failed halfway), removes the
  marked blocks, re-enables only those of Omarchy's own that Overtake's copy switched off (Omarchy's `cloneSourceRestores` record), never one the user turned off before installing (Omarchy's record doesn't list it) or since, and deletes its own files. A switch back that stopped partway (killed, or run outside the session) leaves a marker: `off` finishes it, `on` finishes it first, and uninstall won't delete the saved values until it's done. If `shell.json` can't be updated, uninstall stops before removing anything else. `--purge` also removes
  settings and wallpapers.
- **Why patched copies of Omarchy's notifications and battery services:**
  Omarchy's history is its notifications service's own file, so only the
  service can take entries out (the notification center's remove and Clear
  all); per-app Show / Quiet / Off and the 15-second critical toasts hook into
  its delivery code; and Overtake's battery alerts cover each device instead
  of Omarchy's single 10% warning. The notifications patch changes three files,
  `Service.qml`, `Toast.qml` and `Store.js`. The copies
  are built from the installed Omarchy by exact replacements
  (`patches/apply.py`, `build_copies` in `bin/overtake:283`), at install and
  again after every `omarchy update` (the hook above; the shell reloads a changed plugin folder by itself) and at login, so they follow Omarchy's code. If a patch no longer fits, that copy is removed, Omarchy's own is switched back on until an Overtake update supports that Omarchy (through the shell only if it lists the copy, otherwise in `shell.json`, and `overtake resume` repairs a stale one at login), and a notification says so (held until the shell can show it, if it isn't up yet). The copies are enabled only while Classic
  or Studio is on; in Omarchy mode Omarchy's own services run. Uninstall
  leaves off any of Omarchy's own the user had turned off.
- While a mode is on, `overtake` swaps the bar layout in `shell.json`, adds a
  marked block to `shell.toml`, sets GTK's `button-layout`, and tiles any
  workspace set to Omarchy 4.5's floating layout in Omarchy's own record
  (`~/.local/state/omarchy/workspace-layouts`; Overtake floats every window
  itself, with its own title bars and Dock); all of it is put back when
  switching to Omarchy, a layout you changed meanwhile excepted. Both files are replaced whole through a temp file next to them and a rename (`replace_with`, `bin/overtake:417`), keeping their mode.

## Untrusted input and private data

- **Rich text:** every `Text` in Overtake's own plugins (136) uses `Text.PlainText`. The notifications copy keeps Omarchy's toast body as `Text.StyledText`, fed only by `Markup.render`, which escapes everything and restores `b i u s em strong br` and vetted links, never `img`; the other 27 `Text` items in the built copies are plain. There are no `ToolTip`, `Label` or `TextEdit`.
- **Process arguments:** window titles, window names, workspace names (read by the dispatch's Lua from a private file, `ws_lua` :1080), wallpaper paths when one is set or restored (`set_background` :478; the picker's label is listed below) and notification text (including a verification code you copy) never go into another process's argv. A link in a notification goes to `wl-copy` on stdin, and only `https://<host>/` is opened:
  - jq gets them through `--slurpfile`/`--rawfile` from `<(printf …)`
    (`remember_layout` :1189, `relayout` :1211, `set_name` :1524);
  - battery alerts (which name the device) go to `overtake notify-stdin` on
    stdin and from there over D-Bus, never through `notify-send`'s arguments;
  - the bar's settings (which can name your cities) reach jq through a file
    descriptor, not the command line;
  - names reach `overtake` on stdin (`name … -` :2135; QML:
    `WindowControls.qml:127`); the notification center passes no notification text to anything; a copied code goes to `wl-copy` on stdin (the patched copy replaces Omarchy's `wl-copy --sensitive -- <code>`, whose clipboard server would keep it in its command line);
  - Copy URL passes the page title in the environment (`copy_url` :1442) and
    reads browser history read-only in place;
  - Spotlight lists the home folder once per opening and matches typed text
    in-process (`Spotlight.qml:189`); its calculator is a small parser
    (`Spotlight.qml:104`), no eval.
- **What still goes into process arguments**, and why: file paths a click
  opens (`xdg-open` needs the path); a notification's app name
  (`overtake notification-open`, to find its window, as Omarchy's toasts do
  with `omarchy-hyprland-focus-app`); a web notification's site address
  when it's opened (`https://<host>/`, as Omarchy's toasts open it); clicked file paths to `xdg-open` (`Spotlight.qml`, `StartMenu.qml`, `Dock.qml`); a folder path to nautilus (`StartMenu.qml`); desktop ids to `gtk-launch` (`AppModel.qml:201`, `DesktopIcons.qml:107`, `Spotlight.qml:229`, `StartMenu.qml:78`, `Taskbar.qml:224`, `MenuBar.qml:231`); PipeWire ids and node names when you choose an output or input (`omarchy-audio-*-set-default <id> <name>`, in the audio and Bluetooth copies, as stock), which name the device; a notification's own action when clicked, which may hold a file path, as stock; theme and font names and other Settings values; monitor names, window addresses and history keys; Bluetooth addresses (`panels/bluetooth/Panel.qml`, `Settings.qml:130`), which other local accounts can already read from BlueZ on the system bus (measured with a different kernel uid); the picker's selected entry label to `omarchy-menu-images --selected` (`bin/overtake:2016`), which names a theme or a picture in Overtake's own folders, and Omarchy's picker script then passes its list through `omarchy-shell` arguments. Omarchy's own shell also names the current wallpaper in its `magick identify` probe (stock `plugins/background/Background.qml`), for any wallpaper, Overtake's or not.
- **Shell and Lua:** window addresses must match `^0x[0-9a-fA-F]+$` before any
  command runs (`bin/overtake:2041`); workspace names never enter the Lua text: the dispatch reads them from a private file (`ws_lua` :1080); monitor names in `bin/overtake` with quotes, backslashes, `;` (which `hyprctl --batch` splits on) or control characters are refused (`lua_safe` :1070);
  Settings shell-quotes font and theme names (`Settings.qml:55`).
- **Opening things from other apps' text:** clicking a notification in the
  notification center runs the notification's own action exactly as Omarchy's
  toasts do (`notification-center/Panel.qml`, the same checks as Omarchy's
  `parseExecArgv`, run through `bash -lc 'exec "$@"'`). Without one, a browser's web notification (Omarchy's `web:<host>` group, a plain hostname only) opens `https://<host>/` through `Qt.openUrlExternally`; otherwise the sender's open window comes forward (`notification_open` :1329, its app name as literal text). Omarchy's toast tries the sender's window first, which the center doesn't use: a stored process id may belong to another process by now. In the center, nothing is opened or launched from the message text. On a toast, a link in the text goes to the clipboard whole, and only `https://<host>/` opens; an email address is only copied.
- **Images:** in the notification center, icons are theme icons by plain name only. An app's window class can only select an installed desktop entry or a theme icon by plain name, never a path of its own; an entry's own `Icon=` may be a file path, drawn in the shell as Omarchy's launcher does (a crafted PNG of 801 MiB inflated cost 30 MB by this route, measured: unlike a plain `Image`, it doesn't inflate the text). A theme's preview in Settings is drawn only from a stripped copy made in a child under a memory and time limit (`theme_previews` :1917), as Omarchy's own picker does; a preview that's a link is refused. Toasts are drawn by Overtake's copy of Omarchy's
  notifications service, which never decodes a picture a sender supplies, named by a file path or sent as `image-data`; a card shows the app's installed icon instead, so chat avatars and Chromium's site icons don't show. Quickshell still keeps `image-data` bytes as long as the sender's object lives, up to D-Bus's 64 MiB for each, whether or not they are drawn (measured: 20 pictures of 64 MB grew the shell by about 1.25 GB). So at most 8 cards hold on to such bytes; further cards keep their text and icon, and lose the sender's buttons. A sender's object with more than 64 KB of body or hints, 8 KB of summary or 32 buttons is let go the same way (measured: 10 bodies of 30 MB, about 80 MB; 2 messages of 400,000 buttons, about 150 MB), and a card's body is cut to 8 KB, because stock's patterns take quadratic time on text in the shell every plugin shares (measured: 32 KB of `<` froze it for over a second per message, now under 200 ms).
  The Control Center shows no album art: decoding a player's picture would
  happen inside the shell.
- **Network:** one request, `wttr.in` for sunrise/sunset, only in the optional
  Day & Night wallpaper mode (`sun_times` :580); documented in the README.
- **Local reads** (browser history for Copy URL, recent files, files under
  home for search) are listed in the README's
  Privacy section and never leave the machine.
- **Files:** Overtake's folders (`~/.local/state/overtake`,
  `~/.config/overtake`, `~/.cache/overtake`) are 0700 (a folder you symlinked is left as you set it up), created that way
  before anything is written, and tightened at install and at every start if they've been left open; edits to existing files keep their mode
  (temp file next to them, then a rename: `replace_file`, `install.sh:153`; a failure stops with a message); no `/tmp` state; the slideshow's saved pid is checked against `/proc/<pid>/cmdline`
  before it's stopped (`stop_slideshow` :629).
- **Background work:** in Omarchy mode, none beyond one check at login that the patched copies match the installed Omarchy (and, only if a login notice couldn't be shown, six `overtake status` retries over 60 s), `overtake status` when the Omarchy menu opens, at plugin start, and before each settings write. In Classic and Studio: the mode, the Trash and Do Not Disturb
  (Omarchy's `notifications/history.json` and `quiet.json`) are watched, not
  polled, and Hyprland window events trigger at most one refresh per 100 ms
  (title changes are ignored). In-process timers in Overtake's
  notifications copy (so only in Classic and Studio): an expiry check of history every minute, and
  a read-back of the history file a second after each write, rewritten 5 s later only while it doesn't match; `live.json` and `quiet.json` are read back the same way after each write, and retried about every 6 s while they don't match; every 5 s while the folder can't be prepared. The wallpaper slideshow is one background loop (`slideshow_loop`, `bin/overtake:665`, while Classic or Studio is on): it wakes every 15 minutes (Rotate) or every 5 minutes (Day & Night, whose wttr.in lookup is cached for the day when it succeeds, and tried again in 5 minutes when it doesn't). Process spawns that remain: `overtake remember` while Classic or
  Studio is on, only when a window has moved, resized, opened or closed
  (checked in-process every 5 s), a short bash process before each notification file write and each read-back (on activity, and during those retries), and one status probe (Wi-Fi, Bluetooth, night
  light…) every 2 s only while the Control Center is open. On events: `overtake fill-gap` per opened window, `fix-bar` after a `shell.json` change, `make-room`, `float-all`, `hide-minimized`, `relayout` twice per monitor change, `hyprctl eval` and `hyprctl animations` per drag, `tail` on the recent-files list when it changes, `overtake theme-previews` when Settings shows your themes, and `hyprctl cursorpos` on each 80 ms tick while an app drags its own window. The bell's clock ticks every second in Studio, a plain timer. Battery alerts
  read UPower in-process (on its change events, and every 30 s). In-process Hyprland IPC polling
  that remains: in Classic and Studio every 400 ms (Hyprland sends no event for resizes),
  and while a floating window has focus every 250 ms, 80 ms once it's
  moving (to follow an app dragging its own window).

## Threat model and the tests that check it

Overtake treats as hostile: **other local accounts** (umask 022, readable
`/proc/<pid>/cmdline`, shared `/tmp`), **text and names other programs
choose** (window titles and classes, notification fields, device names,
file names, desktop entries), and **a compromised wttr.in**. Other processes
of the same user are not a new boundary. **A theme installed from git** is untrusted too, as Omarchy's own `omarchy-theme-set` treats it. Each claim below has a test in
`tests/`. GitHub Actions runs `tests/run.sh` on every push against Omarchy 4.5.0's own
plugins (pinned commit; see the Actions tab for the run on this release), but not every test can run there: see the end of this section.

| Boundary | How Overtake holds it | Test |
| --- | --- | --- |
| Private text vs other accounts' `ps` | stdin, `--rawfile`/`--slurpfile`, fds, the environment, D-Bus from a helper; never argv | `t-argv-privacy.sh`: a marker in window titles, classes, the bar's settings, a window name, a battery alert; also a workspace name, a wallpaper's file name, a page title and address; the argv of every stubbed or wrapped tool it starts is logged and must not contain it (checked by planting an `--argjson` leak, which makes it fail) |
| Private files vs other accounts | Overtake's folders 0700 before Overtake's plugins watch or write in them (each file's `OvertakeFolders` runs `overtake status` first, at start and before every write, so a deleted folder can't come back 0755); 0755 folders tightened at install and startup | `t-folders.sh` (statically, and a deleted folder in real Quickshell); `t-lifecycle.sh` (folders 0700 after install and after a start, from 0755) |
| Names apps and devices choose | null-prototype maps and own-key lookups; `__proto__`, `constructor`, `laptop` can't reach built-ins or another device's slot | `t-qml-logic.js` (runs the real functions from the QML files) |
| Rich text and remote images | every `Text` in Overtake's plugins is `Text.PlainText`, and the built copies' one exception is fed only by `Markup.render`; no Label/ToolTip/TextEdit/TextArea; no album art; desktop-entry icons are shown as Omarchy's own launcher and Dock show them | `t-plain-text.py` (item by item, in the plugins and the built copies; no rich-text item types); `t-notifications.js` (hostile inputs through `Markup.render`) |
| What senders supply | no picture is decoded, by path or as `image-data`, so one claiming more pixels than it sends can't crash the shell through its image loader; at most 8 cards keep a sender's picture bytes in memory, and an oversized message's object is let go; a body is cut before the patterns that stall on it | `t-notifications-qs.sh`: a FIFO shows a named file is never opened; a false `image-data` size leaves the shell running (the old line segfaults it); 20 pictures of 64 MB, also with a false size, stay under 800 MB of growth; 30 MB bodies and hints, and 400,000 buttons; 32 KB of the worst text stalls the shell under 500 ms |
| Themes from git | previews drawn only from a stripped copy made in a child under limits | `t-lifecycle-details.sh` (a crafted PNG, a link, modes, no direct `Image.source`) |
| Notification clicks | the action with Omarchy's `parseExecArgv` rules, else a browser's site, else the sender's window; from message text, only `https://<host>/` opens, and the full link is copied on stdin; an email address is only copied | `t-qml-logic.js` (site lookup refuses app names and numeric hosts); `t-notifications-qs.sh` (real clicks' handlers, with a /proc argv watcher); `t-lifecycle-details.sh` (app name as literal text) |
| Omarchy's own files | marked blocks, mode-keeping replacements, floating layouts paused and restored, everything restored on uninstall: byte for byte for bindings, autostart, the menu and shell.toml, `shell.json` by content; screensaver art from before comes back if what's there now is what Overtake wrote, and art you wrote or picked stays, with the old one beside it | `t-lifecycle.sh`, `t-install-files.sh` (21 file shapes) |
| A full disk | Overtake's command and files, your config files and each patched copy are replaced through a temp file and a rename, or a build beside the old one; the old stays if it fails. Overtake's small state files and screensaver art it writes are overwritten in place | `t-full-disk.sh` (real ENOSPC on a tmpfs, by data size and inode count; a read-only state folder) |
| Switching back | each step runs whatever the others do; a half-done switch is finished later, and nothing saved is lost | `t-lifecycle-details.sh` (`hyprctl` failing as it does with no session; `gsettings` failing) |
| The reminder | at most one per shell start; none during install | `t-setup-qs.sh` (real Quickshell) |
| Omarchy updates | copies rebuilt from the new Omarchy; one whose patch no longer fits is dropped | `t-patches.sh` (all five build; a changed plugin drops only its copy) |
| Omarchy mode stays stock | Overtake's notifications and battery copies switched on only with Classic/Studio, off (and the bar back) when switching to Omarchy; switched off in `shell.json` itself when no shell is running | `t-omarchy-mode.sh`, `t-lifecycle-details.sh` |
| Notices and hand-backs | a dropped copy asks for an Overtake update, not a reinstall; a failed rebuild is reported as that; a login notice waits for the shell; uninstall re-enables only what the copies switched off | `t-lifecycle-details.sh` |
| Startup repair | folders left open are tightened at the next `overtake` start | `t-lifecycle.sh` |
| A compromised wttr.in | at most 256 KB read; only real times reach `date` or the cache, else 07:00/19:00 | `t-sun-times.sh` (fails if the cap is removed) |
| Notification history (the maintainer's notification-plugin checks) | Clear all and remove are written without waiting for the save timer, and also in place within milliseconds by a helper that overwrites without truncating and puts the old bytes back on a short write, so a refused write leaves every row in place (a real short write measured; a removal on a full tmpfs measured; real btrfs not measured). On a read-only disk the entry stays and the center says so. `live.json` is read back after each write, so a removed row can't return through it. The folder is prepared again before every write and read-back. On a clean exit a write can't wait, so a detached repair follows 0.3 s later. Any sender naming itself `Battery` with critical urgency passes Do Not Disturb, as a `notify-send` critical does. Clear all is the service's `forgetAll`: also a silenced copy just filed and cards still on screen, in `live.json` too. Each history write is read back a second later and written again about every 6 s until the file matches. History past Omarchy's one day pruned every minute and never listed; nothing removed before history has loaded | `t-notifications-qs.sh`: the real patched copy in real Quickshell, on a private bus and a real full disk (a small tmpfs), covering a copied code on stdin, Clear all then a restart with the disk still full (also a stop within 0.3 s), a removal keeping rows filed since the last load, a silenced copy, a card on screen with a normal and a full disk. `t-notifications.sh`: the copy's own functions, timers and file handlers over a FileView model of Quickshell's measured behaviour (the model writes synchronously; real writes are asynchronous, which the real-Quickshell test covers), for the failure orderings. Each was checked by removing its fix |

Run them yourself (scratch homes, stubbed desktop commands, nothing touches your session): `tests/run.sh`. CI has no `qs`, so it skips the real-Quickshell tests (`t-notifications-qs.sh`, `t-setup-qs.sh`, the second half of `t-folders.sh`, theme previews); those were run locally on this commit. `tests/run.sh`'s last line counts what was skipped. Most of the desktop's QML (Taskbar, Start menu, Dock, title bars, Settings) has no automated run, as it needs a compositor: for this release it was loaded in a private Hyprland with the real Omarchy shell, in Classic and Studio, with its shortcuts checked there.

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
[NOTICE.md](NOTICE.md); each patched copy gets one. The Classic wallpapers are drawn by code written with an AI assistant (`wallpapers/src`); the Studio snow leopard was made with an AI image model.
