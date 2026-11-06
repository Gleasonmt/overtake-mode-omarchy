#!/bin/bash
# A full disk is a passing problem: it never drops a patched copy or cuts one of
# your files short, and an edit that can't be done says so. Real ENOSPC: each
# part mounts a small tmpfs over one folder inside `unshare -r -m`. (Skipped
# where that isn't allowed.)
if [[ ${1:-} != inner ]]; then
  if ! unshare -r -m true 2>/dev/null; then echo "skipped: unshare -r -m isn't allowed here"; exit 0; fi
  exec unshare -r -m bash "$0" inner
fi
source "$(dirname "$0")/lib.sh"
cd "$REPO"
COPIES="workspaces bluetooth audio notifications battery"

H="$T/home"
make_home "$H"
O="$H/.local/bin/overtake"
P="$H/.config/omarchy/plugins"
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
cp -a "$P" "$T/fresh"               # each copy as a build makes it
# Older copies, so a build really has something to replace.
for c in $COPIES; do echo "// older" >>"$P/overtake.$c/manifest.json.old"; done
cp -a "$P" "$T/older"
cp "$H/.config/omarchy/shell.json" "$T/sj.before"

# After a build under pressure: each copy is whole, the older one or the new one.
check_copies() {  # check_copies <what>
  local c
  for c in $COPIES; do
    [[ -d $P/overtake.$c ]] || { cat "$T/out"; fail "$1: overtake.$c was dropped"; }
    diff -rq "$T/older/overtake.$c" "$P/overtake.$c" >/dev/null || diff -rq "$T/fresh/overtake.$c" "$P/overtake.$c" >/dev/null ||
      { diff -rq "$T/fresh/overtake.$c" "$P/overtake.$c" | head -3; fail "$1: overtake.$c was left half written"; }
  done
  grep -q 'left out' "$T/out" && { cat "$T/out"; fail "$1: a disk problem was taken for Omarchy changing"; }
  [[ ! -e $H/.local/state/overtake/copies-left-out ]] || fail "$1: copies recorded as left out"
  cmp -s "$H/.config/omarchy/shell.json" "$T/sj.before" || fail "$1: shell.json changed"
}
kept_seen=0

# No data blocks left, then room for part of a build at various points.
used=$(du -sk "$T/older" | cut -f1)
for room in 0 4 16 64 128 256 512 1024; do
  mount -t tmpfs -o "size=$((used + room + 256))k" tmpfs "$P"
  cp -a "$T/older/." "$P/"
  dd if=/dev/zero of="$P/.fill" bs=4k 2>/dev/null || true
  rm -f "$P/.fill"
  dd if=/dev/zero of="$P/.fill" bs=1k count=$(( $(df -k --output=avail "$P" | tail -1) - room )) 2>/dev/null || true
  sbx "$H" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies with ${room}k left"; }
  rm -f "$P/.fill"
  check_copies "${room}k of data left"
  grep -q 'stays in use' "$T/out" && kept_seen=$((kept_seen + 1))
  umount "$P"
done
(( kept_seen > 0 )) || fail "no size filled the disk (the harness isn't working)"
pass "a disk with no data blocks never drops a copy or leaves one half written ($kept_seen of 8 sizes failed a build)"

# No inodes left, then a few.
inodes=$(find "$T/older" | wc -l)
kept_seen=0
for room in 0 1 2 3 5 10 20 40; do
  mount -t tmpfs -o "nr_inodes=$((inodes + room)),size=64m" tmpfs "$P"
  cp -a "$T/older/." "$P/" 2>/dev/null || true
  diff -rq "$T/older" "$P" >/dev/null || { umount "$P"; continue; }
  sbx "$H" "$O" build-copies update >"$T/out" 2>&1 || { cat "$T/out"; fail "build-copies with $room inodes left"; }
  check_copies "$room inodes left"
  grep -q 'stays in use' "$T/out" && kept_seen=$((kept_seen + 1))
  umount "$P"
done
(( kept_seen > 0 )) || fail "no count ran out of inodes (the harness isn't working)"
pass "a disk with no inodes never drops a copy or leaves one half written ($kept_seen of 8 counts failed a build)"
rm -rf "$P"; cp -a "$T/fresh" "$P"

# Your own files, through the real installer: at every size they're either as
# they were, or whole with the block closed, and a failure stops it.
B="$H/.config/hypr/bindings.lua"
HY="$H/.config/hypr"
MENU_DIR="$H/.config/omarchy/extensions"
head -c 6000 /dev/zero | tr '\0' '#' >"$T/big"; echo >>"$T/big"
sbx "$H" ./uninstall.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
stops=0 goes=0
for kb in 16 20 24 28 32 36 40 44 48 52 56 60; do
  mount -t tmpfs -o "size=${kb}k" tmpfs "$HY"
  cp "$T/big" "$B"; printf -- '-- auto\n' >"$HY/autostart.lua"
  rc=0; sbx "$H" ./install.sh --yes >"$T/out" 2>&1 || rc=$?
  grep -q 'Exception ignored' "$T/out" && { cat "$T/out"; fail "${kb}k: a failed write was only warned about"; }
  if cmp -s "$B" "$T/big"; then
    if [[ $rc == 0 ]]; then cat "$T/out"; fail "${kb}k: install finished without its block in bindings.lua"; fi
    stops=$((stops + 1))
  else
    [[ $(head -c 6001 "$B" | cmp - "$T/big" && echo same) == same ]] || fail "${kb}k: bindings.lua lost your text"
    [[ $(tail -n 1 "$B") == '-- <<< overtake' ]] || { [[ $rc != 0 ]] && fail "${kb}k: bindings.lua cut short and install failed"; fail "${kb}k: bindings.lua has no closing marker, install answered ok"; }
    goes=$((goes + 1))
  fi
  umount "$HY"
done
(( stops > 0 && goes > 0 )) || fail "the sizes didn't cover both outcomes ($stops stopped, $goes went through)"
pass "bindings.lua through a full disk: as it was and install stops ($stops sizes), or whole with its block ($goes sizes)"

# The menu: the same.
head -c 7500 /dev/zero | tr '\0' ' ' >"$T/pad"
{ printf '{\n'; cat "$T/pad"; printf '\n  "personal": {"label":"P"}\n}\n'; } >"$T/menu"
stops=0
for kb in 8 12 16 20; do
  mount -t tmpfs -o "size=${kb}k" tmpfs "$MENU_DIR"
  cp "$T/menu" "$MENU_DIR/omarchy-menu.jsonc"
  rc=0; sbx "$H" ./install.sh --yes >"$T/out" 2>&1 || rc=$?
  grep -q 'Exception ignored' "$T/out" && { cat "$T/out"; fail "${kb}k: a failed menu write was only warned about"; }
  if cmp -s "$MENU_DIR/omarchy-menu.jsonc" "$T/menu"; then
    [[ $rc != 0 ]] || fail "${kb}k: install finished without its menu entry"
    grep -q "couldn't write" "$T/out" || { cat "$T/out"; fail "${kb}k: no clear message"; }
    stops=$((stops + 1))
  else
    grep -q '<<< overtake' "$MENU_DIR/omarchy-menu.jsonc" && tail -n 1 "$MENU_DIR/omarchy-menu.jsonc" | grep -q '^}$' || fail "${kb}k: the menu was cut short"
  fi
  umount "$MENU_DIR"
done
(( stops > 0 )) || fail "no menu size ran out of room (the harness isn't working)"
pass "the menu through a full disk: as it was and install says why ($stops sizes), or whole"

# Uninstall: stops with your file as it was, its own files still there to retry.
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
cp -a "$HY" "$T/hy-saved"
mount -t tmpfs -o size=128k tmpfs "$HY"
cp -a "$T/hy-saved/." "$HY/"
cp "$HY/bindings.lua" "$T/bind"
dd if=/dev/zero of="$HY/.fill" bs=4k 2>/dev/null || true
rc=0; sbx "$H" ./uninstall.sh --yes >"$T/out" 2>&1 || rc=$?
[[ $rc != 0 ]] || { cat "$T/out"; fail "uninstall answered ok with no room to write"; }
grep -q "couldn't write" "$T/out" || { cat "$T/out"; fail "uninstall didn't say what it couldn't write"; }
cmp -s "$HY/bindings.lua" "$T/bind" || fail "uninstall changed bindings.lua with no room"
[[ -x $O ]] || fail "uninstall removed its command before finishing"
rm -f "$HY/.fill"
sbx "$H" ./uninstall.sh --yes >"$T/out" 2>&1 || { cat "$T/out"; fail "uninstall once there was room"; }
grep -q '>>> overtake' "$HY/bindings.lua" && fail "the retry left the block"
umount "$HY"
pass "uninstall on a full disk stops with your file as it was, and works once there's room"

# Screensaver art: the copy is made whole first, or nothing is replaced.
sbx "$H" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
BR="$H/.config/omarchy/branding"
mkdir -p "$BR"; rm -f "$BR/"*
mount -t tmpfs -o size=16k tmpfs "$BR"
head -c 8000 /dev/zero | tr '\0' 'a' >"$BR/screensaver.txt"
cp "$BR/screensaver.txt" "$T/art"
dd if=/dev/zero of="$BR/.fill" bs=4k 2>/dev/null || true
LOGO="$T/om"; mkdir -p "$LOGO"; echo LOGO >"$LOGO/logo.txt"
rc=0; sbx "$H" env OMARCHY_PATH="$LOGO" "$O" screensaver show omarchy >"$T/out" 2>&1 || rc=$?
[[ $rc != 0 ]] || fail "screensaver art went ahead with no room for the copy"
cmp -s "$BR/screensaver.txt" "$T/art" || fail "screensaver art was replaced with no copy kept"
[[ ! -e $BR/screensaver.txt.before-overtake ]] || fail "half a copy was left as the one to put back"
ls -A "$BR" | grep -qv -e '^screensaver.txt$' -e '^\.fill$' && fail "a temp file was left: $(ls -A "$BR")"
umount "$BR"
pass "screensaver art stays as it was if there's no room to keep a copy"

# ---------- A state folder that can't be written ----------
H2="$T/ro"; make_home "$H2"
sbx "$H2" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
sbx "$H2" "$H2/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on"; }
ST="$H2/.local/state/overtake"
mount --bind "$ST" "$ST" && mount -o remount,ro,bind "$ST"
started=$SECONDS
rc=0; sbx "$H2" "$H2/.local/bin/overtake" off >"$T/out" 2>&1 || rc=$?
umount "$ST"
[[ $rc != 0 ]] || { cat "$T/out"; fail "off went ahead with its folder read-only"; }
(( SECONDS - started < 10 )) || fail "a read-only folder made off wait $((SECONDS - started)) s"
grep -q "can't write to" "$T/out" || { cat "$T/out"; fail "a read-only folder was reported as something else"; }
grep -q 'another on/off' "$T/out" && fail "a read-only folder was reported as another on/off"
[[ -e $ST/enabled ]] || fail "off half-happened with its folder read-only"
pass "a state folder that can't be written is said at once, not after a minute"

# ---------- Leaving a mode on a full disk ----------
LK="$ST/looks"; mkdir -p "$LK"
mount -t tmpfs -o size=4k tmpfs "$LK"
dd if=/dev/zero of="$LK/.fill" bs=4k 2>/dev/null || true
sbx "$H2" "$H2/.local/bin/overtake" off >"$T/out" 2>&1 || { umount "$LK"; cat "$T/out"; fail "a full disk stopped the switch back at saving the look"; }
umount "$LK"
[[ $(sbx "$H2" "$H2/.local/bin/overtake" status) == off ]] || fail "off didn't finish on a full disk"
pass "a mode's look that can't be saved doesn't stop the switch back"

# ---------- An update on a full disk leaves the command working ----------
H3="$T/upd"; make_home "$H3"
sbx "$H3" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
B="$H3/.local/bin"
cp -a "$B/overtake" "$T/old-command"
for kb in 4 8 16 64 96; do
  mkdir -p "$T/keep"; cp -a "$B/." "$T/keep/"
  mount -t tmpfs -o "size=$(( $(du -sk "$T/keep" | cut -f1) + kb ))k" tmpfs "$B"
  cp -a "$T/keep/." "$B/"
  printf '# an older version\n' >>"$B/overtake"; chmod 755 "$B/overtake"
  cp -a "$B/overtake" "$T/before"
  dd if=/dev/zero of="$B/.fill" bs=4k 2>/dev/null || true
  rc=0; sbx "$H3" ./install.sh --yes >"$T/out" 2>&1 || rc=$?
  [[ $rc != 0 ]] || { cat "$T/out"; fail "${kb}k: install said it finished with no room"; }
  cmp -s "$B/overtake" "$T/before" || fail "${kb}k: a failed update changed the command"
  [[ -x $B/overtake ]] || fail "${kb}k: a failed update left the command not executable"
  grep -q 'the old one stays' "$T/out" || { cat "$T/out"; fail "${kb}k: no clear message"; }
  ls -A "$B" | grep -qv -e '^overtake$' -e '^\.fill$' && fail "${kb}k: a temp file was left: $(ls -A "$B")"
  umount "$B"
  rm -rf "${T:?}/keep"
done
pass "an update on a full disk leaves the old command whole and says so"

# An own plugin that can't be copied leaves the old one whole, and no build folder.
PL="$H3/.config/omarchy/plugins"
cp -a "$PL" "$T/pl-keep"
mount -t tmpfs -o "size=$(( $(du -sk "$T/pl-keep" | cut -f1) + 8 ))k" tmpfs "$PL"
cp -a "$T/pl-keep/." "$PL/"
dd if=/dev/zero of="$PL/.fill" bs=4k 2>/dev/null || true
rc=0; sbx "$H3" ./install.sh --yes >"$T/out" 2>&1 || rc=$?
[[ $rc != 0 ]] || { cat "$T/out"; fail "install said it finished with no room for its plugins"; }
diff -rq "$T/pl-keep/overtake.taskbar" "$PL/overtake.taskbar" >/dev/null || fail "a failed update changed overtake.taskbar"
ls -A "$PL" | grep -q '^\.overtake-build' && fail "a build folder was left: $(ls -A "$PL")"
umount "$PL"
pass "an own plugin that can't be copied stays as it was"
