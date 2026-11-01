#!/usr/bin/env bash
# Capture App Store screenshots for PocketLocket (iPhone 6.9" set, 1320x2868).
#
# Usage:
#   scripts/appstore-screenshots.sh [<device name or UDID>]
#   Default: iPhone 17 Pro Max on iOS 26.5 (UDID below). Prefer release
#   runtimes; the iOS 27 beta simulator has caused Mach error -308 elsewhere.
#
# Output: screenshots/<device>/NN-name.png — upload these to the App Store
# Connect "6.9 inch display" section.
#
# One-time data seeding (manual, ~1 min, only the first time):
#   The script boots the simulator and builds/installs the app. For populated
#   screens, connect the SimpleFIN *demo* bridge once through the app UI:
#   Connect tab (or Home > Connect) > paste your demo claim URL > Connect.
#   The access URL is stored in the simulator Keychain, so every later run of
#   this script reuses it automatically.
#
#   The demo claim URL is NOT stored in this file (this script is public).
#   Keep it in scripts/demo-token.txt (git-ignored) or pass it via
#   DEMO_TOKEN_URL when you do the one-time manual connect.
#
# Notes:
#   - The biometric gate auto-passes on a simulator with no passcode enrolled
#     (BiometricGate returns .unavailable), so no unlocking is scripted.
#     If you enrolled a passcode, unlock the simulator before running.
#   - The app supports `-tab <home|transactions|accounts|insights>` launch
#     arguments; this script uses them for deterministic navigation.
#   - Settings screenshots: Settings lives behind the Accounts tab's gear.
#     Capture that one manually if you want it in the set.
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro Max}"
PREFERRED_UDID_FOR_NAME="0134A804-B290-4BA0-8478-681AC9336320"  # iPhone 17 Pro Max, iOS 26.5
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/screenshots/$DEVICE"
BUNDLE_ID="com.vratnakaram.PocketLocket"
DERIVED="$REPO_ROOT/build/screenshots-derived"

echo "==> Locating simulator: $DEVICE"
if [[ "$DEVICE" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  UDID="$DEVICE"; DEVICE="device-$UDID"
else
  # simctl list can hang on cold CoreSimulator services; fall back to plists.
  UDID="$(xcrun simctl list devices available 2>/dev/null | grep -F "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}')"
  if [[ -z "$UDID" ]]; then
    for d in ~/Library/Developer/CoreSimulator/Devices/*/; do
      n="$(plutil -extract name raw "$d/device.plist" 2>/dev/null)"
      if [[ "$n" == "$DEVICE" ]]; then
        cand="$(basename "$d")"
        # Prefer the known-good runtime when several clones exist.
        if [[ "$cand" == "$PREFERRED_UDID_FOR_NAME" ]]; then UDID="$cand"; break; fi
        UDID="${UDID:-$cand}"
      fi
    done
  fi
fi
if [[ -z "$UDID" ]]; then
  echo "error: simulator '$DEVICE' not found. Run: xcrun simctl list devices available" >&2
  exit 1
fi

echo "==> Booting $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator

echo "==> Building (Debug, simulator)"
xcodebuild -project "$REPO_ROOT/ios/PocketLocket.xcodeproj" \
  -scheme PocketLocket \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  build -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/PocketLocket.app"
[[ -d "$APP" ]] || { echo "error: app not found at $APP" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP"

mkdir -p "$OUT_DIR"

capture() { # capture <index> <tab> <name> [wait_seconds]
  local idx="$1" tab="$2" name="$3" wait="${4:-6}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab "$tab" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT_DIR/${idx}-${name}.png"
  echo "    saved ${idx}-${name}.png"
}

echo "==> Capturing"
capture 01 home         home-ring        10   # extra wait: first sync + ring render
capture 02 home         category-detail   6   # then tap a ring slice manually for the real shot
capture 03 transactions transactions-list 6
capture 04 accounts     accounts-networth 6
capture 05 insights     save-insights     8   # on-device AI may take a moment
capture 06 transactions manual-entry      6   # open the + sheet manually for this shot

echo
echo "==> Done. Files in: $OUT_DIR"
echo "    Verify each PNG is 1320x2868 (sips -g pixelWidth -g pixelHeight <file>)."
echo "    For polished listing shots, re-run and stage each screen before the"
echo "    screenshot lands (tap a ring slice, open recategorize, etc.) — the"
echo "    automated pass only guarantees clean base screens."
