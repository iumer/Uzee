#!/usr/bin/env bash
# ENV-007: fail if anything that looks like a key, certificate or provisioning profile is committed.
set -euo pipefail
cd "$(dirname "$0")/.."
bad=0
if git ls-files | grep -E '\.(p12|p8|pem|key|mobileprovision|cer|ipa)$|(^|/)\.env$'; then
  echo "Committed secret-like file(s) above"; bad=1
fi
patterns='-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9_-]{32,}|xox[baprs]-[A-Za-z0-9-]{10,}'
if git grep -nE -e "$patterns" -- . ':!scripts/check-secrets.sh'; then
  echo "Secret-like text above"; bad=1
fi
[ $bad -eq 0 ] && echo "No secrets found"
exit $bad
