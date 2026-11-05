#!/bin/bash
# Day & Night's only network request (wttr.in) treated as a compromised
# endpoint: at most 256 KB is read, and only real times reach `date` or the
# cache; anything else falls back to 07:00/19:00 without caching.
source "$(dirname "$0")/lib.sh"

fn=$(sed -n '/^sun_times() {/,/^}/p' "$REPO/bin/overtake")
[[ -n $fn ]] || fail "sun_times not found"
try() {  # try <curl body script> → prints "<result> | <cached files>"
  stub curl "$1"
  rm -rf "$T/st"; mkdir -p "$T/st"
  local out
  out=$(PATH="$STUB:$WRAP:/usr/bin:/bin" STATE_DIR="$T/st" bash -c "set -euo pipefail; $fn; sun_times")
  echo "$out | $(ls "$T/st" | wc -l)"
}
good='{"weather":[{"astronomy":[{"sunrise":"06:52 AM","sunset":"05:41 PM"}]}]}'
[[ $(try "echo '$good'") == "0652 1741 | 1" ]] || fail "a real answer wasn't used and cached: $(try "echo '$good'")"
pass "a real answer is used and cached for the day"
[[ $(try "echo '{\"weather\":[{\"astronomy\":[{\"sunrise\":\"99:99\",\"sunset\":\"05:41 PM\"}]}]}'") == "0700 1900 | 0" ]] || fail "an impossible time was used or cached"
[[ $(try "echo '{\"weather\":[{\"astronomy\":[{\"sunrise\":\"--help\",\"sunset\":\"x\"}]}]}'") == "0700 1900 | 0" ]] || fail "junk reached date or the cache"
pass "impossible or junk times fall back to 07:00/19:00, uncached"
# an endless answer: the valid JSON would only end after 300 KB of padding
big="printf '{\"pad\":\"'; head -c 300000 /dev/zero | tr '\\0' a; printf '\",'; echo '\"weather\":[{\"astronomy\":[{\"sunrise\":\"06:52 AM\",\"sunset\":\"05:41 PM\"}]}]}'"
bash -c "$big" | jq -e .weather >/dev/null || fail "the oversized answer isn't valid JSON (test setup)"
[[ $(try "$big") == "0700 1900 | 0" ]] || fail "more than 256 KB was read: $(try "$big")"
pass "an answer over 256 KB is cut off and not used"
