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
#   (a portal if there is one, then xdg-open). It covers what a click opens and
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
      else if (c === "clickcard") { var b = firstReal(); if (b) svc.activate(b.key); r = b ? "clicked" : "none" }
      else if (c === "pictures") {
        var n = 0, w = 0
        for (var j = 0; j < svc.testToasts.count; j++) {
          if (String(svc.testToasts.get(j).image) !== "") n++
          if (svc.refs[svc.testToasts.get(j).key]) w++
        }
        r = "cards=" + svc.testToasts.count + " pictures=" + n + " senders=" + w
      }
      else if (c === "picture") { var d = firstReal(); r = d && svc.testCards[d.key] ? svc.testCards[d.key].testPicture() : "none" }
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
cat > "$E/root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ov" as Ov
ShellRoot {
  Ov.Service { id: svc }
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
[[ ! -e "\$HOME/clip-fails" ]]
STUB
for tool in xdg-open omarchy-hyprland-focus-app overtake; do
  printf '#!/bin/bash\nprintf "%%s\\n" "%s $*" >> "%s/clip-argv"\n' "$tool" "$E" > "$E/bin/$tool"
done
# omarchy-shell, asked of the test's shell over two files.
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
  full*|stop|stale|aged|removed|dndsave|rohome) mount -t tmpfs -o size=256k tmpfs "$N";;
esac
case $SCEN in
  link*|focus|pathimage|rawimage|flood*|dndrules|dndsave|rohome|onlyhidden)
    ROOT=rootw; WAITS=5
    export QT_QPA_PLATFORM=vnc QT_QUICK_BACKEND=software;;
esac
ctl() { echo "$1 $(date +%s%N)" > "$HOME/ctl"; sleep "${2:-0.5}"; }
start() { ( [[ -n ${FILELIMIT:-} ]] && { trap '' XFSZ; ulimit -f "$FILELIMIT"; }; exec qs -p "$E/$ROOT/shell.qml" ) >>"$E/qs-$SCEN.log" 2>&1 & QS=$!; sleep "$WAITS"; }
stop() { kill -TERM "$QS"; wait "$QS" 2>/dev/null; }
reply() { sed 's/^.*CTL/CTL/' "$E/qs-$SCEN.log" | grep -a "^CTL $1 " | tail -1 | sed 's/^[^>]*> //'; }
rss() { awk '/VmRSS/ { print int($2 / 1024) }' "/proc/$QS/status"; }
send() { python3 -I "$REPO/tests/t-notifications-send.py" "$@" >/dev/null; }
modes() { stat -c '%a %n' "$N" "$N"/* 2>/dev/null | sed "s#$N#N#" | tr '\n' ' '; }
# Every 10 ms: any mode in the folder that isn't private.
watch_modes() { while :; do stat -c '%a %n' "$N" "$N"/* 2>/dev/null | grep -vE '^(700|600) ' >> "$E/badmodes-$SCEN"; sleep 0.01; done & WATCH=$!; }
unwatch() { kill "$WATCH" 2>/dev/null; wait "$WATCH" 2>/dev/null; }
# Every 20 ms: any running program with the marker in its arguments. (The
# pattern doesn't match itself. Senders here read the marker from a file.)
watch_argv() { while :; do grep -lsa 'URLMARKE[R]77' /proc/[0-9]*/cmdline >> "$E/argv-hits-$SCEN"; sleep 0.02; done & WATCH=$!; }
secrets() { grep -o 'SECRET-[0-9]' "$H" 2>/dev/null | sort -u | tr '\n' ' '; }
live() { grep -o 'SECRET-[0-9]' "$N/live.json" 2>/dev/null | sort -u | tr '\n' ' '; }
pad() { head -c 2000 /dev/zero | tr '\0' x; }
fill() { dd if=/dev/zero of="$N/filler" bs=4k 2>/dev/null; sync; }
[[ $SCEN == oldlive ]] && printf '[{"key":"nold","app":"Signal","summary":"Old","body":"SECRET-1","urgency":1,"ts":%s}]\n' "$(( $(date +%s) - 432000 ))" > "$N/live.json"
[[ $SCEN == onlyhidden ]] && printf '[{"key":"nhid","app":"omarchy-action","summary":"Done","body":"SECRET-1","urgency":1,"ts":%s,"closed_ts":%s,"closed_reason":"expired"}]\n' "$(date +%s)" "$(date +%s)" > "$H"
[[ $SCEN == rohome ]] && { : > "$H"; : > "$N/live.json"; : > "$N/quiet.json"; mount --bind "$N" "$N"; mount -o remount,ro,bind "$N" || echo "reply=[(setup) not read-only]"; }
[[ $SCEN == refused ]] || start
case $SCEN in
  link)    # a link in the text, clicked; then a card with one, clicked
    dbus-monitor --session "destination='org.freedesktop.portal.Desktop'" > "$E/portal-$SCEN.log" 2>&1 & MON=$!
    printf '%s' 'https://example.com/reset?token=URLMARKER77&u=me' > "$HOME/body"
    watch_argv
    send --app Mail --summary "Reset" --body-file "$HOME/body"; sleep 1.5
    ctl clicklink 1.5
    echo "toast=[$(reply clicklink)]"
    ctl summaries 0.5
    echo "said=[$(reply summaries)]"
    ctl clickcard 1.5
    echo "card=[$(reply clickcard)]"
    unwatch; kill "$MON" 2>/dev/null
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
  rawimage)    # pixels handed over still show
    send --app Chat --summary "Hi" --image-data 64x64; sleep 1.5
    ctl picture 0.5
    echo "picture=[$(reply picture)]"
    ;;
  flood)   # big raw pictures: memory stays bounded while the cards are up
    base=$(rss)
    send --app Evil --summary "Big" --image-data 4000x4000 --count 20
    sleep 1
    ctl pictures 0.3
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  floodlie)   # the size claimed is tiny, the data isn't
    base=$(rss)
    send --app Evil --summary "Big" --image-data 1x1 --lie-size 64000000 --count 20
    sleep 1
    ctl pictures 0.3
    echo "pictures=[$(reply pictures)]"
    echo "grew=[$(( $(rss) - base ))]"
    ;;
  floodback)  # room again once the cards are gone
    send --app Evil --summary "Big" --image-data 64x64 --count 12
    sleep 1
    ctl pictures 0.3
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
    ctl dnd
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
    ctl forgetoldest 2
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
    ctl racelive 4
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
if grep -q URLMARKER77 "$E/portal-link.log"; then fail "the link's token reached the portal: $(grep URLMARKER77 "$E/portal-link.log" | head -3)"; fi
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
sent=$(sed -n 's/^omarchy-hyprland-focus-app //p' "$E/clip-argv")
[[ $sent == '\.\*\(Evil' ]] || fail "the app name wasn't escaped for the focus command: '$sent' ($(cat "$E/clip-argv"))"
FOCUS=$(dirname "$(dirname "$OMARCHY_SRC")")/bin/omarchy-hyprland-focus-app
if [[ -x $FOCUS ]] && command -v jq >/dev/null; then
  mkdir -p "$E/focusbin"
  cat > "$E/focusbin/hyprctl" <<'STUB'
#!/bin/bash
if [[ $1 == clients ]]; then echo '[{"address":"0xa1","class":"org.signal.Signal","initialClass":"org.signal.Signal","initialTitle":"Signal","focusHistoryID":0}]'; else echo "FOCUSED $*"; fi
STUB
  chmod +x "$E/focusbin/hyprctl"
  if PATH=$E/focusbin:$PATH "$FOCUS" "$sent" >/dev/null 2>&1; then fail "the escaped name still matched a window"; fi
  PATH=$E/focusbin:$PATH "$FOCUS" '.*' >/dev/null 2>&1 || fail "(control) the plain pattern .* should match in Omarchy's command"
  PATH=$E/focusbin:$PATH "$FOCUS" "Signal" >/dev/null 2>&1 || fail "(control) a plain name should still match"
fi
pass "a sender's name is literal text to omarchy-hyprland-focus-app"

# ---- Senders' pictures ----
out=$(run_scen pathimage)
has "$out" count '"toasts=2"' || fail "(setup) the cards weren't there: $out"
has "$out" opened 124 || fail "a picture named by path was opened by the shell: $out"
has "$out" opened2 124 || fail "a picture named by a file:// URL was opened by the shell: $out"
if grep -E '^picture=.*(pic2?\.png|status=1)' <<<"$out"; then fail "a card shows a picture from a path: $out"; fi
pass "a picture named by a path is never opened"

out=$(run_scen rawimage)
has "$out" picture '"image://qsimage/[0-9]*/[0-9]* status=1"' || fail "a sender's raw pixels didn't show: $out"
pass "pixels handed over in image-data still show"

out=$(run_scen flood)
has "$out" pictures '"cards=20 pictures=0 senders=8"' || fail "the limit on raw pictures isn't what's expected: $out"
grew=$(value "$out" grew)
(( grew < 800 )) || fail "20 pictures of 64 MB grew the shell by $grew MB: $out"
pass "20 raw pictures of 64 MB grow the shell by $grew MB, not 2500; the cards all show"
out=$(run_scen floodlie)
has "$out" pictures '"cards=20 pictures=8 senders=8"' || fail "the limit on raw pictures with a false size: $out"
grew=$(value "$out" grew)
(( grew < 800 )) || fail "20 pictures with a false size grew the shell by $grew MB: $out"
pass "the same with a false size: $grew MB"
out=$(run_scen floodback)
has "$out" before '"cards=12 pictures=8 senders=8"' || fail "(setup) a burst of small pictures: $out"
has "$out" after '"cards=[0-9]* pictures=1 senders=1"' || fail "a card's picture stayed counted after it closed: $out"
pass "the limit counts only the cards up now"

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
