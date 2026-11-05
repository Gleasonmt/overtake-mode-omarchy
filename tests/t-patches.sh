#!/bin/bash
# The five patched copies build from the Omarchy shell plugins at
# $OMARCHY_SRC; a plugin Omarchy has changed is left out cleanly (Omarchy's
# own used), never half-built.
source "$(dirname "$0")/lib.sh"

H="$T/home"
mkdir -p "$H/.local/share/overtake" "$H/.config/omarchy"
cp "$REPO/patches/apply.py" "$REPO/NOTICE.md" "$H/.local/share/overtake/"
out=$(sbx "$H" "$REPO/bin/overtake" build-copies all 2>&1)
for n in workspaces bluetooth audio notifications battery; do
  [[ -f $H/.config/omarchy/plugins/overtake.$n/manifest.json ]] || { echo "$out"; fail "overtake.$n not built"; }
  [[ $(stat -c %a "$H/.config/omarchy/plugins/overtake.$n") == 755 ]] || fail "overtake.$n folder mode"
  [[ -f $H/.config/omarchy/plugins/overtake.$n/NOTICE.md ]] || fail "overtake.$n has no NOTICE.md (Omarchy's MIT notice)"
done
pass "all five patched copies build, each with Omarchy's notice"

# An Omarchy whose battery plugin changed: that copy is left out, the others stay.
cp -a "$OMARCHY_SRC" "$T/src"
sed -i 's/function checkBattery() {/function checkBatteryChanged() {/' "$T/src/services/battery/Service.qml"
OVERTAKE_OMARCHY_PLUGINS="$T/src" sbx "$H" env OVERTAKE_OMARCHY_PLUGINS="$T/src" "$REPO/bin/overtake" build-copies update >/dev/null 2>&1 || true
[[ ! -e $H/.config/omarchy/plugins/overtake.battery ]] || fail "a copy whose patch no longer fits was kept"
[[ -d $H/.config/omarchy/plugins/overtake.notifications ]] || fail "an unaffected copy was removed"
ls -A "$H/.config/omarchy/plugins" | grep -q '^\.overtake-build' && fail "a temporary build folder was left behind"
pass "a patch that no longer fits drops only that copy, cleanly"
