#!/bin/bash
# Builds the notifications copy from $OMARCHY_SRC as bin/overtake does, then
# runs the history orderings in t-notifications.js against it.
source "$(dirname "$0")/lib.sh"
cp -a "$OMARCHY_SRC/notifications" "$T/copy"
python3 -I "$REPO/patches/apply.py" notifications "$T/copy" || fail "the notifications patch doesn't apply"
node "$REPO/tests/t-notifications.js" "$T/copy" "$REPO"
