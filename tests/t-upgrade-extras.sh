#!/bin/bash
# Upgrading from v0.1.11 (the release users have), which offered four optional
# extras (link handler, image viewer default, Appearance menus, Claude Code
# name tags), with all four on: this version takes each one back out exactly,
# and uninstall then leaves the user's files as they were before v0.1.11.
source "$(dirname "$0")/lib.sh"

OLD=v0.1.11
if ! git -C "$REPO" cat-file -e "$OLD^{commit}" 2>/dev/null; then
  [[ ${CI:-} == true ]] && fail "$OLD isn't in the git history (CI must fetch it)"
  echo "SKIP: $OLD isn't in this clone's history"
  exit 0
fi
mkdir -p "$T/old"
git -C "$REPO" archive "$OLD" | tar -x -C "$T/old"
# (v0.1.11's installer only looked in /usr/share/omarchy; point it at the
# Omarchy plugins the tests use, as this version's installer can be)
sed -i "s|^OMARCHY_PLUGINS=/usr/share/omarchy/shell/plugins\$|OMARCHY_PLUGINS=$OMARCHY_SRC|" "$T/old/install.sh"
grep -q "^OMARCHY_PLUGINS=$OMARCHY_SRC\$" "$T/old/install.sh" || fail "couldn't point $OLD's installer at the Omarchy plugins (test setup)"

# A working xdg-mime (it writes and reads mimeapps.list as the real one does)
# and an imv-dir, so v0.1.11's image viewer default really is set up.
stub imv-dir
stub xdg-mime "$(cat <<'EOF'
f="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
case $1 in
  default)
    touch "$f"
    grep -q '^\[Default Applications\]' "$f" || printf '[Default Applications]\n' >>"$f"
    python3 -I - "$f" "$3" "$2" <<'PY'
import sys
path, mime, app = sys.argv[1:]
lines = open(path).read().splitlines()
out, sec, done = [], "", False
for l in lines:
    if l.startswith("["):
        if sec == "[Default Applications]" and not done:
            out.append(f"{mime}={app}"); done = True
        sec = l
    elif sec == "[Default Applications]" and l.startswith(mime + "="):
        if not done: out.append(f"{mime}={app}"); done = True
        continue
    out.append(l)
if not done: out.append(f"{mime}={app}")
open(path, "w").write("\n".join(out) + "\n")
PY
    ;;
  query)
    v=$(awk -v t="$3" '/^\[/ { s = ($0 == "[Default Applications]") } s && index($0, t "=") == 1 { print substr($0, length(t) + 2); exit }' "$f" 2>/dev/null)
    echo "${v:-imv.desktop}" ;;
esac
EOF
)"

H="$T/home"
make_home "$H"
printf '[Default Applications]\nimage/png=org.gnome.Loupe.desktop\n' >"$H/.config/mimeapps.list"
cp -a "$H" "$T/before"

( cd "$T/old" && sbx "$H" ./install.sh --yes --style-menus --name-tags --link-handler --image-viewer >"$T/log" 2>&1 ) || { cat "$T/log"; fail "$OLD install"; }
# (the setup really took effect)
[[ -d $H/.config/omarchy/plugins/overtake.session-names ]] || fail "$OLD didn't install its name tags (test setup)"
grep -q 'SUPER + ALT + N' "$H/.config/hypr/bindings.lua" || fail "$OLD didn't add its name-tag shortcut (test setup)"
grep -q 'overtake"\? open-url' "$H/.local/share/applications/omarchy-browser.desktop" || fail "$OLD didn't set its link handler (test setup)"
grep -q 'overtake-image-viewer' "$H/.config/mimeapps.list" || fail "$OLD didn't set its image viewer (test setup)"
grep -q 'appearance\.background' "$H/.config/omarchy/extensions/omarchy-menu.jsonc" || fail "$OLD didn't add its Appearance menus (test setup)"
# What a running shell would have recorded for the name tags, and a name typed
# for one (with no shell during the upgrade, nothing can ask it to forget them).
SESSION_NAMES="$H/.local/state/overtake/session-names.json"
SENTINEL="SESSION_NAME_SENTINEL_$MARK"
printf '{"some-session":"%s"}\n' "$SENTINEL" >"$SESSION_NAMES"
jq '.plugins = [{"id":"overtake.session-names"}]' "$H/.config/omarchy/shell.json" >"$T/s.json" && cat "$T/s.json" >"$H/.config/omarchy/shell.json"

cd "$REPO"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "upgrade"; }
[[ ! -e $H/.config/omarchy/plugins/overtake.session-names ]] || fail "name tags left after the upgrade"
[[ ! -e $SESSION_NAMES ]] || fail "the names typed for the name tags were left after the upgrade"
grep -rqs "$SENTINEL" "$H/.local/state/overtake" && fail "a typed name was left in the state folder"
jq -e 'has("plugins") | not' "$H/.config/omarchy/shell.json" >/dev/null || { cat "$H/.config/omarchy/shell.json"; fail "the name tags' entry was left in shell.json"; }
grep -q 'SUPER + ALT + N' "$H/.config/hypr/bindings.lua" && fail "the name-tag shortcut left after the upgrade"
cmp -s "$T/before/.local/share/applications/omarchy-browser.desktop" "$H/.local/share/applications/omarchy-browser.desktop" || fail "link handler line not restored exactly"
cmp -s "$T/before/.config/mimeapps.list" "$H/.config/mimeapps.list" || { diff "$T/before/.config/mimeapps.list" "$H/.config/mimeapps.list"; fail "mimeapps.list not restored exactly"; }
[[ ! -e $H/.local/share/applications/overtake-image-viewer.desktop && ! -e $H/.local/state/overtake/image-defaults ]] || fail "image viewer files left after the upgrade"
grep -q 'appearance\.background' "$H/.config/omarchy/extensions/omarchy-menu.jsonc" && fail "Appearance menus left after the upgrade"
pass "upgrading from $OLD takes out all four extras exactly (mimeapps.list and the link line byte for byte)"

sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
check_restored "$T/before" "$H"
pass "and uninstall then leaves the user's files as they were before $OLD"

# A link where the names were is not followed, and not removed: not Overtake's file.
H="$T/home-link"
make_home "$H"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
echo "$SENTINEL" >"$T/outside"
ln -s "$T/outside" "$H/.local/state/overtake/session-names.json"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall"; }
[[ -L $H/.local/state/overtake/session-names.json && $(<"$T/outside") == "$SENTINEL" ]] || fail "the upgrade touched a symlink at the name tags' file"
pass "a symlink at the name tags' file is left alone"

# The mode used under $OLD, and off again (which leaves an empty shell.toml),
# then the upgrade, then uninstall: nothing of any of it remains.
H="$T/home-used"
make_home "$H"
cp -a "$H" "$T/before-used"
( cd "$T/old" && sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 ) || { cat "$T/log"; fail "$OLD install"; }
sbx "$H" "$H/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "$OLD on"; }
sbx "$H" "$H/.local/bin/overtake" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "$OLD off"; }
[[ -f $H/.config/omarchy/shell.toml && ! -s $H/.config/omarchy/shell.toml ]] || fail "$OLD didn't leave its empty shell.toml (test setup)"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "upgrade"; }
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
check_restored "$T/before-used" "$H"
pass "$OLD on and off, then the upgrade, then uninstall: the user's files as they were"
