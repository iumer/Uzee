#!/usr/bin/env bash
# Boots one simulator and runs the prebuilt smoke UI tests on it.
#   scripts/ci-run-smoke.sh <simulator-udid> <label>
set -euo pipefail
id="$1"; label="$2"
xcrun simctl boot "$id" 2>/dev/null || true
xcrun simctl bootstatus "$id" -b > /dev/null
echo "$label simulator booted; running smoke tests"
set -o pipefail
xcodebuild test-without-building \
  -project UZee.xcodeproj -scheme UZee -configuration Debug \
  -destination "platform=iOS Simulator,id=$id" -derivedDataPath build/dd \
  -resultBundlePath "build/smoke-$label.xcresult" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "build/smoke-$label.log" | grep -E "error:|Test Case|Test Suite|Executed|\*\* " || { tail -80 "build/smoke-$label.log"; exit 1; }
