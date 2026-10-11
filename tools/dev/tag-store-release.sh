#!/usr/bin/env bash
# Record an App Store release in GitHub once Apple has approved it and you
# pressed Release in App Store Connect. Creates the tag and GitHub release
# with the store notes. It does not build or upload anything.
#   tools/dev/tag-store-release.sh 1.7.0
set -euo pipefail
cd "$(dirname "$0")/../.."
V="${1:-}"; [[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/dev/tag-store-release.sh X.Y.Z" >&2; exit 2; }
git tag -a "v$V" -m "Card Jigsaw World $V on the App Store"
git push -q origin "v$V"
gh release create "v$V" --title "Card Jigsaw World $V" --notes-file store/metadata/en-US/release_notes.txt
