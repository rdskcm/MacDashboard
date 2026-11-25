#!/usr/bin/env bash
# RELEASE-INTEGRITY: prints the path of the installed Xcode whose version equals the pin,
# or fails and says to bump the pin. .github/actions/select-xcode holds the pin and calls
# this. Runnable on a Mac without side effects: .github/scripts/find-xcode.sh 26.6
# Versions compare with trailing ".0"s dropped (26.6 = 26.6.0). Bundles with beta or RC
# in the name never match. With several matches the first in name order is taken.
#
# Usage: find-xcode.sh <pinned-version> [<apps-dir>]   (apps-dir defaults to /Applications)
set -euo pipefail
pin="${1:?usage: find-xcode.sh <pinned-version> [<apps-dir>]}"
apps="${2:-/Applications}"
norm() { sed -E 's/(\.0)+$//' <<<"$1"; }
want="$(norm "$pin")"
found=""
echo "Xcodes in $apps:" >&2
for xc in "$apps"/Xcode*.app; do
  [ -d "$xc" ] || continue
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$xc/Contents/Info.plist" 2>/dev/null || echo '?')"
  echo "  $xc ($ver)" >&2
  case "$xc" in *[Bb]eta*|*_RC*|*[Rr]elease_[Cc]andidate*) continue ;; esac
  if [ -z "$found" ] && [ "$(norm "$ver")" = "$want" ]; then found="$xc"; fi
done
if [ -z "$found" ]; then
  echo "::error::Xcode $pin (PINNED_XCODE in .github/actions/select-xcode/action.yml) is not installed in $apps. The runner image has changed: bump the pin to one of the Xcodes listed above, as its own deliberate one-line change." >&2
  exit 1
fi
echo "$found"
