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

cd "$REPO"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "upgrade"; }
[[ ! -e $H/.config/omarchy/plugins/overtake.session-names ]] || fail "name tags left after the upgrade"
grep -q 'SUPER + ALT + N' "$H/.config/hypr/bindings.lua" && fail "the name-tag shortcut left after the upgrade"
cmp -s "$T/before/.local/share/applications/omarchy-browser.desktop" "$H/.local/share/applications/omarchy-browser.desktop" || fail "link handler line not restored exactly"
cmp -s "$T/before/.config/mimeapps.list" "$H/.config/mimeapps.list" || { diff "$T/before/.config/mimeapps.list" "$H/.config/mimeapps.list"; fail "mimeapps.list not restored exactly"; }
[[ ! -e $H/.local/share/applications/overtake-image-viewer.desktop && ! -e $H/.local/state/overtake/image-defaults ]] || fail "image viewer files left after the upgrade"
grep -q 'appearance\.background' "$H/.config/omarchy/extensions/omarchy-menu.jsonc" && fail "Appearance menus left after the upgrade"
pass "upgrading from $OLD takes out all four extras exactly (mimeapps.list and the link line byte for byte)"

sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
check_restored "$T/before" "$H"
pass "and uninstall then leaves the user's files as they were before $OLD"
