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
    (a file of these it created goes if nothing else was added)
  make sure Omarchy's own notifications and battery run (shell.json; any
    you had turned off yourself stay off)
  put back your own screensaver art, if what's there now is what Overtake wrote
  delete ~/.local/bin/overtake, ~/.config/hypr/overtake*.lua, its Omarchy
    post-update hook (hooks/post-update.d/overtake.hook),
    ~/.config/omarchy/plugins/overtake.*, its .desktop file,
    ~/.local/share/overtake, ~/.local/state/overtake and ~/.cache/overtake
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
overtake_bar() {  # Overtake's bar in shell.json, even if a switch failed halfway
  jq -e '[.bar | .. | .id? // empty] | (index("overtake.taskbar") or index("overtake.menubar"))' \
    "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1
}
if [[ -f $HOME/.local/state/overtake/enabled || -f $HOME/.local/state/overtake/switching-off ]] || overtake_bar; then
  if ! [[ -x $OVERTAKE ]] || ! "$OVERTAKE" off >/dev/null; then
    echo "Couldn't switch Overtake Mode off; nothing removed. Fix that first (overtake off)." >&2
    exit 1
  fi
fi

# The same Python as install.sh's: see there.
FILE_PY=$(cat <<'PY'
import os, re, sys, tempfile

def read_file(path):
    return open(path, encoding="utf-8", errors="surrogateescape", newline="").read()

def replace_file(path, text):
    target = os.path.realpath(path)
    try:
        mode = os.stat(target).st_mode & 0o7777
        fd, temp = tempfile.mkstemp(prefix=os.path.basename(target) + ".", dir=os.path.dirname(target))
        try:
            with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
                f.write(text)
                f.flush()
                os.fsync(f.fileno())
                os.fchmod(f.fileno(), mode)
            os.replace(temp, target)
        except BaseException:
            os.unlink(temp)
            raise
    except OSError as e:
        sys.exit(f"overtake: couldn't write {path}: {e.strerror}; it was left as it was")

def without_block(text, prefix):
    start, end = re.escape(f"{prefix} >>> overtake"), re.escape(f"{prefix} <<< overtake")
    while True:
        # (never past another start: one with its end missing, and your lines after it, stay)
        m = re.search(start + r"([^\n]*)\n(?:(?!" + start + r").)*?" + end + r"\n?", text, re.S)
        if not m:
            return text
        how, before, after = m.group(1), text[:m.start()], text[m.end():]
        joined, braces = re.search(r"joined (\d+)", how), re.search(r"braces (\d+)", how)
        if "same-line" in how:
            before = before.removesuffix("\n")
        elif braces:
            if before.endswith("{\n") and after.lstrip(" ").startswith("}"):
                before = before[:-2]
                after = after.lstrip(" ")[1:].removeprefix("\n")
                before = before.removesuffix("\n" * int(braces.group(1)))
        elif joined:
            before = before.removesuffix("\n" * int(joined.group(1)))
            if after and before and not before.endswith("\n"):
                before += "\n"   # (what you added below it stays on its own line)
        else:   # from an earlier version, which didn't say
            before, after = before.rstrip("\n") + "\n", after
        text = before + after
PY
)
run_py() { { printf '%s\n' "$FILE_PY"; cat; } | python3 -I - "$@"; }

remove_block() {  # remove_block <file> <comment prefix>
  [[ -f $1 ]] || return 0
  run_py "$1" "$2" <<'PY'
path, prefix = sys.argv[1:3]
text = read_file(path)
new = without_block(text, prefix)
if new != text:
    replace_file(path, new)
PY
}
# Hand notifications and battery back to Omarchy's own before removing the
# patched copies. Disabling goes through the shell; if it isn't running, edit
# shell.json directly so Omarchy's own aren't left disabled. Not in a test
# uninstall (OVERTAKE_NO_RELOAD): `omarchy plugin` acts on the running shell
# whatever HOME says.
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [[ -z ${OVERTAKE_NO_RELOAD:-} ]]; then
  for id in overtake.notifications overtake.battery; do
    # (only one recorded there: any change makes the shell write out its whole
    # config, a full bar included, and the lines below hand the rest back)
    if jq -e --arg id "$id" '[(.plugins | arrays | .[] | if type == "object" then .id else . end), (.cloneSourceRestores | arrays | .[])] | index($id) != null' "$SHELL_JSON" >/dev/null 2>&1; then
      omarchy plugin disable "$id" >/dev/null 2>&1 || true
    fi
  done
fi
# Omarchy's own is turned back on only where Overtake's copy switched it off
# (Omarchy's record of that: the copy in cloneSourceRestores, which it doesn't
# set for one that was off already). One you turned off yourself stays off.
if [[ -f $SHELL_JSON ]]; then
  # (written next to the real file, the link's target if it's a symlink, and
  # renamed over it, keeping its mode)
  target=$(readlink -f "$SHELL_JSON")
  tmp=$(mktemp "$target.XXXXXX")
  if jq '(if (.cloneSourceRestores | type) == "array" then .cloneSourceRestores else [] end) as $restores
      # (an Overtake widget put on your own bar: its Omarchy original, or none)
      | (if (.bar.layout | type) == "object" then .bar.layout |= map_values(if type == "array" then map(
          if type == "object" and (.id | type) == "string" and (.id | startswith("overtake.")) then
            . as $w | if ["workspaces", "bluetooth", "audio", "battery"] | index($w.id | ltrimstr("overtake.")) then .id |= "omarchy." + ltrimstr("overtake.") else empty end
          else . end) else . end) else . end)
      | (if (.plugins | type) == "array" then .plugins |= map(select((if type == "object" then .id else . end) | tostring | startswith("overtake.") | not)) else . end)
      | (if (.disabledPlugins | type) == "array" then .disabledPlugins |= map(select((tostring | startswith("overtake.") | not) and (. as $id | (type == "string" and startswith("omarchy.") and ($restores | index("overtake." + ($id | ltrimstr("omarchy."))) != null)) | not))) else . end)
      | (if (.cloneSourceRestores | type) == "array" then .cloneSourceRestores |= map(select(tostring | startswith("overtake.") | not)) else . end)
      | (if .disabledPlugins == [] then del(.disabledPlugins) else . end)
      | (if .cloneSourceRestores == [] then del(.cloneSourceRestores) else . end)' \
      "$SHELL_JSON" >"$tmp"; then
    if jq -e --slurpfile new "$tmp" '. == $new[0]' "$SHELL_JSON" >/dev/null 2>&1; then
      rm -f "$tmp"
    else
      chmod --reference="$target" "$tmp" 2>/dev/null || true
      mv -f "$tmp" "$target"   # (only when something changed)
    fi
  else
    # (invalid, or no room: nothing of Overtake's has gone yet, including what
    # can repair this at login)
    rm -f "$tmp"
    echo "Couldn't update $SHELL_JSON, so Omarchy's own notifications and battery may stay off; nothing more removed. Fix that and run this again." >&2
    exit 1
  fi
fi

# Overtake's marked blocks, now that shell.json is handled (one of them is what
# repairs things at login).
remove_block "$HYPR/bindings.lua" "--"
remove_block "$HYPR/autostart.lua" "--"
remove_block "$MENU" "  //"
# the menu file, if install.sh created it and nothing else was added since
if [[ -f $HOME/.local/state/overtake/created-menu && -f $MENU && -z $(tr -d '{} \n\t' <"$MENU") ]]; then
  rm -f "$MENU"
fi
# and the Hyprland files it had to create, if it left them with nothing in them
remove_if_created() {  # remove_if_created <file> <marker>
  if [[ -f $HOME/.local/state/overtake/$2 && -f $1 && ! -L $1 && -z $(tr -d '[:space:]' <"$1") ]]; then
    rm -f "$1"
  fi
}
remove_if_created "$HYPR/bindings.lua" created-bindings
remove_if_created "$HYPR/autostart.lua" created-autostart

# The bar-size block Overtake adds to shell.toml
SHELL_TOML="$HOME/.config/omarchy/shell.toml"
if [[ -f $SHELL_TOML ]]; then
  run_py "$SHELL_TOML" "$([[ -f $HOME/.local/state/overtake/shell-toml-no-newline ]] && echo 1)" <<'PY'
path, no_newline = sys.argv[1:3]
text = read_file(path)
new = re.sub(r"# >>> overtake[^\n]*\n(?:(?!# >>> overtake).)*?# <<< overtake\n?", "", text, flags=re.S)
if new != text:
    replace_file(path, new.removesuffix("\n") if no_newline else new)
PY
  # (the file goes if Overtake created it and nothing else was added)
  if [[ -f $HOME/.local/state/overtake/created-shell-toml && ! -L $SHELL_TOML && -z $(tr -d '[:space:]' <"$SHELL_TOML") ]]; then
    rm -f "$SHELL_TOML"
  fi
fi

# Taskbar pins live with the state; keep them unless purging.
if [[ -z $PURGE && -f $HOME/.local/state/overtake/taskbar-settings.json ]]; then
  mkdir -p -m 700 "$HOME/.config/overtake"
  cp "$HOME/.local/state/overtake/taskbar-settings.json" "$HOME/.config/overtake/taskbar-settings.json"
fi
rm -f "$HOME/.local/share/applications/overtake-trash.desktop"
rm -f "$HOME/.config/omarchy/hooks/post-update.d/overtake.hook"
# Screensaver art you had before Overtake replaced it, if what's there now is
# what Overtake wrote. Art you wrote or picked stays, with your old art kept
# beside it.
art="$HOME/.config/omarchy/branding/screensaver.txt"
written="$HOME/.local/state/overtake/screensaver-art-written"
if [[ ! -e $art ]] || [[ -f $written && $(sha256sum <"$art") == "$(<"$written")" ]]; then
  [[ -f $art.before-overtake ]] && mv -f "$art.before-overtake" "$art"
  # (or none at all, as it was)
  [[ -f $HOME/.local/state/overtake/screensaver-art-absent ]] && rm -f "$art"
elif [[ -f $art.before-overtake ]]; then
  echo "Kept your current screensaver art; the one from before Overtake is $art.before-overtake"
fi
rm -f "$HOME/.local/bin/overtake" "$HYPR/overtake.lua" "$HYPR/overtake-classic.lua" "$HYPR/overtake-studio.lua"
# (and temp files of Overtake's own, if an install was killed partway)
rm -f "$HOME/.local/bin"/.overtake-tmp.* "$HYPR"/.overtake-tmp.* "$HOME/.config/omarchy/hooks/post-update.d"/.overtake-tmp.*
rm -rf "${PLUGINS:?}/overtake.taskbar" "${PLUGINS:?}/overtake.workspaces" \
       "${PLUGINS:?}/overtake.bluetooth" "${PLUGINS:?}/overtake.audio" \
       "${PLUGINS:?}/overtake.notifications" "${PLUGINS:?}/overtake.notification-center" \
       "${PLUGINS:?}/overtake.battery" "${PLUGINS:?}/overtake.menubar" "${PLUGINS:?}/overtake.control-center" \
       "${PLUGINS:?}"/.overtake-build.* \
       "$HOME/.local/state/overtake" "${XDG_CACHE_HOME:-$HOME/.cache}/overtake" "$HOME/.local/share/overtake"

if [[ $PURGE ]]; then
  if [[ $(readlink -f "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/background" 2>/dev/null) == "$HOME/Pictures/overtake/"* ]]; then
    echo "Your current wallpaper was one of Overtake's, now gone: pick another in Omarchy's Appearance menu."
  fi
  rm -rf "$HOME/.config/overtake" "$HOME/Pictures/overtake"
fi

if [[ -z ${OVERTAKE_NO_RELOAD:-} ]] && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  omarchy-menu refresh >/dev/null 2>&1 || true
fi

if [[ $PURGE ]]; then echo "Overtake Mode removed. Settings and wallpapers removed too."
else echo "Overtake Mode removed. Your settings stay in ~/.config/overtake (./uninstall.sh --purge removes them)."; fi
# The root plugin, if it came through `omarchy plugin add`, is Omarchy's to
# remove. Until then it reminds you to install again, as it would on a first add.
if [[ -e $PLUGINS/gleasonmt.overtake-mode ]]; then
  echo "One step left: omarchy plugin remove gleasonmt.overtake-mode  (until then its reminder to install keeps appearing)."
fi
