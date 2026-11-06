# Shared setup for Overtake Mode's tests: a private scratch home, stubbed
# desktop commands (nothing reaches a live session), and a log of every
# command line any child process is started with.
#
# Sourced by tests/t-*.sh. Needs bash, jq, python3, flock; uses the Omarchy
# shell plugins at $OMARCHY_SRC (default: the installed Omarchy).

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OMARCHY_SRC=${OMARCHY_SRC:-/usr/share/omarchy/shell/plugins}
T=$(mktemp -d "${TMPDIR:-/tmp}/overtake-test.XXXXXX")
chmod 700 "$T"
# Any dispatch real Hyprland would refuse fails the test that sent it, even
# though Overtake (like real `hyprctl --batch`) carries on after one.
finish() {
  local rc=$?
  if [[ -s $T/hypr/bad-dispatch ]]; then
    echo "FAIL: a dispatch Hyprland would refuse:" >&2
    cat "$T/hypr/bad-dispatch" >&2
    rc=1
  fi
  rm -rf "${T:?}"
  exit "$rc"
}
trap finish EXIT

ARGV_LOG="$T/argv.log"
STUB="$T/stub"
WRAP="$T/wrap"
mkdir -p "$STUB" "$WRAP" "$T/run"
chmod 700 "$T/run"
: >"$ARGV_LOG"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

# A marker that must never appear in any child's command line.
MARK="OVERTAKE_PRIVATE_MARKER_7f3a"

# Desktop commands: logged, never real. hyprctl answers -j queries with a
# window whose title (and class) carry the marker.
stub() {
  local name=$1 body=${2:-}
  printf '#!/bin/bash\nprintf "%%s\\0" "$0" "$@" >>"%s"; printf "\\n" >>"%s"\n%s\n' "$ARGV_LOG" "$ARGV_LOG" "$body" >"$STUB/$name"
  chmod +x "$STUB/$name"
}
for c in omarchy omarchy-shell omarchy-notification-send omarchy-theme-set omarchy-theme-bg-set \
         omarchy-restart-shell omarchy-menu omarchy-menu-images omarchy-launch-browser omarchy-launch-screensaver \
         omarchy-hook omarchy-hyprland-focus-app omarchy-toggle omarchy-toggle-enabled omarchy-theme-current \
         omarchy-theme-list omarchy-transcode-ascii omarchy-branding-screensaver omarchy-sleep-disabled \
         notify-send gsettings xdg-mime xdg-open setsid uwsm-app gtk-launch wl-copy busctl curl magick; do
  stub "$c"
done
# and every other omarchy-* command this machine has, so a test can never
# reach a live session
for c in $(compgen -c omarchy- 2>/dev/null | sort -u); do [[ -e $STUB/$c ]] || stub "$c"; done
stub omarchy-version 'echo 4.5.0-test'
# The shell's answer to listPlugins: what's in the plugins folder, as it scans
# it. (Other calls answer nothing, like a shell with nothing to say.)
stub omarchy-shell 'if [[ $* == "shell listPlugins" ]]; then
  for d in "$HOME/.config/omarchy/plugins"/*/; do [[ -d $d ]] && basename "$d"; done | jq -R "{id: .}" | jq -s .
fi'

# What Hyprland reports, from files a test can replace (use_workspace below);
# and what it accepts: dispatches are checked against the forms Overtake sends
# (written from the code; on, off, minimize, restore, snap, maximize, show, send,
# focus-app, relayout and show-desktop ran without error in real Hyprland on
# 2026-11-05), so a typo, a broken quote or an unchecked name is refused, and
# noted for the test's end. As in the real
# program, a refused `dispatch` exits 7 and a refused line of `--batch` doesn't.
HYPR="$T/hypr"
mkdir -p "$HYPR"
cat >"$HYPR/clients.json" <<EOF
[{"address":"0xa1","pid":4242,"class":"app.$MARK","initialClass":"app.$MARK","title":"Window $MARK","initialTitle":"$MARK","workspace":{"id":1,"name":"1"},"monitor":0,"at":[10,40],"size":[800,600],"floating":true,"fullscreen":0,"focusHistoryID":0,"mapped":true,"hidden":false,"tags":[]}]
EOF
cat >"$HYPR/monitors.json" <<EOF
[{"id":0,"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"reserved":[0,30,0,0],"focused":true,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"name":""}}]
EOF
cat >"$HYPR/activewindow.json" <<EOF
{"address":"0xa1","pid":4242,"class":"app.$MARK","title":"Window $MARK","workspace":{"id":1,"name":"1"},"monitor":0,"at":[10,40],"size":[800,600],"floating":true}
EOF
echo '{"id":1,"name":"1","windows":1}' >"$HYPR/activeworkspace.json"
echo '[{"id":1,"name":"1","monitor":"eDP-1"}]' >"$HYPR/workspaces.json"
stub hyprctl "$(cat <<'EOF'
HYPR=@HYPR@
ws='("[0-9]+"|"special:minimized"|"empty"|"name:" \.\. io\.open\("[^"]+"\):read\("a"\))'
win='window = "address:0x[0-9a-fA-F]+"'
forms=(
  'hl\.dsp\.focus\(\{ (workspace = '"$ws"'|'"$win"'|monitor = "[^"]*") \}\)'
  'hl\.dsp\.window\.bring_to_top\(\)'
  'hl\.dsp\.window\.move\(\{ workspace = '"$ws"', follow = (true|false), '"$win"' \}\)'
  'hl\.dsp\.window\.move\(\{ x = -?[0-9]+, y = -?[0-9]+, relative = false, '"$win"' \}\)'
  'hl\.dsp\.window\.resize\(\{ x = [0-9]+, y = [0-9]+, relative = false, '"$win"' \}\)'
  'hl\.dsp\.window\.float\(\{ action = "(enable|disable)", '"$win"' \}\)'
  'hl\.dsp\.window\.fullscreen\(\{ mode = "maximized", '"$win"' \}\)'
  'hl\.dsp\.window\.close\(\{ '"$win"' \}\)'
  'hl\.dsp\.layout\("[a-z0-9. ]+"\)'
  'hl\.dsp\.workspace\.toggle_special\("minimized"\)'
)
file_re='io\.open\("([^"]+)"\)'
eval_re='^hl\.config\(\{ (cursor = \{ no_warps = (true|false) \}|animations = \{ enabled = (true|false) \}) \}\)$'
good_dispatch() {
  local f
  for f in "${forms[@]}"; do
    if [[ $1 =~ ^$f$ ]]; then
      # a name read from a file: the file must really hold it
      if [[ $1 =~ $file_re ]]; then
        [[ -f ${BASH_REMATCH[1]} ]] || return 1
        { cat "${BASH_REMATCH[1]}"; echo; } >>"$HYPR/named-dispatches"
      fi
      return 0
    fi
  done
  return 1
}
good_eval() { [[ $1 =~ $eval_re ]]; }
refuse() { printf '%s\n' "$1" >>"$HYPR/bad-dispatch"; echo "error: refused: $1"; }
case ${1:-} in
  dispatch)
    good_dispatch "${2:-}" && { echo ok; exit 0; }
    refuse "${2:-}"; exit 7 ;;
  --batch)
    IFS=';' read -ra lines <<<"${2:-}"
    for line in "${lines[@]}"; do
      line=${line#"${line%%[![:space:]]*}"}; line=${line%"${line##*[![:space:]]}"}
      case $line in
        "dispatch "*) good_dispatch "${line#dispatch }" || refuse "$line" ;;
        "eval "*) good_eval "${line#eval }" || refuse "$line" ;;
        *) refuse "$line" ;;
      esac
    done
    exit 0 ;;
esac
case "$*" in
  *clients*) cat "$HYPR/clients.json" ;;
  *monitors*) cat "$HYPR/monitors.json" ;;
  *activewindow*) cat "$HYPR/activewindow.json" ;;
  *activeworkspace*) cat "$HYPR/activeworkspace.json" ;;
  *workspaces*) cat "$HYPR/workspaces.json" ;;
  *getoption*) echo '{"int":0,"str":""}' ;;
  *-j*) echo '{}' ;;
esac
EOF
)"
sed -i "s|@HYPR@|$HYPR|" "$STUB/hyprctl"

# The window (and screen) in a workspace with this name, for the tests that
# need one other than the default "1": a named one has a negative id.
use_workspace() {  # use_workspace <name>
  local name=$1 id=-1338
  [[ $name =~ ^[0-9]+$ ]] && id=$name
  jq --argjson id "$id" --arg name "$name" '(.[].workspace) = {id: $id, name: $name}' "$HYPR/clients.json" >"$HYPR/x" && mv "$HYPR/x" "$HYPR/clients.json"
  jq --argjson id "$id" --arg name "$name" '(.[].activeWorkspace) = {id: $id, name: $name}' "$HYPR/monitors.json" >"$HYPR/x" && mv "$HYPR/x" "$HYPR/monitors.json"
  jq --argjson id "$id" --arg name "$name" '.workspace = {id: $id, name: $name}' "$HYPR/activewindow.json" >"$HYPR/x" && mv "$HYPR/x" "$HYPR/activewindow.json"
  jq -n --argjson id "$id" --arg name "$name" '{id: $id, name: $name, windows: 1}' >"$HYPR/activeworkspace.json"
}

# Real tools, wrapped so their command lines are logged too.
for c in jq python3 sed awk grep cp mv rm mkdir chmod mktemp flock date find sort head tail tr cut \
         readlink stat cat ls ln touch install diff cmp dirname basename sleep env timeout ps seq wc tee; do
  real=$(command -v "$c") || continue
  printf '#!/bin/bash\nprintf "%%s\\0" "%s" "$@" >>"%s"; printf "\\n" >>"%s"\nexec "%s" "$@"\n' "$c" "$ARGV_LOG" "$ARGV_LOG" "$real" >"$WRAP/$c"
  chmod +x "$WRAP/$c"
done

# A small Omarchy-like home: a bar with private-looking settings, menus,
# Hyprland files, a floating workspace layout, screensaver art.
make_home() {  # make_home <dir>
  local h=$1
  mkdir -p "$h/.config/omarchy/extensions" "$h/.config/hypr" "$h/.local/share/applications" \
           "$h/.local/state/omarchy/workspace-layouts" "$h/.config/omarchy/branding" \
           "$h/.local/state/omarchy/current" "$h/Pictures"
  # a wallpaper of your own, whose name is private
  printf 'picture' >"$h/Pictures/$MARK-holiday.png"
  ln -s "$h/Pictures/$MARK-holiday.png" "$h/.local/state/omarchy/current/background"
  cat >"$h/.config/omarchy/shell.json" <<EOF
{"bar":{"position":"top","layout":{"left":[{"id":"omarchy.workspaces"}],"center":[{"id":"omarchy.clock"}],"right":[{"id":"omarchy.elsewhen","cities":[{"name":"$MARK City","zone":"Etc/UTC"}]}]}}}
EOF
  printf -- '-- mine\no.bind("SUPER + Q", "x", "y")\n' >"$h/.config/hypr/bindings.lua"
  printf -- '-- auto\n' >"$h/.config/hypr/autostart.lua"
  printf '{\n  // mine\n  "personal": {"label":"P"}\n}\n' >"$h/.config/omarchy/extensions/omarchy-menu.jsonc"
  printf '[Desktop Entry]\nName=Browser\nExec=omarchy-launch-browser %%U\n' >"$h/.local/share/applications/omarchy-browser.desktop"
  echo 'o.workspace_mode({ workspace = "3", mode = "floating" })' >"$h/.local/state/omarchy/workspace-layouts/3.lua"
  echo "my own art" >"$h/.config/omarchy/branding/screensaver.txt"
}

# Run a command in the sandbox: scratch home, no session, stubs and wrappers
# first on PATH.
sbx() {  # sbx <home> <command...>
  local h=$1; shift
  env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
      -u HYPRLAND_INSTANCE_SIGNATURE -u DBUS_SESSION_BUS_ADDRESS -u WAYLAND_DISPLAY \
      HOME="$h" XDG_RUNTIME_DIR="$T/run" OVERTAKE_NO_RELOAD=1 OVERTAKE_OMARCHY_PLUGINS="$OMARCHY_SRC" \
      PATH="$STUB:$WRAP:/usr/bin:/bin" "$@"
}

# After uninstall: every file the user had is back byte for byte (shell.json
# by content: jq rewrites it), and nothing new is left except Overtake's kept
# settings and wallpapers (empty folders are allowed).
check_restored() {  # check_restored <before> <after>
  local before=$1 after=$2 extra changed
  jq -S . "$before/.config/omarchy/shell.json" >"$T/a.json"; jq -S . "$after/.config/omarchy/shell.json" >"$T/b.json"
  cmp -s "$T/a.json" "$T/b.json" || { diff "$T/a.json" "$T/b.json"; fail "shell.json content changed"; }
  (cd "$before" && find . \( -type f -o -type l \) | sort) >"$T/files-before"
  (cd "$after" && find . \( -type f -o -type l \) | sort) >"$T/files-after"
  extra=$(comm -13 "$T/files-before" "$T/files-after" | grep -v -E '^\./(\.config/overtake|Pictures/overtake)/' || true)
  [[ -z $extra ]] || { echo "$extra"; fail "uninstall left files behind"; }
  comm -23 "$T/files-before" "$T/files-after" | grep -q . && { comm -23 "$T/files-before" "$T/files-after"; fail "uninstall removed a file of the user's"; }
  changed=$(diff -rq -x shell.json "$before" "$after" | grep -v '^Only in' || true)
  [[ -z $changed ]] || { echo "$changed"; fail "a file of the user's changed"; }
}
