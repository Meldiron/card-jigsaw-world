#!/usr/bin/env bash
# Archive, export and upload the iOS build to App Store Connect / TestFlight.
#
# Needs: Xcode, Flutter at ~/flutter, secrets/AuthKey_9QC72A5QMN.p8 and the
# Issuer ID in ASC_ISSUER_ID or secrets/app-store-connect-issuer-id.txt.
# Usage: tools/store/upload_build.sh            (from the repository root)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/flutter/bin:$PATH"

KEY_ID="9QC72A5QMN"
KEY_PATH="$ROOT/secrets/AuthKey_${KEY_ID}.p8"
ISSUER_FILE="$ROOT/secrets/app-store-connect-issuer-id.txt"
ARCHIVE="$ROOT/build/ios/archive/Runner.xcarchive"
IPA_DIR="$ROOT/build/ios/ipa"

if [[ -z "${ASC_ISSUER_ID:-}" && -f "$ISSUER_FILE" ]]; then
  ASC_ISSUER_ID="$(tr -d '[:space:]' < "$ISSUER_FILE")"
fi
if [[ -z "${ASC_ISSUER_ID:-}" ]]; then
  echo "ASC_ISSUER_ID is not set and $ISSUER_FILE does not exist." >&2
  echo "App Store Connect > Users and Access > Integrations > App Store Connect API > Issuer ID" >&2
  exit 1
fi
[[ -f "$KEY_PATH" ]] || { echo "private key not found: $KEY_PATH" >&2; exit 1; }

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "== flutter build (generates Flutter assets and the Release pod config)"
flutter pub get
flutter build ios --release --no-codesign

echo "== xcodebuild archive"
rm -rf "$ARCHIVE"
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  "${AUTH[@]}" \
  archive

echo "== xcodebuild export (ios/ExportOptions.plist, method app-store-connect)"
rm -rf "$IPA_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "$IPA_DIR" \
  "${AUTH[@]}"

IPA="$(ls "$IPA_DIR"/*.ipa | head -n 1)"
echo "== altool upload: $IPA"
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "Uploaded. Processing takes 10 to 30 minutes; then run:"
echo "  tools/store/asc_publish.py testflight"
echo "  tools/store/asc_publish.py audit"
