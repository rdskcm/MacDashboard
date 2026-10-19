#!/bin/bash
# tools/bench-app.sh SRC.app DEST_DIR — copy a MacDashboard build to DEST_DIR/MacDashboard.app under the bench
# bundle id com.rdskcm.mac-dashboard.bench, re-signed ad hoc with the app's entitlements and hardened runtime.
# A bench copy has its own defaults domain and saved state, so a test run never reads or writes the user's
# com.rdskcm.mac-dashboard domain, and opening the app by its real bundle id never resolves to a bench copy.
# Idempotent on a bundle that is already a bench copy. Prints the copy's path. Exit 0 ok, 64 usage, 70 failure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH_ID="com.rdskcm.mac-dashboard.bench"
[ $# -eq 2 ] || { echo "usage: tools/bench-app.sh SRC.app DEST_DIR" >&2; exit 64; }
src="$1"; dest="$2/MacDashboard.app"
[ -x "$src/Contents/MacOS/MacDashboard" ] || { echo "bench-app: not an app bundle: $src" >&2; exit 64; }
mkdir -p "$2"
rm -rf "$dest"
ditto "$src" "$dest" || exit 70
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BENCH_ID" "$dest/Contents/Info.plist" || exit 70
codesign --force --options runtime --timestamp=none --entitlements "$ROOT/MacDashboard.entitlements" \
  --sign - "$dest" >/dev/null 2>&1 || { echo "bench-app: codesign failed for $dest" >&2; exit 70; }
echo "$dest"
