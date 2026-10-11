#!/usr/bin/env bash
# Cut a release: bump the version, write release notes, tag, and publish a
# GitHub release. Publishing the release triggers .github/workflows/
# release-testflight.yml, which uploads the build to TestFlight, adds it to the
# public tester group and submits it to Beta App Review. Nothing reaches the
# App Store from here; that is the separate "Submit to App Store" workflow.
#
#   tools/dev/release.sh 1.8.0                      notes from store/metadata/en-US/release_notes.txt
#   tools/dev/release.sh 1.8.0 --notes notes.md     notes from a file
#   tools/dev/release.sh 1.8.0 --dry-run
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
echo "pubspec $CURRENT -> $VERSION+$BUILD, tag v$VERSION, notes from $NOTES"
[ "$DRY" = 0 ] || exit 0
export PATH="$HOME/flutter/bin:$PATH"
sed -i '' "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml
if [ "$NOTES" != store/metadata/en-US/release_notes.txt ]; then cp "$NOTES" store/metadata/en-US/release_notes.txt; fi
flutter analyze --fatal-infos --fatal-warnings
flutter test
git add pubspec.yaml store/metadata/en-US/release_notes.txt
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "Card Jigsaw World $VERSION"
git push -q origin main "v$VERSION"
gh release create "v$VERSION" --title "Card Jigsaw World $VERSION" --notes-file store/metadata/en-US/release_notes.txt
echo "Release published. Watch: gh run list --workflow 'Release to TestFlight'"
