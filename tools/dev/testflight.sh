#!/usr/bin/env bash
# Push the current main to TestFlight as the next build of the version in
# pubspec.yaml. No version bump, no tag: Apple reviews the first build of a
# version for external testers and lets later builds of the same version
# through on their own, so iterating within a version is the fast path.
#
#   tools/dev/testflight.sh            run the workflow and watch it
#   tools/dev/testflight.sh --no-wait  just start it
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -z "$(git status --porcelain)" ] || { echo "working tree is not clean; commit first" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main is not pushed; git push first" >&2; exit 1; }
V=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
echo "TestFlight build of $V from $(git rev-parse --short HEAD)"
gh workflow run "Release to TestFlight" --ref main -f version="$V"
[ "${1:-}" = "--no-wait" ] && exit 0
sleep 20
ID=$(gh run list --workflow "Release to TestFlight" --limit 1 --json databaseId -q '.[0].databaseId')
echo "run $ID"
gh run watch "$ID" --exit-status
