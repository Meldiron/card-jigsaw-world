#!/usr/bin/env bash
# Every app run made while working on the game goes through here (simulator, browser, integration
# tests): silent (CJW_MUTE) and flagged as a QA run (CJW_QA), so the guest it plays on the live
# backend is a test player that never shows in the league; when the run ends, the test players it
# created are purged (user, rows, photos; backup in secrets/purged/).
#
#   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
#       --target=integration_test/screenshots_test.dart -d <udid>
#   tools/dev/qa-run.sh run -d <udid>             interactive run, purged when you quit
#   tools/dev/qa-run.sh run -d chrome             web
#   QA_KEEP=1 tools/dev/qa-run.sh ...             keep the run's players (purge them later)
#
# The run id reaches the app as CJW_QA_RUN and is stored on the guest, so the purge deletes only
# this run's players and runs in other sessions keep theirs. Leftovers (a run killed hard):
#   python3 tools/dev/purge_test_players.py purge --apply
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/flutter/bin:$PATH"
if [ $# -lt 1 ]; then sed -n '2,16p' "$0"; exit 2; fi
cmd=$1; shift
case "$cmd" in
  run|drive|test) ;;
  *) echo "qa-run.sh: the first argument is the flutter command (run, drive or test)" >&2; exit 2 ;;
esac
RUN_ID="qa-$(date +%Y%m%d-%H%M%S)-$$"
PY=python3
[ -x .venv/bin/python ] && PY=.venv/bin/python

purge() {
  if [ -n "${QA_KEEP:-}" ]; then
    echo "qa-run: kept the test players of $RUN_ID (QA_KEEP); purge later with tools/dev/purge_test_players.py purge --apply"
    return
  fi
  if [ ! -f secrets/appwrite-users-key.txt ]; then
    echo "qa-run: secrets/appwrite-users-key.txt missing, test players of $RUN_ID not purged" >&2
    return
  fi
  "$PY" tools/dev/purge_test_players.py purge --run "$RUN_ID" --apply --quiet \
    || echo "qa-run: purge failed; run tools/dev/purge_test_players.py purge --apply later" >&2
}

trap 'purge; exit 130' INT TERM
echo "qa-run: $RUN_ID (silent, test player, purged afterwards)"
flutter "$cmd" --dart-define=CJW_MUTE=true --dart-define=CJW_QA=true --dart-define=CJW_QA_RUN="$RUN_ID" "$@"
code=$?
trap - INT TERM
purge
exit $code
