#!/bin/bash
# Run every Overtake Mode test. Nothing touches your desktop or home folder:
# each test installs into its own scratch home with stubbed desktop commands.
#
#   tests/run.sh                    # against the installed Omarchy
#   OMARCHY_SRC=<omarchy>/shell/plugins tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."

failed=0
run() {  # run <name> <command...>
  echo "# $1"
  if "${@:2}"; then :; else echo "FAILED: $1"; failed=1; fi
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
run "upgrade from v0.1.11" bash tests/t-upgrade-extras.sh
run "wttr.in limits" bash tests/t-sun-times.sh
run "notification history" bash tests/t-notifications.sh

if (( failed )); then echo "SOME TESTS FAILED"; exit 1; fi
echo "ALL TESTS PASSED"
