#!/bin/bash
# Install (or update) Overtake Mode into the current user's Omarchy setup.
#
#   ./install.sh             # lists what it will change, then asks
#   ./install.sh --dry-run   # only lists what it would change
#   ./install.sh --yes       # doesn't ask (scripts, updates)
#
# Nothing is written before you say yes (or pass --yes). In Omarchy mode
# Omarchy runs as it ships: Overtake's changes apply in Classic and Studio.
#
# Safe to run again: files are replaced, the lines it adds to your Hyprland
# and menu config sit between ">>> overtake" / "<<< overtake" markers and are
# rewritten rather than duplicated, and your own Overtake settings
# (~/.config/overtake) are never overwritten.

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OMARCHY_PLUGINS=${OVERTAKE_OMARCHY_PLUGINS:-${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins}   # (the same setting bin/overtake reads)
PLUGINS="$HOME/.config/omarchy/plugins"
HYPR="$HOME/.config/hypr"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
CONFIG="$HOME/.config/overtake"
PICTURES="$HOME/Pictures/overtake"
APPS="$HOME/.local/share/applications"

say() { printf '  %s\n' "$*"; }
die() { printf 'overtake install: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  -n, --dry-run          list what would change; change nothing
  -y, --yes              don't ask
  -h, --help             show this
EOF
}

ASSUME_YES='' DRY_RUN=''
for arg in "$@"; do
  case $arg in
    -y|--yes) ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $arg" ;;
  esac
done

command -v omarchy-version >/dev/null || die "Omarchy isn't installed (omarchy-version not found)."
for tool in jq python3 hyprctl; do
  command -v "$tool" >/dev/null || die "$tool is required."
done
[[ -d $OMARCHY_PLUGINS ]] || die "Omarchy's shell plugins weren't found in $OMARCHY_PLUGINS (Omarchy 4.5 or later is required)."
OMARCHY_VERSION=$(omarchy-version 2>/dev/null || true)
[[ $(printf '%s\n' 4.5 "${OMARCHY_VERSION%%-*}" | sort -V | head -1) == 4.5 ]] ||
  die "Overtake Mode needs Omarchy 4.5 or later (this is ${OMARCHY_VERSION:-unknown}); run omarchy update first."
# A menu extension file of yours that isn't plain JSONC (starting with {) is
# left alone: stop now, before anything is written.
MENU_CHECK="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_FIRST=$(grep -m1 -v '^[[:space:]]*\(//.*\)\?$' "$MENU_CHECK" 2>/dev/null || true)   # (comments only: as good as empty)
if [[ -n $MENU_FIRST && ! $MENU_FIRST =~ ^[[:space:]]*\{ ]]; then
  die "$MENU_CHECK doesn't start with { ; fix it first (Overtake adds its menu entry there)."
fi

# Everything below is listed here first, before anything is written.
plan() {
  cat <<'EOF'
Overtake Mode will add (./uninstall.sh removes all of it):
  ~/.local/bin/overtake
  ~/.config/hypr/overtake.lua, overtake-classic.lua, overtake-studio.lua
  ~/.config/omarchy/plugins/overtake.*   its own plugins, plus patched copies of
                                          Omarchy's workspaces, bluetooth, audio,
                                          notifications and battery (made from
                                          your installed Omarchy; yours is untouched)
  ~/.local/share/applications/overtake-trash.desktop
  ~/.config/overtake/                     settings (only ones you don't have yet)
  ~/Pictures/overtake/                    wallpapers
  ~/.local/share/overtake/                a copy of the uninstaller (`overtake uninstall`)
                                          and of the patcher (patches/apply.py, NOTICE.md),
                                          and which version is installed
  ~/.config/omarchy/hooks/post-update.d/overtake.hook
                                          after `omarchy update`, rebuilds the patched
                                          copies from the new Omarchy (or drops one
                                          whose patch no longer fits)
  ~/.local/state/overtake/, ~/.cache/overtake/
                                          its state (yours only) and the Background lists
EOF
  cat <<'EOF'

and change (or create, if missing) these files (./uninstall.sh undoes each one):
  ~/.config/hypr/bindings.lua             a block between ">>> overtake" markers:
                                          the mode shortcut (Super+Ctrl+Shift+W),
                                          and loading Overtake's shortcuts while
                                          the mode is on
  ~/.config/hypr/autostart.lua            a marked block: at login, check and
                                          rebuild the patched copies, and resume the
                                          wallpaper slideshow if the mode is on
  ~/.config/omarchy/extensions/omarchy-menu.jsonc
                                          a marked block: the Overtake Mode entry
  ~/.config/omarchy/shell.json            only while Classic or Studio is on: its
                                          bar, and its notifications and battery
                                          copies in place of Omarchy's own; all put
                                          back when you switch to Omarchy
  (also only while Classic or Studio is on: a marked bar-size block in
  ~/.config/omarchy/shell.toml, GTK's title-bar buttons, and Omarchy's
  floating workspace layouts tiled; all put back when you switch to Omarchy)
EOF
  cat <<'EOF'

then reload Hyprland and restart the Omarchy shell.
EOF
}

plan
echo
if [[ $DRY_RUN ]]; then
  echo "Dry run: nothing was changed."
  exit 0
fi
if [[ -z $ASSUME_YES ]]; then
  [[ -t 0 ]] || die "can't ask without a terminal. Re-run with --yes to go ahead, or --dry-run to see the list."
  read -r -p "Go ahead? [y/N] " reply
  [[ $reply == [yY]* ]] || { echo "Nothing changed."; exit 1; }
  echo
fi

echo "Installing Overtake Mode (Omarchy) on Omarchy $(omarchy-version)"

# Replace the block between the markers in a file, or append it.
#   set_block <file> <comment prefix> <block text>
set_block() {
  local file=$1 prefix=$2 block=$3
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || touch "$file"
  python3 -I - "$file" "$prefix" "$block" <<'PY'
import sys, re
path, prefix, block = sys.argv[1:4]
start, end = f"{prefix} >>> overtake", f"{prefix} <<< overtake"
text = open(path, encoding="utf-8", errors="surrogateescape", newline="").read()
new = f"{start} (managed by overtake-mode-omarchy/install.sh)\n{block.rstrip()}\n{end}\n"
pattern = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
if pattern.search(text):
    text = pattern.sub(lambda _: new, text, count=1)
else:
    text = text.rstrip("\n") + ("\n\n" if text.strip() else "") + new
open(path, "w", encoding="utf-8", errors="surrogateescape", newline="").write(text)
PY
}

# Overtake's own folders are yours only (settings name your devices and apps;
# state names windows): made 0700, and any left open are tightened too. A symlinked folder is left as you set it up.
for dir in "$HOME/.local/state/overtake" "$HOME/.config/overtake" "${XDG_CACHE_HOME:-$HOME/.cache}/overtake"; do
  mkdir -p -m 700 "$dir"
  [[ -L $dir ]] || chmod 700 "$dir"
done
# on or off, for the plugins to watch (`overtake on|off` keeps it current)
if [[ -f $HOME/.local/state/overtake/enabled ]]; then echo on; else echo off; fi >"$HOME/.local/state/overtake/mode"

# 1. The command.
install -Dm755 "$REPO/bin/overtake" "$HOME/.local/bin/overtake"
# and the uninstaller, so `overtake uninstall` works without this folder
install -Dm755 "$REPO/uninstall.sh" "$HOME/.local/share/overtake/uninstall.sh"
# and the patcher, so the copies of Omarchy's plugins can be rebuilt after an update
install -Dm644 "$REPO/patches/apply.py" "$HOME/.local/share/overtake/apply.py"
install -Dm644 "$REPO/NOTICE.md" "$HOME/.local/share/overtake/NOTICE.md"
say "command: ~/.local/bin/overtake"

# 2. Hyprland: the Overtake shortcuts file, the switch shortcut, and the login hook.
# (files that weren't there go again on uninstall, if nothing else was added)
[[ -e $HYPR/bindings.lua ]] || touch "$HOME/.local/state/overtake/created-bindings"
[[ -e $HYPR/autostart.lua ]] || touch "$HOME/.local/state/overtake/created-autostart"
install -Dm644 "$REPO/hypr/overtake.lua" "$HYPR/overtake.lua"
install -Dm644 "$REPO/hypr/overtake-classic.lua" "$HYPR/overtake-classic.lua"
install -Dm644 "$REPO/hypr/overtake-studio.lua" "$HYPR/overtake-studio.lua"
set_block "$HYPR/bindings.lua" "--" '-- Overtake Mode: SUPER+CTRL+SHIFT+W goes to the next mode, Omarchy -> Classic -> Studio (or `overtake cycle|on|off`).
-- Its shortcuts load only while the mode is on.
o.bind("SUPER + CTRL + SHIFT + W", "Next desktop mode", "overtake cycle")
local overtake_flag = io.open((os.getenv("HOME") or "") .. "/.local/state/overtake/enabled", "r")
if overtake_flag then
  overtake_flag:close()
  dofile((os.getenv("HOME") or "") .. "/.config/hypr/overtake.lua")
end'
set_block "$HYPR/autostart.lua" "--" '-- Overtake Mode: at login, check and rebuild its patched copies of Omarchy plugins, and restart its wallpaper slideshow if the mode is on.
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

# The five patched copies (workspaces, bluetooth, audio; notifications with
# per-app settings, timed critical toasts and the notification center's
# remove / Clear all; battery without Omarchy's single 10% warning) are built by `overtake build-copies`
# (bin/overtake), which the post-update hook below runs again after every
# `omarchy update` (and `overtake resume` at login). One whose patch no longer
# fits is left out, and Omarchy's own is used.
OVERTAKE_OMARCHY_PLUGINS=$OMARCHY_PLUGINS "$HOME/.local/bin/overtake" build-copies all
mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
cat >"$HOME/.config/omarchy/hooks/post-update.d/overtake.hook" <<'EOF'
# Overtake Mode: rebuild its patched copies of Omarchy's plugins from the
# updated Omarchy (removed by Overtake's uninstall.sh).
if [ -x "$HOME/.local/bin/overtake" ]; then "$HOME/.local/bin/overtake" build-copies update; fi
EOF
say "hook: ~/.config/omarchy/hooks/post-update.d/overtake.hook"
# Which of Omarchy's own you had turned off yourself, so ./uninstall.sh leaves
# those off instead of turning them back on.
if [[ ! -e $HOME/.local/state/overtake/disabled-before ]]; then
  # (not one that Overtake's own copy switched off)
  jq -r '(if (.cloneSourceRestores | type) == "array" then .cloneSourceRestores else [] end) as $r
    | (.disabledPlugins // [])[] | select(. == "omarchy.notifications" or . == "omarchy.battery")
    | select(("overtake." + ltrimstr("omarchy.")) as $c | $r | index($c) | not)' \
    "$HOME/.config/omarchy/shell.json" >"$HOME/.local/state/overtake/disabled-before" 2>/dev/null || true
fi
# Omarchy's own notifications and battery run in Omarchy mode; Overtake's
# copies are switched in only while Classic or Studio is on.
if [[ -f $HOME/.local/state/overtake/enabled ]]; then
  "$HOME/.local/bin/overtake" copies on
else
  "$HOME/.local/bin/overtake" copies off   # (in shell.json itself if no shell is running)
fi
say "plugins: ${OWN_PLUGINS// /, }"

# 4. The Omarchy menu entry (Overtake Mode, under the main menu).
mkdir -p "$(dirname "$MENU")"
if [[ ! -s $MENU ]]; then
  printf '{\n}\n' >"$MENU"
  touch "$HOME/.local/state/overtake/created-menu"   # so uninstall.sh removes it again
fi
MENU_BLOCK=$(cat "$REPO/menu/omarchy-menu.jsonc")
python3 -I - "$MENU" "$MENU_BLOCK" <<'PY'
import sys, re
path, block = sys.argv[1:3]
start, end = "  // >>> overtake", "  // <<< overtake"
text = open(path, encoding="utf-8", errors="surrogateescape", newline="").read()
text = re.sub(re.escape(start) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
# Right after the opening { (yours stay below it, so an entry of yours with the
# same id still wins), each line ending in a comma, which Omarchy's JSONC
# reader allows before the }. Nothing of yours is touched.
lines = text.split("\n")
first = next((i for i, l in enumerate(lines) if l.strip() and not l.strip().startswith("//")), None)
if first is None:   # only comments (or nothing): an empty menu, as Omarchy reads it
    while lines and lines[-1] == "":
        lines.pop()
    lines += ["{", "}", ""]
    first = len(lines) - 3
if not lines[first].strip().startswith("{"):
    sys.exit("overtake install: " + path + " doesn't start with {")
block = block.rstrip()
if not block.endswith(","):
    block += ","
opening = lines[first].strip()
lines[first:first + 1] = ["{", start + " (managed by overtake-mode-omarchy/install.sh)", block, end] + \
    (["  " + opening[1:].strip()] if opening[1:].strip() else [])
text = "\n".join(lines)
open(path, "w", encoding="utf-8", errors="surrogateescape", newline="").write(text)
PY
say "menu: Overtake Mode in the Omarchy menu"

# 5. Your settings (only the ones you don't have yet) and the wallpapers.
mkdir -p -m 700 "$CONFIG"
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

# Trash as an app, so it can be found in Start, pinned to Start or the
# taskbar, and added back to the desktop after being removed from it.
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

# Which version is now installed, for the root plugin (Setup.qml): after
# `omarchy plugin update` it asks for this installer to be run again. Written
# last, so an install that stopped halfway still asks, and before the shell
# restarts below.
jq -r '.version' "$REPO/manifest.json" >"$HOME/.local/share/overtake/version"

# 6. Load it all (OVERTAKE_NO_RELOAD=1 skips this, for testing).
if [[ -z ${OVERTAKE_NO_RELOAD:-} ]] && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  omarchy-menu refresh >/dev/null 2>&1 || true
  if [[ $("$HOME/.local/bin/overtake" status) == on ]]; then
    # Updating while the mode is on: switch off and on to pick up the new bar.
    "$HOME/.local/bin/overtake" off >/dev/null && "$HOME/.local/bin/overtake" on >/dev/null
  fi
fi

echo
echo "Done. Turn Overtake Mode on with SUPER+CTRL+SHIFT+W (next mode each press), \`overtake on\`, or"
echo "Omarchy menu → Overtake Mode. Pick its look with \`overtake style classic|studio\`."
echo "Run \`overtake\` for everything else it can do."
