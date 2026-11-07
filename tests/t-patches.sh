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

# The card's icon, as built: every name goes through UserIcons.qml, the same file as
# the taskbar's, written into the copy; a path, or a picture the sender supplies,
# reaches nothing. (Real Quickshell offscreen resolves no theme, so no file could be
# decoded there to show this; a crafted file was measured in a real Hyprland session.)
fresh_icons="$T/icons"; mkdir -p "$fresh_icons"
cp -a "$OMARCHY_SRC/notifications/." "$fresh_icons/"
python3 -I "$REPO/patches/apply.py" notifications "$fresh_icons" >/dev/null || fail "the notifications patch doesn't apply"
cmp -s "$fresh_icons/UserIcons.qml" "$REPO/plugins/overtake.taskbar/UserIcons.qml" || fail "the copy's UserIcons.qml isn't the taskbar's"
grep -q 'Util.fileUrl(value)' "$fresh_icons/Toast.qml" && fail "a card still opens an entry's icon by file path"
grep -q 'Security.localImageUrl(card.row.image)' "$fresh_icons/Toast.qml" && fail "a card still opens a picture a sender names"
grep -q 'Quickshell.iconPath(' "$fresh_icons/Toast.qml" && fail "a card looks an icon up itself, not through UserIcons"
[[ $(grep -c 'card.overtakeIcon(' "$fresh_icons/Toast.qml") == 2 ]] || fail "a card's two lookups don't both go through overtakeIcon"
grep -q 'return scene ? scene.overtakeIcons.source(name) : ""' "$fresh_icons/Toast.qml" || fail "overtakeIcon doesn't ask the service's UserIcons"
grep -q 'readonly property UserIcons overtakeIcons: UserIcons {}' "$fresh_icons/Service.qml" || fail "the service has no UserIcons"
[[ $(grep -c 'Quickshell.iconPath(' "$fresh_icons/UserIcons.qml") == 1 ]] || fail "UserIcons looks up in more than one place"
# (a plugin that already has the file isn't patched over it)
taken="$T/icons-taken"; mkdir -p "$taken"; cp -a "$OMARCHY_SRC/notifications/." "$taken/"; : >"$taken/UserIcons.qml"
rc=0; python3 -I "$REPO/patches/apply.py" notifications "$taken" >/dev/null 2>&1 || rc=$?
(( rc == 3 )) || fail "a plugin that already has UserIcons.qml was patched over it (exit $rc)"
pass "a card's icon goes through the taskbar's UserIcons, written into the copy; never a path or a sender's picture"
