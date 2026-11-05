#!/bin/bash
# The patched notifications copy in real Quickshell: offscreen, on a private
# session bus, with a scratch home and a stand-in wl-copy that logs what it gets,
# and a real full disk (a small tmpfs in a private mount namespace). Nothing
# here reaches the live desktop. Skipped where Quickshell isn't installed (CI).
#   Covers: a copied code stays out of argv; Clear all on a full disk stays
#   cleared after a restart; a silenced copy filed just before Clear all, and a
#   card still on screen at Clear all, leave nothing behind. (The cards' windows
#   are taken out, so the driver closes a card the way its timeout does.)
source "$(dirname "$0")/lib.sh"
for tool in qs dbus-run-session notify-send unshare; do
  command -v "$tool" >/dev/null || { echo "skipped: no $tool (the real-Quickshell test needs it)"; exit 0; }
done
unshare -r -m true 2>/dev/null || { echo "skipped: no user namespaces here"; exit 0; }

E=$T/e2e; mkdir -p "$E/root" "$E/bin" "$E/run"; chmod 700 "$E/run"
SHELL_SRC=$(dirname "$OMARCHY_SRC")
cp -a "$SHELL_SRC/Commons" "$SHELL_SRC/services" "$SHELL_SRC/Ui" "$E/root/"
cp -a "$OMARCHY_SRC/notifications" "$E/root/ov"
python3 -I "$REPO/patches/apply.py" notifications "$E/root/ov" || fail "the notifications patch doesn't apply"
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
t = t.replace("  property var leaving: ({})", "  property var leaving: ({})\n  readonly property var testToasts: toasts", 1)
open(p, "w").write(t)
PY
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

cat > "$E/driver.sh" <<'DRV'
#!/bin/bash
# Inside unshare -r -m and dbus-run-session: argument 1 is the scenario.
E=$1; SCEN=$2
export HOME=$E/home-$SCEN QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none PATH=$E/bin:$PATH XDG_RUNTIME_DIR=$E/run
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DISPLAY
N=$HOME/.local/state/omarchy/notifications; H=$N/history.json
mkdir -p "$N" "$HOME/.local/state/overtake" "$HOME/.config/overtake"; echo on > "$HOME/.local/state/overtake/mode"; : > "$HOME/ctl"
[[ $SCEN == full* || $SCEN == stop || $SCEN == stale || $SCEN == aged ]] && mount -t tmpfs -o size=256k tmpfs "$N"
ctl() { echo "$1 $(date +%s%N)" > "$HOME/ctl"; sleep "${2:-0.5}"; }
start() { ( exec qs -p "$E/root/shell.qml" ) >>"$E/qs-$SCEN.log" 2>&1 & QS=$!; sleep 4; }
stop() { kill -TERM "$QS"; wait "$QS" 2>/dev/null; }
secrets() { grep -o 'SECRET-[0-9]' "$H" 2>/dev/null | sort -u | tr '\n' ' '; }
live() { grep -o 'SECRET-[0-9]' "$N/live.json" 2>/dev/null | sort -u | tr '\n' ' '; }
pad() { head -c 2000 /dev/zero | tr '\0' x; }
fill() { dd if=/dev/zero of="$N/filler" bs=4k 2>/dev/null; sync; }
start
case $SCEN in
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
    timeout 120 unshare -r -m dbus-run-session -- "$E/driver.sh" "$E" "$1" 2>/dev/null | grep -E '^[a-z]+=\[' || true
}
has() { grep -q "^$2=\[$3\]" <<<"$1"; }

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
