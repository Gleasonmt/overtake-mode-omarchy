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

# The card's icon, as built: a name goes to Qt's theme lookup and nothing else;
# a path, or a picture the sender supplies, reaches nothing. (Real Quickshell
# offscreen resolves no theme, so no file could be decoded there to show this;
# a crafted file was measured in a real Hyprland session.)
fresh_icons="$T/icons"; mkdir -p "$fresh_icons"
cp -a "$OMARCHY_SRC/notifications/." "$fresh_icons/"
python3 -I "$REPO/patches/apply.py" notifications "$fresh_icons" >/dev/null || fail "the notifications patch doesn't apply"
grep -q 'Util.fileUrl(value)' "$fresh_icons/Toast.qml" && fail "a card still opens an entry's icon by file path"
grep -q 'Security.localImageUrl(card.row.image)' "$fresh_icons/Toast.qml" && fail "a card still opens a picture a sender names"
[[ $(grep -c 'Quickshell.iconPath(' "$fresh_icons/Toast.qml") == 1 ]] || fail "a card looks an icon up somewhere other than overtakeIcon"
node -e '
const fs = require("fs")
const m = fs.readFileSync(process.argv[1], "utf8").match(/function overtakeIcon\(name\) \{\n([\s\S]*?)\n  \}\n/)
const check = (what, ok) => { if (!ok) { console.log("FAIL: " + what); process.exit(1) } }
check("the card has overtakeIcon", !!m)
const seen = [], Quickshell = { iconPath: (n, c) => { seen.push(n); return c === true ? "image://icon/" + n : "?" } }
const icon = n => new Function("Quickshell", "name", m[1])(Quickshell, n)
for (const bad of ["/tmp/x.png", "/home/me/fifo", "file:///x", "../x", "a/b", "a b", "", null, "x".repeat(200)])
  check("no icon name: " + String(bad).slice(0, 20), icon(bad) === "")
check("none of those reached the lookup", !seen.length)
check("a name is looked up, in the theme only", icon("firefox") === "image://icon/firefox" && seen.join() === "firefox")
' "$fresh_icons/Toast.qml" || fail "a card's icon by name"
pass "a card's icon: a name goes to the theme lookup; a path, or a picture the sender names, goes nowhere"
