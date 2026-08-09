#!/usr/bin/env bash
#
# PocketLocket bootstrap — installs the tooling needed to build the app and
# generates the Xcode project. Safe to re-run.
#
# Usage:  bash scripts/bootstrap.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> PocketLocket bootstrap"

# 1) Homebrew ---------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  echo "==> Installing Homebrew (this may prompt for your password)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Make brew available on Apple Silicon for the rest of this script.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# 2) CLI tools --------------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen…"
  brew install xcodegen
fi

# 3) iOS simulator runtime --------------------------------------------------
if ! xcrun simctl list runtimes 2>/dev/null | grep -qi "iOS"; then
  echo "==> No iOS simulator runtime found. Downloading (large, one-time)…"
  xcodebuild -downloadPlatform iOS
fi

# 4) Generate the Xcode project --------------------------------------------
echo "==> Generating Xcode project…"
( cd ios && xcodegen generate )

cat <<'EOF'

==> Done!

Next steps:
  1. Open:   open ios/PocketLocket.xcodeproj   (then press Run)
  2. Add data in the app: "Auto-sync (SimpleFIN)" or import an OFX/QFX/CSV
     statement. Everything is stored locally on your device — no backend.
EOF
