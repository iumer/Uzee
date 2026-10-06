#!/usr/bin/env bash
# Prints IPHONE_DEST and IPAD_DEST for the newest available iOS simulators.
set -euo pipefail
json=$(xcrun simctl list devices available -j)
pick() {
  echo "$json" | python3 -c '
import json,sys,re
kind=sys.argv[1]
d=json.load(sys.stdin)["devices"]
best=None
for rt,devs in d.items():
    m=re.search(r"iOS-(\d+)-(\d+)",rt)
    if not m: continue
    ver=(int(m.group(1)),int(m.group(2)))
    for dev in devs:
        if dev["name"].startswith(kind) and (best is None or ver>best[0]):
            best=(ver,dev["udid"],dev["name"])
if not best: sys.exit("no "+kind+" simulator")
print(best[1]); print(best[2]+" iOS %d.%d"%best[0], file=sys.stderr)
' "$1"
}
echo "IPHONE_DEST=platform=iOS Simulator,id=$(pick iPhone)"
echo "IPAD_DEST=platform=iOS Simulator,id=$(pick iPad)"
