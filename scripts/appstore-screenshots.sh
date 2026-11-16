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
# One-time data seeding (automatic, if scripts/demo-token.txt exists):
#   Screenshots of an empty app are useless, so the script seeds the SimpleFIN
#   *demo* connection automatically. It passes the access URL to the app via
#   `-seedSimpleFIN <url>` (Debug-only hook, see ios/PocketLocket/App/
#   DebugLaunch.swift), which stores it in the simulator Keychain; every later
#   launch syncs from it.
#
#   Put the access URL (NOT the setup token) in scripts/demo-token.txt:
#     https://demo:demo@beta-bridge.simplefin.org/simplefin
#   That file is git-ignored. Or override with DEMO_ACCESS_URL=<url>.
#
#   Why the access URL and not the claim/setup token: the public demo setup
#   token is single-use — claiming it returns the access URL above, and a
#   second claim 403s ("already claimed"). Store the durable access URL.
#   If you ever need to re-claim, get a fresh token at
#   https://www.simplefin.org/bridge.html and paste it in the app UI once.
#
# Notes:
#   - The biometric gate auto-passes on a simulator with no passcode enrolled
#     (BiometricGate returns .unavailable), so no unlocking is scripted.
#     If you enrolled a passcode, unlock the simulator before running.
#   - The app supports `-tab <home|transactions|accounts|insights>` launch
#     arguments; this script uses them for deterministic navigation.
#   - Settings screenshots: Settings opens from the gear button in the HOME
#     tab's navigation bar (HomeView toolbar -> showSettings), not from Accounts.
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
# Simulator.app moved out of Xcode's Developer/Applications in recent releases;
# don't let a missing GUI launcher kill the capture run.
open -a Simulator 2>/dev/null || true

# Resolve the demo access URL for seeding (git-ignored file or env override).
SEED_ARGS=()
DEMO_ACCESS_URL="${DEMO_ACCESS_URL:-}"
if [[ -z "$DEMO_ACCESS_URL" && -f "$REPO_ROOT/scripts/demo-token.txt" ]]; then
  DEMO_ACCESS_URL="$(grep -vE '^\s*(#|$)' "$REPO_ROOT/scripts/demo-token.txt" | head -1 | tr -d '[:space:]')"
fi
if [[ -n "$DEMO_ACCESS_URL" ]]; then
  SEED_ARGS=(-seedSimpleFIN "$DEMO_ACCESS_URL")
  echo "==> Seeding SimpleFIN demo data"
else
  echo "==> No demo access URL (scripts/demo-token.txt or DEMO_ACCESS_URL);" \
       "screenshots will show an empty app."
fi

# Show an on-track budget in the ring (demo spends ~$5.2k; default $3k shows a
# red "over budget" screen, which is a bad first impression for the listing).
BUDGET="${SCREENSHOT_BUDGET:-7500}"

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
  # ${arr[@]+"${arr[@]}"} is the bash 3.2-safe expansion under set -u.
  # -skipLock: Debug-only gate bypass for headless capture (BiometricGate).
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab "$tab" -skipLock -budget "$BUDGET" ${SEED_ARGS[@]+"${SEED_ARGS[@]}"} >/dev/null
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
