#!/bin/bash
# Builds the notifications copy from $OMARCHY_SRC as bin/overtake does, then
# runs the history orderings in t-notifications.js against it.
source "$(dirname "$0")/lib.sh"
cp -a "$OMARCHY_SRC/notifications" "$T/copy"
python3 -I "$REPO/patches/apply.py" notifications "$T/copy" || fail "the notifications patch doesn't apply"
node "$REPO/tests/t-notifications.js" "$T/copy" "$REPO"

# A disk that runs out while the patcher writes: at every size, it either fails
# or leaves the whole file. Never exit 0 with a cut-off copy. (A real full disk:
# a small tmpfs in a private mount namespace. Skipped without user namespaces.)
if unshare -r -m true 2>/dev/null; then
  cat > "$T/full.sh" <<'FULL'
#!/bin/bash
src=$1; apply=$2; want=$3; d=$4; bad=0; tried=0; failed=0
for kib in $(seq 56 4 400); do
  mkdir -p "$d/m"; mount -t tmpfs -o "size=${kib}k" tmpfs "$d/m" || exit 9
  if cp -r "$src/." "$d/m/" 2>/dev/null; then
    tried=$((tried + 1))
    if python3 -I "$apply" notifications "$d/m" >/dev/null 2>&1; then
      for f in Service.qml Toast.qml Store.js; do cmp -s "$d/m/$f" "$want/$f" || { echo "${kib}k: exit 0 with a cut-off $f"; bad=1; }; done
    else failed=$((failed + 1)); fi
  fi
  umount "$d/m"
done
echo "tried=$tried failed=$failed"
exit $bad
FULL
  out=$(unshare -r -m bash "$T/full.sh" "$OMARCHY_SRC/notifications" "$REPO/patches/apply.py" "$T/copy" "$T" 2>&1) || fail "the patcher on a full disk: $out"
  grep -qE 'failed=[1-9]' <<<"$out" || fail "(setup) the patcher never ran out of room: $out"
  pass "the patcher never exits 0 with a cut-off copy on a full disk ($out)"
else
  echo "skipped: no user namespaces for the patcher's full-disk check"
fi

# A commented-out textFormat doesn't count as plain text. (On a scratch plugin.)
mkdir -p "$T/pt/tests" "$T/pt/plugins/x" "$T/pt/patches"
cp "$REPO/tests/t-plain-text.py" "$T/pt/tests/"
touch "$T/pt/Setup.qml"
printf 'import QtQuick\nText {\n  // textFormat: Text.PlainText\n  text: "x"\n}\n' > "$T/pt/plugins/x/A.qml"
if OMARCHY_SRC=$T/none python3 -I "$T/pt/tests/t-plain-text.py" >/dev/null; then fail "a commented-out textFormat passed the plain-text test"; fi
printf 'import QtQuick\nText {\n  textFormat: Text.PlainText // "plain"\n  text: "http://x/" // {\n}\n' > "$T/pt/plugins/x/A.qml"
OMARCHY_SRC=$T/none python3 -I "$T/pt/tests/t-plain-text.py" >/dev/null || fail "(control) a real textFormat with comments failed the plain-text test"
pass "the plain-text test ignores what's in comments"
