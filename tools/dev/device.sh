#!/usr/bin/env bash
# Build a release build and install it on the iPhone connected over USB.
#
#   tools/dev/device.sh            build + install (keeps app data)
#   tools/dev/device.sh --wipe     uninstall first, so the app starts fresh (onboarding)
#   tools/dev/device.sh --debug    debug build with hot reload (flutter run)
#
# Picks the first paired physical iPhone/iPad. USB is not required: once the
# phone has been paired with Xcode and "Connect via network" is on (Xcode >
# Window > Devices and Simulators), devicectl installs over Wi-Fi as long as
# the phone is unlocked and on the same network. Override with DEVICE_UDID=...
# Skip the build with --no-build to push the last build/ios/iphoneos/Runner.app.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/flutter/bin:$PATH"
BUNDLE_ID=com.matejbaco.cardjigsawworld
WIPE=0; MODE=release; BUILD=1
for a in "$@"; do
  case "$a" in
    --wipe) WIPE=1 ;;
    --debug) MODE=debug ;;
    --no-build) BUILD=0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
UDID="${DEVICE_UDID:-$(xcrun devicectl list devices 2>/dev/null | grep physical | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1 || true)}"
[ -n "$UDID" ] || { echo "No paired iPhone found (xcrun devicectl list devices). Plug it in once or enable Connect via network in Xcode." >&2; exit 1; }
echo "Device $UDID"
if [ "$WIPE" = 1 ]; then
  echo "Removing $BUNDLE_ID"
  xcrun devicectl device uninstall app --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
fi
if [ "$MODE" = debug ]; then
  # QA runs are silent; release installs keep sound.
  exec flutter run -d "$UDID" --dart-define=CJW_MUTE=true
fi
[ "$BUILD" = 0 ] || flutter build ios --release
for attempt in 1 2 3; do
  if xcrun devicectl device install app --device "$UDID" build/ios/iphoneos/Runner.app; then
    echo "Installed $BUNDLE_ID ($(grep '^version:' pubspec.yaml | sed 's/version: //'))"
    exit 0
  fi
  echo "install attempt $attempt failed, retrying in 5s" >&2; sleep 5
done
exit 1
