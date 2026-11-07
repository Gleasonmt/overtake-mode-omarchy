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
  sed -i 's|return Quickshell.iconPath(name, true)|return "image://icon/" + name|; s|interval: 120000 + Math.random() \* 30000|interval: 4000|; s|> 90000|> 2500|; s|< 90000|< 2500|' "$1/UserIcons.qml"
  grep -q 'image://icon/' "$1/UserIcons.qml" || fail "(setup) the lookup wasn't replaced"
  [[ $(grep -o 'interval: 4000\|[<>] 2500' "$1/UserIcons.qml" | wc -l) == 3 ]] || fail "(setup) the two-minute scan wasn't made a four-second one"
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
{ printf 'siteclean\tabc.png\nsitebomb\t\n'; [[ -e $HOME/second ]] && printf 'latecomer\tabc.png\n'; } >"$d/.i"; mv -f "$d/.i" "$d/index"
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
  function say(tag) { console.log("UI", tag, "clean=" + icons.source("siteclean"), "bomb=" + icons.source("sitebomb"), "sys=" + icons.source("firefox"), "bound=" + bound, "prefix=" + icons.source("siteclean-x"), "late=" + icons.source("latecomer"), "path=" + icons.source("/tmp/x.png"), "url=" + icons.source("file:///x")) }
  Timer { interval: 500; running: true; onTriggered: say("early") }
  Timer { interval: 2700; running: true; onTriggered: say("listed") }   // (the list is in; the scan for the asked names isn't, 3 s after the first)
  Timer { interval: 7000; running: true; onTriggered: say("later") }
  Timer { interval: 12500; running: true; onTriggered: say("changed") }   // (latecomer's file landed after a scan had answered for it, and no new name asks: the periodic scan lists it)
}
QML
( sleep 2; touch "$H/go"; sleep 5.5; touch "$H/second" ) &
runqs "$H" "$R" 14 "$E/log1" || true
out=$(grep -a 'UI ' "$E/log1" || true)
early=$(grep -a 'UI early' <<<"$out"); listed=$(grep -a 'UI listed' <<<"$out"); later=$(grep -a 'UI later' <<<"$out")
[[ -n $early && -n $listed && -n $later ]] || fail "(setup) no answers: $out"
[[ $early == *'clean= bomb= sys= bound= prefix= late= path= url='* ]] || fail "something was drawn or looked up before any list: $early"
[[ $listed == *"clean=file://"*"/overtake/user-icons/abc.png"* ]] || fail "a copied icon isn't drawn from its copy: $listed"
[[ $listed == *'bomb= '* ]] || fail "an icon with no copy was drawn: $listed"
[[ $listed == *'sys= '* ]] || fail "a system name was looked up before a scan had looked for it: $listed"
[[ $later == *'sys=image://icon/firefox '* ]] || fail "a system name wasn't looked up once a scan had looked for it: $later"
[[ $later == *'bound=image://icon/boundname '* ]] || fail "what drew nothing didn't look again once a scan had answered: $later"
[[ $later == *'path= url='* ]] || fail "a path was looked up: $later"
[[ $early == *'prefix= '* && $listed == *'prefix= '* && $later == *'prefix= '* ]] || fail "a name whose prefix is in your folder drew something: $later"
[[ $later == *'late=image://icon/latecomer '* ]] || fail "(setup) a name not in your folder wasn't looked up after a scan: $later"
changed=$(grep -a 'UI changed' <<<"$out")
[[ $changed == *"late=file://"*"/abc.png "* ]] || fail "an icon saved under a name already answered wasn't drawn from its copy after the periodic scan: $changed"
(( $(wc -l <"$H/scans") >= 3 )) || fail "unknown names ran too few scans: $(wc -l <"$H/scans")"
pass "nothing before the list; copies drawn, none for a crafted file or a listed prefix; a system name only after a scan; an icon saved under an answered name copied by the periodic scan; a path never"

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
  H=$E/home3; R=$E/run3; IC=$H/.local/share/icons/hicolor/256x256/apps; mkdir -p "$IC" "$H/.icons/hicolor/48x48/apps" "$R"; chmod 700 "$R"
  printf '#!/bin/bash\necho x >>"$HOME/scans"\nexec "%s" "$@"\n' "$REPO/bin/overtake" >"$E/bin/overtake"; chmod +x "$E/bin/overtake"
  vipsthumbnail "$REPO/preview.png" --size 32x32 -o "$E/good.png" 2>/dev/null
  cp "$E/good.png" "$H/.icons/hicolor/48x48/apps/dotdir.png"
  cat >"$E/cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  UserIcons { id: icons }
  // (asked only once they're saved: a name a scan has answered before the file landed is looked up until the next start)
  Timer { interval: 4000; running: true; onTriggered: asks.running = true }
  Timer { id: asks; interval: 500; repeat: true; onTriggered: console.log("UI", "clean=" + icons.source("firstclean"), "junk=" + icons.source("firstjunk"), "dot=" + icons.source("dotdir")) }
}
QML
  runqs "$H" "$R" 14 "$E/log3" &
  QSP=$!
  sleep 2.5
  cp "$E/good.png" "$IC/firstclean.png"
  head -c 2000 /dev/urandom >"$IC/firstjunk.png"
  wait "$QSP" 2>/dev/null || true
  grep -a 'UI ' "$E/log3" | grep -a 'image://icon/first\|image://icon/dot' && fail "an icon in your folders reached the lookup"
  last=$(grep -a 'UI ' "$E/log3" | tail -1)
  [[ $last == *"clean=file://"*"/overtake/user-icons/"* ]] || fail "an icon saved after the start got no copy once asked for: $last"
  [[ $last == *'junk= '* ]] || fail "a file that isn't a picture got something: $last"
  [[ $last == *"dot=file://"*"/overtake/user-icons/"* ]] || fail "an icon in ~/.icons got no copy: $last"
  pass "an icon saved after the start is drawn from its copy once asked for; a non-picture draws nothing; ~/.icons/hicolor is covered"
else
  echo "skipped: no vipsthumbnail (the real scan)"
fi
