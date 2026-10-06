#!/usr/bin/env bash
# Runs one local package's tests on an iOS simulator: scripts/ci-test-package.sh UZeeData "<destination>"
set -euo pipefail
pkg="$1"; dest="$2"
cd "Packages/$pkg"
schemes=$(xcodebuild -list 2>/dev/null)
scheme="$pkg"
if echo "$schemes" | grep -q "$pkg-Package"; then scheme="$pkg-Package"; fi
set -o pipefail
xcodebuild test -scheme "$scheme" -destination "$dest" CODE_SIGNING_ALLOWED=NO \
  | grep -E "error:|✔|✘|Test run|Executed|\*\* " 
