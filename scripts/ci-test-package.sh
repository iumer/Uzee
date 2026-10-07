#!/usr/bin/env bash
# Runs one local package's tests on an iOS simulator: scripts/ci-test-package.sh UZeeData "<destination>"
set -euo pipefail
pkg="$1"; dest="$2"
root="$(pwd)"
mkdir -p "$root/build"
log="$root/build/$pkg-test.log"
cd "Packages/$pkg"
schemes=$(xcodebuild -list 2>/dev/null)
scheme="$pkg"
if echo "$schemes" | grep -q "$pkg-Package"; then scheme="$pkg-Package"; fi
status=0
xcodebuild test -scheme "$scheme" -destination "$dest" CODE_SIGNING_ALLOWED=NO > "$log" 2>&1 || status=$?
grep -E "error:|✔|✘|Test run|Executed|\*\* " "$log" || true
if [ "$status" -ne 0 ]; then
  # Compiler crashes print no "error:" line; show the stack dump context too.
  echo "::group::Failure details"
  tail -40 "$log"
  grep -n -E -A12 "Stack dump|Assertion failed|unable to type-check|While (evaluating|type-checking|emitting|silgen)|1\.\s+Apple Swift" "$log" | head -150 || true
  echo "::endgroup::"
fi
exit "$status"
