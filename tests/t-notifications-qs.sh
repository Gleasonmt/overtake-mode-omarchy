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
[[ $SCEN == full ]] && mount -t tmpfs -o size=256k tmpfs "$N"
ctl() { echo "$1 $(date +%s%N)" > "$HOME/ctl"; sleep "${2:-0.5}"; }
start() { ( exec qs -p "$E/root/shell.qml" ) >>"$E/qs-$SCEN.log" 2>&1 & QS=$!; sleep 4; }
stop() { kill -TERM "$QS"; wait "$QS" 2>/dev/null; }
secrets() { grep -o 'SECRET-[0-9]' "$H" 2>/dev/null | sort -u | tr '\n' ' '; }
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
