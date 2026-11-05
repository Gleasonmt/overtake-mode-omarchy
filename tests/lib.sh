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
trap 'rm -rf "${T:?}"' EXIT

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
stub hyprctl "$(cat <<EOF
case "\$*" in
  *clients*) echo '[{"address":"0xa1","pid":4242,"class":"app.$MARK","initialClass":"app.$MARK","title":"Window $MARK","initialTitle":"$MARK","workspace":{"id":1,"name":"1"},"monitor":0,"at":[10,40],"size":[800,600],"floating":true,"fullscreen":0,"focusHistoryID":0,"mapped":true,"hidden":false}]' ;;
  *monitors*) echo '[{"id":0,"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"reserved":[0,30,0,0],"focused":true,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"name":""}}]' ;;
  *activewindow*) echo '{"address":"0xa1","pid":4242,"class":"app.$MARK","title":"Window $MARK","workspace":{"id":1,"name":"1"},"monitor":0,"at":[10,40],"size":[800,600],"floating":true}' ;;
  *activeworkspace*) echo '{"id":1,"name":"1"}' ;;
  *workspaces*) echo '[{"id":1,"name":"1","monitor":"eDP-1"}]' ;;
  *getoption*) echo '{"int":0,"str":""}' ;;
  *-j*) echo '{}' ;;
esac
EOF
)"

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
           "$h/.local/state/omarchy/workspace-layouts" "$h/.config/omarchy/branding"
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
