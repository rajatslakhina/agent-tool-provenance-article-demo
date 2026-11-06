#!/usr/bin/env bash
# Builds Demo.xcodeproj for the iOS Simulator, installs and launches the app,
# and saves real screenshots of the running app to Demo/Screenshots/.
# Optional: SIM_UDID=<udid> to pick a specific simulator.
set -euo pipefail

RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
BUNDLE_ID="com.rajatlakhina.ProvenanceGateDemo"
OUT="Demo/Screenshots"
mkdir -p "$OUT"

UDID="${SIM_UDID:-}"
if [ -z "$UDID" ]; then
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime, items in sorted(devices.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for d in items:
        if d["name"].startswith("iPhone") and "Pro" in d["name"] and "Max" not in d["name"]:
            print(d["udid"]); sys.exit(0)
sys.exit(1)')
fi
echo "Using simulator $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

xcodebuild -project Demo.xcodeproj -scheme Demo -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

APP="build/Build/Products/Debug-iphonesimulator/Demo.app"
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true

shoot () {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
  sleep 8
  # Fails if the app crashed after launch: a running app has a numeric PID in column one.
  xcrun simctl spawn "$UDID" launchctl list > "$RUNNER_TEMP/processes.txt"
  awk -v id="$BUNDLE_ID" 'index($0, id) && $1 ~ /^[0-9]+$/ { found = 1 } END { exit !found }' "$RUNNER_TEMP/processes.txt"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
}

shoot replay-auto-update -tab fleet -policy auto
shoot replay-digest-lockfile -tab fleet -policy digest
shoot replay-canary -tab fleet -policy canary
shoot compare-policies -tab compare
ls -la "$OUT"
