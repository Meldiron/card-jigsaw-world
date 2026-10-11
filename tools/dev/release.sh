#!/usr/bin/env bash
# Start a NEW version cycle. Use it only after the previous version shipped to
# the App Store (or was abandoned): it bumps pubspec.yaml to X.Y.Z, commits,
# pushes and sends the first TestFlight build of the new version, which Apple
# then reviews once for external testers. Day-to-day builds use
# tools/dev/testflight.sh instead and keep the version string.
#
#   tools/dev/release.sh 1.8.0 [--notes FILE] [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION="${1:-}"; shift || true
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/dev/release.sh X.Y.Z [--notes FILE] [--dry-run]" >&2; exit 2; }
NOTES=store/metadata/en-US/release_notes.txt; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -f "$NOTES" ] || { echo "notes file $NOTES not found" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree is not clean; commit or stash first" >&2; exit 1; }
CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //')
BUILD=$(( ${CURRENT#*+} + 1 ))
echo "pubspec $CURRENT -> $VERSION+$BUILD (new cycle), notes from $NOTES"
[ "$DRY" = 0 ] || exit 0
export PATH="$HOME/flutter/bin:$PATH"
sed -i '' "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml
if [ "$NOTES" != store/metadata/en-US/release_notes.txt ]; then cp "$NOTES" store/metadata/en-US/release_notes.txt; fi
flutter analyze --fatal-infos --fatal-warnings
flutter test
git add pubspec.yaml store/metadata/en-US/release_notes.txt
git commit -q -m "Start $VERSION"
git push -q origin main
exec tools/dev/testflight.sh
