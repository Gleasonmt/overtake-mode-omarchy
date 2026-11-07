#!/bin/bash
# UserIcons.qml in real Quickshell. A name draws from its stripped copy, or nothing,
# and goes to Qt's lookup only once a scan has looked for it in your folders and
# found nothing; a scan that failed answers nothing. (With no icon theme here the
# real lookup answers nothing, for any name, so it's replaced by a recorder:
# "image://icon/<name>" shows what reached it.)
source "$(dirname "$0")/lib.sh"
command -v qs >/dev/null || { echo "skipped: no qs (the real-Quickshell test needs it)"; exit 0; }

recorder() {  # recorder <folder>: UserIcons.qml, its lookup a recorder
  mkdir -p "$1"; cp "$REPO/plugins/overtake.taskbar/UserIcons.qml" "$1/"
  sed -i 's|return Quickshell.iconPath(name, true)|return "image://icon/" + name|' "$1/UserIcons.qml"
  grep -q 'image://icon/' "$1/UserIcons.qml" || fail "(setup) the lookup wasn't replaced"
}
cmp -s "$REPO/plugins/overtake.taskbar/UserIcons.qml" "$REPO/plugins/overtake.notification-center/UserIcons.qml" || fail "the two copies of UserIcons.qml differ"
runqs() {  # runqs <home> <run dir> <seconds> <log>
  env -i HOME="$1" PATH="$E/bin:$PATH" XDG_RUNTIME_DIR="$2" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none timeout "$3" qs -p "$E/cfg/shell.qml" >"$4" 2>&1
}

E=$T/ui; mkdir -p "$E/bin"
recorder "$E/cfg"
# A scan that waits for a sign, then answers; one told to fail, fails.
cat >"$E/bin/overtake" <<'STUB'
#!/bin/bash
[[ $1 == icon-copies ]] || exit 0
echo x >>"$HOME/scans"
[[ -e $HOME/fail ]] && exit 3
until [[ -e $HOME/go ]]; do sleep 0.1; done
d=$HOME/.cache/overtake/user-icons; mkdir -p "$d"
printf 'siteclean\tabc.png\nsitebomb\t\n' >"$d/.i"; mv -f "$d/.i" "$d/index"
STUB
chmod +x "$E/bin/overtake"

# 1. No list yet: nothing is drawn and nothing looked up. The list arrives: copies
# are drawn, a card bound before it looks again, a name with no copy draws nothing,
# a system name is looked up only after a scan has looked for it.
H=$E/home1; R=$E/run1; mkdir -p "$H" "$R"; chmod 700 "$R"
cat >"$E/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  readonly property string bound: icons.source("boundname")   // (as a binding draws it: it has to look again by itself)
  function say(tag) { console.log("UI", tag, "clean=" + icons.source("siteclean"), "bomb=" + icons.source("sitebomb"), "sys=" + icons.source("firefox"), "bound=" + bound, "path=" + icons.source("/tmp/x.png"), "url=" + icons.source("file:///x")) }
  Timer { interval: 500; running: true; onTriggered: say("early") }
  Timer { interval: 3500; running: true; onTriggered: say("listed") }
  Timer { interval: 11000; running: true; onTriggered: say("later") }
}
QML
( sleep 2; touch "$H/go" ) &
runqs "$H" "$R" 13 "$E/log1" || true
out=$(grep -a 'UI ' "$E/log1" || true)
early=$(grep -a 'UI early' <<<"$out"); listed=$(grep -a 'UI listed' <<<"$out"); later=$(grep -a 'UI later' <<<"$out")
[[ -n $early && -n $listed && -n $later ]] || fail "(setup) no answers: $out"
[[ $early == *'clean= bomb= sys= bound= path= url='* ]] || fail "something was drawn or looked up before any list: $early"
[[ $listed == *"clean=file://"*"/overtake/user-icons/abc.png"* ]] || fail "a copied icon isn't drawn from its copy: $listed"
[[ $listed == *'bomb= '* ]] || fail "an icon with no copy was drawn: $listed"
[[ $listed == *'sys= '* ]] || fail "a system name was looked up before a scan had looked for it: $listed"
[[ $later == *'sys=image://icon/firefox '* ]] || fail "a system name wasn't looked up once a scan had looked for it: $later"
[[ $later == *'bound=image://icon/boundname '* ]] || fail "what drew nothing didn't look again once a scan had answered: $later"
[[ $later == *'path= url='* ]] || fail "a path was looked up: $later"
(( $(wc -l <"$H/scans") >= 2 )) || fail "an unknown name ran no scan: $(wc -l <"$H/scans")"
pass "nothing before the list; copies drawn, none for a crafted file; a system name only after a scan; a path never"

# 2. A list from an earlier start is read at once, and a scan that fails answers nothing.
H=$E/home2; R=$E/run2; mkdir -p "$H/.cache/overtake/user-icons" "$R"; chmod 700 "$R"
printf 'old\tabc.png\n' >"$H/.cache/overtake/user-icons/index"; touch "$H/fail"
cat >"$E/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  function say(tag) { console.log("UI", tag, "old=" + icons.source("old"), "sys=" + icons.source("firefox")) }
  Timer { interval: 700; running: true; onTriggered: say("early") }
  Timer { interval: 6000; running: true; onTriggered: say("later") }
}
QML
runqs "$H" "$R" 8 "$E/log2" || true
out=$(grep -a 'UI ' "$E/log2" || true)
early=$(grep -a 'UI early' <<<"$out"); later=$(grep -a 'UI later' <<<"$out")
[[ -n $early && -n $later ]] || fail "(setup) no answers: $out"
[[ $early == *"old=file://"*"/abc.png sys=" ]] || fail "an earlier start's list wasn't read at once, or a name was looked up: $early"
[[ $later == *"sys=" ]] || fail "a scan that failed counted as an answer: $later"
(( $(wc -l <"$H/scans") >= 2 )) || fail "the failed scan wasn't asked again: $(wc -l <"$H/scans")"
pass "an earlier list is used at once; a failed scan answers nothing"

# 3. With the real scan: an icon saved in your folder after the start is drawn from its
# copy once asked for; one that isn't a picture, and one in ~/.icons, are known too.
if command -v vipsthumbnail >/dev/null; then
  H=$E/home3; R=$E/run3; IC=$H/.local/share/icons/hicolor/256x256/apps; mkdir -p "$IC" "$H/.icons/mine/48x48/apps" "$R"; chmod 700 "$R"
  printf '#!/bin/bash\necho x >>"$HOME/scans"\nexec "%s" "$@"\n' "$REPO/bin/overtake" >"$E/bin/overtake"; chmod +x "$E/bin/overtake"
  vipsthumbnail "$REPO/preview.png" --size 32x32 -o "$E/good.png" 2>/dev/null
  cp "$E/good.png" "$H/.icons/mine/48x48/apps/dotdir.png"
  cat >"$E/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  Timer { interval: 500; repeat: true; running: true; onTriggered: console.log("UI", "clean=" + icons.source("firstclean"), "junk=" + icons.source("firstjunk"), "dot=" + icons.source("dotdir")) }
}
QML
  runqs "$H" "$R" 14 "$E/log3" &
  QSP=$!
  sleep 3
  cp "$E/good.png" "$IC/firstclean.png"
  head -c 2000 /dev/urandom >"$IC/firstjunk.png"
  wait "$QSP" 2>/dev/null || true
  grep -a 'UI ' "$E/log3" | grep -a 'image://icon/first\|image://icon/dot' && fail "an icon in your folders reached the lookup"
  last=$(grep -a 'UI ' "$E/log3" | tail -1)
  [[ $last == *"clean=file://"*"/overtake/user-icons/"* ]] || fail "an icon saved after the start got no copy once asked for: $last"
  [[ $last == *'junk= '* ]] || fail "a file that isn't a picture got something: $last"
  [[ $last == *"dot=file://"*"/overtake/user-icons/"* ]] || fail "an icon in ~/.icons got no copy: $last"
  pass "an icon saved after the start is drawn from its copy once asked for; a non-picture draws nothing; ~/.icons is covered"
else
  echo "skipped: no vipsthumbnail (the real scan)"
fi
