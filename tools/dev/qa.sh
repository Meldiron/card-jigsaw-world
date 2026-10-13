#!/usr/bin/env bash
# Run the app on a simulator for QA: silent (no music, no effects) and as a QA run, so the test
# player stays out of the league and is purged afterwards (tools/dev/qa-run.sh).
#   tools/dev/qa.sh                 iPhone 17 Pro
#   tools/dev/qa.sh promax          iPhone 17 Pro Max (store screenshot size)
#   tools/dev/qa.sh shots           full screenshot pass -> screenshots/
set -euo pipefail
cd "$(dirname "$0")/../.."
PRO=CDD7317C-19D6-486D-B258-8AB8A607297D
PROMAX=D03644FB-6169-4E87-8E0F-CCFC884FBE78
case "${1:-run}" in
  run) xcrun simctl boot $PRO 2>/dev/null || true; exec tools/dev/qa-run.sh run -d $PRO ;;
  promax) xcrun simctl boot $PROMAX 2>/dev/null || true; exec tools/dev/qa-run.sh run -d $PROMAX ;;
  shots) xcrun simctl boot $PRO 2>/dev/null || true; exec tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart -d $PRO ;;
  *) echo "usage: tools/dev/qa.sh [run|promax|shots]" >&2; exit 2 ;;
esac
