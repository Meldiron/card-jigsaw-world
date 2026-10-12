#!/usr/bin/env bash
# Build the web app and deploy it to Appwrite Sites
# (site "card-jigsaw-world" -> https://card-jigsaw-world.appwrite.network).
# The site is a static adapter, so we upload the finished build/web folder.
#   tools/dev/deploy-web.sh            build + deploy + wait until live
#   tools/dev/deploy-web.sh --no-build deploy the existing build/web
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/flutter/bin:$PATH"
PROJECT=6acb4de5003e38d5ebd9; SITE=card-jigsaw-world; EP=https://fra.cloud.appwrite.io/v1
KEY=$(cat secrets/appwrite-sites-key.txt)
if [ "${1:-}" != "--no-build" ]; then
  flutter build web --release --base-href / --no-web-resources-cdn
fi
[ -f build/web/index.html ] || { echo "build/web/index.html missing" >&2; exit 1; }
TAR=$(mktemp -t cjw-web).tar.gz
tar -czf "$TAR" -C build/web .
echo "uploading $(du -h "$TAR" | cut -f1)"
ID=$(python3 tools/dev/appwrite_upload.py "$EP" "$PROJECT" "$KEY" "/sites/$SITE/deployments" "$TAR" true)
rm -f "$TAR"
echo "deployment $ID"
for i in $(seq 1 60); do
  S=$(curl -sS "$EP/sites/$SITE/deployments/$ID" -H "X-Appwrite-Project: $PROJECT" -H "X-Appwrite-Key: $KEY" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status"))')
  case "$S" in
    ready) echo "live: https://card-jigsaw-world.appwrite.network"; exit 0 ;;
    failed) echo "build failed; see Appwrite console > Sites > $SITE > deployment $ID" >&2; exit 1 ;;
    *) sleep 5 ;;
  esac
done
echo "timed out waiting for deployment $ID" >&2; exit 1
