#!/bin/bash
# Your own files come back byte for byte, whatever shape they were in: no final
# newline, blank lines at the end, a menu on one line. Install keeps them as
# they are around its marked blocks, and each block's start line says what else
# went in with it. And the edits replace the file whole: mode and symlink kept.
source "$(dirname "$0")/lib.sh"
cd "$REPO"

n=0
round_trip() {  # round_trip <what> <relative file> <contents>: install, again, on, off, uninstall
  local what=$1 rel=$2 text=$3 h
  n=$((n + 1))
  h="$T/rt$n"
  make_home "$h"
  mkdir -p "$(dirname "$h/$rel")"
  printf '%s' "$text" >"$h/$rel"
  cp "$h/$rel" "$T/want"
  sbx "$h" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install ($what)"; }
  # the marked block went in, and the menu is still JSONC Omarchy can read
  case $rel in
    *.lua) grep -q '^-- >>> overtake' "$h/$rel" || fail "no block in $rel ($what)" ;;
    *.jsonc)
      grep -q '^  // >>> overtake' "$h/$rel" || fail "no block in the menu ($what)"
      python3 -I - "$h/$rel" <<'PY' || { cat "$h/$rel"; fail "the menu isn't valid JSONC ($what)"; }
import json, re, sys
t = re.sub(r"^\s*//.*$", "", open(sys.argv[1]).read(), flags=re.M)
json.loads(re.sub(r",(\s*})", r"\1", t))
PY
      ;;
  esac
  sbx "$h" ./install.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "reinstall ($what)"; }
  sbx "$h" "$h/.local/bin/overtake" on >>"$T/log" 2>&1 || { cat "$T/log"; fail "on ($what)"; }
  sbx "$h" "$h/.local/bin/overtake" off >>"$T/log" 2>&1 || { cat "$T/log"; fail "off ($what)"; }
  sbx "$h" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall ($what)"; }
  if ! cmp -s "$T/want" "$h/$rel"; then
    echo "--- wanted:"; od -c "$T/want" | tail -6; echo "--- got:"; od -c "$h/$rel" | tail -6
    fail "$what didn't come back byte for byte"
  fi
  rm -rf "$h"
}

B=.config/hypr/bindings.lua A=.config/hypr/autostart.lua M=.config/omarchy/extensions/omarchy-menu.jsonc S=.config/omarchy/shell.toml
round_trip "bindings with no final newline" "$B" '-- mine'
round_trip "bindings with blank lines at the end" "$B" $'-- mine\n\n\n\n'
round_trip "bindings with one final blank line" "$B" $'-- mine\n\n'
round_trip "bindings ending in spaces" "$B" $'-- mine\n   \n'
round_trip "bindings with Windows line ends" "$B" $'-- mine\r\n-- two\r\n'
round_trip "empty autostart" "$A" ''
round_trip "autostart of only blank lines" "$A" $'\n\n'
round_trip "autostart with no final newline" "$A" '-- auto'
round_trip "a one-line menu" "$M" '{ "personal": {"label":"P"} }'
round_trip "a one-line menu with a final newline" "$M" $'{ "personal": {"label":"P"} }\n'
round_trip "an empty menu object" "$M" '{}'
round_trip "a spaced empty menu object" "$M" $'{ }\n'
round_trip "an indented menu" "$M" $'  {\n    "personal": {"label":"P"}\n  }\n'
round_trip "a menu with trailing spaces after its brace" "$M" $'{   \n  "personal": {"label":"P"}\n}\n'
round_trip "a menu with no final newline" "$M" $'{\n  "personal": {"label":"P"}\n}'
round_trip "a menu with comments before its brace" "$M" $'// mine\n\n{\n}\n'
round_trip "a menu of only comments" "$M" $'// nothing yet\n'
round_trip "a menu of only comments, no final newline" "$M" '// nothing yet'
round_trip "an empty menu file of yours" "$M" ''
round_trip "shell.toml with no final newline" "$S" $'[font]\nbase-size = 12'
round_trip "shell.toml with blank lines at the end" "$S" $'[font]\nbase-size = 12\n\n\n'
pass "bindings, autostart, the menu and shell.toml come back byte for byte, whatever their shape"

# What you added below a block while it was there stays, on its own line.
h="$T/below"
make_home "$h"
printf -- '-- mine' >"$h/$B"
sbx "$h" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
printf -- '-- added later\n' >>"$h/$B"
sbx "$h" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
[[ $(<"$h/$B") == $'-- mine\n-- added later' ]] || { cat "$h/$B"; fail "a line added below the block didn't keep its own line"; }
pass "a line you added below a block stays on its own line"

# A block from an earlier version (its start line says nothing) still comes out.
h="$T/old"
make_home "$h"
printf -- '-- mine\n\n-- >>> overtake (managed by overtake-mode-omarchy/install.sh)\nblock\n-- <<< overtake\n' >"$h/$B"
printf '{\n  // >>> overtake (managed by overtake-mode-omarchy/install.sh)\n  "x": {},\n  // <<< overtake\n  "personal": {"label":"P"}\n}\n' >"$h/$M"
sbx "$h" ./uninstall.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
[[ $(cat "$h/$B"; echo x) == $'-- mine\nx' ]] || { od -c "$h/$B"; fail "an earlier version's block didn't come out cleanly"; }
[[ $(<"$h/$M") == $'{\n  "personal": {"label":"P"}\n}' ]] || { cat "$h/$M"; fail "an earlier version's menu block didn't come out cleanly"; }
pass "a block written by an earlier version still comes out"

# Mode and symlinks are kept, and the file is replaced, never rewritten in place.
h="$T/modes"
make_home "$h"
chmod 640 "$h/$B" "$h/$M"
mkdir -p "$h/dotfiles"; mv "$h/$A" "$h/dotfiles/autostart.lua"; ln -s "$h/dotfiles/autostart.lua" "$h/$A"
ino_b=$(stat -c %i "$h/$B") ino_m=$(stat -c %i "$h/$M")
sbx "$h" ./install.sh --yes >"$T/log" 2>&1 || { cat "$T/log"; fail "install"; }
[[ $(stat -c %a "$h/$B") == 640 && $(stat -c %a "$h/$M") == 640 ]] || fail "install widened a file's mode"
[[ $(stat -c %i "$h/$B") != "$ino_b" && $(stat -c %i "$h/$M") != "$ino_m" ]] || fail "install edited a file in place, not by rename"
[[ -L $h/$A ]] || fail "install replaced your symlink"
grep -q '>>> overtake' "$h/dotfiles/autostart.lua" || fail "install didn't edit the symlink's target"
ls -A "$h/.config/hypr" "$h/.config/omarchy/extensions" | grep -qE '\.(lua|jsonc)\.[A-Za-z0-9_]+$' && fail "a temp file was left next to your files"
ino_b=$(stat -c %i "$h/$B") ino_m=$(stat -c %i "$h/$M")
sbx "$h" ./uninstall.sh --yes >>"$T/log" 2>&1 || { cat "$T/log"; fail "uninstall"; }
[[ $(stat -c %a "$h/$B") == 640 && $(stat -c %a "$h/$M") == 640 ]] || fail "uninstall widened a file's mode"
[[ $(stat -c %i "$h/$B") != "$ino_b" && $(stat -c %i "$h/$M") != "$ino_m" ]] || fail "uninstall edited a file in place, not by rename"
[[ -L $h/$A ]] || fail "uninstall replaced your symlink"
ls -A "$h/.config/hypr" "$h/.config/omarchy/extensions" | grep -qE '\.(lua|jsonc)\.[A-Za-z0-9_]+$' && fail "a temp file was left next to your files"
pass "install and uninstall replace each file whole: mode and symlinks kept, no temp file left"

# The two copies of the Python that does this are the same.
diff <(sed -n "/^FILE_PY=/,/^PY$/p" install.sh | sed '1d;$d') <(sed -n "/^FILE_PY=/,/^PY$/p" uninstall.sh | sed '1d;$d') >/dev/null ||
  fail "install.sh and uninstall.sh disagree on how a block comes out"
pass "install.sh and uninstall.sh share one way of taking a block out"
