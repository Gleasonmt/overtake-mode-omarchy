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
log_text() { tr '\0' ' ' <"$ARGV_LOG"; }
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

# A write that fails at close: Python only warns, and exits 0. (Real ENOSPC,
# from /dev/full.) That's a failed build, not a copy cut short.
fresh
echo older >"$H/.config/omarchy/plugins/overtake.audio/older"
printf 'open("/dev/full", "w").write("x")\n' >"$H/.local/share/overtake/apply.py"
sbx "$H" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies"; }
[[ -f $H/.config/omarchy/plugins/overtake.audio/older ]] || { cat "$T/out"; fail "a build whose write failed at close replaced a working copy"; }
grep -q "stays in use" "$T/out" || { cat "$T/out"; fail "a write that failed at close wasn't reported"; }
pass "a patch whose write fails at close counts as a failed build"

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
for branch in omarchy wallpaper image text; do
  art_home "my own art"; art "$branch"
  art_back "my own art" "$branch from your own art"
done
printf 'THE LOGO\n' >"$T/logo-copy"
art_home "THE LOGO"$'\n'; art wallpaper; [[ $(<"$ART") == "wallpaper art" ]] || fail "wallpaper art wasn't made (test setup)"
art_back "THE LOGO"$'\n' "wallpaper from art equal to Omarchy's logo"
art_home "my own art"; art image; art wallpaper; art omarchy
art_back "my own art" "the first replacement is what's kept"
art_home ""; art image; art_back "" "from empty art"
art_home -; art wallpaper; [[ -s $ART ]] || fail "wallpaper art wasn't made (test setup)"; art_back - "with no art before"
stub omarchy-transcode-ascii; stub omarchy-branding-screensaver; stub omarchy-launch-editor
pass "the art you had before Overtake first replaced it comes back, in every branch"

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
sbx "$H" "$O" notification-open 'a.b*c+d?e(f)g[h]i{j}k|l^m$n\o' >>"$T/log" 2>&1 || true
log_text | grep -aqF 'omarchy-hyprland-focus-app a\.b\*c\+d\?e\(f\)g\[h\]i\{j\}k\|l\^m\$n\\o' || fail "the app name reached omarchy-hyprland-focus-app as a pattern: $(log_text | grep -a focus-app)"
pass "a notification's app name reaches omarchy-hyprland-focus-app as literal text"

# ---------- CI ----------
grep -q '^    timeout-minutes: ' .github/workflows/tests.yml || fail "CI has no time limit"
grep -q 'cancel-in-progress: true' .github/workflows/tests.yml || fail "CI doesn't cancel superseded runs"
pass "CI has a time limit and cancels superseded runs"
