#!/bin/bash
# Install (or update) Overtake Mode into the current user's Omarchy setup.
#
#   ./install.sh
#
# Safe to run again: files are replaced, the lines it adds to your Hyprland
# and menu config sit between ">>> overtake" / "<<< overtake" markers and are
# rewritten rather than duplicated, and your own Overtake settings
# (~/.config/overtake) are never overwritten.

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OMARCHY_PLUGINS=/usr/share/omarchy/shell/plugins
PLUGINS="$HOME/.config/omarchy/plugins"
HYPR="$HOME/.config/hypr"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
CONFIG="$HOME/.config/overtake"
PICTURES="$HOME/Pictures/overtake"

say() { printf '  %s\n' "$*"; }
die() { printf 'overtake install: %s\n' "$*" >&2; exit 1; }

command -v omarchy-version >/dev/null || die "Omarchy isn't installed (omarchy-version not found)."
for tool in jq python3 hyprctl; do
  command -v "$tool" >/dev/null || die "$tool is required."
done
[[ -d $OMARCHY_PLUGINS ]] || die "Omarchy's shell plugins weren't found in $OMARCHY_PLUGINS (Omarchy 4 is required)."

echo "Installing Overtake Mode (Omarchy) on Omarchy $(omarchy-version)"

# Replace the block between the markers in a file, or append it.
#   set_block <file> <comment prefix> <block text>
set_block() {
  local file=$1 prefix=$2 block=$3
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || touch "$file"
  python3 - "$file" "$prefix" "$block" <<'PY'
import sys, re
path, prefix, block = sys.argv[1:4]
start, end = f"{prefix} >>> overtake", f"{prefix} <<< overtake"
text = open(path).read()
new = f"{start} (managed by overtake-mode-omarchy/install.sh)\n{block.rstrip()}\n{end}\n"
pattern = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
if pattern.search(text):
    text = pattern.sub(lambda _: new, text, count=1)
else:
    text = text.rstrip("\n") + ("\n\n" if text.strip() else "") + new
open(path, "w").write(text)
PY
}

# 1. The command.
install -Dm755 "$REPO/bin/overtake" "$HOME/.local/bin/overtake"
say "command: ~/.local/bin/overtake"

# 2. Hyprland: the Overtake shortcuts file, the switch shortcut, and the login hook.
install -Dm644 "$REPO/hypr/overtake.lua" "$HYPR/overtake.lua"
set_block "$HYPR/bindings.lua" "--" '-- Overtake Mode: switch with SUPER+CTRL+SHIFT+W (or `overtake on|off|toggle`).
-- Its shortcuts load only while the mode is on.
o.bind("SUPER + CTRL + SHIFT + W", "Toggle Overtake Mode", "overtake toggle")
local overtake_flag = io.open((os.getenv("HOME") or "") .. "/.local/state/overtake/enabled", "r")
if overtake_flag then
  overtake_flag:close()
  dofile((os.getenv("HOME") or "") .. "/.config/hypr/overtake.lua")
end'
set_block "$HYPR/autostart.lua" "--" '-- Overtake Mode: restart its wallpaper slideshow after login if the mode is on.
o.launch_on_start("overtake resume")'
say "Hyprland: ~/.config/hypr/overtake.lua, plus marked blocks in bindings.lua and autostart.lua"

# 3. Shell plugins: the taskbar (Start menu, title bars, desktop icons,
#    Settings), three Omarchy bar widgets and Omarchy's notifications, copied
#    from this machine's Omarchy and patched. One whose patch no longer
#    applies is left out, and Overtake uses Omarchy's own one instead.
mkdir -p "$PLUGINS"
rm -rf "${PLUGINS:?}/overtake.taskbar" "${PLUGINS:?}/overtake.notification-center"
cp -r "$REPO/plugins/overtake.taskbar" "$PLUGINS/overtake.taskbar"
cp -r "$REPO/plugins/overtake.notification-center" "$PLUGINS/overtake.notification-center"

build_widget() {  # build_widget <name> <source dir> <manifest> <files or dirs...>
  local name=$1 source=$2 manifest=$3; shift 3
  local target="$PLUGINS/overtake.$name"
  # An enabled copy whose rebuild fails below is removed; disable it first, so
  # Omarchy's own (which enabling the copy disabled) comes back.
  omarchy plugin disable "overtake.$name" >/dev/null 2>&1 || true
  rm -rf "${target:?}"
  mkdir -p "$target"
  cp -L "$source/$manifest" "$target/manifest.json"
  local file
  for file in "$@"; do cp -rL "$source/$file" "$target/"; done
  jq --arg id "overtake.$name" --arg name "Overtake ${name^}" --arg from "omarchy.$name" '
    .id = $id | .name = $name
    | if (.barWidget | type) == "object" then .barWidget.displayName = $name else . end
    | .omarchy = ((if (.omarchy | type) == "object" then .omarchy else {} end) + { clonedFrom: $from })
    | del(.omarchy.clonePaths)' "$target/manifest.json" >"$target/manifest.json.tmp"
  mv "$target/manifest.json.tmp" "$target/manifest.json"
  if python3 "$REPO/patches/apply.py" "$name" "$target"; then
    say "widget: overtake.$name"
  else
    rm -rf "${target:?}"
    say "widget: overtake.$name skipped (this Omarchy's omarchy.$name changed; using it unpatched)"
  fi
}
build_widget workspaces "$OMARCHY_PLUGINS/bar/widgets" Workspaces.manifest.json Workspaces.qml
build_widget bluetooth "$OMARCHY_PLUGINS/panels/bluetooth" manifest.json Panel.qml Model.js
build_widget audio "$OMARCHY_PLUGINS/panels/audio" manifest.json Panel.qml Model.js
# Notifications with a close button; `overtake on` switches to it, `off` back.
build_widget notifications "$OMARCHY_PLUGINS/notifications" manifest.json Service.qml NotificationLogic.js components
# Battery service without Omarchy's 10% warning (Overtake's battery alerts replace it).
build_widget battery "$OMARCHY_PLUGINS/services/battery" manifest.json Service.qml BatteryModel.js
say "plugins: overtake.taskbar, overtake.notification-center"

# 4. The Omarchy menu entry (Overtake Mode, under the main menu).
mkdir -p "$(dirname "$MENU")"
[[ -s $MENU ]] || printf '{\n}\n' >"$MENU"
python3 - "$MENU" "$(cat "$REPO/menu/omarchy-menu.jsonc")" <<'PY'
import sys, re
path, block = sys.argv[1:3]
start, end = "  // >>> overtake", "  // <<< overtake"
text = open(path).read()
text = re.sub(re.escape(start) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
close = text.rstrip().rfind("}")
if close == -1:
    sys.exit("overtake install: can't find the closing } in " + path)
head = text[:close].rstrip()
# Drop commas an older install left after a comment (on its own line or on
# a marker line), then add one only if the last real entry lacks it.
head = re.sub(r"^\s*,\s*$\n?", "", head, flags=re.M)
head = re.sub(r"^(\s*//.*?),+\s*$", r"\1", head, flags=re.M).rstrip()
entries = [l for l in head.split("\n") if l.strip() and not l.strip().startswith("//")]
if entries and not entries[-1].rstrip().endswith(("{", ",")):
    head += ","
text = head + "\n" + start + " (managed by overtake-mode-omarchy/install.sh)\n" + block.rstrip() + "\n" + end + "\n}\n"
open(path, "w").write(text)
PY
say "menu: Overtake Mode in the Omarchy menu"

# 5. Your settings (only the ones you don't have yet) and the wallpapers.
mkdir -p "$CONFIG"
for file in desktop-icons.txt no-controls.txt start-pinned.txt; do
  [[ -e $CONFIG/$file ]] || cp "$REPO/config/$file" "$CONFIG/$file"
done
mkdir -p "$PICTURES/slideshow"
cp "$REPO"/wallpapers/*.png "$PICTURES/slideshow/"
say "settings: ~/.config/overtake (existing files kept); wallpapers: ~/Pictures/overtake/slideshow"

# 6. Load it all (OVERTAKE_NO_RELOAD=1 skips this, for testing).
if [[ -z ${OVERTAKE_NO_RELOAD:-} ]] && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  omarchy-menu refresh >/dev/null 2>&1 || true
  if [[ $("$HOME/.local/bin/overtake" status) == on ]]; then
    # Updating while the mode is on: switch off and on to pick up the new bar.
    overtake off >/dev/null && overtake on >/dev/null
  fi
fi

echo
echo "Done. Turn Overtake Mode on with SUPER+CTRL+SHIFT+W, \`overtake on\`, or"
echo "Omarchy menu → Overtake Mode. Run \`overtake\` for everything else it can do."
