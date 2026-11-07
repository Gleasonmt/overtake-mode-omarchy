#!/bin/bash
# UserIcons.qml in real Quickshell. The list of copies doesn't exist when a plugin
# starts, and a file that isn't there can't be watched; the folder may not exist
# either. Icons have to appear anyway, and a name from your folder must never reach
# the lookup. (With no icon theme here the real lookup answers nothing, for any
# name, so it's replaced by a recorder: "image://icon/<name>" shows what reached it.)
source "$(dirname "$0")/lib.sh"
command -v qs >/dev/null || { echo "skipped: no qs (the real-Quickshell test needs it)"; exit 0; }

recorder() {  # recorder <folder>: UserIcons.qml, its lookup a recorder
  mkdir -p "$1"; cp "$REPO/plugins/overtake.taskbar/UserIcons.qml" "$1/"
  sed -i 's|return Quickshell.iconPath(name, true)|return "image://icon/" + name|' "$1/UserIcons.qml"
  grep -q 'image://icon/' "$1/UserIcons.qml" || fail "(setup) the lookup wasn't replaced"
}
cmp -s "$REPO/plugins/overtake.taskbar/UserIcons.qml" "$REPO/plugins/overtake.notification-center/UserIcons.qml" || fail "the two copies of UserIcons.qml differ"

E=$T/ui; H=$E/home; mkdir -p "$E/bin" "$E/run" "$H/.local/share/icons/hicolor/256x256/apps"; chmod 700 "$E/run"
recorder "$E/cfg"
# (the real scan takes a moment: the list arrives a second after the plugin starts)
cat >"$E/bin/overtake" <<'STUB'
#!/bin/bash
[[ $1 == icon-copies ]] || exit 0
echo x >>"$HOME/scans"
sleep 1
d=$HOME/.cache/overtake/user-icons; mkdir -p "$d"
printf 'siteclean\tabc.png\nsitebomb\t\n' >"$d/.i"; mv -f "$d/.i" "$d/index"
STUB
chmod +x "$E/bin/overtake"
: >"$H/.local/share/icons/hicolor/256x256/apps/justsaved.png"
# (a list from before this start, which doesn't know what's been saved since)
mkdir -p "$H/.cache/overtake/user-icons"; printf 'old\tabc.png\n' >"$H/.cache/overtake/user-icons/index"
cat >"$E/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  readonly property string bound: icons.source("boundname")   // (as a binding draws it: it has to look again by itself)
  function say(tag) { console.log("UI", tag, icons.ready, "clean=" + icons.source("siteclean"), "bomb=" + icons.source("sitebomb"), "saved=" + icons.source("justsaved"), "sys=" + icons.source("firefox"), "bound=" + bound, "path=" + icons.source("/tmp/x.png")) }
  Timer { interval: 300; running: true; onTriggered: say("early") }
  Timer { interval: 4000; running: true; onTriggered: { icons.source("firefox"); icons.source("justsaved") } }   // (asks for what isn't known; one just saved stays out)
  Timer { interval: 8000; running: true; onTriggered: say("later") }
}
QML
out=$(env -i HOME="$H" PATH="$E/bin:$PATH" XDG_RUNTIME_DIR="$E/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 11 qs -p "$E/cfg/shell.qml" 2>&1 | grep -a 'UI ' || true)
early=$(grep -a 'UI early' <<<"$out") later=$(grep -a 'UI later' <<<"$out")
[[ -n $early && -n $later ]] || fail "(setup) no answers: $out"
[[ $early == *"UI early false"* ]] || fail "a list from before the scan was trusted: $early"
[[ $early == *'sys= '* ]] || fail "an icon was looked up before the list arrived: $early"
[[ $later == *"UI later true"* ]] || fail "the list that arrived after the start was never read: $later"
[[ $later == *"clean=file://"*"/overtake/user-icons/abc.png"* ]] || fail "a copied icon isn't drawn from its copy: $later"
[[ $later == *'bomb= '* ]] || fail "an icon with no copy was looked up: $later"
[[ $later == *'saved= '* ]] || fail "an icon just saved was looked up before it was copied: $later"
[[ $later == *'sys=image://icon/firefox '* ]] || fail "a system icon wasn't looked up: $later"
[[ $later == *'bound=image://icon/boundname '* ]] || fail "what drew nothing didn't look again once a scan had answered: $later"
[[ $later == *'path=' && $later != *'path=/'* && $later != *'path=image'* ]] || fail "a path was looked up: $later"
pass "icons appear when the list arrives after the plugin starts; with no copy, or just saved, none is looked up; a system icon is"

# The first icon ever: with the real scan, no icon folder at the start.
if command -v vipsthumbnail >/dev/null; then
  E2=$T/ui2; H=$E2/home; mkdir -p "$E2/bin" "$E2/run" "$H/.local/share"; chmod 700 "$E2/run"
  recorder "$E2/cfg"
  printf '#!/bin/bash\necho x >>"$HOME/scans"\nexec "%s" "$@"\n' "$REPO/bin/overtake" >"$E2/bin/overtake"; chmod +x "$E2/bin/overtake"
  cat >"$E2/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  property bool late: false
  Timer { interval: 9000; running: true; onTriggered: late = true }
  Timer { interval: 500; repeat: true; running: true; onTriggered: console.log("UI", "clean=" + icons.source("firstclean"), "junk=" + icons.source("firstjunk"), "chain=" + icons.source("chainsite"), "other=" + (late ? icons.source("othersize") : "wait"), "incoming=" + ("firstclean" in icons.incoming)) }
}
QML
  env -i HOME="$H" PATH="$E2/bin:$PATH" XDG_RUNTIME_DIR="$E2/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 26 qs -p "$E2/cfg/shell.qml" >"$E2/log" 2>&1 &
  QSP=$!
  IC=$H/.local/share/icons/hicolor/256x256/apps
  for _ in {1..40}; do [[ -d $IC && -f $H/.cache/overtake/user-icons/index ]] && break; sleep 0.1; done
  [[ -d $IC ]] || fail "the scan didn't make the icon folder"
  sleep 2
  vipsthumbnail "$REPO/preview.png" --size 32x32 -o "$E2/good.png" 2>/dev/null
  scans_before=$(wc -l <"$H/scans")
  cp "$E2/good.png" "$IC/firstclean.png"
  head -c 2000 /dev/urandom >"$IC/firstjunk.png"
  head -c 2000 /dev/urandom >"$IC/chainsite.png"     # (a site's first answer isn't a picture; the next is, written in place)
  mkdir -p "$H/.local/share/icons/hicolor/48x48/apps"; cp "$E2/good.png" "$H/.local/share/icons/hicolor/48x48/apps/othersize.png"   # (not where the installer saves)
  sleep 1; seen=$(grep -ac 'UI ' "$E2/log")   # (before it's saved, a name is just a name)
  sleep 1; cat "$E2/good.png" >"$IC/chainsite.png"
  wait "$QSP" 2>/dev/null || true
  scans_after=$(wc -l <"$H/scans")
  grep -a 'UI ' "$E2/log" | tail -n +"$((seen + 1))" | grep -a 'image://icon/first\|image://icon/chain' && fail "an icon saved after the start reached the lookup"
  grep -a 'UI ' "$E2/log" | grep -a 'image://icon/othersize' && fail "an icon saved in another size's folder reached the lookup"
  last=$(grep -a 'UI ' "$E2/log" | tail -1)
  [[ $last == *"clean=file://"*"/overtake/user-icons/"* ]] || fail "the first icon saved after the start got no copy: $last"
  [[ $last == *'junk= '* ]] || fail "a file that isn't a picture got something: $last"
  [[ $last == *"chain=file://"*"/overtake/user-icons/"* ]] || fail "an icon written in place, picture second, got no copy: $last"
  [[ $last == *"other=file://"*"/overtake/user-icons/"* ]] || fail "an icon in another size's folder got no copy: $last"
  (( scans_after > scans_before )) || fail "saving an icon ran no scan"
  pass "the first icon, in a folder that didn't exist at the start, is known at once and drawn from its copy; one written in place, or in another size's folder, too"
  # Nothing but a name, and a file saved outside the watched folder: no scan has seen it,
  # so the name draws nothing until one has; and it's still only the copy.
  cat >"$E2/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  Timer { interval: 3000; running: true; onTriggered: console.log("UI", "first=" + icons.source("elsewhere")) }
  Timer { interval: 5500; running: true; onTriggered: console.log("UI", "then=" + icons.source("elsewhere")) }
}
QML
  H=$E2/home4; mkdir -p "$H/.local/share/icons/hicolor/48x48/apps" "$E2/run4"; chmod 700 "$E2/run4"
  env -i HOME="$H" PATH="$E2/bin:$PATH" XDG_RUNTIME_DIR="$E2/run4" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 7 qs -p "$E2/cfg/shell.qml" >"$E2/log4" 2>&1 &
  QSP=$!
  sleep 2; cp "$E2/good.png" "$H/.local/share/icons/hicolor/48x48/apps/elsewhere.png"
  wait "$QSP" 2>/dev/null || true
  grep -a 'UI first= *$' "$E2/log4" >/dev/null || fail "a name no scan had looked for drew something: $(grep -a 'UI ' "$E2/log4")"
  grep -a 'UI then=file://.*/overtake/user-icons/' "$E2/log4" >/dev/null || fail "an icon saved outside the watched folder wasn't drawn from its copy: $(grep -a 'UI ' "$E2/log4")"
  pass "a name draws nothing until a scan has looked for it, and an icon saved outside the watched folder is drawn from its copy"
  # With nothing asked for: a start scans once, with or without icons there, and a folder made
  # by that scan is watched, so the first icon saved in it is copied unasked.
  cat >"$E2/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot { UserIcons { } }
QML
  for icons_there in 0 1; do
    H=$E2/home3$icons_there; IC=$H/.local/share/icons/hicolor/256x256/apps; mkdir -p "$IC" "$E2/run3"; chmod 700 "$E2/run3"
    (( icons_there )) && cp "$E2/good.png" "$IC/already.png"
    env -i HOME="$H" PATH="$E2/bin:$PATH" XDG_RUNTIME_DIR="$E2/run3" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 5 qs -p "$E2/cfg/shell.qml" >"$E2/log3" 2>&1 || true
    [[ $(wc -l <"$H/scans") == 1 ]] || fail "a start ran $(wc -l <"$H/scans") scans (icons there: $icons_there)"
  done
  H=$E2/home5; mkdir -p "$H/.local/share" "$E2/run5"; chmod 700 "$E2/run5"
  env -i HOME="$H" PATH="$E2/bin:$PATH" XDG_RUNTIME_DIR="$E2/run5" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 7 qs -p "$E2/cfg/shell.qml" >"$E2/log5" 2>&1 &
  QSP=$!
  sleep 3; IC=$H/.local/share/icons/hicolor/256x256/apps; [[ -d $IC ]] || fail "the scan didn't make the folder"
  cp "$E2/good.png" "$IC/unasked.png"
  wait "$QSP" 2>/dev/null || true
  grep -q '^unasked' "$H/.cache/overtake/user-icons/index" || fail "the first icon in a folder the scan made wasn't noticed"
  pass "a start scans once, with or without icons there; the folder it made is watched"
else
  echo "skipped: no vipsthumbnail (the first icon)"
fi
