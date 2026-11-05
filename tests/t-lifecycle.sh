#!/bin/bash
# Install → reinstall → on → off → uninstall:
# every file the user had comes back byte for byte, Overtake's folders are
# private (also when they were left open), and Omarchy's floating
# workspace layouts are paused while the mode is on and restored after.
source "$(dirname "$0")/lib.sh"

H="$T/home"
make_home "$H"
mkdir -p "$H/.config/overtake" && chmod 755 "$H/.config/overtake"   # left open
cp -a "$H" "$T/before"
L="$H/.local/state/omarchy/workspace-layouts"

cd "$REPO"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
for d in .config/overtake .local/state/overtake .cache/overtake; do
  [[ $(stat -c %a "$H/$d") == 700 ]] || fail "$d is $(stat -c %a "$H/$d"), not 700"
done
pass "install: Overtake's folders are 0700 (a 0755 one tightened)"

# Left open after install, too: the next
# start of any `overtake` command tightens them again.
chmod 755 "$H/.local/state/overtake" "$H/.config/overtake" "$H/.cache/overtake"
sbx "$H" "$H/.local/bin/overtake" status >/dev/null
for d in .config/overtake .local/state/overtake .cache/overtake; do
  [[ $(stat -c %a "$H/$d") == 700 ]] || fail "$d is $(stat -c %a "$H/$d") after a start, not 700"
done
pass "startup: folders left open are tightened at the next start"

sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || fail "reinstall"
pass "reinstall keeps working"

sbx "$H" "$H/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
grep -q '"dwindle"' "$L/3.lua" || fail "floating layout not paused while on"
sbx "$H" "$H/.local/bin/overtake" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
grep -q '"floating"' "$L/3.lua" || fail "floating layout not restored after off"
pass "on/off: Omarchy's floating layout paused, then restored"

sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }

check_restored "$T/before" "$H"
pass "uninstall: every pre-existing file restored, nothing left but kept settings and wallpapers"
