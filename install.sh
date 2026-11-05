#!/bin/bash
# Install (or update) Overtake Mode into the current user's Omarchy setup.
#
#   ./install.sh             # asks about the optional extras, lists what it will change, then asks
#   ./install.sh --dry-run   # only lists what it would change
#   ./install.sh --yes       # doesn't ask (scripts, updates); extras stay as they are
#
# Nothing is written before you say yes (or pass --yes). The optional extras
# (link handler, image viewer, Style menus, name tags) are off unless you
# choose them; an update keeps your earlier choices.
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
APPS="$HOME/.local/share/applications"
BROWSER_ENTRY="$APPS/omarchy-browser.desktop"

say() { printf '  %s\n' "$*"; }
die() { printf 'overtake install: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  -n, --dry-run          list what would change; change nothing
  -y, --yes              don't ask (the extras stay as they are; off on a
                         first install)

Optional extras, each off unless chosen (asked when run in a terminal):
      --link-handler     links clicked in other apps open on the workspace
                         you're on (changes omarchy-browser.desktop)
      --image-viewer     images open with their whole folder in imv-dir
                         (changes your default image viewer)
      --style-menus      Overtake's Style > Background (every theme's
                         wallpapers) and Style > Theme in the Omarchy menu,
                         in every mode
      --name-tags        name tags on Claude Code windows, in every mode
                         (reads ~/.claude/sessions), and Super+Alt+N
      --no-link-handler, --no-image-viewer, --no-style-menus, --no-name-tags
                         turn one off (an update removes it)
  -h, --help             show this
EOF
}

ASSUME_YES='' DRY_RUN='' LINKS='' IMAGES='' STYLE_MENUS='' NAME_TAGS=''
for arg in "$@"; do
  case $arg in
    -y|--yes) ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --link-handler) LINKS=yes ;;
    --no-link-handler) LINKS=no ;;
    --image-viewer) IMAGES=yes ;;
    --no-image-viewer) IMAGES=no ;;
    --style-menus) STYLE_MENUS=yes ;;
    --no-style-menus) STYLE_MENUS=no ;;
    --name-tags) NAME_TAGS=yes ;;
    --no-name-tags) NAME_TAGS=no ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $arg" ;;
  esac
done

command -v omarchy-version >/dev/null || die "Omarchy isn't installed (omarchy-version not found)."
for tool in jq python3 hyprctl; do
  command -v "$tool" >/dev/null || die "$tool is required."
done
[[ -d $OMARCHY_PLUGINS ]] || die "Omarchy's shell plugins weren't found in $OMARCHY_PLUGINS (Omarchy 4 is required)."

# The optional extras. Each is off unless chosen; an update keeps what's
# installed now. Choosing one off that's on now takes it back out.
have_links() { [[ -f $BROWSER_ENTRY ]] && grep -q '^Exec=.*/overtake open-url ' "$BROWSER_ENTRY"; }
have_images() { [[ -s $HOME/.local/state/overtake/image-defaults || -f $APPS/overtake-image-viewer.desktop ]]; }
have_style_menus() { [[ -f $MENU ]] && grep -q '"style.background".*overtake bg-picker' "$MENU"; }
have_name_tags() { [[ -d $PLUGINS/overtake.session-names ]]; }
ask_extra() {  # ask_extra <current yes|no> <question>
  local reply hint="[y/N]"
  [[ $1 == yes ]] && hint="[Y/n]"
  read -r -p "$2 $hint " reply
  if [[ -z $reply ]]; then echo "$1"; elif [[ $reply == [yY]* ]]; then echo yes; else echo no; fi
}
choose() {  # choose <flag value> <have function> <question>: yes or no
  local now=no
  "$2" && now=yes
  if [[ -n $1 ]]; then echo "$1"
  elif [[ -z $ASSUME_YES && -z $DRY_RUN && -t 0 ]]; then ask_extra "$now" "$3"
  else echo "$now"
  fi
}
[[ -n $ASSUME_YES || -n $DRY_RUN || ! -t 0 ]] || echo "Optional extras (each is off unless you say yes):"
LINKS=$(choose "$LINKS" have_links "  Open links from other apps on the workspace you're on (changes omarchy-browser.desktop)?")
IMAGES=$(choose "$IMAGES" have_images "  Open images with their whole folder in imv-dir (changes your default image viewer)?")
STYLE_MENUS=$(choose "$STYLE_MENUS" have_style_menus "  Use Overtake's Style > Background and Style > Theme in the Omarchy menu, in every mode?")
NAME_TAGS=$(choose "$NAME_TAGS" have_name_tags "  Name tags on Claude Code windows in every mode (reads ~/.claude/sessions), and Super+Alt+N?")
[[ -n $ASSUME_YES || -n $DRY_RUN || ! -t 0 ]] || echo

# Which of them change something on this machine.
CHANGE_LINKS='' CHANGE_IMAGES=''
if [[ $LINKS == yes && -f $BROWSER_ENTRY ]] && grep -q '^Exec=omarchy-launch-browser ' "$BROWSER_ENTRY"; then
  CHANGE_LINKS=1
fi
if [[ $IMAGES == yes ]] && command -v imv-dir >/dev/null; then
  CHANGE_IMAGES=1
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
                                          and of the patcher (patches/apply.py, NOTICE.md)
  ~/.config/omarchy/hooks/post-update.d/overtake.hook
                                          after `omarchy update`, rebuilds the patched
                                          copies from the new Omarchy (or drops one
                                          whose patch no longer fits)
  ~/.local/state/overtake/, ~/.cache/overtake/
                                          its state (yours only) and picture previews
EOF
  [[ $NAME_TAGS == yes ]] && echo "  ~/.config/omarchy/plugins/overtake.session-names   name tags on Claude Code windows"
  [[ $CHANGE_IMAGES ]] && echo "  ~/.local/share/applications/overtake-image-viewer.desktop"
  cat <<'EOF'

and change files you already have (./uninstall.sh undoes each one):
  ~/.config/hypr/bindings.lua             a block between ">>> overtake" markers:
                                          the mode shortcut (Super+Ctrl+Shift+W),
                                          and loading Overtake's shortcuts while
                                          the mode is on
  ~/.config/hypr/autostart.lua            a marked block: resume the wallpaper
                                          slideshow at login if the mode is on
  ~/.config/omarchy/extensions/omarchy-menu.jsonc
                                          a marked block: the Overtake Mode entry
  ~/.config/omarchy/shell.json            enables overtake.notifications and
                                          overtake.battery in place of Omarchy's
                                          own (Omarchy turns its own off while a
                                          copy is on, in every mode; while the mode
                                          is off they act like Omarchy's own)
EOF
  [[ $NAME_TAGS == yes ]] && echo "                                          and overtake.session-names; Super+Alt+N in bindings.lua"
  [[ $STYLE_MENUS == yes ]] && cat <<'EOF'
  omarchy-menu.jsonc (same marked block)  Style > Background and Style > Theme,
                                          replaced in every mode
EOF
  [[ $CHANGE_LINKS ]] && cat <<'EOF'
  ~/.local/share/applications/omarchy-browser.desktop
                                          links clicked in other apps open on the
                                          workspace you're on
EOF
  [[ $CHANGE_IMAGES ]] && cat <<'EOF'
  default image viewer (xdg-mime)         only for image types that open with imv
                                          or nothing: imv-dir, so the arrow keys
                                          step through the folder
EOF
  local off=()
  [[ $LINKS == no ]] && have_links && off+=("the link handler")
  [[ $IMAGES == no ]] && have_images && off+=("the image viewer")
  [[ $STYLE_MENUS == no ]] && have_style_menus && off+=("the Style menus")
  [[ $NAME_TAGS == no ]] && have_name_tags && off+=("the name tags")
  if (( ${#off[@]} )); then
    echo
    local list
    printf -v list '%s, ' "${off[@]}"
    echo "and take back out, as you chose: ${list%, }"
  fi
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

# Overtake's state (window names, Claude Code session ids, layouts) is yours
# alone: an older install made the folder readable by others.
mkdir -p -m 700 "$HOME/.local/state/overtake"
chmod 700 "$HOME/.local/state/overtake"
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
install -Dm644 "$REPO/hypr/overtake.lua" "$HYPR/overtake.lua"
install -Dm644 "$REPO/hypr/overtake-classic.lua" "$HYPR/overtake-classic.lua"
install -Dm644 "$REPO/hypr/overtake-studio.lua" "$HYPR/overtake-studio.lua"
NAME_TAG_BIND=""
[[ $NAME_TAGS == yes ]] && NAME_TAG_BIND='
-- Name tags: name the focused window (a Claude Code window keeps it with its session).
o.bind("SUPER + ALT + N", "Name window", "overtake rename")'
set_block "$HYPR/bindings.lua" "--" '-- Overtake Mode: SUPER+CTRL+SHIFT+W goes to the next mode, Omarchy -> Classic -> Studio (or `overtake cycle|on|off`).
-- Its shortcuts load only while the mode is on.
o.bind("SUPER + CTRL + SHIFT + W", "Next desktop mode", "overtake cycle")'"$NAME_TAG_BIND"'
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
if [[ $NAME_TAGS == yes ]]; then
  OWN_PLUGINS+=" overtake.session-names"
elif [[ -d $PLUGINS/overtake.session-names ]]; then
  # name tags chosen off: out again (not in a test install: `omarchy plugin` acts on the running shell)
  [[ -n ${OVERTAKE_NO_RELOAD:-} ]] || omarchy plugin disable overtake.session-names >/dev/null 2>&1 || true
  rm -rf "${PLUGINS:?}/overtake.session-names"
fi
for plugin in $OWN_PLUGINS; do
  rm -rf "${PLUGINS:?}/$plugin"
  cp -r "$REPO/plugins/$plugin" "$PLUGINS/$plugin"
done

# The five patched copies (workspaces, bluetooth, audio; notifications with a
# close button and the notification center's history; battery without
# Omarchy's single 10% warning) are built by `overtake build-copies`
# (bin/overtake), which the post-update hook below runs again after every
# `omarchy update`. One whose patch no longer fits is left out, and Omarchy's
# own is used.
OVERTAKE_OMARCHY_PLUGINS=$OMARCHY_PLUGINS "$HOME/.local/bin/overtake" build-copies all
mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
cat >"$HOME/.config/omarchy/hooks/post-update.d/overtake.hook" <<'EOF'
# Overtake Mode: rebuild its patched copies of Omarchy's plugins from the
# updated Omarchy (removed by Overtake's uninstall.sh).
[ -x "$HOME/.local/bin/overtake" ] && "$HOME/.local/bin/overtake" build-copies update
EOF
say "hook: ~/.config/omarchy/hooks/post-update.d/overtake.hook"
# Both stay enabled in either mode (they check it themselves), so switching
# modes needs no shell restart. The reload below picks them up. So do the
# name tags on Claude Code windows (overtake.session-names).
# Turn a plugin on through the running shell. Just after its files are
# written the shell may not know it yet ("not known"): ask it to look again and
# retry for a few seconds rather than fail quietly.
enable_plugin() {
  local id=$1 out="" i
  for i in $(seq 15); do
    out=$(omarchy plugin enable "$id" 2>&1) && return 0
    [[ $out == *"not known"* ]] || break
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    sleep 0.2
  done
  say "couldn't turn on $id (${out:-no reply from the shell}); afterwards run: omarchy plugin enable $id"
  return 0
}

# Which of Omarchy's own you had turned off yourself, so ./uninstall.sh leaves
# those off instead of turning them back on.
if [[ ! -e $HOME/.local/state/overtake/disabled-before ]]; then
  jq -r '(.disabledPlugins // [])[] | select(. == "omarchy.notifications" or . == "omarchy.battery")' \
    "$HOME/.config/omarchy/shell.json" >"$HOME/.local/state/overtake/disabled-before" 2>/dev/null || true
fi
if [[ -z ${OVERTAKE_NO_RELOAD:-} ]]; then
  for id in notifications battery $([[ $NAME_TAGS == yes ]] && echo session-names || true); do
    [[ -d $PLUGINS/overtake.$id ]] && enable_plugin "overtake.$id"
  done
fi
say "plugins: ${OWN_PLUGINS// /, }"

# 4. The Omarchy menu entry (Overtake Mode, under the main menu).
mkdir -p "$(dirname "$MENU")"
if [[ ! -s $MENU ]]; then
  printf '{\n}\n' >"$MENU"
  touch "$HOME/.local/state/overtake/created-menu"   # so uninstall.sh removes it again
fi
MENU_BLOCK=$(cat "$REPO/menu/omarchy-menu.jsonc")
[[ $STYLE_MENUS == yes ]] && MENU_BLOCK+=$'\n'$(cat "$REPO/menu/style-menus.jsonc")
python3 - "$MENU" "$MENU_BLOCK" <<'PY'
import sys, re
path, block = sys.argv[1:3]
start, end = "  // >>> overtake", "  // <<< overtake"
text = open(path).read()
text = re.sub(re.escape(start) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
# Right after the opening { (yours stay below it, so an entry of yours with the
# same id still wins), each line ending in a comma, which Omarchy's JSONC
# reader allows before the }. Nothing of yours is touched.
lines = text.split("\n")
first = next((i for i, l in enumerate(lines) if l.strip() and not l.strip().startswith("//")), None)
if first is None or not lines[first].strip().startswith("{"):
    sys.exit("overtake install: " + path + " doesn't start with {")
block = block.rstrip()
if not block.endswith(","):
    block += ","
opening = lines[first].strip()
lines[first:first + 1] = ["{", start + " (managed by overtake-mode-omarchy/install.sh)", block, end] + \
    (["  " + opening[1:].strip()] if opening[1:].strip() else [])
text = "\n".join(lines)
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
# previews for Style > Background, made now (by Omarchy's omarchy-menu-images,
# in its own cache) so the first opening doesn't wait
setsid "$HOME/.local/bin/overtake" bg-picker cache </dev/null >/dev/null 2>&1 &

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

# Links clicked in other apps go through Omarchy's link handler, which hands
# them to the browser window used last, wherever it is. Route them through
# Overtake, which opens them on the workspace you're on (and, while the mode
# is off, passes them straight back to Omarchy's handler). --no-link-handler skips it.
if [[ $CHANGE_LINKS ]]; then
  bin_escaped=$(printf '%s' "$HOME/.local/bin/overtake" | sed 's/[\\|&]/\\&/g')   # (for sed's replacement)
  sed -i "s|^Exec=omarchy-launch-browser |Exec=$bin_escaped open-url |" "$BROWSER_ENTRY"
  say "links: open on the workspace you're on"
elif [[ $LINKS == no ]] && have_links; then
  sed -i 's|^Exec=.*/overtake open-url |Exec=omarchy-launch-browser |' "$BROWSER_ENTRY"
  say "links: back to Omarchy's own handler"
fi

# Images open with their whole folder, so the arrow keys step through the
# others (imv-dir, which ships with imv). Only while images still open with
# Omarchy's imv; your own choice of viewer is left alone. --no-image-viewer skips it.
IMAGE_DEFAULTS="$HOME/.local/state/overtake/image-defaults"
MIMEAPPS="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
IMAGE_TYPES="image/png image/jpeg image/jpg image/gif image/bmp image/webp image/tiff image/avif image/heif image/jxl image/svg+xml"
if [[ $CHANGE_IMAGES ]]; then
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
    [[ -z $current || $current == imv.desktop ]] || continue
    # your own setting for it in mimeapps.list (often none: imv is the
    # system's), so ./uninstall.sh can put exactly that back
    grep -q "^$t	" "$IMAGE_DEFAULTS" 2>/dev/null ||
      printf '%s\t%s\n' "$t" "$(awk -v t="$t" '/^\[/ { s = ($0 == "[Default Applications]") } s && index($0, t "=") == 1 { print substr($0, length(t) + 2); exit }' "$MIMEAPPS" 2>/dev/null)" >>"$IMAGE_DEFAULTS"
    xdg-mime default overtake-image-viewer.desktop "$t"
  done
  say "images: open with their folder (arrow keys step through them)"
elif [[ $IMAGES == no ]] && have_images; then
  # chosen off: each type back to what opened it before (as ./uninstall.sh does)
  for t in $IMAGE_TYPES; do
    [[ $(xdg-mime query default "$t" 2>/dev/null) == overtake-image-viewer.desktop ]] || continue
    before=""
    [[ -f $IMAGE_DEFAULTS ]] && before=$(awk -F'\t' -v t="$t" '$1 == t { print $2; exit }' "$IMAGE_DEFAULTS")
    tmp=$(mktemp "$MIMEAPPS.XXXXXX")
    awk -v t="$t" -v before="$before" '
      /^\[/ { s = ($0 == "[Default Applications]") }
      s && index($0, t "=overtake-image-viewer.desktop") == 1 { if (before != "") print t "=" before; next }
      { print }' "$MIMEAPPS" >"$tmp" && cat "$tmp" >"$MIMEAPPS"
    rm -f "$tmp"
  done
  rm -f "$APPS/overtake-image-viewer.desktop" "$IMAGE_DEFAULTS"
  say "images: back to what opened them before"
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
echo "Done. Turn Overtake Mode on with SUPER+CTRL+SHIFT+W (next mode each press), \`overtake on\`, or"
echo "Omarchy menu → Overtake Mode. Pick its look with \`overtake style classic|studio\`."
echo "Run \`overtake\` for everything else it can do."
