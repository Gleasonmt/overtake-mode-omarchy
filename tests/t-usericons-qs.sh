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
  function say(tag) { console.log("UI", tag, icons.ready, "clean=" + icons.source("siteclean"), "bomb=" + icons.source("sitebomb"), "saved=" + icons.source("justsaved"), "sys=" + icons.source("firefox"), "path=" + icons.source("/tmp/x.png")) }
  Timer { interval: 300; running: true; onTriggered: say("early") }
  Timer { interval: 6000; running: true; onTriggered: say("later") }
}
QML
out=$(env -i HOME="$H" PATH="$E/bin:$PATH" XDG_RUNTIME_DIR="$E/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 9 qs -p "$E/cfg/shell.qml" 2>&1 | grep -a 'UI ' || true)
early=$(grep -a 'UI early' <<<"$out") later=$(grep -a 'UI later' <<<"$out")
[[ -n $early && -n $later ]] || fail "(setup) no answers: $out"
[[ $early == *"UI early false"* ]] || fail "a list from before the scan was trusted: $early"
[[ $early == *'sys= '* ]] || fail "an icon was looked up before the list arrived: $early"
[[ $later == *"UI later true"* ]] || fail "the list that arrived after the start was never read: $later"
[[ $later == *"clean=file://"*"/overtake/user-icons/abc.png"* ]] || fail "a copied icon isn't drawn from its copy: $later"
[[ $later == *'bomb= '* ]] || fail "an icon with no copy was looked up: $later"
[[ $later == *'saved= '* ]] || fail "an icon just saved was looked up before it was copied: $later"
[[ $later == *'sys=image://icon/firefox '* ]] || fail "a system icon wasn't looked up: $later"
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
  Timer { interval: 500; repeat: true; running: true; onTriggered: console.log("UI", "clean=" + icons.source("firstclean"), "junk=" + icons.source("firstjunk"), "incoming=" + ("firstclean" in icons.incoming)) }
}
QML
  env -i HOME="$H" PATH="$E2/bin:$PATH" XDG_RUNTIME_DIR="$E2/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 14 qs -p "$E2/cfg/shell.qml" >"$E2/log" 2>&1 &
  QSP=$!
  IC=$H/.local/share/icons/hicolor/256x256/apps
  for _ in {1..40}; do [[ -d $IC && -s $H/.cache/overtake/user-icons/index || -f $H/.cache/overtake/user-icons/index ]] && break; sleep 0.1; done
  [[ -d $IC ]] || fail "the scan didn't make the icon folder"
  sleep 2
  scans_before=$(wc -l <"$H/scans")
  vipsthumbnail "$REPO/preview.png" --size 32x32 -o "$IC/firstclean.png" 2>/dev/null
  head -c 2000 /dev/urandom >"$IC/firstjunk.png"
  sleep 1; seen=$(grep -ac 'UI ' "$E2/log")   # (before it's saved, a name is just a name)
  wait "$QSP" 2>/dev/null || true
  scans_after=$(wc -l <"$H/scans")
  grep -a 'UI ' "$E2/log" | tail -n +"$((seen + 1))" | grep -a 'image://icon/first' && fail "the first icon saved after the start reached the lookup"
  last=$(grep -a 'UI ' "$E2/log" | tail -1)
  [[ $last == *"clean=file://"*"/overtake/user-icons/"* ]] || fail "the first icon saved after the start got no copy: $last"
  [[ $last == *'junk= '* ]] || fail "a file that isn't a picture got something: $last"
  (( scans_before == 1 )) || fail "a start ran $scans_before scans with nothing saved"
  (( scans_after > scans_before )) || fail "saving an icon ran no scan"
  pass "the first icon, in a folder that didn't exist at the start, is known at once and drawn from its copy; a start scans once"
  # Icons already there: the first listing is of what the scan just copied, so no second scan.
  H=$E2/home2; IC=$H/.local/share/icons/hicolor/256x256/apps; mkdir -p "$IC" "$E2/run2"; chmod 700 "$E2/run2"
  vipsthumbnail "$REPO/preview.png" --size 32x32 -o "$IC/already.png" 2>/dev/null
  env -i HOME="$H" PATH="$E2/bin:$PATH" XDG_RUNTIME_DIR="$E2/run2" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 6 qs -p "$E2/cfg/shell.qml" >"$E2/log2" 2>&1 || true
  [[ $(wc -l <"$H/scans") == 1 ]] || fail "a start with an icon already there ran $(wc -l <"$H/scans") scans"
  pass "a start with icons already there scans once"
else
  echo "skipped: no vipsthumbnail (the first icon)"
fi
