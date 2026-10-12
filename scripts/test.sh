#!/usr/bin/env bash
# Runs unit tests on the newest available iPhone simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted((k for k in devices if "iOS" in k), reverse=True):
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit(0)
sys.exit("no iPhone simulator found")
')
echo "Testing on simulator $UDID"

xcodebuild test \
  -project GymApp.xcodeproj \
  -scheme GymApp \
  -destination "id=$UDID" \
  CODE_SIGNING_ALLOWED=NO \
  | tee build/test.log
