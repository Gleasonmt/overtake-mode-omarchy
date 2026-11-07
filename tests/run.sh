#!/bin/bash
# Run every Overtake Mode test. Nothing touches your desktop or home folder:
# each test installs into its own scratch home with stubbed desktop commands.
#
#   tests/run.sh                    # against the installed Omarchy
#   OMARCHY_SRC=<omarchy>/shell/plugins tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."

failed=0
skipped=0
run() {  # run <name> <command...>
  local out
  echo "# $1"
  out=$(mktemp)
  # (shown as it goes; skip lines are counted for the last line)
  if "${@:2}" 2>&1 | tee "$out"; (( PIPESTATUS[0] == 0 )); then :; else echo "FAILED: $1"; failed=1; fi
  skipped=$(( skipped + $(grep -c '^skipped' "$out" || true) ))
  rm -f "$out"
}

run "syntax" bash -c 'for f in bin/overtake install.sh uninstall.sh tests/*.sh; do bash -n "$f" || exit 1; done; python3 -I -m py_compile patches/apply.py && echo "ok - bash and python parse"'
if command -v qmllint >/dev/null || [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  QMLLINT=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
  # (syntax errors only: Quickshell's own modules aren't needed to parse)
  run "qml" bash -c "for f in plugins/*/*.qml Setup.qml; do if $QMLLINT \"\$f\" 2>&1 | grep -q -E '\\[syntax\\]|Expected token|Unexpected token'; then echo \"qmllint syntax error: \$f\"; exit 1; fi; done; echo 'ok - every QML file parses'"
fi
run "plain text" python3 -I tests/t-plain-text.py
run "qml logic" node tests/t-qml-logic.js
run "patches" bash tests/t-patches.sh
run "argv privacy" bash tests/t-argv-privacy.sh
run "lifecycle" bash tests/t-lifecycle.sh
run "lifecycle details" bash tests/t-lifecycle-details.sh
run "omarchy mode" bash tests/t-omarchy-mode.sh
run "your files, byte for byte" bash tests/t-install-files.sh
run "full disk" bash tests/t-full-disk.sh
run "root plugin in real Quickshell" bash tests/t-setup-qs.sh
run "icons in real Quickshell" bash tests/t-usericons-qs.sh
run "wttr.in limits" bash tests/t-sun-times.sh
run "private folders" bash tests/t-folders.sh
run "notification history" bash tests/t-notifications.sh
run "notification history in real Quickshell" bash tests/t-notifications-qs.sh

if (( failed )); then echo "SOME TESTS FAILED"; exit 1; fi
if (( skipped )); then echo "ALL TESTS PASSED, $skipped part(s) skipped"; else echo "ALL TESTS PASSED, none skipped"; fi
