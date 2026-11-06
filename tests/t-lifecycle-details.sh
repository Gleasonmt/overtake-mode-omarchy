#!/bin/bash
# The smaller promises of install, update, switching and uninstall: what the
# notices say and that they arrive, the order things are written in, what is
# handed back to Omarchy, and which leftovers go.
source "$(dirname "$0")/lib.sh"
cd "$REPO"

n=0
fresh() {  # fresh: a new scratch home with Overtake installed; sets H and O
  n=$((n + 1))
  H="$T/home$n"
  make_home "$H"
  O="$H/.local/bin/overtake"
  sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
}
# (a grep -q that stops early kills this writer: not a failure)
log_text() { tr '\0' ' ' <"$ARGV_LOG" || true; }
config() { echo "$H/.config/omarchy/shell.json"; }
set_config() {  # set_config <jq filter>
  jq "$1" "$(config)" >"$T/s.json" && cat "$T/s.json" >"$(config)"
}
notify_works() { stub omarchy-notification-send; }
notify_fails() { stub omarchy-notification-send 'exit 1'; }

# An Omarchy whose workspaces widget a patch can no longer fit.
UNFIT="$T/omarchy-unfit"
cp -rL "$OMARCHY_SRC" "$UNFIT"
rm -f "$UNFIT/bar/widgets/Workspaces.qml"

# ---------- A new window at a reused address ----------
fresh
# ---------- What a new desktop calls things ----------
icons=$(grep -v '^#' "$H/.config/overtake/desktop-icons.txt")
grep -qx 'trash | Recycle Bin' <<<"$icons" || fail "the default desktop has no Recycle Bin"
# (a label naming a browser has to open that browser, not the default one)
grep -qx 'chromium | Chromium' <<<"$icons" || fail "the default desktop has no Chromium"
grep -q '^browser' <<<"$icons" && fail "the default desktop still has the default-browser icon"
grep -qx 'Name=Recycle Bin' "$H/.local/share/applications/overtake-trash.desktop" || fail "the launcher entry isn't called Recycle Bin"
pass "a new desktop has Recycle Bin and Chromium, the launcher entry matches, and Chromium's icon is Chromium itself"

sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
echo "$MARK name" | sbx "$H" "$O" name 0xa1 -
jq -e '.["0xa1"]' "$H/.local/state/overtake/names.json" >/dev/null || fail "the window's name wasn't kept (test setup)"
sbx "$H" "$O" fill-gap 0xa1 >>"$T/log" 2>&1 || true
jq -e 'has("0xa1") | not' "$H/.local/state/overtake/names.json" >/dev/null || fail "a new window at a reused address kept the old window's name"
pass "a new window at a reused address doesn't show the old window's name"

# ---------- The installed version ----------
[[ $(<"$H/.local/share/overtake/version") == "$(jq -r .version manifest.json)" ]] || fail "install didn't record the manifest's version"
pass "install records the installed version"
node -e '
  const src = require("fs").readFileSync("Setup.qml", "utf8")
  const start = src.indexOf("function versionToInstall(")
  if (start < 0) throw new Error("versionToInstall not found in Setup.qml")
  let depth = 0, i = src.indexOf("{", start)
  for (; i < src.length; i++) { if (src[i] === "{") depth++; else if (src[i] === "}" && --depth === 0) break }
  const f = new Function(src.slice(start, i + 1) + "; return versionToInstall")()
  const m = JSON.stringify({ version: "0.2.0" })
  const cases = [[m, "0.2.0\n", ""], [m, "0.3.0\n", ""], [m, "0.1.15\n", "0.2.0"], [m, "", "0.2.0"], ["not json", "0.1.15", ""], ["{}", "0.1.15", ""], [m, "0.2.0", "0.2.0", true], [m, "0.3.0", "", true]]
  for (const [a, b, want, differs] of cases) if (f(a, b, differs) !== want) { console.error("FAIL: versionToInstall", a, JSON.stringify(b), "gave", f(a, b)); process.exit(1) }
' || fail "Setup.qml's version check"
grep -q 'Run ./install.sh again in' Setup.qml || fail "Setup.qml doesn't ask for the installer again"
grep -q 'root.folder +.*install\|install.*root.folder' Setup.qml && fail "Setup.qml puts this machine's path in notify-send's arguments"
pass "Setup.qml asks for ./install.sh again when this folder is newer than what was installed, or nothing was recorded"
sbx "$H" "$O" off >>"$T/log" 2>&1
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
[[ ! -e $H/.local/share/overtake/version ]] || fail "uninstall left the version file"
pass "uninstall removes the version file"

# ---------- What the bar notice says ----------
fresh
sbx "$H" env OVERTAKE_OMARCHY_PLUGINS="$UNFIT" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies with an unfit Omarchy"; }
[[ ! -e $H/.config/omarchy/plugins/overtake.workspaces ]] || fail "the copy that no longer fits wasn't dropped (test setup)"
grep -qw workspaces "$H/.local/state/overtake/copies-left-out" || fail "the dropped copy wasn't recorded"
log_text | grep -q "own version is used for workspaces until an Overtake update supports this Omarchy" || fail "no clear notice for the dropped copy at update"
log_text | grep -q "workspaces is" && fail "bad grammar in a notice"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
: >"$ARGV_LOG"
sbx "$H" "$O" fix-bar >>"$T/log" 2>&1
log_text | grep -q "own version is used for workspaces until an Overtake update supports this Omarchy" || { log_text | tail -5; fail "the bar notice doesn't say an Overtake update is needed"; }
log_text | grep -q "install.sh" && fail "the bar notice says installing again fixes a copy that no longer fits"
: >"$ARGV_LOG"
sbx "$H" "$O" fix-bar >>"$T/log" 2>&1
log_text | grep -q "until an Overtake update" && fail "the bar notice was repeated"
pass "a copy dropped for not fitting: the notice asks for an Overtake update, once"

fresh
rm -rf "$H/.config/omarchy/plugins/overtake.audio"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
: >"$ARGV_LOG"
sbx "$H" "$O" fix-bar >>"$T/log" 2>&1
log_text | grep -q "version of audio because Overtake's isn't installed. Installing Overtake again (./install.sh)" || { log_text | tail -5; fail "a copy missing for another reason lost its reinstall advice"; }
pass "a copy missing for another reason: the notice keeps the advice to install again"

# A later install that can build it again clears the record.
fresh
sbx "$H" env OVERTAKE_OMARCHY_PLUGINS="$UNFIT" "$O" build-copies update >"$T/out" 2>&1
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall"; }
[[ ! -e $H/.local/state/overtake/copies-left-out ]] || fail "the record of a dropped copy outlived its rebuild"
pass "a copy built again is no longer recorded as dropped"

# ---------- A rebuild that fails ----------
fresh
rm -f "$H/.local/share/overtake/NOTICE.md"   # (a passing error, not Omarchy changing)
: >"$ARGV_LOG"
sbx "$H" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies"; }
grep -q unchanged "$T/out" && { cat "$T/out"; fail "a failed rebuild said unchanged"; }
grep -q "the copy from before stays in use" "$T/out" || { cat "$T/out"; fail "a failed rebuild wasn't reported"; }
[[ -d $H/.config/omarchy/plugins/overtake.audio ]] || fail "a passing error removed a working copy"
log_text | grep -q "couldn't rebuild its copy" || fail "update mode didn't notify about a failed rebuild"
pass "a failed rebuild is reported as that, and notified in update mode"
: >"$ARGV_LOG"
sbx "$H" ./install.sh --yes >"$T/out" 2>&1 || { cat "$T/out"; fail "reinstall"; }
sbx "$H" "$O" build-copies update >"$T/out" 2>&1
grep -q unchanged "$T/out" || { cat "$T/out"; fail "a build with nothing to do should say unchanged"; }
pass "nothing to rebuild still says unchanged"

# ---------- A notice the shell wasn't up for ----------
fresh
notify_fails
sbx "$H" env OVERTAKE_OMARCHY_PLUGINS="$UNFIT" "$O" resume >>"$T/log" 2>&1 || { cat "$T/log"; fail "resume"; }
P="$H/.local/state/overtake/pending-notices"
[[ -s $P ]] || fail "the login notice was lost: nothing kept when the shell wasn't up"
[[ $(stat -c %a "$P") == 600 && $(stat -c %a "$(dirname "$P")") == 700 ]] || fail "the kept notice isn't private"
sbx "$H" env OVERTAKE_OMARCHY_PLUGINS="$UNFIT" "$O" status >/dev/null
[[ -s $P ]] || fail "a kept notice was dropped while the shell still wasn't up"
[[ $(wc -l <"$P") == 1 ]] || fail "the kept notice was duplicated"
notify_works
: >"$ARGV_LOG"
sbx "$H" "$O" status >/dev/null
log_text | grep -q "own version is used for workspaces" || fail "the next command didn't show the kept notice"
[[ ! -e $P ]] || fail "a shown notice stayed kept"
: >"$ARGV_LOG"
sbx "$H" "$O" status >/dev/null
log_text | grep -q "own version is used" && fail "a shown notice came back"
pass "a login notice waits for the shell, shows once, then is gone"

# ...and a notification that gets through brings it along.
printf 'x\tkept notice %s\n' "$n" >"$P"
sbx "$H" bash -c "sed -i 's/^\[\[ ! -s \$PENDING_NOTICES \]\] || show_pending_notices\$/:/' '$O'"   # (only the send path below)
: >"$ARGV_LOG"
sbx "$H" "$O" style studio >>"$T/log" 2>&1
log_text | grep -q "kept notice $n" || fail "a notification that got through didn't bring the kept one"
[[ ! -e $P ]] || fail "the kept notice stayed after being shown"
pass "the next notification that gets through shows a kept one too"

# ---------- Shell answers while starting ----------
fresh
echo 0 >"$T/tries"
stub omarchy "$(cat <<EOF
c=\$(<"$T/tries"); echo \$((c + 1)) >"$T/tries"
if (( c < 2 )); then echo "omarchy-shell is not ready" >&2; exit 1; fi
EOF
)"
sbx "$H" env -u OVERTAKE_NO_RELOAD "$O" copies on >"$T/out" 2>&1
grep -q "couldn't switch" "$T/out" && { cat "$T/out"; fail "\"not ready\" wasn't retried"; }
(( $(<"$T/tries") >= 3 )) || fail "\"not ready\" wasn't retried"
pass "switching the copies retries while the shell says not ready"
stub omarchy

# ---------- Switching off: order, and no shell ----------
fresh
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
cp "$(config)" "$T/stale.json"
# (the shell saves shell.json from the copy it holds when it switches a plugin)
stub omarchy "$(cat <<EOF
[[ \$2 == disable ]] && cat "$T/stale.json" >"$(config)"
exit 0
EOF
)"
sbx "$H" env -u OVERTAKE_NO_RELOAD "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
jq -e '.bar | tostring | test("overtake") | not' "$(config)" >/dev/null || fail "the shell's write put Overtake's bar back over yours"
pass "off switches the plugins before writing the bar"

fresh
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
set_config '.plugins = [{"id":"overtake.notifications"},{"id":"overtake.battery"}]
  | .disabledPlugins = ["omarchy.notifications","omarchy.battery"]
  | .cloneSourceRestores = ["overtake.notifications","overtake.battery"]'
stub omarchy 'echo "omarchy-shell is not running" >&2; exit 1'
sbx "$H" env -u OVERTAKE_NO_RELOAD "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off with no shell"; }
jq -e '(.bar | tostring | test("overtake") | not) and (.bar.position == "top")
       and (has("disabledPlugins") | not) and (has("cloneSourceRestores") | not)
       and ((.plugins // []) | length == 0)' "$(config)" >/dev/null || { cat "$(config)"; fail "off with no shell left something behind"; }
stub omarchy
pass "off with no shell: your bar back, and the copies handed back in shell.json"

# No saved bar: none in shell.json, so Omarchy's default is followed.
fresh
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
rm -f "$H/.local/state/overtake/omarchy-bar.json"
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
jq -e 'has("bar") | not' "$(config)" >/dev/null || { cat "$(config)"; fail "the no-saved-bar fallback wrote a bar into shell.json"; }
pass "with no saved bar, shell.json keeps none and Omarchy's default is used"

# ---------- Uninstall hands back only what the copies switched off ----------
uninstall_with() {  # uninstall_with <jq filter>: the result in $H's shell.json
  fresh
  set_config "$1"
  sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
}
uninstall_with '.disabledPlugins = ["omarchy.battery"]'
jq -e '.disabledPlugins == ["omarchy.battery"]' "$(config)" >/dev/null || { cat "$(config)"; fail "uninstall turned on an Omarchy plugin you had turned off"; }
pass "uninstall leaves off an Omarchy plugin you turned off after installing"
uninstall_with '.disabledPlugins = ["omarchy.notifications"] | .cloneSourceRestores = ["overtake.notifications"]'
jq -e '(has("disabledPlugins") | not) and (has("cloneSourceRestores") | not)' "$(config)" >/dev/null || { cat "$(config)"; fail "uninstall didn't hand back what the copy switched off, or left empty lists"; }
pass "uninstall turns back on what Overtake's copy switched off, and leaves no empty lists"
uninstall_with '.disabledPlugins = ["omarchy.notifications","omarchy.battery"] | .cloneSourceRestores = ["overtake.notifications"]'
jq -e '.disabledPlugins == ["omarchy.battery"] and (has("cloneSourceRestores") | not)' "$(config)" >/dev/null || { cat "$(config)"; fail "uninstall mixed up your plugin and the copy's"; }
pass "uninstall tells the two apart"

# ---------- Files Overtake had to create ----------
n=$((n + 1))
H="$T/home$n"
make_home "$H"
rm -f "$H/.config/hypr/bindings.lua" "$H/.config/hypr/autostart.lua"
cp -a "$H" "$T/before-created"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
[[ -s $H/.config/hypr/bindings.lua && -s $H/.config/hypr/autostart.lua ]] || fail "install didn't make the Hyprland files (test setup)"
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
check_restored "$T/before-created" "$H"
pass "bindings.lua and autostart.lua that install created go again"

n=$((n + 1))
H="$T/home$n"
make_home "$H"
rm -f "$H/.config/hypr/autostart.lua"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
echo '-- added by me' >>"$H/.config/hypr/autostart.lua"
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
grep -q 'added by me' "$H/.config/hypr/autostart.lua" || fail "uninstall removed a created file you had added to"
pass "one you added to since stays"

# ---------- shell.toml ----------
fresh
TOML="$H/.config/omarchy/shell.toml"
rm -f "$TOML"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
[[ -s $TOML ]] || fail "on didn't write the bar size"
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ ! -e $TOML ]] || fail "off left the shell.toml it created"
printf '\n' >"$TOML"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ -e $TOML ]] || fail "off deleted a blank shell.toml that was yours"
printf '[font]\nbase-size = 12\n' >"$TOML"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ $(<"$TOML") == $'[font]\nbase-size = 12' ]] || fail "off changed your shell.toml"
pass "a shell.toml Overtake created goes with it; one that was yours stays, blank or not"

# ---------- What the code and the login line say ----------
grep -q "omarchy-shell-config writes them" bin/overtake && fail "replace_with's comment claims it works as omarchy-shell-config does"
grep -q "the installer runs it" bin/overtake && fail "the bg-picker comment says the installer runs it"
fresh
grep -q 'check and rebuild its patched copies' "$H/.config/hypr/autostart.lua" || fail "the login line's comment doesn't say it rebuilds the copies"
grep -q 'check and$' <<<"$(sbx "$H" ./install.sh --dry-run)" || fail "the install list doesn't say the login line rebuilds the copies"
pass "comments and the install list describe what the code does"

# ...and the copy from before isn't lost if the new one can't be moved into place.
fresh
echo older >"$H/.config/omarchy/plugins/overtake.audio/older"
stub mv 'if [[ $1 == -T && $3 == */overtake.audio && $2 == */.overtake-build.?????? ]]; then echo "mv: no" >&2; exit 1; fi
exec /usr/bin/mv "$@"'
sbx "$H" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies"; }
rm -f "$STUB/mv"
[[ -f $H/.config/omarchy/plugins/overtake.audio/older ]] || { cat "$T/out"; fail "the copy from before was lost when the new one couldn't be moved in"; }
grep -q "stays in use.*audio" "$T/out" || { cat "$T/out"; fail "a failed move wasn't reported"; }
ls -A "$H/.config/omarchy/plugins" | grep -q '^\.overtake-build' && fail "a build folder was left behind"
pass "the copy from before goes only once the new one is in its place"

# A patcher that fails for any reason but "doesn't fit": the copy from before stays.
fresh
echo older >"$H/.config/omarchy/plugins/overtake.audio/older"
printf 'with open("/dev/full", "w") as f:\n    f.write("x")\n' >"$H/.local/share/overtake/apply.py"
sbx "$H" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies"; }
[[ -f $H/.config/omarchy/plugins/overtake.audio/older ]] || { cat "$T/out"; fail "a failed build replaced a working copy"; }
grep -q "stays in use" "$T/out" || { cat "$T/out"; fail "a failed build wasn't reported"; }
pass "a patcher that fails keeps the copy from before, and says so"

# The real patcher on a write that fails only at close: small enough to sit in
# Python's buffer, under a file-size limit of 0 (EFBIG, wherever this runs). Left
# to close by itself, Python would exit 0: silently on older versions.
LIMITED="$T/limited"; mkdir -p "$LIMITED"
printf '      if (b === Qt.RightButton) root.toggleBluetooth()\n      else root.toggle()\n' >"$LIMITED/Panel.qml"
if ( trap '' XFSZ; ulimit -f 0; python3 -I patches/apply.py bluetooth "$LIMITED" ) >/dev/null 2>&1; then
  fail "the patcher exited 0 when its write failed at close"
fi
pass "the real patcher fails when its write fails at close"

# ---------- No Omarchy to build from ----------
fresh
cp "$(config)" "$T/sj.before"
sbx "$H" env OVERTAKE_OMARCHY_PLUGINS="$T/no-such-omarchy" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies with no source"; }
for c in workspaces bluetooth audio notifications battery; do
  [[ -d $H/.config/omarchy/plugins/overtake.$c ]] || { cat "$T/out"; fail "a missing Omarchy dropped overtake.$c"; }
done
grep -q "nothing changed" "$T/out" || { cat "$T/out"; fail "a missing Omarchy wasn't reported"; }
grep -q "left out" "$T/out" && { cat "$T/out"; fail "a missing Omarchy was taken for Omarchy changing"; }
[[ ! -e $H/.local/state/overtake/copies-left-out ]] || fail "a missing Omarchy recorded copies as left out"
cmp -s "$(config)" "$T/sj.before" || fail "a missing Omarchy changed shell.json"
pass "with no Omarchy to build from, nothing changes"

# ---------- "unchanged" only when it's true ----------
fresh
rm -rf "$H/.config/omarchy/plugins/overtake.audio"
sbx "$H" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies"; }
grep -q unchanged "$T/out" && { cat "$T/out"; fail "\"unchanged\" with a copy absent"; }
grep -q "no copy here.*audio" "$T/out" || { cat "$T/out"; fail "an absent copy wasn't reported"; }
pass "an absent copy isn't called unchanged"

# ---------- A shell.json that can't be used ----------
fresh
odd_config() {  # odd_config <what the message says> <command...>
  local said=$1 before; shift
  before=$(cat "$(config)" 2>/dev/null; echo x)
  if "$@" >"$T/out" 2>&1; then cat "$T/out"; fail "$* went ahead with a shell.json that $said"; fi
  grep -q "shell.json $said, so nothing was changed" "$T/out" || { cat "$T/out"; fail "$* with a shell.json that $said: no clear message"; }
  grep -q '^jq: ' "$T/out" && { cat "$T/out"; fail "$* showed a raw jq error"; }
  [[ $(cat "$(config)" 2>/dev/null; echo x) == "$before" ]] || fail "$* changed a shell.json that $said"
  [[ ! -e $H/.local/state/overtake/enabled ]] || fail "$* turned the mode on with a shell.json that $said"
  [[ $(sbx "$H" "$O" status) == off ]] || fail "$* says the mode is on"
}
for setup in "is missing|rm -f" "is empty|truncate -s 0" "isn't valid JSON|sed -i s/^/x/"; do
  said=${setup%%|*} make=${setup#*|}
  $make "$(config)"
  for c in on toggle cycle; do odd_config "$said" sbx "$H" "$O" "$c"; done
  printf '{"bar":{}}\n' >"$(config)"
done
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
cp "$(config)" "$T/good.json"
: >"$(config)"
if sbx "$H" "$O" off >"$T/out" 2>&1; then cat "$T/out"; fail "off went ahead with an empty shell.json"; fi
grep -q "shell.json is empty, so nothing was changed" "$T/out" || { cat "$T/out"; fail "off with an empty shell.json: no clear message"; }
[[ -e $H/.local/state/overtake/enabled ]] || fail "off half-happened with an empty shell.json"
if sbx "$H" "$O" style studio >"$T/out" 2>&1; then cat "$T/out"; fail "style went ahead with an empty shell.json"; fi
[[ $(sbx "$H" "$O" style) == classic ]] || fail "style changed with an empty shell.json"
if sbx "$H" "$O" screensaver start >"$T/out" 2>&1; then cat "$T/out"; fail "screensaver start went ahead with an empty shell.json"; fi
cp "$T/good.json" "$(config)"
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off after the file came back"; }
pass "a missing, empty or invalid shell.json is said plainly and nothing changes"

# ---------- Your screensaver art ----------
art_home() {  # art_home <what's there: text, or - for no file>
  fresh
  ART="$H/.config/omarchy/branding/screensaver.txt"
  if [[ $1 == - ]]; then rm -f "$ART"; else printf '%s' "$1" >"$ART"; fi
}
LOGO="$T/om"; mkdir -p "$LOGO"; printf 'THE LOGO\n' >"$LOGO/logo.txt"
stub omarchy-transcode-ascii 'printf "wallpaper art\n" >"$2"'
stub omarchy-branding-screensaver 'printf "image art\n" >"$HOME/.config/omarchy/branding/screensaver.txt"'
stub omarchy-launch-editor 'printf "typed art\n" >"$1"'
art() { sbx "$H" env OMARCHY_PATH="$LOGO" "$O" screensaver show "$@" >>"$T/log" 2>&1; }
art_back() {  # art_back <what should be there>
  sbx "$H" env OMARCHY_PATH="$LOGO" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
  if [[ $1 == - ]]; then [[ ! -e $ART ]] || fail "art made by Overtake stayed after uninstall: $(cat "$ART")"
  else [[ $(cat "$ART"; echo x) == "$1"x ]] || fail "art not restored ($2): '$(cat "$ART" 2>/dev/null)', not '$1'"; fi
  [[ ! -e $ART.before-overtake ]] || fail "the kept copy stayed after uninstall ($2)"
}
for branch in omarchy wallpaper; do
  art_home "my own art"; art "$branch"
  art_back "my own art" "$branch from your own art"
done
printf 'THE LOGO\n' >"$T/logo-copy"
art_home "THE LOGO"$'\n'; art wallpaper; [[ $(<"$ART") == "wallpaper art" ]] || fail "wallpaper art wasn't made (test setup)"
art_back "THE LOGO"$'\n' "wallpaper from art equal to Omarchy's logo"
art_home "my own art"; art wallpaper; art omarchy
art_back "my own art" "the first replacement is what's kept"
art_home ""; art wallpaper; art_back "" "from empty art"
art_home -; art wallpaper; [[ -s $ART ]] || fail "wallpaper art wasn't made (test setup)"; art_back - "with no art before"
pass "art Overtake wrote goes, and what you had before it comes back"
# Art you wrote or picked, or changed afterwards, stays; the old art stays beside it.
art_kept() {  # art_kept <what should be there> <what>
  sbx "$H" env OMARCHY_PATH="$LOGO" ./uninstall.sh --yes >"$T/out" 2>&1 || { cat "$T/out"; fail "uninstall"; }
  [[ $(<"$ART") == "$1" ]] || fail "your art was replaced on uninstall ($2): '$(<"$ART")'"
  [[ $(<"$ART.before-overtake") == "my own art" ]] || fail "the art from before went ($2)"
  grep -q 'Kept your current screensaver art' "$T/out" || { cat "$T/out"; fail "uninstall didn't say it kept your art ($2)"; }
}
art_home "my own art"; art image; art_kept "image art" "picked through Omarchy"
art_home "my own art"; art text; art_kept "typed art" "written in the editor"
art_home "my own art"; art wallpaper; printf 'edited later\n' >"$ART"; art_kept "edited later" "edited after Overtake wrote it"
stub omarchy-transcode-ascii; stub omarchy-branding-screensaver; stub omarchy-launch-editor
pass "art you wrote, picked or changed stays on uninstall"

# ---------- Switching back outside the desktop session ----------
fresh
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
cp "$STUB/hyprctl" "$T/hyprctl.real"
SAVED="$H/.local/state/overtake/gtk-button-layout"
echo "'appmenu:close'" >"$SAVED"
stub hyprctl 'echo "HYPRLAND_INSTANCE_SIGNATURE not set!"; exit 1'
: >"$ARGV_LOG"
if sbx "$H" "$O" off >"$T/out" 2>&1; then cat "$T/out"; fail "off said it finished outside the session"; fi
grep -q 'in your desktop session to finish' "$T/out" || { cat "$T/out"; fail "off didn't say what's left to do"; }
[[ -e $H/.local/state/overtake/switching-off ]] || fail "a half-done switch left no marker"
log_text | grep -aq 'button-layout appmenu:close' || fail "off stopped before it restored GTK's buttons"
[[ ! -s $SAVED ]] || fail "the saved GTK setting stayed after it was put back"
# Not "already off", and `on` won't start here, nor save over what's left to do.
if sbx "$H" "$O" on >"$T/out" 2>&1; then cat "$T/out"; fail "on went ahead outside the session"; fi
grep -q 'needs your desktop session' "$T/out" || { cat "$T/out"; fail "on didn't say why it stopped"; }
if sbx "$H" ./uninstall.sh --yes >"$T/out" 2>&1; then cat "$T/out"; fail "uninstall went ahead with a switch half done"; fi
[[ -x $O ]] || fail "uninstall removed the command with a switch half done"
cp "$T/hyprctl.real" "$STUB/hyprctl"
# (what's showing is Omarchy's by now: finishing can't save that as the mode's)
L="$H/.local/state/overtake/looks"
printf 'classictheme\n' >"$L/classic.theme"; rm -f "$L/classic.picked"
printf 'mytheme\n' >"$H/.local/state/omarchy/current/theme.name"
( cd "$L" && sha256sum * ) >"$T/looks.before"
printf 'a = 1' >"$H/.config/omarchy/shell.toml"; sha256sum <"$H/.config/omarchy/shell.toml" >"$T/toml.before"
sbx "$H" "$O" off >"$T/out" 2>&1 || { cat "$T/out"; fail "off in the session didn't finish it"; }
sha256sum <"$H/.config/omarchy/shell.toml" | cmp -s - "$T/toml.before" || fail "a second off changed a shell.toml that had no block"
( cd "$L" && sha256sum classic.* ) | while read -r line; do grep -qF "$line" "$T/looks.before" || fail "finishing a switch changed a saved look: $line"; done
[[ $(<"$L/classic.theme") == classictheme && ! -e $L/classic.picked ]] || fail "finishing a switch overwrote Classic's saved look"
[[ ! -e $H/.local/state/overtake/switching-off ]] || fail "the marker stayed after off finished"
grep -q 'already off' "$T/out" && fail "off said already off with a switch half done"
pass "off outside the session does what it can, says so, and finishes later; nothing is lost"
# A GTK setting that can't be written stays saved for the retry.
fresh
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
echo "'appmenu:close'" >"$H/.local/state/overtake/gtk-button-layout"
stub gsettings 'exit 1'
if sbx "$H" "$O" off >"$T/out" 2>&1; then cat "$T/out"; fail "off finished with GTK's setting not put back"; fi
[[ -s $H/.local/state/overtake/gtk-button-layout ]] || fail "the saved GTK setting went though it wasn't put back"
stub gsettings
sbx "$H" "$O" off >"$T/out" 2>&1 || { cat "$T/out"; fail "off on retry"; }
[[ ! -e $H/.local/state/overtake/gtk-button-layout ]] || fail "the saved GTK setting stayed after the retry"
pass "GTK's buttons are put back, and a failed try keeps what's needed"

# ---------- Back to Omarchy: tiles, tags, refused steps ----------
fresh
cat >"$HYPR/clients.json" <<'EOF'
[{"address":"0xb1","class":"a","initialClass":"a","title":"a","workspace":{"id":1,"name":"1"},"floating":false,"tags":[],"at":[0,0],"size":[500,1000],"focusHistoryID":0,"mapped":true},
 {"address":"0xb2","class":"b","initialClass":"b","title":"b","workspace":{"id":1,"name":"1"},"floating":false,"tags":["omarchy-mode-floated*"],"at":[510,0],"size":[1400,1000],"focusHistoryID":1,"mapped":true}]
EOF
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
jq 'map(.floating = true)' "$HYPR/clients.json" >"$HYPR/x" && mv "$HYPR/x" "$HYPR/clients.json"
sbx "$H" "$O" off >"$T/out" 2>&1 || { cat "$T/out"; fail "off"; }
# (the stub fails this test at its end if Hyprland wouldn't take the form)
log_text | grep -aqE 'splitratio 0\.[0-9]+ exact' || fail "the tiles' split wasn't set: $(log_text | grep -a -c splitratio)"
log_text | grep -aqF 'tag = "+omarchy-mode-floated", window = "address:0xb2"' || fail "Omarchy's floating tag wasn't put back on its window"
log_text | grep -aqF 'address:0xb1" })' && log_text | grep -aqF 'tag = "+omarchy-mode-floated", window = "address:0xb1"' && fail "a window got a tag it never had"
pass "off rebuilds the split at its ratio and gives Omarchy's floating tag back"
# A refused step shows.
cp "$STUB/hyprctl" "$T/hyprctl.real"
printf '#!/bin/bash\nif [[ $1 == --batch ]]; then echo ok; echo "error: failed to parse"; exit 0; fi\nexec "%s" "$@"\n' "$T/hyprctl.real" >"$STUB/hyprctl"; chmod +x "$STUB/hyprctl"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" "$O" off >"$T/out" 2>&1 || true
grep -q 'Hyprland refused a step' "$T/out" || { cat "$T/out"; fail "a refused line of a batch wasn't said"; }
grep -q 'failed to parse' "$H/.local/state/overtake/hyprland-refused.log" || fail "a refused line wasn't kept"
cp "$T/hyprctl.real" "$STUB/hyprctl"
pass "a line of a batch Hyprland refuses is said and kept"
echo '[{"address":"0xa1","pid":4242,"class":"x","initialClass":"x","title":"t","initialTitle":"t","workspace":{"id":21,"name":"21"},"monitor":1,"at":[10,40],"size":[800,600],"floating":true,"mapped":true,"focusHistoryID":0,"tags":[]}]' >"$HYPR/clients.json"
sbx "$H" "$O" send 23 0xa1 >>"$T/log" 2>&1 || true
log_text | grep -aqF 'workspace = "23", follow = false' || fail "send to a second monitor's workspace didn't go there"
pass "a window can be sent to another monitor's workspace numbers"

# ---------- No session: what's left to do is kept ----------
fresh
cat >"$HYPR/clients.json" <<'EOF'
[{"address":"0xb1","class":"a","initialClass":"a","title":"a","workspace":{"id":1,"name":"1"},"floating":false,"tags":["omarchy-mode-floated"],"at":[0,0],"size":[500,1000],"focusHistoryID":0,"mapped":true},
 {"address":"0xb2","class":"b","initialClass":"b","title":"b","workspace":{"id":1,"name":"1"},"floating":false,"tags":[],"at":[510,0],"size":[1400,1000],"focusHistoryID":1,"mapped":true}]
EOF
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
S="$H/.local/state/overtake"
[[ -s $S/tiled.json && -s $S/omarchy-floated ]] || fail "(setup) places and tags weren't saved"
cp "$STUB/hyprctl" "$T/hyprctl.real"
printf '#!/bin/bash\necho "HYPRLAND_INSTANCE_SIGNATURE not set!"; exit 1\n' >"$STUB/hyprctl"; chmod +x "$STUB/hyprctl"
sbx "$H" "$O" off >"$T/out" 2>&1 && { cat "$T/out"; fail "off finished with no session"; }
grep -q 'Traceback' "$T/out" && { cat "$T/out"; fail "a traceback outside the session"; }
[[ -s $S/tiled.json && -s $S/omarchy-floated ]] || fail "off outside the session lost window places or Omarchy's tag"
cp "$T/hyprctl.real" "$STUB/hyprctl"
jq 'map(.floating = true)' "$HYPR/clients.json" >"$HYPR/x" && mv "$HYPR/x" "$HYPR/clients.json"
sbx "$H" "$O" off >"$T/out" 2>&1 || { cat "$T/out"; fail "off in the session"; }
log_text | grep -aqE 'splitratio 0\.[0-9]+ exact' || fail "off in the session didn't rebuild the split saved earlier"
log_text | grep -aqF 'tag = "+omarchy-mode-floated", window = "address:0xb1"' || fail "off in the session didn't put the tag back"
pass "off outside the session keeps window places and Omarchy's tag for the session's off"
# A layout with no split to rebuild: tiled plainly, nothing refused.
fresh
: >"$ARGV_LOG"
cat >"$HYPR/clients.json" <<'EOF'
[{"address":"0xb1","class":"a","initialClass":"a","title":"a","workspace":{"id":1,"name":"1"},"floating":false,"tags":[],"at":[0,0],"size":[500,1000],"focusHistoryID":0,"mapped":true},
 {"address":"0xb2","class":"b","initialClass":"b","title":"b","workspace":{"id":1,"name":"1"},"floating":false,"tags":[],"at":[510,0],"size":[1400,1000],"focusHistoryID":1,"mapped":true}]
EOF
cp "$HYPR/workspaces.json" "$T/ws.json"; echo '[{"id":1,"name":"1","monitor":"eDP-1","tiledLayout":"scrolling"}]' >"$HYPR/workspaces.json"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
jq 'map(.floating = true)' "$HYPR/clients.json" >"$HYPR/x" && mv "$HYPR/x" "$HYPR/clients.json"
sbx "$H" "$O" off >"$T/out" 2>&1 || { cat "$T/out"; fail "off"; }
log_text | grep -aqE 'splitratio|preselect' && fail "a scrolling workspace was sent dwindle's split commands"
cp "$T/ws.json" "$HYPR/workspaces.json"
pass "a workspace on another layout gets no split commands"
# A warning in a batch's reply isn't a refusal.
fresh
cp "$STUB/hyprctl" "$T/hyprctl.real"
printf '#!/bin/bash\nif [[ $1 == --batch ]]; then echo ok; echo "warning: cannot alter split ratio on no / single node"; exit 0; fi\nexec "%s" "$@"\n' "$T/hyprctl.real" >"$STUB/hyprctl"; chmod +x "$STUB/hyprctl"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" "$O" off >"$T/out" 2>&1 || true
grep -q 'refused' "$T/out" && { cat "$T/out"; fail "a warning was reported as refused"; }
cp "$T/hyprctl.real" "$STUB/hyprctl"
pass "a warning in a batch's reply isn't called a refusal"

# ---------- shell.toml ----------
fresh
TOML="$H/.config/omarchy/shell.toml"
printf 'a = 1\n# >>> overtake (managed by ~/.local/bin/overtake)\nmine = 1\nb = 2\n' >"$TOML"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
[[ $(<"$TOML") == *'mine = 1'* ]] || fail "on took your lines after a start marker with no end"
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ $(<"$TOML") == *'mine = 1'* ]] || fail "off took your lines after a start marker with no end"
pass "a shell.toml start marker with no end keeps your lines"
fresh
TOML="$H/.config/omarchy/shell.toml"
printf 'a = 1' >"$TOML"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
printf 'a = 1\n' >"$TOML"   # (the block taken out by hand, and a final newline of yours)
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ $(tail -c 2 "$TOML" | od -An -c | tr -d ' ') == '1\n' ]] || fail "a stale flag stripped your final newline: $(od -c "$TOML" | tail -2)"
pass "a stale no-newline flag doesn't strip your final newline"

# ---------- Agent terminals, and icon copies ----------
fresh
echo '[{"address":"0xc1","pid":1,"class":"org.omarchy.agent","initialClass":"org.omarchy.agent","title":"t","initialTitle":"kitty","workspace":{"id":1,"name":"1"},"monitor":0,"at":[0,0],"size":[800,600],"floating":false,"mapped":true,"focusHistoryID":0,"tags":[]}]' >"$HYPR/clients.json"
: >"$ARGV_LOG"
printf 'kitty\n' | sbx "$H" "$O" notification-open >>"$T/log" 2>&1 || fail "an agent terminal's window wasn't found"
log_text | grep -aqF 'address:0xc1' || fail "an agent terminal's window wasn't focused"
pass "a click finds an agent terminal by its first title"
if command -v vipsthumbnail >/dev/null; then
  real_vips_icons=$(command -v vipsthumbnail)
  IC="$H/.local/share/icons/hicolor/256x256/apps"; mkdir -p "$IC"
  python3 -I - "$IC" <<'PY'
import struct, sys, zlib
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
def png(extra=b""):
    rows = (b"\0" + b"\x20\x60\xa0" * 64) * 64
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + extra + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
open(sys.argv[1] + "/siteclean.png", "wb").write(png())
open(sys.argv[1] + "/sitebomb.png", "wb").write(png(chunk(b"zTXt", b"k\0\0" + zlib.compress(b"A" * 7000000, 9)) * 120))
PY
  cp "$IC/siteclean.png" "$IC/PRIVATEICONNAME.png"
  # (XMP in a JPEG: what vips carries over unless told to strip)
  "$real_vips_icons" "$IC/siteclean.png" --size 64x64 -o "$T/ibase.jpg"
  python3 -I - "$T/ibase.jpg" "$IC/sitenoted.jpg" <<'PY'
import struct, sys
j = open(sys.argv[1], "rb").read()
xmp = b"http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">ICONMARKER</x:xmpmeta>"
open(sys.argv[2], "wb").write(j[:2] + b"\xff\xe1" + struct.pack(">H", len(xmp) + 2) + xmp + j[2:])
PY
  mkfifo "$IC/sitefifo.png"
  real_vips=$(command -v vipsthumbnail); stub vipsthumbnail "exec $real_vips \"\$@\""
  : >"$ARGV_LOG"
  sbx "$H" "$O" icon-copies >"$T/out" 2>&1 || { cat "$T/out"; fail "icon-copies"; }
  CD="$H/.cache/overtake/user-icons"
  idx() { sed -n "s/^$1\t//p" "$CD/index"; }
  [[ -n $(idx siteclean) && -s $CD/$(idx siteclean) ]] || fail "no copy of a clean icon: $(cat "$CD/index")"
  [[ -n $(idx sitenoted) && -s $CD/$(idx sitenoted) ]] || fail "no copy of an icon with metadata: $(cat "$CD/index")"
  grep -qa ICONMARKER "$CD/$(idx sitenoted)" && fail "an icon's own metadata survived in the copy"
  python3 -I - "$CD/$(idx sitenoted)" <<'PY' || fail "a copy holds text or metadata chunks"
import struct, sys
d = open(sys.argv[1], "rb").read(); i = 8; bad = []
while i < len(d):
    n, kind = struct.unpack(">I4s", d[i:i + 8]); i += n + 12
    if kind in (b"tEXt", b"zTXt", b"iTXt", b"eXIf", b"iCCP"): bad.append(kind)
sys.exit(1 if bad else 0)
PY
  grep -q '^sitebomb' "$CD/index" && [[ -z $(idx sitebomb) ]] || fail "a crafted icon got a copy: $(cat "$CD/index")"
  grep -q '^sitefifo' "$CD/index" && fail "a pipe was listed as an icon"
  log_text | grep -aq PRIVATEICONNAME && fail "an icon's name was in a command line"
  log_text >"$T/l"; grep -aq 'vipsthumbnail' "$T/l" || fail "(setup) the child didn't run"
  [[ $(stat -c %a "$CD") == 700 && $(stat -c %a "$CD/index") == 600 ]] || fail "icon copies aren't private"
  rm -f "$STUB/vipsthumbnail"
  pass "icons in your folder get stripped copies from a limited child; a crafted one and a pipe get none; no name in a command line"
else
  echo "skipped: no vipsthumbnail (icon copies)"
fi

# ---------- Modes are kept ----------
fresh
LAY="$H/.local/state/omarchy/workspace-layouts"; mkdir -p "$LAY"; printf 'return { default = "floating" }\n' >"$LAY/one.lua"
chmod 640 "$H/.config/omarchy/shell.json" "$LAY/one.lua"   # (not 600: a temp file gets that anyway)
printf 'a = 1\n' >"$H/.config/omarchy/shell.toml"; chmod 640 "$H/.config/omarchy/shell.toml"
modes() { stat -c %a "$H/.config/omarchy/shell.json" "$H/.config/omarchy/shell.toml" "$LAY/one.lua" | tr '\n' ' '; }
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
[[ $(modes) == '640 640 640 ' ]] || fail "on changed a file's mode: $(modes)"
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ $(modes) == '640 640 640 ' ]] || fail "off changed a file's mode: $(modes)"
jq '.plugins = (.plugins // []) + ["overtake.notifications"]' "$H/.config/omarchy/shell.json" >"$T/j" && cat "$T/j" >"$H/.config/omarchy/shell.json"
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
[[ $(modes) == '640 640 640 ' ]] || fail "uninstall changed a file's mode: $(modes)"
pass "on, off and uninstall keep the modes of shell.json, shell.toml and a floating layout"

# ---------- Uninstall: your bar, the wallpaper's message, stray temp files ----------
fresh
jq '.bar = {layout: {left: [{id:"overtake.bluetooth"},{id:"omarchy.menu"}], right: [{id:"overtake.notification-center"}]}}' "$H/.config/omarchy/shell.json" >"$T/j" && cat "$T/j" >"$H/.config/omarchy/shell.json"
touch "$H/.local/bin/.overtake-tmp.AbC123" "$H/.config/hypr/.overtake-tmp.XyZ789" "$H/.local/bin/overtake.backup" "$H/.config/hypr/overtake.lua.backup"
ln -sf "$H/Pictures/overtake/slideshow/1-hills-day.png" "$H/.local/state/omarchy/current/background"
sbx "$H" ./uninstall.sh --yes --purge >"$T/out" 2>&1 || { cat "$T/out"; fail "uninstall"; }
[[ $(jq -c '.bar.layout' "$H/.config/omarchy/shell.json") == '{"left":[{"id":"omarchy.bluetooth"},{"id":"omarchy.menu"}],"right":[]}' ]] || fail "uninstall left Overtake's widgets on your bar: $(jq -c '.bar.layout' "$H/.config/omarchy/shell.json")"
grep -q "was one of Overtake's" "$T/out" || { cat "$T/out"; fail "--purge didn't say the wallpaper went"; }
[[ ! -e $H/.local/bin/.overtake-tmp.AbC123 && ! -e $H/.config/hypr/.overtake-tmp.XyZ789 ]] || fail "uninstall left a killed install's temp files"
[[ -e $H/.local/bin/overtake.backup && -e $H/.config/hypr/overtake.lua.backup ]] || fail "uninstall removed a file of yours"
pass "uninstall takes Overtake's widgets off your bar, says when a purged wallpaper was up, and clears its own temp files"

# ---------- Block markers, a final return, a partial install ----------
H="$T/orphan"; make_home "$H"
printf 'a = 1\n-- >>> overtake old\nmine = 1\n' >"$H/.config/hypr/autostart.lua"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall"; }   # (the update path)
[[ $(<"$H/.config/hypr/autostart.lua") == *'mine = 1'* ]] || fail "a reinstall took your lines after a start marker with no end"
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
[[ $(<"$H/.config/hypr/autostart.lua") == *'mine = 1'* ]] || fail "a start marker with no end took your lines with it"
pass "a start marker with no end doesn't take your lines with it"
H="$T/ret"; make_home "$H"
printf 'x = 1\nreturn {\n  a = 1,\n}\n' >"$H/.config/hypr/bindings.lua"; cp "$H/.config/hypr/bindings.lua" "$T/bind"
if sbx "$H" ./install.sh --dry-run >"$T/out" 2>&1; then cat "$T/out"; fail "--dry-run didn't say a final return stops it"; fi
if sbx "$H" ./install.sh --yes >"$T/out" 2>&1; then cat "$T/out"; fail "install added lines after a final return"; fi
grep -q 'has a return at its top level' "$T/out" || { cat "$T/out"; fail "install didn't say why it stopped"; }
[[ ! -e $H/.local/bin/overtake ]] || fail "install wrote files before stopping at a final return"
cmp -s "$H/.config/hypr/bindings.lua" "$T/bind" || fail "bindings.lua changed"
pass "a Lua file ending in return is left alone, and install says why"
fresh
rm -rf "$H/.config/omarchy/plugins/overtake.taskbar"
cp "$H/.config/omarchy/shell.json" "$T/j"
if sbx "$H" "$O" on >"$T/out" 2>&1; then cat "$T/out"; fail "on showed a bar with its plugin missing"; fi
grep -q 'install.sh again' "$T/out" || { cat "$T/out"; fail "on didn't say what to do"; }
cmp -s "$H/.config/omarchy/shell.json" "$T/j" || fail "on changed shell.json with a plugin missing"
pass "on won't show a bar whose plugin an interrupted install left out"

# ---------- Uninstall stops if shell.json can't be updated ----------
fresh
echo '{ not json' >"$H/.config/omarchy/shell.json"
if sbx "$H" ./uninstall.sh --yes >"$T/out" 2>&1; then cat "$T/out"; fail "uninstall said it finished with shell.json invalid"; fi
grep -q "Overtake Mode removed" "$T/out" && fail "uninstall said removed with shell.json invalid"
[[ -x $O && -d $H/.config/omarchy/plugins/overtake.taskbar ]] || fail "uninstall removed things before it could hand notifications back"
grep -q '>>> overtake' "$H/.config/hypr/autostart.lua" || fail "uninstall removed the login repair before it could update shell.json"
grep -q '>>> overtake' "$H/.config/hypr/bindings.lua" || fail "uninstall removed the mode shortcut before it could update shell.json"
pass "uninstall stops, and says so, if it can't update shell.json"

# ---------- Your own off stays off ----------
H="$T/own-off"; make_home "$H"; O="$H/.local/bin/overtake"
jq '.disabledPlugins = ["omarchy.notifications"]' "$H/.config/omarchy/shell.json" >"$T/s.json" && cat "$T/s.json" >"$H/.config/omarchy/shell.json"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
jq -e '.disabledPlugins // [] | index("omarchy.notifications")' "$H/.config/omarchy/shell.json" >/dev/null || fail "uninstall switched on what you had turned off"
pass "what you had turned off before installing stays off"

# ---------- Theme previews ----------
if command -v vipsthumbnail >/dev/null; then
  fresh
  TH="$H/.config/omarchy/themes"; mkdir -p "$TH/clean" "$TH/crafted" "$TH/noted" "$TH/huge" "$TH/linked" "$TH/none"
  python3 -I - "$TH" <<'PY'
import struct, sys, zlib
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
def png(extra=b""):
    head = chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 36, 8, 2, 0, 0, 0))
    rows = (b"\0" + b"\x20\x60\xa0" * 64) * 36
    return b"\x89PNG\r\n\x1a\n" + head + extra + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
open(sys.argv[1] + "/clean/preview.png", "wb").write(png())
# (real text: Qt and vips keep it; NUL bytes they don't)
one = chunk(b"zTXt", b"k\0\0" + zlib.compress(b"A" * 7000000, 9))
open(sys.argv[1] + "/crafted/preview.png", "wb").write(png(one * 120))
note = chunk(b"tEXt", b"Comment\0PREVIEWMARKER")
open(sys.argv[1] + "/noted/preview.png", "wb").write(png(note))
open(sys.argv[1] + "/huge/preview.png", "wb").write(png(chunk(b"tEXt", b"x\0" + b"A" * 34000000)))
PY
  ln -s "$TH/clean/preview.png" "$TH/linked/preview.png"   # (a link to a real picture, so only the link check stops it)
  real_vips=$(command -v vipsthumbnail)
  # (XMP in a JPEG: what vips carries over unless told to strip)
  "$real_vips" "$TH/clean/preview.png" --size 64x36 -o "$T/base.jpg"
  python3 -I - "$T/base.jpg" "$TH/noted/preview.jpg" <<'PY'
import struct, sys
j = open(sys.argv[1], "rb").read()
xmp = b"http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">PREVIEWMARKER</x:xmpmeta>"
open(sys.argv[2], "wb").write(j[:2] + b"\xff\xe1" + struct.pack(">H", len(xmp) + 2) + xmp + j[2:])
PY
  rm -f "$TH/noted/preview.png"
  "$real_vips" "$TH/noted/preview.jpg" --size 64x36 -o "$T/kept.jpg"; grep -qa PREVIEWMARKER "$T/kept.jpg" || fail "(setup) vips doesn't carry this metadata over, so the strip check can't fail"
  stub vipsthumbnail "exec $real_vips \"\$@\""
  sbx "$H" "$O" theme-previews >"$T/out" 2>&1 || { cat "$T/out"; fail "theme-previews"; }
  C="$H/.cache/overtake/theme-previews"
  [[ -s $C/clean.jpg ]] || fail "no stripped copy of a clean preview"
  [[ $(head -c 2 "$C/clean.jpg" | od -An -tx1 | tr -d ' ') == ffd8 ]] || fail "the stripped copy isn't a re-encoded JPEG"
  [[ ! -s $C/linked.jpg ]] || fail "a preview that's a link was followed"
  grep -qa PREVIEWMARKER "$C/noted.jpg" && fail "a preview's own text survived in the copy"
  [[ -s $C/noted.jpg ]] || fail "no stripped copy of a preview with text"
  [[ -e $C/huge.jpg && ! -s $C/huge.jpg ]] || fail "a preview over the size limit was read"
  [[ -e $C/crafted.jpg && ! -s $C/crafted.jpg ]] || fail "a crafted preview was read past the memory limit"
  [[ ! -e $C/none.jpg ]] || fail "a theme with no preview got a copy"
  [[ $(stat -c %a "$C") == 700 && $(stat -c %a "$C/clean.jpg") == 600 ]] || fail "theme previews aren't private"
  log_text >"$T/l"; grep -aq 'vipsthumbnail' "$T/l" || fail "(setup) the child didn't run"
  rm -f "$STUB/vipsthumbnail"
  rm -rf "$TH/clean"; sbx "$H" "$O" theme-previews >>"$T/log" 2>&1
  [[ ! -e $C/clean.jpg ]] || fail "a removed theme's copy stayed"
  pass "a theme's preview is drawn only from a stripped copy made in a child; links are refused"
else
  echo "skipped: no vipsthumbnail (theme previews)"
fi
# Settings draws a theme from git only from those copies.
if grep -nE 'omarchy/themes/.*preview|"/preview\.(jpg|png)"' plugins/overtake.taskbar/Settings.qml | grep -v omarchyDir | grep -q .; then
  fail "Settings points an Image straight at a theme's own preview"
fi
grep -q 'root.themePreviewDir' plugins/overtake.taskbar/Settings.qml || fail "Settings doesn't use the stripped copies"
pass "Settings points no Image at a theme's own file"

# ---------- The Lua that install writes, and ships, parses ----------
# (a stray quote in install.sh once cut the block short: it reached Hyprland, which
# then skipped the whole of your bindings.lua, and nothing else noticed)
fresh
grep -qF 'pcall(dofile' "$H/.config/hypr/bindings.lua" || fail "the mode's shortcuts aren't loaded from bindings.lua"
awk '/>>> overtake/,/<<< overtake/' "$H/.config/hypr/bindings.lua" | grep -q '^end$' || fail "the block in bindings.lua is cut short"
LUAC=$(command -v luac luac5.4 luac5.5 2>/dev/null | head -1 || true)
if [[ -n $LUAC ]]; then
  for f in "$H/.config/hypr/bindings.lua" "$H/.config/hypr/autostart.lua" hypr/*.lua; do
    "$LUAC" -p -o /dev/null "$f" 2>"$T/out" || { cat "$T/out"; fail "$f doesn't parse"; }
  done
  pass "the Lua that install writes and ships parses"
else
  pass "the mode's block in bindings.lua is whole (no luac here to parse it)"
fi

# ---------- Omarchy's layout shortcuts don't reach Overtake's modes ----------
for key in $(grep -hE 'workspace-layout-toggle' "$(dirname "$(dirname "$OMARCHY_SRC")")/default/hypr/bindings/"*.lua 2>/dev/null | sed -nE 's/^o\.bind\("([^"]+)".*/\1/p' | tr ' ' '_'); do
  for f in hypr/overtake-classic.lua hypr/overtake-studio.lua; do
    # (Studio's app_shortcut takes the key over the same way)
    grep -qF -e "hl.unbind(\"${key//_/ }\")" -e "app_shortcut(\"${key//_/ }\"" "$f" || fail "$f leaves Omarchy's layout shortcut ${key//_/ } on"
  done
done
grep -qF 'hl.unbind("SUPER + ALT + L")' hypr/overtake-classic.lua || fail "Classic leaves SUPER + ALT + L on"
grep -qF 'hl.unbind("SUPER + ALT + L")' hypr/overtake-studio.lua || fail "Studio leaves SUPER + ALT + L on"
if grep -q 'suppress_event' hypr/overtake.lua; then fail "a suppress rule is back: rules add up, it can't lift Omarchy's"; fi
pass "neither mode leaves a shortcut that changes a workspace's layout"

# ---------- File names in terminal output ----------
fresh
echo mine >"$H/.local/state/omarchy/current/theme.name"
stub omarchy-menu-images 'find "$HOME/.cache/overtake/bg-picker/1-theme" -mindepth 1 | head -1'
pick_named() {  # pick_named <file name>: sets OUT and RC from `overtake bg-picker`
  rm -rf "$H/.config/omarchy/backgrounds/mine"; mkdir -p "$H/.config/omarchy/backgrounds/mine"
  printf 'picture' >"$H/.config/omarchy/backgrounds/mine/$1"
  RC=0; sbx "$H" "$O" bg-picker >"$T/out" 2>"$T/err" || RC=$?
}
pick_named $'evil\033]0;PWNED\a.png'
[[ $RC != 0 ]] || fail "bg-picker printed a file name with escape codes"
LC_ALL=C grep -q $'\033' "$T/out" "$T/err" && fail "bg-picker let an escape code through"
grep -q 'control characters' "$T/err" || fail "bg-picker didn't say why it refused"
pick_named $'evil\xc2\x9b0m.png'     # (a C1 control, as UTF-8)
[[ $RC != 0 ]] || fail "bg-picker printed a file name with a C1 control"
pick_named $'two\nlines.png'
[[ $RC != 0 ]] || fail "bg-picker printed a file name with a newline"
pick_named 'plain café.png'
[[ $RC == 0 && $(<"$T/out") == "$H/.config/omarchy/backgrounds/mine/plain café.png" ]] || { cat "$T/out" "$T/err"; fail "bg-picker refused an ordinary name"; }
pick_named $'evil\033[2J.png'
sbx "$H" "$O" bg-picker apply >"$T/out" 2>&1 || { cat "$T/out"; fail "bg-picker apply"; }
[[ -s $T/out ]] && fail "bg-picker apply printed something"
[[ $(readlink "$H/.local/state/omarchy/current/background") == "$H/.config/omarchy/backgrounds/mine/"* ]] || fail "bg-picker apply didn't put the picture up"
stub omarchy-menu-images
pass "bg-picker refuses to print a file name with control characters; apply puts one up without printing"

# ---------- Studio's old pictures ----------
grep -q '1-mesa-day.png' <<<"$(sbx "$H" ./install.sh --dry-run)" || fail "the install list doesn't mention the old pictures it removes"
fresh
S="$H/Pictures/overtake/studio"
printf 'my own picture' >"$S/1-mesa-day.png"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall"; }
[[ $(<"$S/1-mesa-day.png") == "my own picture" ]] || fail "install removed a picture you made with an old picture's name"
# (the real pictures aren't in the repository any more: a copy of the installer
# that knows this test's bytes stands in for them)
mkdir -p "$T/repo2"; cp -r bin config hypr menu patches plugins wallpapers install.sh uninstall.sh manifest.json NOTICE.md "$T/repo2/"
sum=$(printf 'old shipped picture' | sha256sum | cut -c1-64)
sed -i -E "s/^[0-9a-f]{64} 1-mesa-day\.png$/$sum 1-mesa-day.png/" "$T/repo2/install.sh"
grep -q "^$sum 1-mesa-day.png$" "$T/repo2/install.sh" || fail "no digest line for 1-mesa-day.png"
printf 'old shipped picture' >"$S/1-mesa-day.png"
sbx "$H" "$T/repo2/install.sh" --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "install from the copy"; }
[[ ! -e $S/1-mesa-day.png ]] || fail "install kept an old picture exactly as shipped"
[[ $(grep -cE '^[0-9a-f]{64} [1-6]-[a-z-]+\.png$' install.sh) == 6 ]] || fail "install.sh should know six old pictures"
pass "of the six old pictures, only one exactly as shipped is removed, and the list says so"

# ---------- The post-update hook ----------
fresh
HOOK="$H/.config/omarchy/hooks/post-update.d/overtake.hook"
[[ -f $HOOK ]] || fail "install didn't add the hook"
: >"$ARGV_LOG"
# (run the way omarchy-hook runs it)
sbx "$H" env OVERTAKE_OMARCHY_PLUGINS="$UNFIT" bash "$HOOK" >"$T/out" 2>&1 || { cat "$T/out"; fail "the hook failed"; }
[[ ! -e $H/.config/omarchy/plugins/overtake.workspaces ]] || fail "the hook didn't rebuild from the new Omarchy"
log_text | grep -q "own version is used for workspaces" || fail "the hook's drop wasn't notified"
sbx "$H" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
[[ ! -e $HOOK ]] || fail "uninstall left the hook"
sbx "$H" bash -c "mkdir -p \"$(dirname "$HOOK")\"" ; sed -n '/^cat >.*overtake.hook/,/^EOF$/p' install.sh | sed '1d;$d' >"$HOOK"
sbx "$H" bash "$HOOK" >"$T/out" 2>&1 || { cat "$T/out"; fail "the hook with Overtake gone should do nothing"; }
rm -f "$HOOK"
pass "the post-update hook rebuilds the copies and notifies, goes on uninstall, and is harmless if left"

# ---------- While the installer runs ----------
fresh
stub omarchy-restart-shell "cat \"\$HOME/.local/share/overtake/installing\" >\"$T/seen\" 2>/dev/null"
sbx "$H" env -u OVERTAKE_NO_RELOAD ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall"; }
[[ -s $T/seen ]] || fail "no installing marker while the installer ran"
[[ $(<"$T/seen") =~ ^[0-9]+$ ]] || fail "the installing marker doesn't name the installer's process"
[[ ! -e $H/.local/share/overtake/installing ]] || fail "the installing marker stayed after the install"
rm -f "$T/seen"
stub omarchy-restart-shell
sed -i 's/^jq -r .\.version. .*/false/' "$T/repo2/install.sh"
sbx "$H" "$T/repo2/install.sh" --yes >>"$T/log" 2>&1 && fail "the broken copy of the installer should fail"
[[ ! -e $H/.local/share/overtake/installing ]] || fail "the installing marker stayed after an install that stopped"
pass "the installer marks itself while it runs, and the mark goes however it ends"

# ---------- What uninstall leaves you to do ----------
fresh
mkdir -p "$H/.config/omarchy/plugins/gleasonmt.overtake-mode"
sbx "$H" "$O" uninstall --yes >"$T/out" 2>&1 || { cat "$T/out"; fail "overtake uninstall"; }
grep -q 'omarchy plugin remove gleasonmt.overtake-mode' "$T/out" || { cat "$T/out"; fail "uninstall didn't say to remove the root plugin"; }
[[ -d $H/.config/omarchy/plugins/gleasonmt.overtake-mode ]] || fail "uninstall removed what omarchy plugin add installed"
rm -rf "$H/.config/omarchy/plugins/gleasonmt.overtake-mode"
sbx "$H" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall"; }
sbx "$H" "$O" uninstall --yes >"$T/out" 2>&1 || { cat "$T/out"; fail "overtake uninstall"; }
grep -q 'omarchy plugin remove' "$T/out" && { cat "$T/out"; fail "uninstall mentioned a root plugin that isn't there"; }
pass "uninstall names the omarchy plugin remove step when the root plugin is there, and only then"

# ---------- What reaches Hyprland's Lua ----------
fresh
for c in minimize restore show make-room maximize close unsnap copy-url fill-gap rename hide-app hide-others quit-app; do
  : >"$ARGV_LOG"
  if sbx "$H" "$O" "$c" 'x" }) ; hl.exec_cmd("touch /tmp/owned") --' >/dev/null 2>&1; then fail "overtake $c took a hostile address"; fi
  log_text | grep -q 'hl\.' && fail "overtake $c passed a hostile address to Hyprland"
done
for c in "snap left" "send 1"; do
  : >"$ARGV_LOG"
  # shellcheck disable=SC2086
  if sbx "$H" "$O" $c 'x" })' >/dev/null 2>&1; then fail "overtake $c took a hostile address"; fi
  log_text | grep -q 'hl\.' && fail "overtake $c passed a hostile address to Hyprland"
done
pass "a window address that isn't one is refused before it reaches Lua"

# A monitor name (from the hardware or a config) that would break out of its
# Lua string isn't sent; the same name as a workspace gets there intact.
fresh
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
cp "$HYPR/monitors.json" "$T/monitors.json"
jq '(.[].name) = "e\"vil" | (.[].specialWorkspace.name) = "special:minimized"' "$T/monitors.json" >"$HYPR/monitors.json"
: >"$ARGV_LOG"
sbx "$H" "$O" hide-minimized >>"$T/log" 2>&1
log_text | grep -q 'toggle_special' && fail "a monitor name with a quote was sent to Hyprland"
jq '(.[].specialWorkspace.name) = "special:minimized"' "$T/monitors.json" >"$HYPR/monitors.json"
: >"$ARGV_LOG"
sbx "$H" "$O" hide-minimized >>"$T/log" 2>&1
log_text | grep -q 'toggle_special' || fail "an ordinary monitor wasn't sent (test setup)"
cp "$T/monitors.json" "$HYPR/monitors.json"
hostile='Mail "; hl.exec_cmd("touch /tmp/owned") --'
use_workspace "$hostile"
: >"$HYPR/named-dispatches"
sbx "$H" "$O" minimize 0xa1 >>"$T/log" 2>&1
sbx "$H" "$O" restore 0xa1 >>"$T/log" 2>&1
grep -qxF "$hostile" "$HYPR/named-dispatches" || fail "a hostile workspace name didn't arrive as data"
use_workspace 1
pass "a monitor name that would break its Lua string isn't sent; a workspace name is only ever data"

# ---------- A notification's app name is literal text to Omarchy's focus command ----------
fresh
: >"$ARGV_LOG"
# (regex characters are plain text; a name that matches nothing brings up nothing)
printf '%s\n' '.*' | sbx "$H" "$O" notification-open >>"$T/log" 2>&1 && fail "the name .* matched a window as a pattern"
log_text | grep -aq 'omarchy-hyprland-focus-app' && fail "the app name reached a command line"
pass "a notification's app name is plain text, on stdin"

# ---------- CI ----------
grep -q '^    timeout-minutes: ' .github/workflows/tests.yml || fail "CI has no time limit"
grep -q 'cancel-in-progress: true' .github/workflows/tests.yml || fail "CI doesn't cancel superseded runs"
pass "CI has a time limit and cancels superseded runs"
