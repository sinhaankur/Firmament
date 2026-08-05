#!/usr/bin/env bash
# Run Firmament's unit tests on an available iPhone simulator.
set -euo pipefail

cd "$(dirname "$0")"
xcodegen generate >/dev/null

SIM=$(xcrun simctl list devices available | grep -m1 "iPhone 1" | grep -oE "[0-9A-F-]{36}")
if [ -z "$SIM" ]; then
  echo "No available iPhone simulator found." >&2
  exit 1
fi

echo "Testing on simulator $SIM…"
xcodebuild test \
  -project NightSky.xcodeproj \
  -scheme NightSky \
  -destination "id=$SIM" \
  | grep -E "Test Case.*(passed|failed)|Executed|\*\* TEST"
