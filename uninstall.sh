#!/bin/bash
# Remove Overtake Mode. Switches back to Omarchy first if the mode is on.
#
#   ./uninstall.sh          # keep your Overtake settings and wallpapers
#   ./uninstall.sh --purge  # remove those too

set -euo pipefail

PLUGINS="$HOME/.config/omarchy/plugins"
HYPR="$HOME/.config/hypr"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

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

# The taller-taskbar block Overtake adds to shell.toml
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
if [[ ${1:-} != --purge && -f $HOME/.local/state/overtake/taskbar-settings.json ]]; then
  mkdir -p "$HOME/.config/overtake"
  cp "$HOME/.local/state/overtake/taskbar-settings.json" "$HOME/.config/overtake/taskbar-settings.json"
fi
rm -f "$HOME/.local/bin/overtake" "$HYPR/overtake.lua"
rm -rf "${PLUGINS:?}/overtake.taskbar" "${PLUGINS:?}/overtake.workspaces" \
       "${PLUGINS:?}/overtake.bluetooth" "${PLUGINS:?}/overtake.audio" \
       "${PLUGINS:?}/overtake.notifications" "${PLUGINS:?}/overtake.notification-center" \
       "${PLUGINS:?}/overtake.battery" \
       "$HOME/.local/state/overtake" "$HOME/.cache/overtake"

if [[ ${1:-} == --purge ]]; then
  rm -rf "$HOME/.config/overtake" "$HOME/Pictures/overtake"
fi

if [[ -z ${OVERTAKE_NO_RELOAD:-} ]] && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  omarchy-menu refresh >/dev/null 2>&1 || true
fi

if [[ ${1:-} == --purge ]]; then echo "Overtake Mode removed. Settings and wallpapers removed too."
else echo "Overtake Mode removed. Your settings stay in ~/.config/overtake (./uninstall.sh --purge removes them)."; fi
