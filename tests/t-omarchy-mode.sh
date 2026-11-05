#!/bin/bash
# In Omarchy mode Omarchy runs as it ships: Overtake's copies of Omarchy's
# notifications and battery services are switched on only with Classic or
# Studio, and off again when you switch back (checked through the stubbed
# `omarchy plugin` calls, with reloads allowed, all against stubs).
source "$(dirname "$0")/lib.sh"

H="$T/home"
make_home "$H"
cd "$REPO"
live() { env -u OVERTAKE_NO_RELOAD "$@"; }   # (reloads on: they only reach stubs)
calls() { tr '\0' ' ' <"$ARGV_LOG" | grep -o "omarchy plugin [a-z]* overtake\.[a-z]*" || true; }

: >"$ARGV_LOG"
sbx "$H" env -u OVERTAKE_NO_RELOAD ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
for id in notifications battery; do
  calls | grep -q "enable overtake.$id" && fail "install switched overtake.$id on in Omarchy mode"
  calls | grep -q "disable overtake.$id" || fail "install didn't make sure Omarchy's own $id runs"
done
pass "install in Omarchy mode leaves Omarchy's own notifications and battery running"

: >"$ARGV_LOG"
sbx "$H" env -u OVERTAKE_NO_RELOAD "$H/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
for id in notifications battery; do calls | grep -q "enable overtake.$id" || fail "on didn't switch overtake.$id on"; done
pass "Classic/Studio switch Overtake's notifications and battery on"

: >"$ARGV_LOG"
sbx "$H" env -u OVERTAKE_NO_RELOAD "$H/.local/bin/overtake" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off"; }
for id in notifications battery; do calls | grep -q "disable overtake.$id" || fail "off didn't switch overtake.$id off"; done
jq -e '.bar | tostring | test("overtake") | not' "$H/.config/omarchy/shell.json" >/dev/null || fail "Overtake's bar left in Omarchy mode"
pass "switching to Omarchy turns them off and puts the bar back"
