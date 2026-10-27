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
install -Dm644 "$REPO/hypr/overtake-classic.lua" "$HYPR/overtake-classic.lua"
install -Dm644 "$REPO/hypr/overtake-studio.lua" "$HYPR/overtake-studio.lua"
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
say "Hyprland: ~/.config/hypr/overtake{,-classic,-studio}.lua, plus marked blocks in bindings.lua and autostart.lua"

# 3. Shell plugins: the taskbar (Start menu, title bars, desktop icons,
#    Settings), three Omarchy bar widgets and Omarchy's notifications, copied
#    from this machine's Omarchy and patched. One whose patch no longer
#    applies is left out, and Overtake uses Omarchy's own one instead.
mkdir -p "$PLUGINS"
OWN_PLUGINS="overtake.taskbar overtake.notification-center overtake.menubar overtake.control-center"
for plugin in $OWN_PLUGINS; do
  rm -rf "${PLUGINS:?}/$plugin"
  cp -r "$REPO/plugins/$plugin" "$PLUGINS/$plugin"
done

build_widget() {  # build_widget <name> <source dir> <manifest> <files or dirs...>
  local name=$1 source=$2 manifest=$3; shift 3
  local target="$PLUGINS/overtake.$name"
  # An enabled copy whose rebuild fails below is removed; disable it first, so
  # Omarchy's own (which enabling the copy disabled) comes back. Not in a test
  # install (OVERTAKE_NO_RELOAD): `omarchy plugin` acts on the running shell
  # whatever HOME says, and disabling a bar widget swaps it back to Omarchy's
  # in the live bar.
  [[ -n ${OVERTAKE_NO_RELOAD:-} ]] || omarchy plugin disable "overtake.$name" >/dev/null 2>&1 || true
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
# Both stay enabled in either mode (they check it themselves), so switching
# modes needs no shell restart. The reload below picks them up.
if [[ -z ${OVERTAKE_NO_RELOAD:-} ]]; then
  for id in notifications battery; do
    [[ -d $PLUGINS/overtake.$id ]] && { omarchy plugin enable "overtake.$id" >/dev/null 2>&1 || true; }
  done
fi
say "plugins: ${OWN_PLUGINS// /, }"

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
for file in desktop-icons.txt no-controls.txt start-pinned.txt dock-pinned.txt; do
  [[ -e $CONFIG/$file ]] || cp "$REPO/config/$file" "$CONFIG/$file"
done
mkdir -p "$PICTURES/slideshow"
cp "$REPO"/wallpapers/*.png "$PICTURES/slideshow/"
mkdir -p "$PICTURES/studio"
for file in "$REPO"/wallpapers/studio/*; do
  [[ -f $file ]] && cp "$file" "$PICTURES/studio/"
done
# Studio's first drawn set, since dropped
for file in 1-mesa-day.png 2-mesa-night.png 3-ribbons.png 4-aurora.png 5-orbs.png 6-sunrise.png; do
  rm -f "${PICTURES:?}/studio/$file"
done
say "settings: ~/.config/overtake (existing files kept); wallpapers: ~/Pictures/overtake/{slideshow,studio}"
# previews for Style > Background, made now so its first opening doesn't wait
setsid "$HOME/.local/bin/overtake" bg-picker cache </dev/null >/dev/null 2>&1 &

# Trash as an app, so it can be found in Start, pinned to Start or the
# taskbar, and added back to the desktop after being removed from it.
APPS="$HOME/.local/share/applications"
mkdir -p "$APPS"
cat >"$APPS/overtake-trash.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Trash
Comment=Files you've deleted
Keywords=recycle;bin;deleted;
Exec=nautilus --new-window trash:///
Icon=user-trash
Type=Application
Terminal=false
Categories=System;FileTools;
DESKTOP

# Links clicked in other apps go through Omarchy's link handler, which hands
# them to the browser window used last, wherever it is. Route them through
# Overtake, which opens them on the workspace you're on (and, while the mode
# is off, passes them straight back to Omarchy's handler).
BROWSER_ENTRY="$APPS/omarchy-browser.desktop"
if [[ -f $BROWSER_ENTRY ]] && grep -q '^Exec=omarchy-launch-browser ' "$BROWSER_ENTRY"; then
  sed -i "s|^Exec=omarchy-launch-browser |Exec=$HOME/.local/bin/overtake open-url |" "$BROWSER_ENTRY"
  say "links: open on the workspace you're on"
fi

# Images open with their whole folder, so the arrow keys step through the
# others (imv-dir, which ships with imv). Only while images still open with
# Omarchy's imv; your own choice of viewer is left alone.
IMAGE_TYPES="image/png image/jpeg image/jpg image/gif image/bmp image/webp image/tiff image/avif image/heif image/jxl image/svg+xml"
if command -v imv-dir >/dev/null; then
  mkdir -p "$APPS"
  cat >"$APPS/overtake-image-viewer.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Image Viewer
Comment=Opens the image with the rest of its folder (left/right arrows step through them)
Exec=imv-dir %F
Icon=imv
Type=Application
Terminal=false
NoDisplay=true
Categories=Graphics;Viewer;
MimeType=image/png;image/jpeg;image/jpg;image/gif;image/bmp;image/webp;image/tiff;image/avif;image/heif;image/jxl;image/svg+xml;
DESKTOP
  for t in $IMAGE_TYPES; do
    current=$(xdg-mime query default "$t" 2>/dev/null || true)
    [[ -z $current || $current == imv.desktop ]] && xdg-mime default overtake-image-viewer.desktop "$t"
  done
  say "images: open with their folder (arrow keys step through them)"
fi

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
echo "Omarchy menu → Overtake Mode. Pick its look with \`overtake style classic|studio\`."
echo "Run \`overtake\` for everything else it can do."
