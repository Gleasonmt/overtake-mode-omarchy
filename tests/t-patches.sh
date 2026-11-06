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

# The card's icon by name, as built: a name in your own folder never reaches Qt's
# lookup. (Real Quickshell offscreen resolves no theme, so no file could be decoded
# there to show this; a crafted file was measured in a real Hyprland session.)
fresh_icons="$T/icons"; mkdir -p "$fresh_icons"
cp -a "$OMARCHY_SRC/notifications/." "$fresh_icons/"
python3 -I "$REPO/patches/apply.py" notifications "$fresh_icons" >/dev/null || fail "the notifications patch doesn't apply"
node -e '
const fs = require("fs")
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma.*$/m, "").replace(/^\.import.*$/mg, "")
const I = new Function("Security", src + "; return { overtakeSetCopies, overtakeSetSaved, overtakeSource }")({})
const seen = [], look = n => { seen.push(n); return "image://icon/" + n }
const check = (what, ok) => { if (!ok) { console.log("FAIL: " + what); process.exit(1) } }
check("no list yet: nothing is looked up", I.overtakeSource("firefox", look) === "" && !seen.length)
I.overtakeSetCopies("site\tabc.png\nbomb\t\n", "/c"); I.overtakeSetSaved(["justsaved", "site"])
check("a copied icon is drawn from its copy", I.overtakeSource("site", look) === "file:///c/abc.png")
check("one with no copy shows none", I.overtakeSource("bomb", look) === "")
check("one just saved shows none", I.overtakeSource("justsaved", look) === "")
check("a path is no name", I.overtakeSource("/tmp/x.png", look) === "" && I.overtakeSource("file:///x", look) === "")
check("none of those reached the lookup", !seen.length)
check("a system icon is looked up", I.overtakeSource("firefox", look) === "image://icon/firefox" && seen.length === 1)
' "$fresh_icons/Icons.js" || fail "a card's icon by name"
pass "a card's icon by name: copies for your folder, the lookup only for the rest"
