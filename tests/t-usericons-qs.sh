#!/bin/bash
# UserIcons.qml in real Quickshell: the list of copies doesn't exist when a plugin
# starts, and a file that isn't there can't be watched. Icons have to appear anyway.
source "$(dirname "$0")/lib.sh"
command -v qs >/dev/null || { echo "skipped: no qs (the real-Quickshell test needs it)"; exit 0; }

E=$T/ui; H=$E/home; mkdir -p "$E/cfg" "$E/bin" "$E/run" "$H/.local/share/icons/hicolor/256x256/apps"; chmod 700 "$E/run"
cp "$REPO/plugins/overtake.taskbar/UserIcons.qml" "$E/cfg/"
# (the real scan takes a moment: the list arrives a second after the plugin starts)
cat >"$E/bin/overtake" <<'STUB'
#!/bin/bash
[[ $1 == icon-copies ]] || exit 0
sleep 1
d=$HOME/.cache/overtake/user-icons; mkdir -p "$d"
printf 'siteclean\tabc.png\nsitebomb\t\n' >"$d/.i"; mv -f "$d/.i" "$d/index"
STUB
chmod +x "$E/bin/overtake"
: >"$H/.local/share/icons/hicolor/256x256/apps/justsaved.png"
cat >"$E/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  function say(tag) { console.log("UI", tag, icons.ready, "clean=" + icons.source("siteclean"), "bomb=" + icons.source("sitebomb"), "saved=" + icons.source("justsaved"), "path=" + icons.source("/tmp/x.png")) }
  Timer { interval: 300; running: true; onTriggered: say("early") }
  Timer { interval: 6000; running: true; onTriggered: say("later") }
}
QML
out=$(env -i HOME="$H" PATH="$E/bin:$PATH" XDG_RUNTIME_DIR="$E/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout 9 qs -p "$E/cfg/shell.qml" 2>&1 | grep -a ' UI ' || true)   # (killed by the timeout: it doesn't quit)
early=$(grep -a 'UI early' <<<"$out") later=$(grep -a 'UI later' <<<"$out")
[[ -n $early && -n $later ]] || fail "(setup) no answers: $out"
[[ $early == *"UI early false"* ]] || fail "(setup) the list was there too soon: $early"
[[ $early == *'clean= '* ]] || fail "an icon was looked up before the list arrived: $early"
[[ $later == *"UI later true"* ]] || fail "the list that arrived after the start was never read: $later"
[[ $later == *"clean=file://"*"/overtake/user-icons/abc.png"* ]] || fail "a copied icon isn't drawn from its copy: $later"
[[ $later == *'bomb= '* ]] || fail "an icon with no copy was looked up: $later"
[[ $later == *'saved= '* ]] || fail "an icon just saved was looked up before it was copied: $later"
[[ $later == *'path=' && $later != *'path=/'* ]] || fail "a path was looked up: $later"
pass "icons appear when the list arrives after the plugin starts; with no copy, or just saved, none is looked up"
