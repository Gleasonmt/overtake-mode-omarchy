#!/bin/bash
# The patched notifications copy in real Quickshell: offscreen, on a private
# session bus, with a scratch home and a stand-in wl-copy that logs what it gets,
# and a real full disk (a small tmpfs in a private mount namespace). Nothing
# here reaches the live desktop. Skipped where Quickshell isn't installed (CI).
#   Covers: a copied code stays out of argv; Clear all on a full disk stays
#   cleared after a restart; a silenced copy filed just before Clear all, and a
#   card still on screen at Clear all, leave nothing behind. (The cards' windows
#   are taken out, so the driver closes a card the way its timeout does.)
#
#   A second build keeps the real cards and the real center, in an ordinary
#   window on Qt's VNC platform (no network here: its own network namespace).
#   That platform is used because, unlike offscreen, it opens links the real way
#   (with no portal on this bus, through xdg-open). It covers what a click opens and
#   copies, senders' pictures, and what the center says. Clicks are made by
#   calling the handlers, with no synthetic input.
source "$(dirname "$0")/lib.sh"
for tool in qs dbus-run-session notify-send unshare; do
  command -v "$tool" >/dev/null || { echo "skipped: no $tool (the real-Quickshell test needs it)"; exit 0; }
done
unshare -r -m -n true 2>/dev/null || { echo "skipped: no user namespaces here"; exit 0; }

[[ -n ${OVERTAKE_TEST_KEEP:-} ]] && { trap - EXIT; echo "kept: $T"; }   # (to read the logs after a failure)
E=$T/e2e; mkdir -p "$E/root" "$E/rootw" "$E/bin" "$E/run"; chmod 700 "$E/run"
SHELL_SRC=$(dirname "$OMARCHY_SRC")
cp -a "$SHELL_SRC/Commons" "$SHELL_SRC/services" "$SHELL_SRC/Ui" "$E/root/"
cp -a "$OMARCHY_SRC/notifications" "$E/root/ov"
python3 -I "$REPO/patches/apply.py" notifications "$E/root/ov" || fail "the notifications patch doesn't apply"
cp -a "$E/root/." "$E/rootw/"
# No layer-shell offscreen: take out the toast windows, keep everything else.
python3 -I - "$E/root/ov/Service.qml" <<'PY' || fail "couldn't strip the toast windows"
import sys
p = sys.argv[1]; t = open(p).read()
s = t.index("  Variants {\n    id: surfaceVariants")
d = 0; i = t.index("{", s)
while True:
    if t[i] == "{": d += 1
    elif t[i] == "}":
        d -= 1
        if d == 0: break
    i += 1
t = t[:s] + t[i + 1:]
assert t.count("surfaceVariants.instances") == 1
t = t.replace("surfaceVariants.instances", "[]")
# what the driver needs from outside
t = t.replace("  property var leaving: ({})", "  property var leaving: ({})\n  readonly property var testToasts: toasts\n  property var testCards: ({})", 1)
open(p, "w").write(t)
PY
# The second build: the real cards in an ordinary window (no layer shell here),
# and the real center with its layer-shell popup swapped for a plain item.
python3 -I - "$E/rootw/ov/Service.qml" "$E/rootw/ov/Toast.qml" <<'PY' || fail "couldn't set up the windowed build"
import re, sys
p, q = sys.argv[1:3]; t = open(p).read()
def must(s, new):
    global t
    assert s in t, s
    t = t.replace(s, new, 1)
must("    PanelWindow {\n      id: surface", "    FloatingWindow {\n      id: surface")
t = re.sub(r"^\s*WlrLayershell\.[^\n]*\n", "", t, flags=re.M)
must("      exclusionMode: ExclusionMode.Ignore\n", "")
must("      anchors { top: true; bottom: true; right: true }\n", "      implicitHeight: 800\n")
must("      mask: Region { item: surface.showingNotifications ? deck : null }\n", "")
must("  property var leaving: ({})", "  property var leaving: ({})\n  readonly property var testToasts: toasts\n  property var testCards: ({})")
open(p, "w").write(t)
t = open(q).read()
must("  id: card\n", """  id: card
  Component.onCompleted: if (scene) scene.testCards[String(row.key)] = card
  // The link under the start of the body, as Qt reads it from the rendered text.
  function testClickLink() {
    var url = bodyBox.linkAt(2, 5)
    if (url) bodyBox.linkActivated(url)
    return !!url
  }
  function testPicture() { return thumb.best + " status=" + picture.status }
  function testSources() { return thumb.sources.join(",") }
""")
open(q, "w").write(t)
PY
mkdir -p "$E/rootw/np"
cp "$REPO/plugins/overtake.notification-center/"*.qml "$E/rootw/np/"
sed -i 's/^  KeyboardPanel {/  TestPanelBox {/' "$E/rootw/np/Panel.qml"
grep -q 'TestPanelBox {' "$E/rootw/np/Panel.qml" || fail "(setup) the center's popup wasn't swapped"
cat > "$E/rootw/np/TestPanelBox.qml" <<'QML'
import QtQuick
Item {
  property var anchorItem; property var owner; property var bar; property bool open
  property var focusTarget; property real contentWidth; property real contentHeight
  function fittedContentWidth(w) { return w }
  function fittedContentHeight(h) { return h }
}
QML
cat > "$E/rootw/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ov" as Ov
import "np" as Np
ShellRoot {
  Ov.Service { id: svc }
  // The longest the GUI thread went without running this, since the last read.
  property real lastBeat: Date.now()
  property real worstGap: 0
  Timer { interval: 50; running: true; repeat: true; onTriggered: { var now = Date.now(); worstGap = Math.max(worstGap, now - lastBeat); lastBeat = now } }
  Np.Panel { id: panel }
  // What omarchy-shell would do: the stand-in in the test's PATH asks here.
  FileView {
    path: Quickshell.env("HOME") + "/ctl-ipc"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var p = text().trim().split(" ")
      if (p.length < 2) return
      var res = IpcRegistry.call("notifications", p[1], p.slice(2))
      reply.setText(p[0] + " " + (res.ran ? res.output : "(no such call)") + "\n")
    }
  }
  FileView { id: reply; path: Quickshell.env("HOME") + "/ctl-reply"; printErrors: false }
  FileView {
    path: Quickshell.env("HOME") + "/ctl"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var c = text().trim().split(" ")[0], r = ""
      var first = svc.testToasts.count ? svc.testToasts.get(0) : null
      function firstReal() {
        for (var i = 0; i < svc.testToasts.count; i++)
          if (String(svc.testToasts.get(i).key).indexOf("placeholder") !== 0) return svc.testToasts.get(i)
        return null
      }
      if (c === "dnd") svc.setDoNotDisturb(true)
      else if (c === "count") r = "toasts=" + svc.testToasts.count
      else if (c === "summaries") {
        var s = []
        for (var i = 0; i < svc.testToasts.count; i++) s.push(svc.testToasts.get(i).summary)
        r = s.join("|")
      }
      else if (c === "clicklink") { var a = firstReal(); r = a && svc.testCards[a.key] && svc.testCards[a.key].testClickLink() ? "clicked" : "nolink" }
      else if (c === "clickcode") { var k = firstReal(); if (k) svc.copyCode(String(k.codes).split(" ")[0], k.key); r = k ? "clicked" : "none" }
      else if (c === "clickcard") { var b = firstReal(); if (b) svc.activate(b.key); r = b ? "clicked" : "none" }
      else if (c === "gap") { r = "gap=" + Math.round(worstGap); worstGap = 0 }
      else if (c === "pictures") {
        var n = 0, w = 0
        for (var j = 0; j < svc.testToasts.count; j++) {
          if (String(svc.testToasts.get(j).image) !== "") n++
          if (svc.refs[svc.testToasts.get(j).key]) w++
        }
        r = "cards=" + svc.testToasts.count + " pictures=" + n + " senders=" + w
      }
      else if (c === "picture") { var d = firstReal(); r = d && svc.testCards[d.key] ? svc.testCards[d.key].testPicture() : "none" }
      else if (c === "sources") { var e = firstReal(); r = e && svc.testCards[e.key] ? svc.testCards[e.key].testSources() : "none" }
      else if (c === "closeall") svc.clearAll("dismissed", true)
      else if (c === "forgetall") r = IpcRegistry.call("notifications", "forgetAll", []).output
      else if (c === "paneldnd") panel.toggleDnd()
      else if (c === "panelclear") panel.clearAll()
      else if (c === "panelreload") panel.reload()
      else if (c === "panelcan") r = "canClear=" + panel.canClear + " shown=" + panel.entries.length
      else if (c === "panelnotice") r = panel.notice
      console.log("CTL " + c + " -> " + JSON.stringify(r))
    }
  }
}
QML
# A third build for the card's icon by name: with no theme here every lookup answers
# nothing, so the copy's UserIcons gets a recorder in place of it.
cp -a "$E/rootw/." "$E/rooti/"
for f in "$E/rooti/ov/UserIcons.qml" "$E/rooti/np/UserIcons.qml"; do
  sed -i 's|return Quickshell.iconPath(name, true)|return "image://icon/" + name|' "$f"
  grep -q 'image://icon/' "$f" || fail "(setup) the recorder wasn't put into $f"
done
cat > "$E/root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ov" as Ov
ShellRoot {
  Ov.Service { id: svc }
  // The longest the GUI thread went without running this, since the last read.
  property real lastBeat: Date.now()
  property real worstGap: 0
  Timer { interval: 50; running: true; repeat: true; onTriggered: { var now = Date.now(); worstGap = Math.max(worstGap, now - lastBeat); lastBeat = now } }
  FileView {
    path: Quickshell.env("HOME") + "/ctl"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var c = text().trim().split(" ")[0], r = ""
      if (c === "dnd") svc.setDoNotDisturb(true)
      else if (c === "forgetall") r = IpcRegistry.call("notifications", "forgetAll", []).output
      else if (c === "closecard") {
        var card = svc.testToasts.get(0)     // what a card's timeout comes to
        r = card ? String(card.key) : "none"
        if (card) svc.finishClose(card.key, "expired")
      }
      else if (c === "age") {      // every history row a day and more older
        svc.historyEntries = svc.historyEntries.map(function(e) { var o = Object.assign({}, e); o.closed_ts = o.closed_ts - 90000; return o })
        svc.currentHistory()
      }
      else if (c === "reloadlive") svc.overtakeLiveInPlace.reload()   // (its load order at start varies)
      else if (c === "count") r = "toasts=" + svc.testToasts.count
      else if (c === "forgetfirst") {   // the row closed last
        var hist = svc.historyEntries
        r = hist.length ? IpcRegistry.call("notifications", "forget", [String(hist[0].key)]).output : "empty"
      }
      else if (c === "quit") Qt.quit()   // (a clean exit runs the service's last write; SIGTERM doesn't: measured)
      else if (c === "racelive") {  // Clear all, and a card saved in the same tick
        var was = svc.liveEntries[0]
        IpcRegistry.call("notifications", "forgetAll", [])
        svc.liveEntries = [Object.assign({}, was, { key: "nrace" })]
        svc.saveSoon("live"); svc.flushStore()
      }
      else if (c === "forgetoldest") {
        var all = svc.historyEntries
        r = IpcRegistry.call("notifications", "forget", [String(all[all.length - 1].key)]).output
      }
      else if (c === "copycode") {
        var row = svc.testToasts.get(0)
        r = "codes=" + row.codes
        svc.copyCode(String(row.codes).split(" ")[0], row.key)
      }
      console.log("CTL " + c + " -> " + JSON.stringify(r))
    }
  }
}
QML
for tool in wl-copy wl-paste; do
  cat > "$E/bin/$tool" <<STUB
#!/bin/bash
printf '%s\n' "$tool \$*" >> "$E/clip-argv"
[[ $tool == wl-copy && \$* != *--clear* ]] && cat >> "$E/clip-stdin"
exit 0
STUB
  chmod +x "$E/bin/$tool"
done
# What a click may start: logged, never real. wl-copy fails when asked to.
cat > "$E/bin/wl-copy" <<STUB
#!/bin/bash
printf '%s\n' "wl-copy \$*" >> "$E/clip-argv"
[[ \$* == *--clear* ]] && exit 0
cat >> "$E/clip-stdin"; echo >> "$E/clip-stdin"
[[ ! -e "\$HOME/clip-slow" ]] || sleep 3
[[ ! -e "\$HOME/clip-fails" ]]
STUB
for tool in xdg-open omarchy-hyprland-focus-app; do
  printf '#!/bin/bash\nprintf "%%s\\n" "%s $*" >> "%s/clip-argv"\n' "$tool" "$E" > "$E/bin/$tool"
done
# omarchy-shell, asked of the test's shell over two files.
# (the app's name comes on stdin)
printf '#!/bin/bash\nprintf "%%s\\n" "overtake $*" >> "%s/clip-argv"\n[[ $1 == notification-open ]] && cat >> "%s/focus-stdin"\nexit 0\n' "$E" "$E" > "$E/bin/overtake"
# (the scan: a list at once, so names are drawn; the card-icon scenario's waits for a sign and lists two)
cat >> "$E/bin/overtake" <<'STUB'
if [[ $1 == icon-copies ]]; then
  d=$HOME/.cache/overtake/user-icons; mkdir -p "$d"
  if [[ -e $HOME/cardicon ]]; then
    until [[ -e $HOME/go ]]; do sleep 0.1; done
    printf 'siteok\tabc.png\nsitebad\t\n' >"$d/.i"; mv -f "$d/.i" "$d/index"
  else
    [[ -e $d/index ]] || : >"$d/index"
  fi
fi
STUB
sed -i 's/^exit 0$//' "$E/bin/overtake"; echo 'exit 0' >> "$E/bin/overtake"
chmod +x "$E/bin/overtake"
cat > "$E/bin/omarchy-shell" <<'STUB'
#!/bin/bash
[[ ${1:-} == notifications ]] || exit 0
shift
id=$$$RANDOM
echo "$id $*" > "$HOME/ctl-ipc"
for _ in {1..100}; do
  if read -r got out < "$HOME/ctl-reply" 2>/dev/null && [[ $got == "$id" ]]; then echo "$out"; exit 0; fi
  sleep 0.05
done
exit 1
STUB
chmod +x "$E/bin/"*
# A private bus that can start nothing: no real portal, or anything else.
cat > "$E/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><keep_umask/><listen>unix:abstract=overtake-test-bus</listen>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
<limit name="max_message_size">1000000000</limit><limit name="max_incoming_bytes">4000000000</limit><limit name="max_outgoing_bytes">4000000000</limit>
</busconfig>
CONF

cat > "$E/driver.sh" <<'DRV'
#!/bin/bash
# Inside unshare -r -m -n and dbus-run-session: argument 2 is the scenario.
E=$1; SCEN=$2; REPO=$3
export HOME=$E/home-$SCEN QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none PATH=$E/bin:$PATH XDG_RUNTIME_DIR=$E/run
export XDG_CACHE_HOME=$HOME/.cache XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state XDG_DATA_HOME=$HOME/.local/share
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DISPLAY
ulimit -c 1   # (no core file for the system's crash handler, whatever happens)
umask 022     # (the usual one, so anything that isn't made private shows)
N=$HOME/.local/state/omarchy/notifications; H=$N/history.json
mkdir -p "$N" "$HOME/.local/state/overtake" "$HOME/.config/overtake"; echo on > "$HOME/.local/state/overtake/mode"; : > "$HOME/ctl"; : > "$HOME/ctl-ipc"; : > "$HOME/ctl-reply"
ROOT=root; WAITS=4
case $SCEN in
  full*|stop|stale|aged|removed|closedfull|nearfull|dndsave|rohome) mount -t tmpfs -o size=256k tmpfs "$N";;
esac
case $SCEN in
  link*|focus|pathimage|rawclaim|flood*|stall|huge*|entry*|textargv|linkrace|codefail|dndrules|dndsave|rohome|onlyhidden|appmodes|critical|emptylist)
    ROOT=rootw; WAITS=5
    export QT_QPA_PLATFORM=vnc QT_QUICK_BACKEND=software;;
  cardicon)
    ROOT=rooti; WAITS=5; touch "$HOME/cardicon"
    export QT_QPA_PLATFORM=vnc QT_QUICK_BACKEND=software;;
esac
ctl() { echo "$1 $(date +%s%N)" > "$HOME/ctl"; sleep "${2:-0.5}"; }
start() { ( [[ -n ${FILELIMIT:-} ]] && { trap '' XFSZ; ulimit -f "$FILELIMIT"; }; exec qs -p "$E/$ROOT/shell.qml" ) >>"$E/qs-$SCEN.log" 2>&1 & QS=$!; sleep "$WAITS"; }
stop() { kill -TERM "$QS"; wait "$QS" 2>/dev/null; }
reply() { sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a "^CTL $1 " | tail -1 | sed 's/^[^>]*> //'; }
# Until that many cards are up and their pictures have settled (cards go on arriving after the sender returns).
allcards() { local last=""; for _ in {1..12}; do ctl pictures 0.5; [[ $(reply pictures) == *"cards=$1 "* && $(reply pictures) == "$last" ]] && return; last=$(reply pictures); done; }
rss() { awk '/VmRSS/ { print int($2 / 1024) }' "/proc/$QS/status"; }
peak() { awk '/VmHWM/ { print int($2 / 1024) }' "/proc/$QS/status"; }
send() { python3 -I "$REPO/tests/t-notifications-send.py" "$@" >/dev/null; }
modes() { stat -c '%a %n' "$N" "$N"/* 2>/dev/null | sed "s#$N#N#" | tr '\n' ' '; }
# Every 10 ms: any mode in the folder that isn't private.
watch_modes() { while :; do stat -c '%a %n' "$N" "$N"/* 2>/dev/null | grep -vE '^(700|600) ' >> "$E/badmodes-$SCEN"; sleep 0.01; done & WATCH=$!; }
unwatch() { kill "$WATCH" 2>/dev/null; wait "$WATCH" 2>/dev/null; }
# Every 20 ms: any running program with the marker in its arguments. (The
# pattern doesn't match itself. Senders here read the marker from a file.)
# (only this run's programs: another run on the machine has the same marker)
watch_argv() { while :; do for f in $(grep -lsa 'URLMARKE[R]77' /proc/[0-9]*/cmdline); do grep -qsa "HOME=$HOME" "${f%cmdline}environ" && echo "$f" >> "$E/argv-hits-$SCEN"; done; sleep 0.02; done & WATCH=$!; }
secrets() { grep -o 'SECRET-[0-9]' "$H" 2>/dev/null | sort -u | tr '\n' ' '; }
live() { grep -o 'SECRET-[0-9]' "$N/live.json" 2>/dev/null | sort -u | tr '\n' ' '; }
pad() { head -c 2000 /dev/zero | tr '\0' x; }
fill() { dd if=/dev/zero of="$N/filler" bs=4k 2>/dev/null; sync; }
[[ $SCEN == oldlive ]] && printf '[{"key":"nold","app":"Signal","summary":"Old","body":"SECRET-1","urgency":1,"ts":%s}]\n' "$(( $(date +%s) - 432000 ))" > "$N/live.json"
[[ $SCEN == onlyhidden ]] && printf '[{"key":"nhid","app":"omarchy-action","summary":"Done","body":"SECRET-1","urgency":1,"ts":%s,"closed_ts":%s,"closed_reason":"expired"}]\n' "$(date +%s)" "$(date +%s)" > "$H"
[[ $SCEN == rohome ]] && { : > "$H"; : > "$N/live.json"; : > "$N/quiet.json"; mount --bind "$N" "$N"; mount -o remount,ro,bind "$N" || echo "reply=[(setup) not read-only]"; }
[[ $SCEN == refused ]] || start
case $SCEN in
  appmodes)   # the center's per-app settings, as the service reads them
    printf '{"apps":{"OffApp":"off","QuietApp":"quiet"}}\n' > "$HOME/.config/overtake/notifications.json"
    sleep 1
    notify-send -a OffApp "Off" "SECRET-1 $(pad)"
    notify-send -a QuietApp "Quiet" "SECRET-2 $(pad)"
    notify-send -a ShowApp "Show" "SECRET-3 $(pad)"
    sleep 1.5
    ctl summaries 0.5
    echo "shown=[$(reply summaries)]"
    echo "history=[$(secrets)]"
    echo "live=[$(live)]"
    ;;
  critical)   # a critical card leaves after 15 s, and so does one restored after a restart
    notify-send -a Alarm -u critical "One" "SECRET-1"; sleep 5
    ctl summaries 0.2; echo "at5=[$(reply summaries)]"
    sleep 12
    ctl summaries 0.2; echo "at17=[$(reply summaries)]"
    echo "filed=[$(secrets)]"
    notify-send -a Alarm -u critical "Two" "SECRET-2"; sleep 1.5
    stop; start          # (5 s of it passes here)
    ctl summaries 0.2; echo "back=[$(reply summaries)]"
    sleep 13
    ctl summaries 0.2; echo "backgone=[$(reply summaries)]"
    ;;
  link)    # a link in the text, clicked; then a card with one, clicked
    printf '%s' 'https://example.com/reset?token=URLMARKER77&u=me' > "$HOME/body"
    watch_argv
    send --app Mail --summary "Reset" --body-file "$HOME/body"; sleep 1.5
    ctl clicklink 1.5
    echo "toast=[$(reply clicklink)]"
    ctl summaries 0.5
    echo "said=[$(reply summaries)]"
    ctl clickcard 1.5
    echo "card=[$(reply clickcard)]"
    unwatch
    ;;
  linkfail)   # the copy fails: the card says so
    printf '%s' 'https://example.com/reset?token=URLMARKER77' > "$HOME/body"
    touch "$HOME/clip-fails"
    send --app Mail --summary "Reset" --body-file "$HOME/body"; sleep 1.5
    ctl clicklink 1.5
    ctl summaries 0.5
    echo "said=[$(reply summaries)]"
    ;;
  linkmail)   # an email address: copied, nothing opened
    printf '%s' '<a href="mailto:a.person@example.com">write</a>' > "$HOME/body"
    send --app Mail --summary "Contact" --body-file "$HOME/body"; sleep 1.5
    ctl clicklink 1.5
    ctl summaries 0.5
    echo "said=[$(reply summaries)]"
    ;;
  focus)   # a sender's name reaches the focus command as literal text
    notify-send -a '.*(Evil' "Hello" "no link here"; sleep 1.5
    ctl clickcard 1.5
    ;;
  pathimage)   # a picture named by path: the file is never even opened
    mkfifo "$HOME/pic.png" "$HOME/pic2.png"
    send --app Mail --summary "Path" --image-path "$HOME/pic.png"; sleep 0.5
    timeout 3 bash -c 'exec 3>"$1"' _ "$HOME/pic.png"; echo "opened=[$?]"
    send --app Mail --summary "Url" --image-path "file://$HOME/pic2.png"; sleep 0.5
    timeout 3 bash -c 'exec 3>"$1"' _ "$HOME/pic2.png"; echo "opened2=[$?]"
    ctl picture 0.5
    echo "picture=[$(reply picture)]"
    ctl count 0.5
    echo "count=[$(reply count)]"
    ;;
  rawclaim)    # image-data claiming more pixels than it sends: stock Omarchy's shell dies on this
    send --app Chat --summary "Claims" --image-data 2000x2000 --lie-size 16; sleep 2
    kill -0 "$QS" 2>/dev/null && echo "alive=[yes]" || echo "alive=[no]"
    ctl picture 0.5
    echo "picture=[$(reply picture)]"
    ctl summaries 0.5
    echo "shown=[$(reply summaries)]"
    ;;
  stall)   # text a sender chooses, in the worst shapes for the copy's patterns
    for shape in '<' '<a ' '&lt;' '<a href="x">'; do
      python3 -I -c 'import sys; s=sys.argv[1]; sys.stdout.write((s*(32768//len(s)+1))[:32768])' "$shape" > "$HOME/body"
      ctl gap 1
      send --app Evil --summary "Stall" --body-file "$HOME/body"; sleep 2.5
      ctl gap 0.5
      echo "gap=[$(reply gap | sed 's/[^0-9]//g')]"
    done
    ;;
  hugetext)   # what a sender passes beyond a picture: let go past the limits
    head -c 30000000 /dev/zero | tr '\0' x > "$HOME/body"
    base=$(rss)
    send --app Evil --summary "Big" --body-file "$HOME/body" --count 10
    allcards 10
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  hugehint)
    base=$(rss)
    send --app Evil --summary "Big" --hint-size 30000000 --count 10
    allcards 10
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  hugeapp|hugeicon|hugeactext|hugelist|hugevar|hugestruct)   # every field a sender's object keeps counts
    base=$(rss)
    case $SCEN in
      hugeapp) send --summary Big --app-size 20000000 --count 8 ;;
      hugeicon) send --app Evil --summary Big --icon-size 20000000 --count 8 ;;
      hugeactext) send --app Evil --summary Big --actions 2 --action-text-size 10000000 --count 8 ;;
      hugelist) send --app Evil --summary Big --list-hint 4x5000000 --count 8 ;;
      hugevar) send --app Evil --summary Big --var-hint 20000000 --count 8 ;;
      # (three: at about five, reading hints this big stalls Quickshell itself, with or
      # without this copy; see Known limits)
      hugestruct) send --app Evil --summary Big --struct-hint 20000000 --count 3 ;;
    esac
    [[ $SCEN == hugestruct ]] && allcards 3 || allcards 8
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  emptylist)   # an empty list isn't a hint of unknown size
    send --app Evil --summary Fine --actions 1 --empty-list-hint
    allcards 1
    echo "pictures=[$(reply pictures)]"
    ;;
  cardicon)   # the icon a card draws, by name: nothing before a scan has listed your folders
    notify-send -a benign -i siteok Early Early
    sleep 1; ctl sources; echo "before=[$(reply sources)]"
    touch "$HOME/go"
    sleep 2; ctl sources; echo "arrived=[$(reply sources)]"
    for name in siteok sitebad sysicon /etc/passwd; do
      ctl closeall 1
      notify-send -a benign -i "$name" Card Card
      sleep 1; ctl sources; echo "${name##*/}=[$(reply sources)]"
    done
    sleep 5; ctl closeall 1   # (by now a scan has looked for sysicon and not found it)
    notify-send -a benign -i sysicon Card Card
    sleep 1; ctl sources; echo "sysiconlater=[$(reply sources)]"
    ;;
  entrybomb|entryfifo)   # an app whose Icon= names a file, and a sender naming that app
    mkdir -p "$HOME/.local/share/applications"
    python3 -I - "$HOME/bomb.png" <<'PNG'
import struct, sys, zlib
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
rows = (b"\0" + b"\x80\x80\x80" * 32) * 32
one = chunk(b"zTXt", b"k\0\0" + zlib.compress(b"A" * 7000000, 9))   # (real text: Qt keeps it; NUL bytes it doesn't)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 32, 32, 8, 2, 0, 0, 0)) + one * 120 + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
PNG
    mkfifo "$HOME/fifo"
    file=$HOME/bomb.png; [[ $SCEN == entryfifo ]] && file=$HOME/fifo
    printf '[Desktop Entry]\nType=Application\nName=evilapp\nExec=true\nIcon=%s\n' "$file" > "$HOME/.local/share/applications/evilapp.desktop"
    sleep 2   # (the shell reads the new entry)
    base=$(peak)
    notify-send -a evilapp "Hello" "hi"
    sleep 4
    ctl count 1
    echo "count=[$(reply count)]"
    echo "picture=[$(grep -a 'PICTURE' "$E/qs-$SCEN.log" | tail -1)]"
    kill -0 "$QS" 2>/dev/null && echo "alive=[yes]" || echo "alive=[no]"
    echo "grew=[$(( $(peak) - base ))]"
    ;;
  nearfull)   # room for live.json's small write, none for history's big one
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do notify-send -a Signal "Old $i" "$(pad)$(pad)$(pad)"; sleep 0.2; ctl closecard 0.2; done
    sleep 3
    notify-send -a Signal "Alice" "SECRET-1 on screen"; sleep 1.5
    fill; truncate -s -16K "$N/filler"; sleep 0.5
    ctl closecard 3
    echo "kept=[$(live)]"
    echo "history=[$(secrets)]"
    stop; start
    ctl count 0.5
    echo "after=[$(sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a '^CTL count' | tail -1)]"
    rm -f "$N/filler"
    ctl closecard 7
    echo "rows=[$(grep -o 'SECRET-1' "$H" | wc -l)]"
    echo "liveafter=[$(live)]"
    ;;
  textclose)   # the same words, closed and removed
    printf 'Hi URLMARKER77' > "$HOME/sum"
    printf 'Your code URLMARKER77 is here' > "$HOME/body"
    watch_argv
    send --app Mail --summary-file "$HOME/sum" --body-file "$HOME/body"; sleep 1.5
    ctl closecard 2
    echo "filed=[$(grep -c URLMARKER77 "$H")]"
    ctl forgetfirst 2
    send --app Mail --summary-file "$HOME/sum" --body-file "$HOME/body"; sleep 1.5
    ctl forgetall 2
    unwatch
    echo "hits=[$(sort -u "$E/argv-hits-$SCEN" 2>/dev/null | wc -l)]"
    ;;
  textargv)   # a message's words, watched through everything that can happen to it
    printf 'Hi URLMARKER77' > "$HOME/sum"
    printf 'Your code URLMARKER77 is here' > "$HOME/body"
    watch_argv
    send --app Mail --summary-file "$HOME/sum" --body-file "$HOME/body"; sleep 1.5
    ctl count 0.5; echo "seen=[$(reply count)]"
    ctl clickcard 1.5
    unwatch
    echo "hits=[$(sort -u "$E/argv-hits-$SCEN" 2>/dev/null | wc -l)]"
    ;;
  closedfull)   # closed on a full disk: the only copy stays until history has it
    notify-send -a Signal "Alice" "SECRET-1 on screen $(pad)"; sleep 1.5
    fill
    ctl closecard 3
    echo "kept=[$(live)]"
    echo "history=[$(secrets)]"
    stop; start
    ctl count 0.5
    echo "after=[$(sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a '^CTL count' | tail -1)]"
    ;;
  hugeacts)
    base=$(rss)
    send --app Evil --summary "Big" --actions 400000 --count 2
    allcards 2
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  linkrace)   # a second click while the first copy is still running
    printf '%s' 'https://example.com/a?token=URLMARKER77' > "$HOME/body"
    touch "$HOME/clip-slow"
    send --app Mail --summary "Reset" --body-file "$HOME/body"; sleep 1.5
    ctl clicklink 0.3
    ctl clicklink 3.5
    rm -f "$HOME/clip-slow"
    ;;
  codefail)   # a copy that fails keeps the card, and says so
    touch "$HOME/clip-fails"
    notify-send -a Bank "Sign-in" "Your verification code is 482913"; sleep 1.5
    ctl clickcode 1.5
    ctl summaries 0.5
    echo "said=[$(reply summaries)]"
    ;;
  flood)   # big raw pictures: never drawn, but the bytes stay while a sender's object does
    base=$(rss)
    send --app Evil --summary "Big" --image-data 4000x4000 --count 20
    allcards 20
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  floodlie)   # the size claimed is tiny, the data isn't
    base=$(rss)
    send --app Evil --summary "Big" --image-data 1x1 --lie-size 64000000 --count 20
    allcards 20
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  floodback)  # room again once the cards are gone
    send --app Evil --summary "Big" --image-data 64x64 --count 12
    allcards 12
    echo "before=[$(reply pictures)]"
    ctl closeall 1
    send --app Evil --summary "Next" --image-data 64x64
    sleep 1
    ctl pictures 0.3
    echo "after=[$(reply pictures)]"
    ;;
  removed)   # closed on a full disk, room again, removed, restarted
    notify-send -a Signal "Alice" "SECRET-1 on screen $(pad)"; sleep 1.5
    fill
    ctl closecard 2
    rm -f "$N/filler"; sleep 7
    echo "filed=[$(secrets)]"
    ctl forgetfirst 2
    echo "forget=[$(sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a '^CTL forgetfirst' | tail -1)]"
    echo "history=[$(secrets)]"
    echo "live=[$(live)]"
    stop; start
    ctl count 0.5
    echo "after=[$(sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a '^CTL count' | tail -1)]"
    ctl closecard 1.5
    echo "again=[$(secrets)]"
    ;;
  folder)    # the folder deleted, then a new notification
    ctl dnd
    notify-send -a Signal "Alice" "SECRET-1 first"; sleep 2.5
    watch_modes
    rm -rf "$N"
    sleep 0.2
    notify-send -a Signal "Bob" "SECRET-2 second"; sleep 2.5
    unwatch
    echo "modes=[$(modes)]"
    echo "history=[$(secrets)]"
    ;;
  window)    # the folder deleted between a write and its read-back; no new notification
    ctl dnd 2.5    # (so Do Not Disturb's own read-back has finished)
    notify-send -a Signal "Alice" "SECRET-1 first"; sleep 0.3
    rm -rf "$N"
    watch_modes
    sleep 8
    unwatch
    echo "modes=[$(modes)]"
    echo "history=[$(secrets)]"
    ;;
  filegone)   # only the file deleted
    ctl dnd
    notify-send -a Signal "Alice" "SECRET-1 first"; sleep 2.5
    watch_modes
    rm -f "$H"
    notify-send -a Signal "Bob" "SECRET-2 second"; sleep 2.5
    unwatch
    echo "modes=[$(modes)]"
    ;;
  liveonly)   # the folder deleted, then only a card on screen writes
    watch_modes
    rm -rf "$N"; sleep 0.2
    notify-send -a Signal "Alice" "SECRET-1 on screen"; sleep 2.5
    unwatch
    echo "modes=[$(modes)]"
    echo "live=[$(live)]"
    ;;
  removegone)  # the folder deleted, then a removal
    ctl dnd
    notify-send -a Signal "Alice" "SECRET-1 first"; sleep 2.5
    watch_modes
    rm -rf "$N"; sleep 0.2
    ctl forgetoldest 2.5
    unwatch
    echo "modes=[$(modes)]"
    echo "history=[$(secrets)]"
    ;;
  exitrace)   # the folder deleted, a row filed, and a clean exit at once
    ctl dnd
    notify-send -a Signal "Alice" "SECRET-1 first"; sleep 2.5
    rm -rf "$N"; notify-send -a Signal "Bob" "SECRET-2 second"
    ctl quit 0
    wait "$QS" 2>/dev/null
    sleep 1.5
    echo "modes=[$(modes)]"
    echo "history=[$(secrets)]"
    exit 0
    ;;
  refused)  # a disk that refuses the write part-way: other rows stay, after a restart too
    start
    ctl dnd
    for i in 1 2 3; do notify-send -a Signal "Alice $i" "SECRET-$i $(pad)"; done; sleep 2.5
    echo "before=[$(secrets)]"
    stop
    FILELIMIT=2 start       # (a real short write from the kernel, past 2 KiB)
    ctl forgetfirst 2       # (the first in the file, so everything after it has to move)
    echo "after=[$(secrets)]"
    tr -d ' \n' < "$H" | python3 -I -c 'import json, sys; print("valid=[%d]" % len(json.load(sys.stdin)))' 2>/dev/null || echo "valid=[broken]"
    stop
    FILELIMIT= start
    ctl dnd
    echo "restart=[$(secrets)]"
    ;;
  oldlive)   # a card from days ago in live.json
    ctl count 0.5
    echo "count=[$(sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a '^CTL count' | tail -1)]"
    sleep 1
    echo "live=[$(live)]"
    echo "history=[$(secrets)]"
    ;;
  dndrestart)  # a card on screen, Do Not Disturb, a restart: it goes to history instead
    notify-send -a Signal "Alice" "SECRET-1 on screen"; sleep 1.5
    ctl dnd 1.5
    stop; start
    ctl count 0.5
    echo "count=[$(sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a '^CTL count' | tail -1)]"
    sleep 1
    echo "history=[$(secrets)]"
    echo "live=[$(live)]"
    ;;
  dndrules)   # what the center's text says happens under Do Not Disturb
    ctl dnd
    notify-send -a Signal "Plain app" "SECRET-1 $(pad)"
    notify-send -a Bank "Sign-in" "Your verification code is 482913"
    notify-send -a Battery -u critical "Battery" "SECRET-3 low"
    notify-send -u critical "From a script" "SECRET-4"
    notify-send "Plain script" "SECRET-5"
    notify-send -a Signal -h int:transient:1 "Temporary" "SECRET-6"
    sleep 1.5
    ctl summaries 0.5
    echo "shown=[$(reply summaries)]"
    ctl closeall 2
    echo "kept=[$(secrets)]"
    ;;
  dndsave)   # Do Not Disturb on a full disk: said, and saved once there's room
    fill
    ctl paneldnd 3
    echo "quiet=[$(cat "$N/quiet.json")]"
    ctl panelnotice 0.3
    echo "notice=[$(reply panelnotice)]"
    rm -f "$N/filler"; sleep 7
    echo "room=[$(cat "$N/quiet.json")]"
    ;;
  rohome)  # a read-only folder: not "still loading"
    ctl forgetall 0.5
    echo "reply=[$(reply forgetall)]"
    ctl panelclear 1.5
    ctl panelnotice 0.3
    echo "notice=[$(reply panelnotice)]"
    mount -o remount,rw,bind "$N"
    ctl forgetall 2
    echo "writable=[$(reply forgetall)]"
    ctl forgetall 0.5
    echo "writable2=[$(reply forgetall)]"
    ;;
  onlyhidden)  # only rows the center hides: Clear all is still offered, and works
    ctl panelcan 0.3
    echo "can=[$(reply panelcan)]"
    ctl panelclear 2
    echo "history=[$(secrets)]"
    ;;
  code)
    notify-send -a Bank "Sign-in" "Your verification code is 482913"; sleep 1.5
    ctl copycode 1.5
    ;;
  full)
    ctl dnd
    for i in 1 2 3 4 5; do notify-send -a Signal "Alice $i" "SECRET-$i $(head -c 2000 /dev/zero | tr '\0' x)"; done; sleep 1.5
    echo "before=[$(secrets)]"
    dd if=/dev/zero of="$N/filler" bs=4k 2>/dev/null; sync
    ctl forgetall 2
    echo "full=[$(secrets)]"
    stop; start    # restart while the disk is still full
    echo "restart=[$(secrets)]"
    rm -f "$N/filler"; sleep 8
    echo "room=[$(secrets)]"
    ;;
  stop)    # shut down within 0.3 s of Clear all, disk full
    ctl dnd
    for i in 1 2 3 4 5; do notify-send -a Signal "Alice $i" "SECRET-$i $(pad)"; done; sleep 1.5
    fill
    ctl forgetall 0.3
    stop; start
    echo "restart=[$(secrets)]"
    ;;
  stale)   # rows filed since the last load survive a removal on a full disk
    ctl dnd
    for i in 1 2 3; do notify-send -a Signal "Alice $i" "SECRET-$i $(pad)"; done; sleep 1.5
    stop; start; ctl dnd
    for i in 7 8; do notify-send -a Signal "Bob $i" "SECRET-$i $(pad)"; done; sleep 1.5
    fill
    ctl forgetoldest 0.3
    echo "after=[$(secrets)]"
    stop; start
    echo "restart=[$(secrets)]"
    ;;
  fullcard)  # a card on screen at Clear all, disk full
    notify-send -a Signal "Bob" "SECRET-2 on screen $(pad)"; sleep 1.5
    echo "before=[$(live)]"
    fill
    ctl forgetall 1
    echo "live=[$(live)]"
    stop; start
    ctl closecard 1
    echo "history=[$(secrets)]"
    ;;
  aged)    # a row past its day on a full disk, after an earlier in-place write
    ctl dnd
    notify-send -a Signal "Alice" "SECRET-1 $(pad)"; sleep 1.5
    fill; ctl forgetall 2; rm -f "$N/filler"; sleep 7
    notify-send -a Signal "Bob" "SECRET-2 $(pad)"; sleep 1.5
    echo "filed=[$(secrets)]"
    fill; ctl age 3
    echo "aged=[$(secrets)]"
    ;;
  restart)  # a healthy restart keeps a card on screen
    notify-send -a Signal "Alice" "SECRET-1 on screen"; sleep 1.5
    echo "before=[$(live)]"
    stop; start
    ctl reloadlive 1
    echo "after=[$(live)]"
    ctl count 1
    ;;
  race)    # a card saved in the same tick as Clear all isn't lost from the file
    notify-send -a Signal "Alice" "SECRET-1 on screen"; sleep 1.5
    ctl racelive 2
    for _ in {1..13}; do [[ -n $(live) ]] && break; sleep 1; done   # (retries are about 6 s apart)
    echo "live=[$(live)]"
    ;;
  dnd)
    ctl dnd
    notify-send -a Signal "Alice" "SECRET-1 old"; sleep 1.5
    notify-send -a Signal "Bob" "SECRET-2 just filed"; sleep 0.1
    ctl forgetall 2
    echo "after=[$(secrets)]"
    stop; start
    echo "restart=[$(secrets)]"
    ;;
  card)
    notify-send -a Signal "Alice" "SECRET-1 closed as usual"; sleep 1
    ctl closecard 1.5
    echo "usual=[$(secrets)]"
    notify-send -a Signal "Bob" "SECRET-2 on screen"; sleep 1
    ctl forgetall 1
    ctl closecard 1.5
    echo "closed=[$(secrets)]"
    stop; start
    echo "restart=[$(secrets)]"
    ;;
esac
stop
DRV
chmod +x "$E/driver.sh"

run_scen() {
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    timeout 120 unshare -r -m -n dbus-run-session --config-file="$E/bus.conf" -- "$E/driver.sh" "$E" "$1" "$REPO" 2>>"$E/driver-errors" | grep -E '^[a-z0-9]+=\[' || true
}
has() { grep -q "^$2=\[$3\]" <<<"$1"; }
value() { sed -n "s/^$2=\[\(.*\)\]\$/\1/p" <<<"$1"; }
nofolderleak() { [[ ! -s $E/badmodes-$1 ]] || fail "$2: $(sort -u "$E/badmodes-$1" | head -5 | tr '\n' ';')"; }
private() {   # the folder 700, each file in it 600
  [[ $2 == "700 N "* ]] || fail "$1: $2"
  if grep -oE '[0-9]+ N/[^ ]+' <<<"$2" | grep -vE '^600 '; then fail "$1: $2"; fi
}

# ---- A link in a notification ----
out=$(run_scen link)
has "$out" toast '"clicked"' || fail "(setup) the card's link wasn't found in the rendered text: $out"
has "$out" card '"clicked"' || fail "(setup) the card wasn't clicked: $out"
log=$(cat "$E/clip-argv" 2>/dev/null)
# (the positive controls: both clicks opened the site, both copied the full link)
[[ $(grep -c '^xdg-open https://example.com/$' <<<"$log") == 2 ]] || fail "a click didn't open exactly https://<host>/ twice: $log"
[[ $(grep -c '^wl-copy --sensitive$' <<<"$log") -ge 2 ]] || fail "the link didn't go to wl-copy with no argument: $log"
[[ $(grep -c 'token=URLMARKER77&u=me' "$E/clip-stdin") == 2 ]] || fail "the full link didn't reach wl-copy on stdin, twice: $(cat "$E/clip-stdin")"
if grep -q URLMARKER77 "$E/clip-argv"; then fail "the link's token reached a logged argument: $log"; fi
[[ ! -s $E/argv-hits-link ]] || fail "the link's token was in a running program's arguments: $(cat "$E/argv-hits-link")"
has "$out" said ".*Full link copied. Opening example.com only.*" || fail "the card didn't say what happened: $out"
if grep -q URLMARKER77 <<<"$out"; then fail "the token was in what the card says: $out"; fi
pass "a link's full address goes to the clipboard on stdin, only https://<host>/ opens, and the card says so"

rm -f "$E/clip-argv" "$E/clip-stdin"
out=$(run_scen linkfail)
has "$out" said ".*Couldn't copy the full link. Opening example.com only.*" || fail "a failed copy wasn't reported: $out"
grep -q '^xdg-open https://example.com/$' "$E/clip-argv" || fail "the site didn't open after a failed copy: $(cat "$E/clip-argv")"
pass "a failed copy is reported, and still only the site opens"

rm -f "$E/clip-argv" "$E/clip-stdin"
out=$(run_scen linkmail)
has "$out" said ".*Email address copied.*" || fail "a copied address wasn't reported: $out"
grep -q '^a.person@example.com$' "$E/clip-stdin" || fail "the address didn't reach wl-copy on stdin: $(cat "$E/clip-stdin" 2>/dev/null)"
if grep -E 'xdg-open|a\.person' "$E/clip-argv"; then fail "an email address was opened, or put in an argument"; fi
pass "an email address is copied and nothing opens"

# ---- A sender's name is literal text to the focus command ----
rm -f "$E/clip-argv"
run_scen focus >/dev/null
[[ $(cat "$E/focus-stdin") == '.*(Evil' ]] || fail "the app name didn't arrive whole on stdin: '$(cat "$E/focus-stdin")'"
grep -q '^overtake notification-open$' "$E/clip-argv" || fail "the focus command wasn't run: $(cat "$E/clip-argv")"
if grep -qa 'Evil' "$E/clip-argv"; then fail "a sender's name reached a command line: $(cat "$E/clip-argv")"; fi
pass "a sender's name goes on stdin, never in a command line"

# ---- Senders' pictures ----
out=$(run_scen pathimage)
has "$out" count '"toasts=2"' || fail "(setup) the cards weren't there: $out"
has "$out" opened 124 || fail "a picture named by path was opened by the shell: $out"
has "$out" opened2 124 || fail "a picture named by a file:// URL was opened by the shell: $out"
if grep -E '^picture=.*(pic2?\.png|status=1)' <<<"$out"; then fail "a card shows a picture from a path: $out"; fi
pass "a picture named by a path is never opened"

out=$(run_scen rawclaim)
has "$out" alive yes || fail "image-data claiming too many pixels crashed the shell: $out"
has "$out" shown '"Claims"' || fail "(setup) the card wasn't there: $out"
if grep -E '^picture=.*qsimage' <<<"$out"; then fail "a card loads pixels a sender handed over: $out"; fi
pass "image-data claiming too many pixels doesn't crash the shell; the picture is never loaded"

out=$(run_scen flood)
has "$out" pictures '"cards=20 pictures=8 senders=8"' || fail "the limit on raw pictures isn't what's expected: $out"
grew=$(value "$out" grew)
(( grew < 800 )) || fail "20 pictures of 64 MB grew the shell by $grew MB: $out"
pass "20 raw pictures of 64 MB grow the shell by $grew MB, not 1250; the cards all show"
out=$(run_scen floodlie)
has "$out" pictures '"cards=20 pictures=8 senders=8"' || fail "the limit on raw pictures with a false size: $out"
grew=$(value "$out" grew)
(( grew < 800 )) || fail "20 pictures with a false size grew the shell by $grew MB: $out"
pass "the same with a false size: $grew MB"
out=$(run_scen floodback)
has "$out" before '"cards=12 pictures=8 senders=8"' || fail "(setup) a burst of small pictures: $out"
has "$out" after '"cards=[0-9]* pictures=1 senders=1"' || fail "a card's picture stayed counted after it closed: $out"
pass "the limit counts only the cards up now"

out=$(run_scen hugetext)
has "$out" pictures '"cards=10 pictures=0 senders=0"' || fail "a body past the limit kept its sender's object: $out"
grew=$(value "$out" grew); (( grew < 200 )) || fail "10 bodies of 30 MB grew the shell by $grew MB: $out"
pass "10 bodies of 30 MB: the senders' objects are let go, $grew MB"
out=$(run_scen hugehint)
has "$out" pictures '"cards=10 pictures=0 senders=0"' || fail "a hint past the limit kept its sender's object: $out"
grew=$(value "$out" grew); (( grew < 200 )) || fail "10 hints of 30 MB grew the shell by $grew MB: $out"
pass "10 hints of 30 MB: the same, $grew MB"
out=$(run_scen hugeacts)
has "$out" pictures '"cards=2 pictures=0 senders=0"' || fail "a message of many buttons kept its sender's object: $out"
grew=$(value "$out" grew); (( grew < 600 )) || fail "2 messages of many buttons grew the shell by $grew MB: $out"
pass "2 messages of 400,000 buttons: the same, $grew MB"

for scen in hugeapp hugeicon hugeactext hugelist hugevar hugestruct; do
  out=$(run_scen $scen)
  cards=8; [[ $scen == hugestruct ]] && cards=3
  has "$out" pictures "\"cards=$cards pictures=0 senders=0\"" || fail "$scen: its sender's object was kept: $out"
  grew=$(value "$out" grew); (( grew < 250 )) || fail "$scen: 8 messages grew the shell by $grew MB: $out"
done
pass "app names, icons, button text, list hints, variants and structs count too: let go, the shell's growth is bounded"

out=$(run_scen emptylist)
has "$out" pictures '"cards=1 pictures=0 senders=1"' || fail "an empty list hint was counted as too big: $out"
pass "an empty list hint isn't counted as too big"

# ---- A card's icon by name ----
out=$(run_scen cardicon)
[[ $(value "$out" before) != *siteok* && $(value "$out" before) != *looked-up* ]] || fail "a card drew or looked up an icon before the list arrived: $out"
[[ $(value "$out" arrived) == *overtake/user-icons/abc.png* ]] || fail "a card up when the list arrived didn't get its icon: $out"
[[ $(value "$out" siteok) == *overtake/user-icons/abc.png* ]] || fail "a card didn't draw the copy of an icon in your folder: $out"
for name in siteok sitebad; do [[ $(value "$out" $name) != *"image://icon/$name"* ]] || fail "$name reached the lookup: $out"; done
[[ $(value "$out" sitebad) != *sitebad* ]] || fail "an icon with no copy was drawn: $out"
[[ $(value "$out" sysicon) != *"image://icon/sysicon"* ]] || fail "a system name was looked up before a scan had looked for it: $out"
[[ $(value "$out" sysiconlater) == *"image://icon/sysicon"* ]] || fail "a system name wasn't looked up once a scan had looked for it: $out"
[[ $(value "$out" passwd) != *passwd* ]] || fail "a path reached a card's icon: $out"
pass "a card draws the copy of an icon in your folder, also when the list arrives late; a system name only after a scan; no copy or a path draws nothing"

# ---- An app whose icon is a file ----
out=$(run_scen entrybomb)
has "$out" alive yes || fail "a crafted icon file killed the shell: $out"
has "$out" count '"toasts=1"' || fail "(setup) the card wasn't there: $out"
grew=$(value "$out" grew); (( grew < 150 )) || fail "a crafted icon file grew the shell by $grew MB: $out"
out=$(run_scen entryfifo)
has "$out" alive yes || fail "an icon that's a named pipe killed the shell: $out"
has "$out" count '"toasts=1"' || fail "an icon that's a named pipe hung the shell: $out"
pass "an app's Icon= naming a file isn't opened"

# ---- A message's words stay out of every command line ----
out=$(run_scen textargv)
has "$out" seen '"toasts=1"' || fail "(setup) the message didn't arrive: $out"
has "$out" hits 0 || fail "a message's words reached a command line: $out ($(sort -u "$E/argv-hits-textargv" 2>/dev/null | head -3))"
out=$(run_scen textclose)
has "$out" filed 1 || fail "(setup) the row wasn't filed: $out"
has "$out" hits 0 || fail "a message's words reached a command line on close or remove: $out"
pass "a message's summary and body are in no command line seen by a 20 ms watcher, on arrival, click, close, remove or Clear all"

# ---- Closed on a nearly full disk ----
out=$(run_scen nearfull)
has "$out" kept "SECRET-1 " || fail "a closed card left live.json while history couldn't take it, with room for live.json alone: $out"
has "$out" after 'CTL count -> "toasts=1"' || fail "a card closed on a nearly full disk was lost at the restart: $out"
has "$out" rows 1 || fail "once there was room the row should be filed once: $out"
has "$out" liveafter "" || fail "the row stayed in live.json once history had it: $out"
pass "a card closed with room only for live.json survives a restart, and is filed once when there's room"

# ---- Closed on a full disk ----
out=$(run_scen closedfull)
has "$out" kept "SECRET-1 " || fail "a closed card left live.json while history couldn't take it: $out"
has "$out" after 'CTL count -> "toasts=1"' || fail "a card closed on a full disk was lost at the restart: $out"
pass "a card closed on a full disk stays in live.json, and survives a restart, until history has it"

# ---- Text a sender chooses doesn't stall the shared shell ----
out=$(run_scen stall)
worst=$(sed -n 's/^gap=\[\(.*\)\]$/\1/p' <<<"$out" | sort -n | tail -1)
[[ $(grep -c '^gap=' <<<"$out") == 4 && -n $worst ]] || fail "(setup) no timings: $out"
(( worst < 500 )) || fail "a hostile body stalled the shell for $worst ms: $out"
pass "32 KB of the worst text stalls the shell for at most $worst ms"

# ---- A code or link copy that goes wrong ----
out=$(run_scen codefail)
has "$out" said '"Sign-in|Couldn.t copy the code."' || has "$out" said '"Couldn.t copy the code.|Sign-in"' || fail "a failed code copy closed its card, or didn't say so: $out"
pass "a failed code copy keeps its card and says so"
: >"$E/clip-stdin"
run_scen linkrace >/dev/null
[[ $(grep -c 'URLMARKER77' "$E/clip-stdin") == 2 && -z $(grep -vc 'URLMARKER77' "$E/clip-stdin" | grep -v '^0$') ]] || fail "a second link click lost its copy: $(cat "$E/clip-stdin")"
pass "a second link click waits for the first copy"

# ---- A removed row and live.json ----
out=$(run_scen removed)
has "$out" filed "SECRET-1 " || fail "(setup) history didn't land once there was room: $out"
has "$out" forget 'CTL forgetfirst -> "ok"' || fail "(setup) forget didn't answer ok: $out"
has "$out" history "" || fail "forget left the row in history: $out"
has "$out" live "" || fail "the removed row is still in live.json: $out"
has "$out" after 'CTL count -> "toasts=0"' || fail "a removed row came back as a card after a restart: $out"
has "$out" again "" || fail "a removed row filed itself into history again: $out"
pass "a removed row can't come back through live.json"

# ---- The folder stays private when it's deleted ----
out=$(run_scen folder)
private "the folder deleted, then a write" "$(value "$out" modes)"
nofolderleak folder "the folder was recreated with default permissions"
has "$out" history "SECRET-1 SECRET-2 " || fail "history wasn't written back after the folder went: $out"
pass "a deleted folder comes back private when a row is filed"
out=$(run_scen window)
private "the folder deleted in the read-back window" "$(value "$out" modes)"
nofolderleak window "the read-back recreated the folder with default permissions"
has "$out" history "SECRET-1 " || fail "the read-back didn't write the row back: $out"
pass "a folder deleted before the read-back comes back private, with its rows"
out=$(run_scen filegone)
private "the file deleted, then a write" "$(value "$out" modes)"
nofolderleak filegone "a deleted file came back with default permissions"
pass "a deleted file comes back private"
out=$(run_scen liveonly)
private "the folder deleted, then a card" "$(value "$out" modes)"
nofolderleak liveonly "a card's write recreated the folder with default permissions"
has "$out" live "SECRET-1 " || fail "the card didn't get back into live.json: $out"
pass "a card's write brings the folder back private too"
out=$(run_scen removegone)
private "the folder deleted, then a removal" "$(value "$out" modes)"
nofolderleak removegone "a removal recreated the folder with default permissions"
has "$out" history "" || fail "a removal after the folder went left the row: $out"
pass "a removal brings the folder back private too"
out=$(run_scen exitrace)
private "the folder deleted just before the shell stops" "$(value "$out" modes)"
has "$out" history "SECRET-1 SECRET-2 " || fail "a stop right after a row was filed lost it: $out"
pass "a stop right after the folder went: the row is written, and the folder ends up private"

# ---- A write the disk refuses part-way ----
out=$(run_scen refused)
has "$out" before "SECRET-1 SECRET-2 SECRET-3 " || fail "(setup) rows weren't on disk: $out"
has "$out" after "SECRET-1 SECRET-2 SECRET-3 " || fail "a refused in-place write changed the file: $out"
has "$out" valid 3 || fail "a refused in-place write left the file broken: $out"
has "$out" restart "SECRET-1 SECRET-2 SECRET-3 " || fail "other rows were lost after a refused write and a restart: $out"
pass "an in-place removal the disk refuses part-way leaves every row in place"

# ---- Cards restored after a restart ----
out=$(run_scen oldlive)
has "$out" count 'CTL count -> "toasts=0"' || fail "a card days old was restored: $out"
has "$out" live "" || fail "a card days old stayed in live.json: $out"
has "$out" history "" || fail "a card days old was filed in history: $out"
pass "a card past its day isn't restored or filed"
out=$(run_scen dndrestart)
has "$out" count 'CTL count -> "toasts=0"' || fail "a card popped up at restart under Do Not Disturb: $out"
has "$out" history "SECRET-1 " || fail "that card wasn't kept in history: $out"
has "$out" live "" || fail "that card stayed in live.json: $out"
pass "under Do Not Disturb a restored card goes to history instead of popping up"

# ---- Do Not Disturb: what the center says ----
out=$(run_scen dndrules)
shown=$(value "$out" shown)
for what in Sign-in Battery "From a script"; do grep -q "$what" <<<"$shown" || fail "'$what' should show under Do Not Disturb: $out"; done
for what in "Plain app" "Plain script" Temporary; do if grep -q "$what" <<<"$shown"; then fail "'$what' shouldn't show under Do Not Disturb: $out"; fi; done
grep -q 'SECRET-1' <<<"$(value "$out" kept)" || fail "a plain app's notification wasn't kept: $out"
for what in SECRET-5 SECRET-6; do if grep -q "$what" <<<"$(value "$out" kept)"; then fail "$what shouldn't be kept under Do Not Disturb: $out"; fi; done
pass "Do Not Disturb does what the center's text says"
out=$(run_scen dndsave)
has "$out" quiet "" || fail "(setup) the full disk took Do Not Disturb: $out"
has "$out" notice '".*couldn.t be saved.*"' || fail "the user wasn't told Do Not Disturb couldn't be saved: $out"
has "$out" room '{"dnd":true}' || fail "Do Not Disturb wasn't saved once there was room: $out"
pass "Do Not Disturb that can't be saved is reported, and saved once there's room"

# ---- A read-only folder ----
out=$(run_scen rohome)
has "$out" reply '"unwritable"' || fail "forgetAll on a read-only folder: $out"
has "$out" notice '".*can.t be written.*"' || fail "the center said the wrong thing on a read-only folder: $out"
if grep -q 'still loading' <<<"$out"; then fail "the center says still loading on a read-only folder: $out"; fi
has "$out" writable2 '"none"' || fail "it didn't recover once the folder was writable: $out"
pass "a read-only folder is reported as that, and recovers when writable"

# ---- Each app's setting, and how long a critical card stays ----
out=$(run_scen appmodes)
has "$out" shown '"Show"' || fail "only the Show app's card should be up: $out"
has "$out" live "SECRET-3 " || fail "(setup) the Show app's card wasn't in live.json: $out"
has "$out" history "SECRET-2 " || fail "Off should keep nothing and Quiet should file its row: $out"
pass "an app set to Off leaves nothing, Quiet files without a card, Show shows"
out=$(run_scen critical)
has "$out" at5 '"One"' || fail "a critical card left too soon: $out"
has "$out" at17 '""' || fail "a critical card was still up after 17 s: $out"
has "$out" filed "SECRET-1 " || fail "a critical card that left wasn't filed for the center: $out"
has "$out" back '"Two"' || fail "(setup) a critical card wasn't restored: $out"
has "$out" backgone '""' || fail "a restored critical card was still up after 15 s: $out"
pass "a critical card leaves after 15 s for the center, a restored one too"

# ---- Clear all with only hidden rows ----
out=$(run_scen onlyhidden)
has "$out" can '"canClear=true shown=0"' || fail "Clear all isn't offered with only hidden rows: $out"
has "$out" history "" || fail "Clear all left hidden rows: $out"
pass "Clear all is offered, and works, with only hidden rows"

# A copied code reaches wl-copy on stdin, and no argument carries it.
run_scen code >/dev/null
grep -q '^CTL copycode -> "codes=482913"' <(sed 's/^.*CTL/CTL/' "$E/qs-code.log") || fail "(setup) the code wasn't detected or copied: $(grep -c . "$E/qs-code.log") log lines"
grep -q 482913 "$E/clip-stdin" 2>/dev/null || fail "the code didn't reach wl-copy on stdin"
if grep -q 482913 "$E/clip-argv" 2>/dev/null; then fail "a copied code reached wl-copy's arguments: $(grep 482913 "$E/clip-argv")"; fi
pass "a copied code goes to wl-copy on stdin, not in its arguments"

# Clear all on a real full disk stays cleared across a restart.
out=$(run_scen full)
has "$out" before "SECRET-1 SECRET-2 SECRET-3 SECRET-4 SECRET-5 " || fail "(setup) history wasn't on disk: $out"
has "$out" full "" || fail "Clear all on a full disk left entries in the file: $out"
has "$out" restart "" || fail "a restart with the disk still full brought cleared entries back: $out"
has "$out" room "" || fail "cleared entries came back once the disk had room: $out"
pass "Clear all on a real full disk stays cleared across a restart"

# ... also when the shell stops within 0.3 s of it.
out=$(run_scen stop)
has "$out" restart "" || fail "a stop 0.3 s after Clear all on a full disk brought entries back: $out"
pass "Clear all on a full disk holds through a stop 0.3 s later"

# A removal on a full disk keeps rows filed since the file was last loaded.
out=$(run_scen stale)
has "$out" after "SECRET-2 SECRET-3 SECRET-7 SECRET-8 " || fail "a removal on a full disk changed other rows: $out"
has "$out" restart "SECRET-2 SECRET-3 SECRET-7 SECRET-8 " || fail "other rows were lost after a restart: $out"
pass "a removal on a full disk takes that row only, also rows filed since the last load stay"

# A card on screen at Clear all, disk full, doesn't come back.
out=$(run_scen fullcard)
has "$out" before "SECRET-2 " || fail "(setup) the card wasn't in live.json: $out"
has "$out" live "" || fail "a card on screen at Clear all stayed in live.json on a full disk: $out"
has "$out" history "" || fail "that card came back and filed itself after a restart: $out"
pass "a card on screen at Clear all doesn't come back on a full disk"

# A row past its day leaves on a full disk too.
out=$(run_scen aged)
has "$out" filed "SECRET-2 " || fail "(setup) the row wasn't on disk: $out"
has "$out" aged "" || fail "a row past its day stayed in the file on a full disk: $out"
pass "a row past its day leaves on a full disk"

# A normal restart keeps a card on screen (the in-place view takes out only what memory dropped).
out=$(run_scen restart)
has "$out" before "SECRET-1 " || fail "(setup) the card wasn't in live.json: $out"
has "$out" after "SECRET-1 " || fail "a restart took a card on screen out of live.json: $out"
grep -q 'CTL count -> "toasts=1"' <(sed 's/^.*CTL/CTL/' "$E/qs-restart.log") || fail "a restart lost a card on screen"
pass "a normal restart keeps a card on screen"

# A card saved in the same tick as Clear all isn't lost from live.json.
out=$(run_scen race)
has "$out" live "SECRET-1 " || fail "a card saved during Clear all stayed missing from live.json: $out"
pass "a card saved during Clear all gets back into live.json"

# A silenced copy filed a moment before Clear all goes with it.
out=$(run_scen dnd)
has "$out" after "" || fail "a silenced copy filed just before Clear all survived it: $out"
has "$out" restart "" || fail "a silenced copy came back after a restart: $out"
pass "a silenced copy filed just before Clear all goes with it"

# A card on screen at Clear all files nothing when it closes.
out=$(run_scen card)
has "$out" usual "SECRET-1 " || fail "(setup) a card closing as usual didn't land in history: $out"
has "$out" closed "" || fail "a card on screen at Clear all landed in history when it closed: $out"
has "$out" restart "" || fail "a card on screen at Clear all came back after a restart: $out"
pass "a card on screen at Clear all leaves nothing behind"
