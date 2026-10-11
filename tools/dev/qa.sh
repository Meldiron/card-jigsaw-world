#!/usr/bin/env bash
# Run the app on a simulator for QA, silently (no music, no effects).
#   tools/dev/qa.sh                 iPhone 17 Pro
#   tools/dev/qa.sh promax          iPhone 17 Pro Max (store screenshot size)
#   tools/dev/qa.sh shots           full screenshot pass -> screenshots/
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/flutter/bin:$PATH"
PRO=CDD7317C-19D6-486D-B258-8AB8A607297D
PROMAX=D03644FB-6169-4E87-8E0F-CCFC884FBE78
case "${1:-run}" in
  run) xcrun simctl boot $PRO 2>/dev/null || true; exec flutter run -d $PRO --dart-define=CJW_MUTE=true ;;
  promax) xcrun simctl boot $PROMAX 2>/dev/null || true; exec flutter run -d $PROMAX --dart-define=CJW_MUTE=true ;;
  shots) xcrun simctl boot $PRO 2>/dev/null || true; exec flutter drive --dart-define=CJW_MUTE=true --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart -d $PRO ;;
  *) echo "usage: tools/dev/qa.sh [run|promax|shots]" >&2; exit 2 ;;
esac
