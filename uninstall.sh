#!/bin/bash
# Remove Overtake Mode. Switches back to Omarchy first if the mode is on.
#
#   ./uninstall.sh            # keep your Overtake settings and wallpapers
#   ./uninstall.sh --purge    # remove those too
#   ./uninstall.sh --dry-run  # only list what it would do
#   ./uninstall.sh --yes      # don't ask

set -euo pipefail

PLUGINS="$HOME/.config/omarchy/plugins"
HYPR="$HOME/.config/hypr"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

die() { printf 'overtake uninstall: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--purge] [--dry-run] [--yes]

      --purge    also delete ~/.config/overtake and ~/Pictures/overtake
  -n, --dry-run  list what would be removed; change nothing
  -y, --yes      don't ask
  -h, --help     show this
EOF
}

PURGE='' ASSUME_YES='' DRY_RUN=''
for arg in "$@"; do
  case $arg in
    --purge) PURGE=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $arg" ;;
  esac
done

cat <<'EOF'
Uninstalling Overtake Mode will:
  switch back to Omarchy, if the mode is on
  remove its marked blocks from ~/.config/hypr/bindings.lua, autostart.lua,
    ~/.config/omarchy/extensions/omarchy-menu.jsonc and shell.toml
  hand notifications and battery back to Omarchy's own (shell.json)
  point links and images back at Omarchy's own handlers
  delete ~/.local/bin/overtake, ~/.config/hypr/overtake*.lua,
    ~/.config/omarchy/plugins/overtake.*, its .desktop files,
    ~/.local/state/overtake and ~/.cache/overtake
EOF
if [[ $PURGE ]]; then
  echo "  delete ~/.config/overtake and ~/Pictures/overtake (--purge)"
else
  echo "  keep ~/.config/overtake and ~/Pictures/overtake (--purge deletes them)"
fi
echo
if [[ $DRY_RUN ]]; then
  echo "Dry run: nothing was changed."
  exit 0
fi
if [[ -z $ASSUME_YES ]]; then
  [[ -t 0 ]] || die "can't ask without a terminal. Re-run with --yes to go ahead, or --dry-run to see the list."
  read -r -p "Go ahead? [y/N] " reply
  [[ $reply == [yY]* ]] || { echo "Nothing changed."; exit 1; }
fi

# Back to Omarchy first. The state folder holds your saved Omarchy bar and
# background, so stop here if switching off fails rather than delete them.
OVERTAKE="$HOME/.local/bin/overtake"
if [[ -f $HOME/.local/state/overtake/enabled ]]; then
  if ! [[ -x $OVERTAKE ]] || ! "$OVERTAKE" off >/dev/null; then
    echo "Couldn't switch Overtake Mode off; nothing removed. Fix that first (overtake off)." >&2
    exit 1
  fi
fi

remove_block() {  # remove_block <file> <comment prefix>
  [[ -f $1 ]] || return 0
  python3 - "$1" "$2" <<'PY'
import sys, re
path, prefix = sys.argv[1:3]
text = open(path).read()
text = re.sub(r"\n*" + re.escape(f"{prefix} >>> overtake") + r".*?" + re.escape(f"{prefix} <<< overtake") + r"\n?", "\n", text, flags=re.S)
open(path, "w").write(text)
PY
}
remove_block "$HYPR/bindings.lua" "--"
remove_block "$HYPR/autostart.lua" "--"
remove_block "$MENU" "  //"

# Hand notifications and battery back to Omarchy's own before removing the
# patched copies. Disabling goes through the shell; if it isn't running, edit
# shell.json directly so Omarchy's own aren't left disabled.
SHELL_JSON="$HOME/.config/omarchy/shell.json"
for id in overtake.notifications overtake.battery; do
  omarchy plugin disable "$id" >/dev/null 2>&1 || true
done
if [[ -f $SHELL_JSON ]]; then
  tmp=$(mktemp "$SHELL_JSON.XXXXXX")
  jq '(.plugins |= (if type == "array" then map(select((if type == "object" then .id else . end) | tostring | startswith("overtake.") | not)) else . end))
      | (.disabledPlugins |= (if type == "array" then map(select(. != "omarchy.notifications" and . != "omarchy.battery")) else . end))' \
    "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON" || rm -f "$tmp"
fi

# The bar-size block Overtake adds to shell.toml
SHELL_TOML="$HOME/.config/omarchy/shell.toml"
if [[ -f $SHELL_TOML ]]; then
  python3 - "$SHELL_TOML" <<'PY'
import sys, re
p = sys.argv[1]
t = open(p).read()
open(p, "w").write(re.sub(r"\n?# >>> overtake.*?# <<< overtake\n?", "\n", t, flags=re.S))
PY
fi

# Taskbar pins live with the state; keep them unless purging.
if [[ -z $PURGE && -f $HOME/.local/state/overtake/taskbar-settings.json ]]; then
  mkdir -p "$HOME/.config/overtake"
  cp "$HOME/.local/state/overtake/taskbar-settings.json" "$HOME/.config/overtake/taskbar-settings.json"
fi
# Images back to Omarchy's own viewer entry
for t in image/png image/jpeg image/jpg image/gif image/bmp image/webp image/tiff image/avif image/heif image/jxl image/svg+xml; do
  [[ $(xdg-mime query default "$t" 2>/dev/null) == overtake-image-viewer.desktop ]] && xdg-mime default imv.desktop "$t"
done
# Links back to Omarchy's own handler
sed -i 's|^Exec=.*/overtake open-url |Exec=omarchy-launch-browser |' "$HOME/.local/share/applications/omarchy-browser.desktop" 2>/dev/null || true
rm -f "$HOME/.local/share/applications/overtake-image-viewer.desktop"
rm -f "$HOME/.local/share/applications/overtake-trash.desktop"
rm -f "$HOME/.local/bin/overtake" "$HYPR/overtake.lua" "$HYPR/overtake-classic.lua" "$HYPR/overtake-studio.lua"
rm -rf "${PLUGINS:?}/overtake.taskbar" "${PLUGINS:?}/overtake.workspaces" \
       "${PLUGINS:?}/overtake.bluetooth" "${PLUGINS:?}/overtake.audio" \
       "${PLUGINS:?}/overtake.notifications" "${PLUGINS:?}/overtake.notification-center" \
       "${PLUGINS:?}/overtake.battery" "${PLUGINS:?}/overtake.menubar" "${PLUGINS:?}/overtake.control-center" \
       "$HOME/.local/state/overtake" "$HOME/.cache/overtake"

if [[ $PURGE ]]; then
  rm -rf "$HOME/.config/overtake" "$HOME/Pictures/overtake"
fi

if [[ -z ${OVERTAKE_NO_RELOAD:-} ]] && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  omarchy-menu refresh >/dev/null 2>&1 || true
fi

if [[ $PURGE ]]; then echo "Overtake Mode removed. Settings and wallpapers removed too."
else echo "Overtake Mode removed. Your settings stay in ~/.config/overtake (./uninstall.sh --purge removes them)."; fi
