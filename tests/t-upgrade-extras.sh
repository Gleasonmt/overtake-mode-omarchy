#!/bin/bash
# Upgrading from 0.1.12, which offered four optional extras (link handler,
# image viewer, Appearance menus, Claude Code name tags), with all of them on:
# this version takes each one back out, exactly, and uninstall leaves the
# user's files as they were before 0.1.12.
source "$(dirname "$0")/lib.sh"

OLD=65ba1c1   # v0.1.12 (the last version with the extras)
git -C "$REPO" cat-file -e "$OLD^{commit}" 2>/dev/null || { echo "ok - skipped (no git history for $OLD)"; exit 0; }
mkdir -p "$T/old"
git -C "$REPO" archive "$OLD" | tar -x -C "$T/old"

H="$T/home"
make_home "$H"
printf '[Default Applications]\nimage/png=org.gnome.Loupe.desktop\n' >"$H/.config/mimeapps.list"
cp -a "$H" "$T/before"
( cd "$T/old" && sbx "$H" ./install.sh --yes --style-menus --name-tags --link-handler >"$T/log" 2>&1 ) || { cat "$T/log"; fail "0.1.12 install"; }
[[ -d $H/.config/omarchy/plugins/overtake.session-names ]] || fail "0.1.12 didn't install its name tags (test setup)"
grep -q "overtake\"\\? open-url" "$H/.local/share/applications/omarchy-browser.desktop" || fail "0.1.12 didn't set its link handler (test setup)"

cd "$REPO"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "upgrade"; }
[[ ! -e $H/.config/omarchy/plugins/overtake.session-names ]] || fail "name tags left after the upgrade"
grep -q '^Exec=omarchy-launch-browser ' "$H/.local/share/applications/omarchy-browser.desktop" || fail "link handler left after the upgrade"
grep -q 'appearance\.background' "$H/.config/omarchy/extensions/omarchy-menu.jsonc" && fail "Appearance menus left after the upgrade"
grep -q 'SUPER + ALT + N' "$H/.config/hypr/bindings.lua" && fail "the name-tag shortcut left after the upgrade"
pass "upgrading from 0.1.12 takes out all four extras"

sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
jq -S . "$T/before/.config/omarchy/shell.json" >"$T/a.json"; jq -S . "$H/.config/omarchy/shell.json" >"$T/b.json"
cmp -s "$T/a.json" "$T/b.json" || fail "shell.json content changed"
changes=$(diff -r -x shell.json "$T/before" "$H" | grep -v -E "^Only in .*: (\.cache|Pictures|overtake|bin|state|hooks|plugins|shell\.toml)$" |
          grep -v -E "^Only in $H/\.config/overtake: " || true)
[[ -z $changes ]] || { echo "$changes"; fail "uninstall after the upgrade left differences"; }
pass "and uninstall then restores every file of the user's"
