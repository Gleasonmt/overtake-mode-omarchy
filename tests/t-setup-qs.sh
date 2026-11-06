#!/bin/bash
# The root plugin in real Quickshell: at most one reminder per shell start,
# however often Omarchy reloads it; none while the installer runs. And
# Spotlight's real file list, through a real Process, with a newline in a name.
# (Skipped where qs isn't installed; the logic parts are in t-qml-logic.js.)
source "$(dirname "$0")/lib.sh"
command -v qs >/dev/null || { echo "skipped: no qs"; exit 0; }

E="$T/qs"
mkdir -p "$E/shell/bin" "$E/bin" "$E/run"; chmod 700 "$E/run"
cp "$REPO/Setup.qml" "$E/shell/Setup.qml"
printf '{"version":"0.2.0"}\n' >"$E/shell/manifest.json"
printf '#!/bin/sh\n# this folder'"'"'s command\n' >"$E/shell/bin/overtake"
printf '#!/bin/bash\nprintf "%%s\\n" "$5" >>"%s/cards"\n' "$E" >"$E/bin/notify-send"
chmod +x "$E/bin/notify-send"
# Reloaded as Omarchy reloads a plugin: destroyed and made again, several times.
cat >"$E/shell/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  Loader { id: plugin; source: "Setup.qml" }
  property int reloads: 0
  Timer {
    interval: 350; running: true; repeat: true
    onTriggered: {
      if (reloads++ >= 5) { Qt.quit(); return }
      plugin.active = false
      plugin.active = true
    }
  }
}
QML
HOME_="$E/home"
start_shell() {  # a shell start, with its reloads; new process, new shell
  env -i PATH="$E/bin:/usr/bin" HOME="$HOME_" XDG_RUNTIME_DIR="$E/run" QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 \
    timeout 15 qs -p "$E/shell/shell.qml" >"$E/qs.log" 2>&1 || true
  sleep 0.2   # (the last card, started as the shell quit)
}
cards() { grep -c "${1:-.}" "$E/cards" 2>/dev/null || true; }
reset() { rm -rf "$HOME_" "$E/cards" "$E/run"/overtake-reminded.*; mkdir -p "$HOME_/.local/share/overtake" "$HOME_/.local/bin"; : >"$E/cards"; }
installed() {  # installed <recorded version> <the command's text>
  printf '%s\n' "$1" >"$HOME_/.local/share/overtake/version"
  printf '%s' "$2" >"$HOME_/.local/bin/overtake"; chmod +x "$HOME_/.local/bin/overtake"
}
SAME=$(cat "$E/shell/bin/overtake"; echo x); SAME=${SAME%x}

reset
start_shell
[[ $(cards) == 1 ]] || { cat "$E/cards"; tail -5 "$E/qs.log"; fail "not installed: $(cards) reminders in one shell start with its reloads"; }
grep -q 'Run ./install.sh in' "$E/cards" || fail "the wrong reminder for a missing install"
start_shell
[[ $(cards) == 2 ]] || fail "the next shell start didn't remind again ($(cards) in all)"
[[ $(find "$E/run" -maxdepth 1 -name 'overtake-reminded.*' | wc -l) == 1 ]] || fail "marks of earlier shells pile up in the runtime folder"
# A second shell running at the same time keeps its own mark.
sleep 300 & other=$!
mkdir "$E/run/overtake-reminded.$other"
start_shell
[[ -d $E/run/overtake-reminded.$other ]] || fail "a mark of a shell still running was removed"
kill "$other"; wait "$other" 2>/dev/null || true
pass "not installed: one reminder per shell start, however many reloads"

reset; installed 0.1.15 "$SAME"
sleep 300 & alive=$!
echo "$alive" >"$HOME_/.local/share/overtake/installing"
start_shell
kill "$alive"; wait "$alive" 2>/dev/null || true
[[ $(cards) == 0 ]] || { cat "$E/cards"; fail "a reminder while the installer is running"; }
start_shell     # (that process is gone now: an install that stopped halfway)
[[ $(cards) == 1 ]] || { cat "$E/cards"; fail "an install that stopped halfway got $(cards) reminders"; }
grep -q 'finish updating to 0.2.0' "$E/cards" || fail "the wrong reminder for an older install"
pass "no reminder while the installer runs; one if it stopped halfway"

reset; installed 0.2.0 "$SAME"
start_shell
[[ $(cards) == 0 ]] || { cat "$E/cards"; fail "a reminder with everything up to date"; }
installed 0.3.0 "other"
start_shell
[[ $(cards) == 0 ]] || { cat "$E/cards"; fail "a reminder with a newer version installed"; }
installed 0.2.0 "a different command"
start_shell
[[ $(cards) == 1 ]] || { cat "$E/cards"; fail "the same version with a different command got $(cards) reminders"; }
pass "up to date or newer: nothing; the same version with another command: one reminder"

# ---------- Spotlight's file list ----------
command -v fd >/dev/null || { echo "skipped: no fd"; exit 0; }
F="$T/files"
mkdir -p "$F/evil"$'\n'"/etc"
: >"$F/evil"$'\n'"/etc/shadow"    # (split on the newline, one line would read /etc/shadow)
: >"$F/plain name.txt"
S="$REPO/plugins/overtake.taskbar/Spotlight.qml"
mkdir -p "$T/qs2"
python3 -I - "$S" "$F" >"$T/qs2/shell.qml" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
command = re.search(r'id: fileList\n.*?command: (\[.*?\])\n', src, re.S).group(1).replace("root.home", '"%s"' % sys.argv[2])
fn = re.search(r'  function splitFileList\(text\) \{.*?\n  \}\n', src, re.S).group(0)
print('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: root
%s
  Process {
    running: true
    command: %s
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { console.log("LIST " + JSON.stringify(root.splitFileList(text))); Qt.quit() }
    }
  }
}''' % (fn, command))
PY
env -i PATH=/usr/bin HOME="$E/home" XDG_RUNTIME_DIR="$E/run" QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 timeout 10 qs -p "$T/qs2/shell.qml" >"$T/qs2/log" 2>&1 || true
python3 -I - "$T/qs2/log" "$F" <<'PY' || fail "Spotlight's file list splits a name with a newline"
import json, re, sys
line = next(l for l in open(sys.argv[1]) if "LIST " in l)
names = json.loads(line[line.index("LIST ") + 5:].strip().replace("\x1b[0m", ""))
want = sys.argv[2] + "/evil\n/etc/shadow"
sys.exit(0 if want in names and sys.argv[2] + "/plain name.txt" in names and "/etc/shadow" not in names else 1)
PY
pass "a newline in a file name stays in that one Spotlight result, in real Quickshell and real fd"
