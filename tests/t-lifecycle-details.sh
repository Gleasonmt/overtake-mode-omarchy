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
  const cases = [[m, "0.2.0\n", ""], [m, "0.3.0\n", ""], [m, "0.1.15\n", "0.2.0"], [m, "", "0.2.0"], ["not json", "0.1.15", ""], ["{}", "0.1.15", ""]]
  for (const [a, b, want] of cases) if (f(a, b) !== want) { console.error("FAIL: versionToInstall", a, JSON.stringify(b), "gave", f(a, b)); process.exit(1) }
' || fail "Setup.qml's version check"
grep -q 'Run ./install.sh again in' Setup.qml || fail "Setup.qml doesn't ask for the installer again"
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
printf '\n' >"$TOML"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ ! -e $TOML ]] || fail "off left a shell.toml with only white space"
printf '[font]\nbase-size = 12\n' >"$TOML"
sbx "$H" "$O" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
sbx "$H" "$O" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
[[ $(<"$TOML") == $'[font]\nbase-size = 12' ]] || fail "off changed your shell.toml"
pass "shell.toml goes when only white space is left, and keeps what's yours"

# ---------- What the code and the login line say ----------
grep -q "omarchy-shell-config writes them" bin/overtake && fail "replace_with's comment claims it works as omarchy-shell-config does"
grep -q "the installer runs it" bin/overtake && fail "the bg-picker comment says the installer runs it"
fresh
grep -q 'check and rebuild its patched copies' "$H/.config/hypr/autostart.lua" || fail "the login line's comment doesn't say it rebuilds the copies"
grep -q 'check and$' <<<"$(sbx "$H" ./install.sh --dry-run)" || fail "the install list doesn't say the login line rebuilds the copies"
pass "comments and the install list describe what the code does"

# ---------- CI ----------
grep -q '^    timeout-minutes: ' .github/workflows/tests.yml || fail "CI has no time limit"
grep -q 'cancel-in-progress: true' .github/workflows/tests.yml || fail "CI doesn't cancel superseded runs"
pass "CI has a time limit and cancels superseded runs"
