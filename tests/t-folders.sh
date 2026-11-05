#!/bin/bash
# Overtake's folders are private before anything watches or writes in them:
# every FileView path there waits for OvertakeFolders, every write goes through
# it; and in real Quickshell (skipped where it isn't installed) a deleted folder
# comes back 0700, and a watch on a folder missing at start still works.
source "$(dirname "$0")/lib.sh"
python3 -I - "$REPO" <<'PY' || fail "a FileView in Overtake's folders isn't gated"
import glob, os, re, sys
repo = sys.argv[1]; bad = []
own = re.compile(r'/\.(local/state|config|cache)/overtake|root\.(pinsPath|configPath|configDir|seenFile|modesFile)')
for p in glob.glob(f"{repo}/plugins/*/*.qml"):
    if os.path.basename(p) == "OvertakeFolders.qml": continue
    t = open(p).read()
    for m in re.finditer(r"\bpath: (.+?)(?:;|$)", t, re.M):
        if own.search(m.group(1)) and not m.group(1).startswith("folders.ready ?"): bad.append(f"{p}: path {m.group(1)}")
    for m in re.finditer(r'\b\w+\.setText\(', t): bad.append(f"{p}: direct {m.group(0)}")
    if "folders." in t and "OvertakeFolders { id: folders }" not in t: bad.append(f"{p}: no gate")
    if "folders." in t and not os.path.exists(os.path.join(os.path.dirname(p), "OvertakeFolders.qml")): bad.append(f"{p}: no gate file")
if bad: print("\n".join(bad)); sys.exit(1)
PY
pass "every FileView path in Overtake's folders waits for the gate, and every write goes through it"

command -v qs >/dev/null || { echo "skipped: no qs (the real-Quickshell part needs it)"; exit 0; }
E=$T/qs; mkdir -p "$E/shell" "$E/bin" "$E/run" "$E/home"; chmod 700 "$E/run"
mkdir -p -m 700 "$E/home/.config" "$E/home/.config/overtake"     # (the state folder stays missing)
cp "$REPO/plugins/overtake.taskbar/OvertakeFolders.qml" "$REPO/plugins/overtake.taskbar/BatteryAlerts.qml" "$E/shell/"
ln -s "$REPO/bin/overtake" "$E/bin/overtake"
cat > "$E/shell/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  BatteryAlerts { }
  OvertakeFolders { id: folders }
  FileView {
    path: folders.ready ? Quickshell.env("HOME") + "/.local/state/overtake/mode" : ""
    watchChanges: true; printErrors: false
    onFileChanged: reload()
    onLoaded: console.log("MODE " + text().trim())
  }
}
QML
( cd "$E"; umask 022; env -i PATH="$E/bin:/usr/bin" HOME="$E/home" XDG_RUNTIME_DIR="$E/run" QT_QPA_PLATFORM=offscreen DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
    timeout 12 qs -p "$E/shell/shell.qml" > "$E/qs.log" 2>&1 & 
  sleep 3
  echo on > "$E/home/.local/state/overtake/mode"     # that folder was missing when the shell started
  sleep 1
  rm -rf "${E:?}/home/.config/overtake"
  sleep 4
  stat -c %a "$E/home/.config/overtake" > "$E/mode-after-delete" 2>/dev/null
  wait ) || true
grep -q 'MODE on' "$E/qs.log" || fail "a watch on a folder missing at start never woke up: $(grep -c . "$E/qs.log") log lines"
pass "a watch on a folder missing at shell start still works"
[[ $(cat "$E/mode-after-delete" 2>/dev/null) == 700 ]] || fail "a deleted settings folder came back '$(cat "$E/mode-after-delete" 2>/dev/null)' (should be 700)"
pass "a deleted settings folder comes back owner-only"

# If `overtake` can't start at all, watching doesn't wait forever.
F=$T/qs2; mkdir -p "$F/shell" "$F/run" "$F/home/.local/state/overtake"; chmod 700 "$F/run"
cp "$REPO/plugins/overtake.taskbar/OvertakeFolders.qml" "$F/shell/"
sed '/BatteryAlerts { }/d' "$E/shell/shell.qml" > "$F/shell/shell.qml"
echo on > "$F/home/.local/state/overtake/mode"
( cd "$F"; env -i PATH=/usr/bin HOME="$F/home" XDG_RUNTIME_DIR="$F/run" QT_QPA_PLATFORM=offscreen timeout 4 qs -p "$F/shell/shell.qml" > "$F/qs.log" 2>&1 ) || true
grep -q 'MODE on' "$F/qs.log" || fail "with no overtake command, file watches never started"
pass "with no overtake command, file watches still start"
