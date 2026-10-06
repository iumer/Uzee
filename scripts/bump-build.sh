#!/usr/bin/env bash
# Bumps the build number (and optionally the version) in Config/Version.xcconfig.
#   scripts/bump-build.sh            -> build +1
#   scripts/bump-build.sh 0.1.0      -> version 0.1.0, build +1
# Then add the entry to docs/BUILD_HISTORY.md.
set -euo pipefail
f="$(dirname "$0")/../Config/Version.xcconfig"
build=$(grep CURRENT_PROJECT_VERSION "$f" | sed 's/.*= *//')
next=$((build + 1))
sed -i.bak "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $next/" "$f"
if [ $# -ge 1 ]; then sed -i.bak "s/MARKETING_VERSION = .*/MARKETING_VERSION = $1/" "$f"; fi
rm -f "$f.bak"
grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' "$f"
