#!/usr/bin/env bash
# Friend gift notification on a simulator (docs/friend-gifts.md, "Checking it"): what Flutter
# cannot drive. A fresh QA install turns on Settings > Gifts from friends, taps Allow on the iOS
# prompt, goes to the background; a QA friend sends a ticket through the real server (/gift/send on function api);
# Apple's sandbox service delivers the push; the check taps the banner and claims the gift it
# opens. Screenshots gift_10..15 land in screenshots/ (GIFT_QA_DIR to change).
#
#   tools/dev/notification_check.sh <simulator udid>
#
# Like tools/dev/qa-run.sh it builds a silent QA build (CJW_MUTE, CJW_QA, a run id) and purges the
# run's players at the end (the guest and its QA friend, tools/dev/gift_qa.py). The UI test target
# exists only while it runs: tools/dev/notification_check/add_ui_target.rb adds it, and the Xcode
# project is put back afterwards (never commit RunnerUITests). Uninstalls the app first, so iOS asks
# for notifications again. Needs CocoaPods (its xcodeproj gem) and secrets/appwrite-users-key.txt.
set -uo pipefail
cd "$(dirname "$0")/../.."
UDID=${1:?usage: tools/dev/notification_check.sh <simulator udid>}
export PATH="$HOME/flutter/bin:$PATH"
export FLUTTER_ROOT="$HOME/flutter"
RUN_ID="qa-$(date +%Y%m%d-%H%M%S)-$$"
OUT="${GIFT_QA_DIR:-screenshots}"
HERE=tools/dev/notification_check
PBX=ios/Runner.xcodeproj/project.pbxproj
SCHEME=ios/Runner.xcodeproj/xcshareddata/xcschemes/RunnerUITests.xcscheme
PY=python3
[ -x .venv/bin/python ] && PY=.venv/bin/python
BACKUP="$(mktemp)"
cp "$PBX" "$BACKUP"
HELPER=

finish() {
  cp "$BACKUP" "$PBX"
  rm -f "$BACKUP" "$SCHEME"
  rm -rf ios/RunnerUITests
  [ -n "$HELPER" ] && kill "$HELPER" 2>/dev/null
  "$PY" tools/dev/gift_qa.py end >/dev/null 2>&1
  "$PY" tools/dev/purge_test_players.py purge --run "$RUN_ID" --apply --quiet \
    || echo "notification_check: purge failed; run tools/dev/purge_test_players.py purge --apply later" >&2
}
trap finish EXIT

echo "notification_check: $RUN_ID (silent QA build, players purged afterwards)"
mkdir -p ios/RunnerUITests "$OUT"
cp "$HERE/GiftNotificationUITests.swift" ios/RunnerUITests/
GEM_HOME="$(brew --prefix cocoapods)/libexec" "$(brew --prefix ruby)/bin/ruby" "$HERE/add_ui_target.rb" ios/Runner.xcodeproj || exit 1
rm -f secrets/gift_qa.json
xcrun simctl uninstall "$UDID" com.matejbaco.cardjigsawworld 2>/dev/null
flutter build ios --simulator --debug --dart-define=CJW_MUTE=true --dart-define=CJW_QA=true --dart-define=CJW_QA_RUN="$RUN_ID" || exit 1

# The guest the test's launch makes gets a QA friend, whose session the test sends the gift with.
"$PY" tools/dev/gift_qa.py befriend-run --run "$RUN_ID" &
HELPER=$!
TEST_RUNNER_GIFT_QA_DIR="$PWD/$OUT" TEST_RUNNER_GIFT_QA_STATE="$PWD/secrets/gift_qa.json" \
  xcodebuild test -workspace ios/Runner.xcworkspace -scheme RunnerUITests \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/uitest 2>&1 \
  | grep -E --line-buffered "error:|Test Case|GIFT_QA_SENT|\*\* TEST"
code=${PIPESTATUS[0]}
echo "notification_check: screenshots in $OUT/gift_1*.png"
exit "$code"
