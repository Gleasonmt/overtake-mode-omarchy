#!/bin/bash
# Install (every option) → reinstall → on → off → options off → uninstall:
# every file the user had comes back byte for byte, Overtake's folders are
# private (also when an older version left them open), and Omarchy's floating
# workspace layouts are paused while the mode is on and restored after.
source "$(dirname "$0")/lib.sh"

H="$T/home"
make_home "$H"
mkdir -p "$H/.config/overtake" && chmod 755 "$H/.config/overtake"   # as an older version left it
cp -a "$H" "$T/before"
L="$H/.local/state/omarchy/workspace-layouts"

cd "$REPO"
sbx "$H" ./install.sh --yes --style-menus --name-tags --link-handler --image-viewer >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
for d in .config/overtake .local/state/overtake .cache/overtake; do
  [[ $(stat -c %a "$H/$d") == 700 ]] || fail "$d is $(stat -c %a "$H/$d"), not 700"
done
pass "install: Overtake's folders are 0700 (an old 0755 one tightened)"

sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || fail "reinstall"
pass "reinstall keeps working"

sbx "$H" "$H/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
grep -q '"dwindle"' "$L/3.lua" || fail "floating layout not paused while on"
sbx "$H" "$H/.local/bin/overtake" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
grep -q '"floating"' "$L/3.lua" || fail "floating layout not restored after off"
pass "on/off: Omarchy's floating layout paused, then restored"

sbx "$H" ./install.sh --yes --no-style-menus --no-name-tags --no-link-handler --no-image-viewer >>"$T/log" 2>&1 || fail "options off"
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }

# Everything the user had is back byte for byte, except shell.json, which jq
# rewrites (same content, Omarchy's own formatting). Overtake's own folders
# and settings may stay (kept without --purge), as may empty folders.
jq -S . "$T/before/.config/omarchy/shell.json" >"$T/a.json"; jq -S . "$H/.config/omarchy/shell.json" >"$T/b.json"
cmp -s "$T/a.json" "$T/b.json" || { diff "$T/a.json" "$T/b.json"; fail "shell.json content changed"; }
changes=$(diff -r -x shell.json "$T/before" "$H" | grep -v -E "^Only in .*: (\.cache|Pictures|overtake|bin|state|hooks|plugins|shell\.toml)$" |
          grep -v -E "^Only in $H/\.config/overtake: " || true)
[[ -z $changes ]] || { echo "$changes"; fail "uninstall left differences"; }
pass "uninstall: every pre-existing file restored (shell.json: same content)"
