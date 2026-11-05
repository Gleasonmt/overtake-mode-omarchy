#!/bin/bash
# Private text never appears in any child process's command line, where other
# local accounts could read it (/proc/<pid>/cmdline): window titles and
# classes, the bar's settings, window names, notification text, battery
# device names. Every command started by Overtake is logged with its full
# argv (stubs and wrappers in lib.sh) and searched for a marker.
source "$(dirname "$0")/lib.sh"

H="$T/home"
make_home "$H"
cd "$REPO"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
O="$H/.local/bin/overtake"

: >"$ARGV_LOG"   # from here on: the commands Overtake itself runs
sbx "$H" "$O" on >>"$T/log" 2>&1 || true                       # bar settings (with the marker) saved and swapped
sbx "$H" "$O" remember >>"$T/log" 2>&1 || true                 # window titles/classes from hyprctl
sbx "$H" "$O" relayout all >>"$T/log" 2>&1 || true
echo "Name $MARK" | sbx "$H" "$O" name 0xa1 - >>"$T/log" 2>&1 || true
printf '{"app":"Battery","summary":"%s mouse low","body":"%s"}' "$MARK" "$MARK" | sbx "$H" "$O" notify-stdin >>"$T/log" 2>&1 || true
sbx "$H" "$O" notification-open "Slack" >>"$T/log" 2>&1 || true
for c in hide-app hide-others quit-app; do sbx "$H" "$O" "$c" 0xa1 >>"$T/log" 2>&1 || true; done   # look up windows by class
sbx "$H" "$O" off >>"$T/log" 2>&1 || true                      # saved bar (with the marker) restored

[[ -s $ARGV_LOG ]] || fail "no commands were logged (the harness isn't working)"
grep -q "jq" "$ARGV_LOG" || fail "jq calls weren't logged (the harness isn't working)"
if tr '\0' ' ' <"$ARGV_LOG" | grep -n "$MARK"; then
  fail "the private marker appeared in a command line (above)"
fi
pass "no private text in any of $(wc -l <"$ARGV_LOG") logged command lines"

# The marker did reach where it belongs (so the test exercised the paths).
grep -q "$MARK" "$H/.local/state/overtake/names.json" || fail "the window name wasn't stored (path not exercised)"
grep -q "$MARK" "$H/.config/omarchy/shell.json" || fail "the bar settings didn't come back after off"

# A name given as an argument (where other accounts could read it) is refused.
if sbx "$H" "$O" name 0xa1 "ARGNAME" >/dev/null 2>&1; then fail "a window name given as an argument was accepted"; fi
grep -q "ARGNAME" "$H/.local/state/overtake/names.json" && fail "a window name given as an argument was stored"
pass "the private text reached its private destinations (names.json, shell.json); names are taken on stdin only"
