#!/bin/bash
# In Omarchy mode Omarchy runs as it ships: Overtake's copies of Omarchy's
# notifications and battery services are switched on only with Classic or
# Studio, and off again when you switch back. Installing while in Omarchy mode
# doesn't touch shell.json, and a hand-back that the shell can't do is finished
# in the file (the stub below answers as the real shell was measured to: any
# change writes out its whole config, a full bar included; disabling a plugin
# it doesn't know answers ok and does nothing).
source "$(dirname "$0")/lib.sh"

H="$T/home"
make_home "$H"
SJ="$H/.config/omarchy/shell.json"
cd "$REPO"
calls() { tr '\0' ' ' <"$ARGV_LOG" | grep -o "omarchy plugin [a-z]* overtake\.[a-z]*" || true; }

stub omarchy "$(cat <<EOF
SJ="$SJ"
id=\${3:-}; own=omarchy.\${id#overtake.}
[[ \${1:-} == plugin ]] || exit 0
shell_writes() {
  jq --arg id "\$id" --arg own "\$own" "(if has(\"bar\") then . else .bar = {layout: {}, added_by_the_shell: true} end) | \$1" "\$SJ" >"\$SJ.new" && cat "\$SJ.new" >"\$SJ"; rm -f "\$SJ.new"
}
if [[ ! -d \$HOME/.config/omarchy/plugins/\$id ]]; then
  [[ \$2 == disable ]] && { echo "Disabled \$id"; exit 0; }
  echo "plugin '\$id' is not known" >&2; exit 1
fi
case \$2 in
  enable) shell_writes '.plugins = ((.plugins // []) + [{id: \$id}]) | .disabledPlugins = ((.disabledPlugins // []) + [\$own]) | .cloneSourceRestores = ((.cloneSourceRestores // []) + [\$id])' ;;
  disable) shell_writes '.plugins = ((.plugins // []) | map(select(.id != \$id))) | .disabledPlugins = ((.disabledPlugins // []) - [\$own]) | .cloneSourceRestores = ((.cloneSourceRestores // []) - [\$id]) | (if .disabledPlugins == [] then del(.disabledPlugins) else . end) | (if .cloneSourceRestores == [] then del(.cloneSourceRestores) else . end)' ;;
esac
EOF
)"

# A shell.json with no bar of its own (Omarchy's default stays followed), and
# formatting of its own, which only byte-for-byte can show.
printf '{ "theme":  "x" }\n' >"$SJ"
cp "$SJ" "$T/sj.before"
: >"$ARGV_LOG"
sbx "$H" env -u OVERTAKE_NO_RELOAD ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
for id in notifications battery; do
  calls | grep -q "overtake.$id" && fail "install in Omarchy mode asked the shell about overtake.$id: $(calls)"
done
cmp -s "$SJ" "$T/sj.before" || { cat "$SJ"; fail "install in Omarchy mode rewrote shell.json"; }
pass "install in Omarchy mode leaves shell.json as it was and doesn't ask the shell to change anything"
sbx "$H" env -u OVERTAKE_NO_RELOAD ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall"; }
cmp -s "$SJ" "$T/sj.before" || { cat "$SJ"; fail "a reinstall in Omarchy mode rewrote shell.json"; }
sbx "$H" env -u OVERTAKE_NO_RELOAD ./uninstall.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
cmp -s "$SJ" "$T/sj.before" || { cat "$SJ"; fail "uninstall from Omarchy mode rewrote shell.json"; }
pass "reinstall and uninstall from Omarchy mode leave it as it was too"

rm -rf "$H"
make_home "$H"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }

: >"$ARGV_LOG"
sbx "$H" env -u OVERTAKE_NO_RELOAD "$H/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
for id in notifications battery; do calls | grep -q "enable overtake.$id" || fail "on didn't switch overtake.$id on"; done
pass "Classic/Studio switch Overtake's notifications and battery on"

: >"$ARGV_LOG"
sbx "$H" env -u OVERTAKE_NO_RELOAD "$H/.local/bin/overtake" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
for id in notifications battery; do calls | grep -q "disable overtake.$id" || fail "off didn't switch overtake.$id off"; done
jq -e '.bar | tostring | test("overtake") | not' "$SJ" >/dev/null || fail "Overtake's bar left in Omarchy mode"
jq -e '(has("disabledPlugins") | not) and (has("cloneSourceRestores") | not)' "$SJ" >/dev/null || { cat "$SJ"; fail "off left Omarchy's own switched off"; }
pass "switching to Omarchy turns them off and puts the bar back"

# A hand-back the shell can't do: it doesn't list the copy (its folder is gone,
# or it hasn't scanned it), so a disable would answer "ok" and do nothing.
stale='.plugins = [{"id":"overtake.notifications"}] | .disabledPlugins = ["omarchy.notifications"] | .cloneSourceRestores = ["overtake.notifications"]'
jq "$stale" "$SJ" >"$T/s.json" && cat "$T/s.json" >"$SJ"
mv "$H/.config/omarchy/plugins/overtake.notifications" "$T/held"
: >"$ARGV_LOG"
sbx "$H" env -u OVERTAKE_NO_RELOAD "$H/.local/bin/overtake" copies off >>"$T/log" 2>&1 || { cat "$T/log"; fail "copies off"; }
jq -e '(has("disabledPlugins") | not) and (has("cloneSourceRestores") | not) and ((.plugins // []) | length == 0)' "$SJ" >/dev/null ||
  { cat "$SJ"; fail "a copy the shell doesn't list wasn't handed back: no notification service"; }
calls | grep -q "disable overtake.notifications" && fail "the shell was asked to disable a copy it doesn't list"
mv "$T/held" "$H/.config/omarchy/plugins/overtake.notifications"
pass "a disable counts only if the shell lists the copy; otherwise shell.json is put right"

# Stale from an earlier run: `resume` at login repairs it, in Omarchy mode...
jq "$stale" "$SJ" >"$T/s.json" && cat "$T/s.json" >"$SJ"
sbx "$H" "$H/.local/bin/overtake" resume >>"$T/log" 2>&1 || { cat "$T/log"; fail "resume"; }
jq -e '(has("disabledPlugins") | not) and (has("cloneSourceRestores") | not)' "$SJ" >/dev/null || { cat "$SJ"; fail "resume didn't repair a stale hand-back in Omarchy mode"; }
# ...and with the mode on, when the copy's folder is gone...
sbx "$H" "$H/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
jq "$stale" "$SJ" >"$T/s.json" && cat "$T/s.json" >"$SJ"
mv "$H/.config/omarchy/plugins/overtake.notifications" "$T/held"
sbx "$H" "$H/.local/bin/overtake" resume >>"$T/log" 2>&1 || { cat "$T/log"; fail "resume"; }
jq -e '(has("disabledPlugins") | not) and (has("cloneSourceRestores") | not)' "$SJ" >/dev/null || { cat "$SJ"; fail "resume didn't repair a copy whose folder is gone"; }
mv "$T/held" "$H/.config/omarchy/plugins/overtake.notifications"
# ...not when the copy is really in use, and never one you turned off yourself.
jq "$stale" "$SJ" >"$T/s.json" && cat "$T/s.json" >"$SJ"
sbx "$H" "$H/.local/bin/overtake" resume >>"$T/log" 2>&1 || { cat "$T/log"; fail "resume"; }
jq -e '.cloneSourceRestores == ["overtake.notifications"]' "$SJ" >/dev/null || { cat "$SJ"; fail "resume undid a copy in use"; }
sbx "$H" "$H/.local/bin/overtake" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
jq 'del(.plugins, .cloneSourceRestores) | .disabledPlugins = ["omarchy.battery"]' "$SJ" >"$T/s.json" && cat "$T/s.json" >"$SJ"
sbx "$H" "$H/.local/bin/overtake" resume >>"$T/log" 2>&1 || { cat "$T/log"; fail "resume"; }
jq -e '.disabledPlugins == ["omarchy.battery"]' "$SJ" >/dev/null || { cat "$SJ"; fail "resume turned on what you turned off"; }
jq 'del(.disabledPlugins)' "$SJ" >"$T/s.json" && cat "$T/s.json" >"$SJ"
pass "resume repairs a stale hand-back, and leaves a copy in use and your own choice alone"

# No shell to ask (a TTY or SSH session): switching off is done in shell.json
# itself, so Omarchy's own run when the shell next starts.
stub omarchy 'echo "omarchy-shell is not running" >&2; exit 1'
stub omarchy-shell 'echo "omarchy-shell is not running" >&2; exit 1'
jq '.plugins = [{"id":"overtake.notifications"},{"id":"overtake.battery"}]
    | .disabledPlugins = ["omarchy.notifications","omarchy.battery"]
    | .cloneSourceRestores = ["overtake.notifications","overtake.battery"]' \
  "$SJ" >"$T/s.json" && cat "$T/s.json" >"$SJ"
SECONDS=0
sbx "$H" env -u OVERTAKE_NO_RELOAD "$H/.local/bin/overtake" copies off >>"$T/log" 2>&1 || { cat "$T/log"; fail "copies off"; }
jq -e '((.plugins // []) | map(.id? // .) | any(startswith("overtake.notifications") or startswith("overtake.battery")) | not)
       and (has("disabledPlugins") | not) and (has("cloneSourceRestores") | not)' \
  "$SJ" >/dev/null || { cat "$SJ"; fail "with no shell running, the copies weren't switched off in shell.json"; }
(( SECONDS < 4 )) || fail "with no shell running, switching off waited for one ($SECONDS s)"
pass "with no shell running, switching off is done in shell.json itself, without waiting"
