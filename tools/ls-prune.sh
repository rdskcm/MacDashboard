#!/bin/bash
# tools/ls-prune.sh — keep the installed MacDashboard the only copy LaunchServices knows.
#
# LaunchServices remembers every bundle with CFBundleIdentifier com.rdskcm.mac-dashboard it
# has seen: a dist.noindex/ build, a test copy in a scratchpad, a copy inside a backup snapshot or a
# mounted Time Machine backup, a bundle in the Trash. Opening the app by bundle ID can then
# launch any of them (APP-ID-DUPLICATES). This script unregisters every registration of that
# ID except the install locations, and re-registers the installed copy as it is on disk.
# It never touches a file — only LaunchServices records.
#
# A copy that is running is left registered: unregistering it would make
# `tell application id ...` resolve to the installed copy while the other copy still runs.
# The next run catches it.
#
# Usage: tools/ls-prune.sh           unregister
#        tools/ls-prune.sh --list    print every registration, change nothing
# Output, one line per registration, "<STATUS><TAB><path>":
#   --list:     INSTALLED | EXISTS | GONE | STUB (a registration with no Info.plist)
#   unregister: REMOVED (unregistered) | RUNNING (left registered) | STILL (survived);
#               nothing is printed when there was nothing to remove.
# Exit: 0 ok, 1 a registration survived unregistering, 2 lsregister missing, 64 usage.
# Callers (build_app.sh, tools/visual/run.sh, backup_auto.sh) treat non-zero as a warning.
set -uo pipefail

BUNDLE_ID="com.rdskcm.mac-dashboard"
# The install locations README.md names; build_app.sh --install uses the first.
INSTALLED=("$HOME/Applications/MacDashboard.app" "/Applications/MacDashboard.app")
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

usage() { echo "usage: tools/ls-prune.sh [--list]" >&2; exit 64; }
MODE="prune"
[ $# -le 1 ] || usage
if [ $# -eq 1 ]; then
  if [ "$1" = "--list" ]; then MODE="list"; else usage; fi
fi
[ -x "$LSREG" ] || { echo "ls-prune: lsregister not found at $LSREG" >&2; exit 2; }

# Every registered path whose record carries $BUNDLE_ID, one per line. Dump records are
# separated by lines of dashes; a "path:" or "identifier:" value may end in a
# " (0x...)" record handle that is not part of the value.
registered() {
  "$LSREG" -dump 2>/dev/null | awk -v want="$BUNDLE_ID" '
    function val(s) { sub(/^[a-z]+:[ \t]+/, "", s); sub(/ \(0x[0-9a-fA-F]+\)$/, "", s); return s }
    function flush() { if (id == want && path != "") print path; path = ""; id = "" }
    /^----------/ { flush(); next }
    /^path:/ { if (path == "") path = val($0); next }
    /^identifier:/ { if (id == "") id = val($0); next }
    END { flush() }
  ' | sort -u
}

# Stub records: a registration of a bundle with no Info.plist (an empty or half-copied
# MacDashboard.app). It has no "identifier:" line, so registered() never sees it; its
# "bundle id:" is the directory name. Matched on all three: bundle id MacDashboard.app, no
# identifier, path ending in /MacDashboard.app. Never on the path alone.
stubs() {
  "$LSREG" -dump 2>/dev/null | awk '
    function val(s) { sub(/^[a-z ]+:[ \t]+/, "", s); sub(/ \(0x[0-9a-fA-F]+\)$/, "", s); return s }
    function flush() {
      if (bid == "MacDashboard.app" && id == "" && path ~ /\/MacDashboard\.app$/) print path
      path = ""; id = ""; bid = ""
    }
    /^----------/ { flush(); next }
    /^bundle id:/ { if (bid == "") bid = val($0); next }
    /^path:/ { if (path == "") path = val($0); next }
    /^identifier:/ { if (id == "") id = val($0); next }
    END { flush() }
  ' | sort -u
}

is_installed() {
  local p
  for p in "${INSTALLED[@]}"; do [ "$1" = "$p" ] && return 0; done
  return 1
}

# Bundle paths of every running MacDashboard process (a function, not an inline $(...):
# bash 3.2 misparses some constructs inside command substitution).
running_bundles() {
  local pid comm
  for pid in $(pgrep -x MacDashboard 2>/dev/null); do
    comm="$(ps -o comm= -p "$pid" 2>/dev/null)" || continue
    if [ "${comm%/Contents/MacOS/MacDashboard}" != "$comm" ]; then
      printf '%s\n' "${comm%/Contents/MacOS/MacDashboard}"
    fi
  done
  return 0
}
RUNNING="$(running_bundles)"
is_running() { [ -n "$RUNNING" ] && printf '%s\n' "$RUNNING" | grep -qxF -- "$1"; }

if [ "$MODE" = "list" ]; then
  registered | while IFS= read -r p; do
    if is_installed "$p"; then s=INSTALLED; elif [ -e "$p" ]; then s=EXISTS; else s=GONE; fi
    printf '%s\t%s\n' "$s" "$p"
  done
  stubs | while IFS= read -r p; do
    is_installed "$p" || printf 'STUB\t%s\n' "$p"
  done
  exit 0
fi

for p in "${INSTALLED[@]}"; do
  if [ -d "$p" ]; then "$LSREG" -f "$p" >/dev/null 2>&1; fi
done

unregister_all() {
  registered | while IFS= read -r p; do
    is_installed "$p" && continue
    is_running "$p" && continue
    "$LSREG" -u "$p" >/dev/null 2>&1 || true
    printf 'REMOVED\t%s\n' "$p"
  done
}
unregister_stubs() {
  stubs | while IFS= read -r p; do
    is_installed "$p" && continue
    "$LSREG" -u "$p" >/dev/null 2>&1 || true
    printf 'REMOVED\t%s\n' "$p"
  done
}
stub_survivors() {
  stubs | while IFS= read -r p; do
    is_installed "$p" && continue
    printf 'STILL\t%s\n' "$p"
  done
}
survivors() {
  registered | while IFS= read -r p; do
    is_installed "$p" && continue
    if is_running "$p"; then printf 'RUNNING\t%s\n' "$p"; else printf 'STILL\t%s\n' "$p"; fi
  done
}

unregister_all
unregister_stubs
LEFT="$(survivors; stub_survivors)"
if printf '%s\n' "$LEFT" | grep -q '^STILL'; then
  # A record for a path that no longer exists can survive -u; -gc drops such records.
  "$LSREG" -gc >/dev/null 2>&1 || true
  LEFT="$(survivors; stub_survivors)"
fi
[ -z "$LEFT" ] || printf '%s\n' "$LEFT"
if printf '%s\n' "$LEFT" | grep -q '^STILL'; then exit 1; fi
exit 0
