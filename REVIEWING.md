# Reviewing Overtake Mode

Notes for marketplace reviewers: what the automated baseline will report, where
to find each thing it points at, and how to check the rest quickly. Line numbers
are for release v0.1.17.

## Shape

- **Root plugin** `manifest.json` → `Setup.qml` (`gleasonmt.overtake-mode`, a
  service). It only checks for `~/.local/bin/overtake` and its recorded version and, if it's missing or older than this folder and the plugin is enabled, sends one notification at most per shell start (not per plugin reload), and none while the installer is running, until that's done, saying where to run `./install.sh`; it also compares this folder's `bin/overtake` with the installed one when the versions match. Its only write is the marker folder for that once-per-shell (`$XDG_RUNTIME_DIR/overtake-reminded.<pid>`), pruned at the next reminder, and gone at logout. Nothing else.
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
| `remote-build` | `README.md:43` (the bot also shows `README.md:1`: it numbers lines inside each fenced shell block); the update step at `README.md:67` fetches this repository's tags | The README's install and update steps clone or fetch this repository and run its own `./install.sh`. Nothing outside the repository is fetched or built. |

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

- `install.sh`: `plan()` (line 74) prints every file it will add and every
  existing file it will change; nothing is written before the prompt (line 135)
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
  marked blocks, re-enables only those of Omarchy's own that Overtake's copy switched off (Omarchy's `cloneSourceRestores` record), never one the user turned off before installing (Omarchy's record doesn't list it) or since, and deletes its own files. A switch back that stopped partway (killed, or run outside the session) leaves a marker: `off` finishes it, `on` finishes it first, and uninstall won't delete the saved values until it's done. If `shell.json` can't be updated, uninstall stops before removing anything: it re-enables Omarchy's own first, and removes the marked blocks after. `--purge` also removes
  settings and wallpapers.
- **Why patched copies of Omarchy's notifications and battery services:**
  Omarchy's history is its notifications service's own file, so only the
  service can take entries out (the notification center's remove and Clear
  all); per-app Show / Quiet / Off and the 15-second critical toasts hook into
  its delivery code; and Overtake's battery alerts cover each device instead
  of Omarchy's single 10% warning. The notifications patch changes four files,
  `Service.qml`, `Toast.qml`, `Store.js` and `Icons.js`. The copies
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
  switching to Omarchy, a layout you changed meanwhile excepted. Both files are replaced whole through a temp file next to them and a rename (`replace_with`, `bin/overtake:429`), keeping their mode.

## Untrusted input and private data

- **Rich text:** every `Text` in Overtake's own plugins (136) uses `Text.PlainText`. The notifications copy keeps Omarchy's toast body as `Text.StyledText`, fed only by `Markup.render`, which escapes everything and restores `b i u s em strong br` and vetted links, never `img`; the other 27 `Text` items in the built copies are plain. There are no `ToolTip`, `Label` or `TextEdit`.
- **Process arguments:** window titles, window names, workspace names (read by the dispatch's Lua from a private file, `ws_lua` :1127), wallpaper paths when one is set or restored (`set_background` :492; the picker's label and Omarchy's own lookups are listed below) and notification text (including a verification code you copy) never go into another process's argv. A link in a notification goes to `wl-copy` on stdin, and only `https://<host>/` is opened:
  - jq gets them through `--slurpfile`/`--rawfile` from `<(printf …)`
    (`remember_layout` :1236, `relayout` :1258, `set_name` :1575);
  - battery alerts (which name the device) go to `overtake notify-stdin` on
    stdin and from there over D-Bus, never through `notify-send`'s arguments;
  - the bar's settings (which can name your cities) reach jq through a file
    descriptor, not the command line;
  - names reach `overtake` on stdin (`name … -` :2285; QML:
    `WindowControls.qml:127`); the notification center passes no notification text to anything; a copied code goes to `wl-copy` on stdin (the patched copy replaces Omarchy's `wl-copy --sensitive -- <code>`, whose clipboard server would keep it in its command line);
  - Copy URL passes the page title in the environment (`copy_url` :1493) and
    reads browser history read-only in place;
  - Spotlight lists the home folder once per opening and matches typed text
    in-process (`Spotlight.qml:190`); its calculator is a small parser
    (`Spotlight.qml:105`), no eval.
- **What still goes into process arguments**, and why: file paths a click
  opens (`xdg-open` needs the path); a web notification's site address
  when it's opened (`https://<host>/`, as Omarchy's toasts open it); clicked file paths to `xdg-open` (`Spotlight.qml`, `StartMenu.qml`, `Dock.qml`); a folder path to nautilus (`StartMenu.qml`); desktop ids to `gtk-launch` (`AppModel.qml:202`, `DesktopIcons.qml:110`, `Spotlight.qml:230`, `StartMenu.qml:79`, `Taskbar.qml:225`, `MenuBar.qml:231`); PipeWire ids and node names when you choose an output or input (`omarchy-audio-*-set-default <id> <name>`, in the audio and Bluetooth copies, as stock), which name the device; a notification's own action when clicked, which may hold a file path, as stock; theme and font names and other Settings values; monitor names, window addresses and history keys; Bluetooth addresses (`panels/bluetooth/Panel.qml`, `Settings.qml:130`), which other local accounts can already read from BlueZ on the system bus (measured with a different kernel uid); the picker's selected entry label to `omarchy-menu-images --selected` (`bin/overtake:2170`), only for a theme's or one of the pictures Overtake ships, since Omarchy's script runs `find -samefile` on its real path (any other picture isn't marked as selected, and one you add to Overtake's folders is labelled by a number), and Omarchy's picker script then passes its list through `omarchy-shell` arguments. Omarchy's own shell also names the current wallpaper in its `magick identify` probe (stock `plugins/background/Background.qml`), for any wallpaper, Overtake's or not.
- **Shell and Lua:** window addresses must match `^0x[0-9a-fA-F]+$` before any
  command runs (`bin/overtake:2195`); workspace names never enter the Lua text: the dispatch reads them from a private file (`ws_lua` :1127); monitor names in `bin/overtake` with quotes, backslashes, `;` (which `hyprctl --batch` splits on) or control characters are refused (`lua_safe` :1117);
  Settings shell-quotes font and theme names (`Settings.qml:55`).
- **Opening things from other apps' text:** clicking a notification in the
  notification center runs the notification's own action exactly as Omarchy's
  toasts do (`notification-center/Panel.qml`, the same checks as Omarchy's
  `parseExecArgv`, run through `bash -lc 'exec "$@"'`). Without one, a browser's web notification (Omarchy's `web:<host>` group, a plain hostname only) opens `https://<host>/` through `Qt.openUrlExternally`; otherwise the sender's open window comes forward (`notification_open` :1377, its app name on stdin, matched as plain text, on the center and on toasts). Omarchy's toast tries the sender's window first, which the center doesn't use: a stored process id may belong to another process by now. In the center, the only thing taken from the message text is that site's host: Omarchy reads it from the link a browser's message starts with, and any sender can name itself a browser, so one click opens `https://<host>/` of a sender's choosing, with no path or query, as Omarchy's toast does. Nothing is launched from the text. On a toast, a link in the text goes to the clipboard whole, and only `https://<host>/` opens; an email address is only copied.
- **Images:** icons are theme icons by plain name only, on the desktop, the taskbar, the Start menu, Spotlight, the Dock, the notification center and toasts, every one through `UserIcons.qml` (the same file in the taskbar, the center and, written in by the patch, the notifications copy, whose cards ask the service's instance). An app's window class can only select an installed desktop entry or a theme icon by plain name, never a path of its own. An entry's `Icon=` that names a file is never opened in the shell, on the desktop or on a card (a sender can select one by naming the app): such an app shows the generic icon, because Qt's lookup opens the file on the main thread (a named pipe hangs the shell for good) and a small PNG with compressed text takes gigabytes (both measured, with real text; NUL-filled text costs almost nothing and hides this). A name goes through the same decoder, and a crafted PNG in `~/.local/share/icons` took a Quickshell process to about 2 GB and `bad_alloc` by name (measured in real Hyprland with a real theme, v0.1.16's candidate). `omarchy-webapp-install` saves a site's icon there unmodified. So a name from the hicolor trees under your home (`~/.icons/hicolor`, `~/.local/share/icons/hicolor` and the same under any data folder of yours: where installers save an app's icon; a whole theme you installed under your home is yours to trust, like the system's, and Qt draws it itself) is drawn only from a stripped copy a child makes under a memory and time limit (`icon_copies` :2033; the child sees only numbered temp names, so neither the name nor its hash is in argv), a crafted one gets none, and a name goes to Qt's lookup only after a scan has listed those trees and not found it, however it got there; until then it draws nothing. Qt's icon loader has a dash fallback from `name-x` to `name`; on Qt 6.12, with a real theme on the live desktop and Qt's loader log on, it tried that fallback for `name-x` and still answered nothing while `name` resolved from the same folder (measured), and a name with a listed prefix draws nothing here anyway. An `overtake` not on the shell's PATH never answers: nothing is drawn, nothing looked up. A scan that couldn't run (its lock busy for a minute, a full disk) exits non-zero and answers nothing: its names wait for another, 30 s later. Once a scan has answered that a name isn't in your folders, it isn't asked again, so an icon saved later under a name something had already asked for (a sender can ask for any name) is looked up by Qt until a scan lists it: one runs when a new name is asked for, and at least every two to two and a half minutes (each place's timer, spread so that whichever is first scans and the others find the list fresh and skip), so for about two minutes at most. One saved under a new name never is. A list from an earlier start is used at once (a name in it draws its copy or nothing; one not in it waits), so icons are up without waiting for the start's scan. Nothing watches your folders: an icon saved later is copied when something first asks for its name (a window, a card), at most one scan every 3 s; a file replaced under a name already listed keeps its old copy until the next start, and one replaced with an older date keeps it for good. The first 500 names get copies; past that, and for a link to nowhere or anything that isn't a file, a name is listed with no copy and draws nothing (the cap is in the README's Known limits). A copy whose icon is gone is removed at the next scan. A copy that failed is tried again after a day (a full disk looks the same as a crafted file). Not covered, in the README's Known limits: Omarchy's own launcher and dock, in the same shell, resolve an entry's icon through Qt's lookup themselves (`services/AppLibrary.qml`'s `iconSource`, read, not measured); an icon theme installed outside your home is the system's. A theme's preview in Settings is drawn only from a stripped copy made in a child under a memory and time limit (`theme_previews` :1984), as Omarchy's own picker does; a preview that's a link is refused. Toasts are drawn by Overtake's copy of Omarchy's
  notifications service, which never decodes a picture a sender supplies, named by a file path or sent as `image-data`; a card shows the app's installed icon instead, so chat avatars and Chromium's site icons don't show. Quickshell still keeps `image-data` bytes as long as the sender's object lives, up to D-Bus's 64 MiB for each, whether or not they are drawn (measured: 20 pictures of 64 MB grew the shell by about 1.25 GB). So at most 8 cards hold on to such bytes; further cards keep their text and icon, and lose the sender's buttons. A sender's object with more than 64 KB of body, of button text or of hints (counted at any depth), 8 KB of summary, 4 KB of app name or icon, or 32 buttons is let go the same way, and so is a hint QML can't read the size of (a map, struct or variant, except the picture's own) (not covered: reading the hints of about five 20 MB structs stalls Quickshell's notification server until the shell restarts, also in a six-line server with none of this code, measured; in the README's Known limits) (measured: 10 bodies of 30 MB, about 80 MB; 2 messages of 400,000 buttons, about 180 MB), and a card's body is cut to 8 KB, because stock's patterns take quadratic time on text in the shell every plugin shares (measured: 32 KB of `<` froze it for over a second per message, now about 200 ms, and the test's limit is 500 ms).
  The Control Center shows no album art: decoding a player's picture would
  happen inside the shell.
- **Network:** one request, `wttr.in` for sunrise/sunset, only in the optional
  Day & Night wallpaper mode (`sun_times` :594); documented in the README.
- **Local reads** (browser history for Copy URL, recent files, files under
  home for search) are listed in the README's
  Privacy section and never leave the machine.
- **Files:** Overtake's folders (`~/.local/state/overtake`,
  `~/.config/overtake`, `~/.cache/overtake`) are 0700 (a folder you symlinked is left as you set it up), created that way
  before anything is written, and tightened at install and at every start if they've been left open; edits to existing files keep their mode
  (temp file next to them, then a rename: `replace_file`, `install.sh:183`; a failure stops with a message); no `/tmp` state; the slideshow's saved pid is checked against `/proc/<pid>/cmdline`
  before it's stopped (`stop_slideshow` :643).
- **Background work:** in Omarchy mode, none beyond one check at login that the patched copies match the installed Omarchy (and, only if a login notice couldn't be shown, six `overtake status` retries over 60 s), `overtake status` when the Omarchy menu opens, at plugin start, and before each settings write. In Classic and Studio: the mode, the Trash and Do Not Disturb
  (Omarchy's `notifications/history.json` and `quiet.json`) are watched, not
  polled, and Hyprland window events trigger at most one refresh per 100 ms
  (title changes are ignored). In-process timers in Overtake's
  notifications copy (so only in Classic and Studio): an expiry check of history every minute, and
  a read-back of the history file a second after each write, rewritten 5 s later only while it doesn't match; `live.json` and `quiet.json` are read back the same way after each write, and retried about every 6 s while they don't match; every 5 s while the folder can't be prepared. The wallpaper slideshow is one background loop (`slideshow_loop`, `bin/overtake:679`, while Classic or Studio is on): it wakes every 15 minutes (Rotate) or every 5 minutes (Day & Night, whose wttr.in lookup is cached for the day when it succeeds, and tried again in 5 minutes when it doesn't). Process spawns that remain: `overtake remember` while Classic or
  Studio is on, only when a window has moved, resized, opened or closed
  (checked in-process every 5 s), a short bash process before each notification file write and each read-back (on activity, and during those retries), and one status probe (Wi-Fi, Bluetooth, night
  light…) every 2 s only while the Control Center is open. On events: `overtake fill-gap` per opened window, `fix-bar` after a `shell.json` change, `make-room`, `float-all`, `hide-minimized`, `relayout` twice per monitor change, `hyprctl eval` and `hyprctl animations` per drag, `omarchy-shell notifications isDnd` when the center opens, Settings' `sh -c` probes for each row it shows, the default-browser probe, `tail` on the recent-files list when it changes, `overtake theme-previews` when Settings shows your themes, `overtake icon-copies` at shell start from each place that draws icons (about 7 on one monitor, one at a time under a lock, a fraction of a second each with few icons, about a second each with 500) and, at most once every 3 s from each of those places, when one meets a name no scan has looked for, and one every two to two and a half minutes while the mode is on (every place has the timer, spread; whichever fires first scans, the others find the list fresh and skip), and `hyprctl cursorpos` on each 80 ms tick while an app drags its own window. The bell's clock ticks every second in Studio, a plain timer. Battery alerts
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
| Rich text and remote images | every `Text` in Overtake's plugins is `Text.PlainText`, and the built copies' one exception is fed only by `Markup.render`; no Label/ToolTip/TextEdit/TextArea; no album art; a desktop entry's icon only by plain theme name, never a file | `t-plain-text.py` (item by item, in the plugins and the built copies; no rich-text item types); `t-notifications.js` (hostile inputs through `Markup.render`); `t-qml-logic.js` (every lookup of a name not written in the code goes through `UserIcons.qml`, the same file in both plugins and in the patch); `t-usericons-qs.sh` (real Quickshell with a recorder in place of the lookup: nothing drawn or looked up before a list, copies drawn, none for a file with no copy or a name with a listed prefix, a system name looked up only after a scan, an icon saved under an answered name copied by the periodic scan (made a four-second one in the test copy), a failed scan answering nothing, an earlier start's list used at once, an icon saved after the start copied once asked for, a path never); `t-notifications-qs.sh` (the same on real cards, with the list arriving late; and a crafted PNG and a named pipe as an entry's icon, with a sender naming it: the shell lives and doesn't grow); `t-patches.sh` (the built copy draws only through its UserIcons; never a path or a sender's picture); `t-lifecycle-details.sh` (`icon-copies`: copies stripped of metadata under `prlimit` and `timeout`, a non-picture and a pipe listed with no copy, `~/.icons/hicolor`, a linked hicolor and a linked file covered, a theme folder of yours not scanned, a removed icon's copy removed, neither a name nor its hash in argv, a scan that can't lock exits non-zero and leaves the old list); `t-full-disk.sh` (a scan on a full disk exits non-zero and leaves the old list); a crafted icon by name run in a private Hyprland with the real shell for v0.1.16's candidate (Quickshell offscreen resolves no theme) |
| What senders supply | no picture is decoded, by path or as `image-data`, so one claiming more pixels than it sends can't crash the shell through its image loader; at most 8 cards keep a sender's picture bytes in memory, and an oversized message's object is let go; a body is cut before the patterns that stall on it | `t-notifications-qs.sh`: a FIFO shows a named file is never opened; a false `image-data` size leaves the shell running (the old line segfaults it); 20 pictures of 64 MB, also with a false size, stay under 800 MB of growth; 30 MB bodies and hints, 400,000 buttons, and 20 MB app names, icons, button text, list hints, variants and structs; 32 KB of the worst text stalls the shell under 500 ms |
| Themes from git | previews drawn only from a stripped copy made in a child under limits | `t-lifecycle-details.sh` (a PNG with 801 MiB of real text leaves an empty record, an oversized file isn't read, a preview's own text doesn't survive, a link is refused; modes; no direct `Image.source`) |
| Notification clicks | the action with Omarchy's `parseExecArgv` rules, else a browser's site, else the sender's window; from message text, only `https://<host>/` opens, and the full link is copied on stdin; an email address is only copied | `t-qml-logic.js` (site lookup refuses app names and numeric hosts); `t-notifications-qs.sh` (real clicks' handlers, with a /proc argv watcher); `t-lifecycle-details.sh` (app name as plain text, on stdin) |
| Omarchy's own files | marked blocks, mode-keeping replacements, floating layouts paused and restored, everything restored on uninstall: byte for byte for bindings, autostart, the menu and shell.toml, `shell.json` by content; screensaver art from before comes back if what's there now is what Overtake wrote, and art you wrote or picked stays, with the old one beside it | `t-lifecycle.sh`, `t-install-files.sh` (21 file shapes); `t-lifecycle-details.sh` (modes of `shell.json`, `shell.toml` and a floating layout through on, off and uninstall; a start marker with no end; widgets on your own bar) |
| A full disk | Overtake's command, uninstaller, patcher, Hyprland files, default settings, your config files and each patched copy are replaced through a temp file and a rename, or a build beside the old one; the old stays if it fails. The hook, the `.desktop` file, the version file and wallpapers are written directly, and a failure stops the install. Overtake's small state files and screensaver art it writes are overwritten in place | `t-full-disk.sh` (real ENOSPC on a tmpfs, by data size and inode count; a read-only state folder) |
| Switching back | each step runs whatever the others do; a half-done switch is finished later, and nothing saved is lost | `t-lifecycle-details.sh` (`hyprctl` failing as it does with no session, the saved looks and `shell.toml` compared before and after; `gsettings` failing; a refused line of a batch is said; the split ratio and Omarchy's floating tag put back) |
| The reminder | at most one per shell start; none during install | `t-setup-qs.sh` (real Quickshell) |
| Omarchy updates | copies rebuilt from the new Omarchy; one whose patch no longer fits is dropped | `t-patches.sh` (all five build; a changed plugin drops only its copy) |
| Omarchy mode stays stock | Overtake's notifications and battery copies switched on only with Classic/Studio, off (and the bar back) when switching to Omarchy; switched off in `shell.json` itself when no shell is running | `t-omarchy-mode.sh`, `t-lifecycle-details.sh` |
| Notices and hand-backs | a dropped copy asks for an Overtake update, not a reinstall; a failed rebuild is reported as that; a login notice waits for the shell; uninstall re-enables only what the copies switched off | `t-lifecycle-details.sh` |
| Startup repair | folders left open are tightened at the next `overtake` start | `t-lifecycle.sh` |
| A compromised wttr.in | at most 256 KB read; only real times reach `date` or the cache, else 07:00/19:00 | `t-sun-times.sh` (fails if the cap is removed) |
| Notification history (the maintainer's notification-plugin checks) | Clear all and remove are written without waiting for the save timer, and also in place within milliseconds by a helper that overwrites without truncating and puts the old bytes back on a short write, so a refused write leaves every row in place (a real short write measured; a removal on a full tmpfs measured; real btrfs not measured). On a read-only disk the entry stays and the center says so. `live.json` is read back after each write, so a removed row can't return through it, while a card closed before history's file has it stays there until it does (measured: a restart on a full disk keeps it). The same goes for `live.json`'s own write, so a disk with room for it and not for history keeps the row too (measured). The folder is prepared again before every write and read-back. On a clean exit a write can't wait, so a detached repair follows 0.3 s later. Any sender naming itself `Battery` with critical urgency passes Do Not Disturb, as a `notify-send` critical does. Clear all is the service's `forgetAll`: also a silenced copy just filed and cards still on screen, in `live.json` too. Each history write is read back a second later and written again about every 6 s until the file matches. History past Omarchy's one day pruned every minute and never listed; nothing removed before history has loaded | `t-notifications-qs.sh`: the real patched copy in real Quickshell, on a private bus and a real full disk (a small tmpfs), covering a copied code on stdin, a message's words in no command line through arrival, click, close, remove and Clear all (a /proc watcher polling every 20 ms, so a program that lives for less could go unseen), a card closed then a restart on a full disk and on one with room only for `live.json`, Clear all then a restart with the disk still full (also a stop within 0.3 s), a removal keeping rows filed since the last load, a silenced copy, a card on screen with a normal and a full disk. `t-notifications.sh`: the copy's own functions, timers and file handlers over a FileView model of Quickshell's measured behaviour (the model writes synchronously; real writes are asynchronous, which the real-Quickshell test covers), for the failure orderings. Each was checked by removing its fix |

Run them yourself (scratch homes, stubbed desktop commands, nothing touches your session): `tests/run.sh`. CI has no `qs`, so it skips the real-Quickshell tests (`t-notifications-qs.sh`, `t-setup-qs.sh`, `t-usericons-qs.sh`, the second half of `t-folders.sh`), and no `vipsthumbnail`, so it skips theme previews and icon copies; with no `luac` it checks the Lua blocks with a simpler match, and its partial Omarchy checkout has no `default/` for one shortcut check. All of these were run locally on this commit. `tests/run.sh`'s last line counts what was skipped. Most of the desktop's QML (Taskbar, Start menu, Dock, title bars, Settings) has no automated run, as it needs a compositor: for this release it was loaded in a private Hyprland with the real Omarchy shell, in Classic and Studio, with its shortcuts checked there.

## Trying it without touching your desktop

```bash
git clone --branch v0.1.17 https://github.com/Gleasonmt/overtake-mode-omarchy.git && cd overtake-mode-omarchy
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
[NOTICE.md](NOTICE.md); each patched copy gets one. The wallpapers were made for this project with AI tools (`wallpapers/src` has the scripts behind the ones drawn by code).
