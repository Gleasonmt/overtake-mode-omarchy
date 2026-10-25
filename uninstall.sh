#!/bin/bash
# Remove Overtake Mode. Switches back to Omarchy first if the mode is on.
#
#   ./uninstall.sh          # keep your Overtake settings and wallpapers
#   ./uninstall.sh --purge  # remove those too

set -euo pipefail

PLUGINS="$HOME/.config/omarchy/plugins"
HYPR="$HOME/.config/hypr"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

if command -v overtake >/dev/null && [[ $(overtake status 2>/dev/null) == on ]]; then
  overtake off >/dev/null
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

# Hand notifications back to Omarchy's own before removing the patched copy.
omarchy plugin disable overtake.notifications >/dev/null 2>&1 || true
rm -f "$HOME/.local/bin/overtake" "$HYPR/overtake.lua"
rm -rf "${PLUGINS:?}/overtake.taskbar" "${PLUGINS:?}/overtake.workspaces" \
       "${PLUGINS:?}/overtake.bluetooth" "${PLUGINS:?}/overtake.audio" \
       "${PLUGINS:?}/overtake.notifications" "${PLUGINS:?}/overtake.notification-center" \
       "$HOME/.local/state/overtake"

if [[ ${1:-} == --purge ]]; then
  rm -rf "$HOME/.config/overtake" "$HOME/Pictures/overtake"
fi

if [[ -z ${OVERTAKE_NO_RELOAD:-} ]] && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  omarchy-menu refresh >/dev/null 2>&1 || true
fi

echo "Overtake Mode removed.${1:+ Settings and wallpapers removed too.}"
