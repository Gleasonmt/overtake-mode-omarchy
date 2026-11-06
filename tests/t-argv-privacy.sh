#!/bin/bash
# Private text never appears in any child process's command line, where other
# local accounts could read it (/proc/<pid>/cmdline): window titles and
# classes, the bar's settings, window names, notification text, battery
# device names, the workspace names you choose and your wallpaper's file name.
# Every command started by Overtake is logged with its full argv (stubs and
# wrappers in lib.sh) and searched for a marker.
source "$(dirname "$0")/lib.sh"

H="$T/home"
make_home "$H"
cd "$REPO"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
O="$H/.local/bin/overtake"
BG="$H/.local/state/omarchy/current/background"
WS="Work $MARK"
# a browser's history, which `copy-url` reads the address from
mkdir -p "$H/.config/chromium/Default"
python3 -I - "$H/.config/chromium/Default/History" "$MARK" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table urls (url text, title text, last_visit_time integer)")
con.execute("insert into urls values (?, ?, 1)", (f"https://example.com/{sys.argv[2]}", f"Page {sys.argv[2]}"))
con.commit()
PY
stub wl-copy "cat >>\"$T/clipboard\""
stub omarchy-menu-images "echo \"\$HOME/.cache/overtake/bg-picker/1-theme/Studio.png\""

use_workspace "$WS"
: >"$ARGV_LOG"   # from here on: the commands Overtake itself runs
run() { sbx "$H" "$O" "$@" >>"$T/log" 2>&1 || true; }

run on                                                         # bar settings (with the marker) saved and swapped
[[ $(readlink "$BG") != *"$MARK"* ]] || fail "turning the mode on didn't put the slideshow up (path not exercised)"
run remember                                                   # window titles/classes from hyprctl
run relayout all
echo "Name $MARK" | sbx "$H" "$O" name 0xa1 - >>"$T/log" 2>&1 || true
printf '{"app":"Battery","summary":"%s mouse low","body":"%s"}' "$MARK" "$MARK" | sbx "$H" "$O" notify-stdin >>"$T/log" 2>&1 || true
run notification-open "Slack"
for c in hide-app hide-others quit-app; do run "$c" 0xa1; done  # look up windows by class

# Window controls, on a workspace you named
run minimize 0xa1
jq -e --arg w "$WS" '.["0xa1"] == $w' "$H/.local/state/overtake/minimized.json" >/dev/null || fail "minimize didn't record the workspace name (path not exercised)"
run restore 0xa1
run restore 0xa1 stay
run focus-app "app."
run minimize-all
run minimize-all eDP-1
run restore-all
run snap left 0xa1
jq -e --arg w "$WS" '.["0xa1"].ws == $w' "$H/.local/state/overtake/zones.json" >/dev/null || fail "snap didn't record the workspace name (path not exercised)"
run snap right 0xa1
run unsnap 0xa1
run snap left 0xa1
rm -f "$H/.local/state/overtake/no-fill"
run fill-gap 0xa1
run show-desktop
use_workspace "2"; jq '.windows = 0' "$HYPR/activeworkspace.json" >"$HYPR/x"; mv "$HYPR/x" "$HYPR/activeworkspace.json"
run show-desktop                                               # back to the named one
use_workspace "$WS"
run fix-bar
for c in maximize show make-room close; do run "$c" 0xa1; done
run send 2 0xa1 10 40

# A browser window's address, with a page title that's private
jq --arg t "Page $MARK" '(.[].class) = "chromium" | (.[].title) = $t' "$HYPR/clients.json" >"$HYPR/c2"
cp "$HYPR/clients.json" "$HYPR/c1"; cp "$HYPR/c2" "$HYPR/clients.json"
run copy-url 0xa1
cp "$HYPR/c1" "$HYPR/clients.json"
grep -q "$MARK" "$T/clipboard" || fail "copy-url didn't copy the address (path not exercised)"

# Wallpapers: your own back, as screensaver art, and through the picker
mkdir -p "$H/.config/overtake" "$H/.config/omarchy/backgrounds/x"
printf 'picture' >"$H/.config/omarchy/backgrounds/x/$MARK-theme.png"
echo x >"$H/.local/state/omarchy/current/theme.name"
run bg-picker
run bg-picker apply
run next-wallpaper
ln -sfn "$H/Pictures/$MARK-holiday.png" "$BG"
run screensaver show wallpaper
[[ -e $H/.config/omarchy/branding/screensaver.txt.before-overtake ]] || fail "screensaver art wasn't exercised"
run style studio                                               # a wallpaper you picked, kept per look
run style classic
run next-wallpaper                                             # (the slideshow up again, so off must bring yours back)
run off                                                        # saved bar (with the marker) restored; your wallpaper back

[[ -s $ARGV_LOG ]] || fail "no commands were logged (the harness isn't working)"
grep -q "jq" "$ARGV_LOG" || fail "jq calls weren't logged (the harness isn't working)"
grep -qa "dispatch" "$ARGV_LOG" || fail "hyprctl dispatches weren't logged (the harness isn't working)"
if tr '\0' ' ' <"$ARGV_LOG" | grep -n "$MARK"; then
  fail "the private marker appeared in a command line (above)"
fi
pass "no private text in any of $(wc -l <"$ARGV_LOG") logged command lines"

# The marker did reach where it belongs (so the test exercised the paths).
grep -q "$MARK" "$H/.local/state/overtake/names.json" 2>/dev/null || { echo "Name $MARK" | sbx "$H" "$O" name 0xa1 -; grep -q "$MARK" "$H/.local/state/overtake/names.json"; } || fail "the window name wasn't stored (path not exercised)"
grep -q "$MARK" "$H/.config/omarchy/shell.json" || fail "the bar settings didn't come back after off"
[[ $(readlink "$BG") == *"$MARK-holiday.png" ]] || fail "your wallpaper didn't come back after off: $(readlink "$BG")"
# ...and Hyprland was really given the workspace by name, from a file
grep -qxF "$WS" "$HYPR/named-dispatches" || fail "no dispatch reached the named workspace"
ls -A "$H/.local/state/overtake" | grep -q '^\.ws-name' && fail "a workspace name was left in a file after its dispatch"

# A name given as an argument (where other accounts could read it) is refused.
if sbx "$H" "$O" name 0xa1 "ARGNAME" >/dev/null 2>&1; then fail "a window name given as an argument was accepted"; fi
grep -q "ARGNAME" "$H/.local/state/overtake/names.json" && fail "a window name given as an argument was stored"
pass "the private text reached its private destinations (names.json, shell.json, minimized.json, zones.json, the clipboard, the wallpaper link); names are taken on stdin only"
