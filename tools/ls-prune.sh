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
# Exit: 0 ok, 1 a registration survived unregistering, 2 lsregister or /usr/bin/perl missing,
#       3 an lsregister call timed out (killed after LSREG_TIMEOUT seconds; the script stopped there), 64 usage.
# Callers (build_app.sh, tools/visual/run.sh, backup_auto.sh) treat non-zero as a warning.
set -uo pipefail

BUNDLE_ID="com.rdskcm.mac-dashboard"
# The install locations README.md names; build_app.sh --install uses the first.
INSTALLED=("$HOME/Applications/MacDashboard.app" "/Applications/MacDashboard.app")
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
LSREG_TIMEOUT=60   # seconds allowed for each lsregister call; a hung lsregister must not block callers (backup_auto.sh)

usage() { echo "usage: tools/ls-prune.sh [--list]" >&2; exit 64; }
MODE="prune"
[ $# -le 1 ] || usage
if [ $# -eq 1 ]; then
  if [ "$1" = "--list" ]; then MODE="list"; else usage; fi
fi
[ -x "$LSREG" ] || { echo "ls-prune: lsregister not found at $LSREG" >&2; exit 2; }
[ -x /usr/bin/perl ] || { echo "ls-prune: /usr/bin/perl not found (needed for the lsregister timeout)" >&2; exit 2; }

# Run lsregister with a time limit. macOS ships no timeout(1): perl forks, execs lsregister,
# and on SIGALRM kills it with SIGKILL and exits 124. Otherwise returns lsregister's status.
lsreg() {
  /usr/bin/perl -e '
    my $t = shift @ARGV;
    my $pid = fork();
    defined $pid or exit 125;
    if ($pid == 0) { exec { $ARGV[0] } @ARGV; exit 127; }
    $SIG{ALRM} = sub { kill "KILL", $pid; waitpid($pid, 0); exit 124; };
    alarm $t;
    waitpid($pid, 0);
    alarm 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$LSREG_TIMEOUT" "$LSREG" "$@"
}

# Called only from the main shell (never from a pipeline or $(...)), so exit stops the script.
timed_out() {
  echo "ls-prune: lsregister $1 timed out after ${LSREG_TIMEOUT}s (killed); stopped here, LaunchServices records may be incomplete — run tools/ls-prune.sh again later" >&2
  exit 3
}

# Every registered path whose record carries $BUNDLE_ID, one per line. Dump records are
# separated by lines of dashes; a "path:" or "identifier:" value may end in a
# " (0x...)" record handle that is not part of the value.
registered() {
  lsreg -dump 2>/dev/null | awk -v want="$BUNDLE_ID" '
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
  lsreg -dump 2>/dev/null | awk '
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

# Dumps are captured into variables in this shell and read back from here-strings, not
# streamed into `while` loops in pipeline subshells: a timeout then stops the script before
# anything acts on a partial dump.
if [ "$MODE" = "list" ]; then
  REG="$(registered)"; [ $? -ne 124 ] || timed_out -dump
  STB="$(stubs)"; [ $? -ne 124 ] || timed_out -dump
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if is_installed "$p"; then s=INSTALLED; elif [ -e "$p" ]; then s=EXISTS; else s=GONE; fi
    printf '%s\t%s\n' "$s" "$p"
  done <<< "$REG"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    is_installed "$p" || printf 'STUB\t%s\n' "$p"
  done <<< "$STB"
  exit 0
fi

for p in "${INSTALLED[@]}"; do
  [ -d "$p" ] || continue
  lsreg -f "$p" >/dev/null 2>&1
  [ $? -ne 124 ] || timed_out -f
done

# $1: registered() output. Runs in the main shell, so timed_out stops the script.
unregister_all() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    is_installed "$p" && continue
    is_running "$p" && continue
    lsreg -u "$p" >/dev/null 2>&1
    [ $? -ne 124 ] || timed_out -u
    printf 'REMOVED\t%s\n' "$p"
  done <<< "$1"
}
# $1: stubs() output.
unregister_stubs() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    is_installed "$p" && continue
    lsreg -u "$p" >/dev/null 2>&1
    [ $? -ne 124 ] || timed_out -u
    printf 'REMOVED\t%s\n' "$p"
  done <<< "$1"
}
# What is still registered outside the install locations: RUNNING / STILL lines. Runs inside
# $(...), so it returns 124 on a timed-out dump instead of calling timed_out.
left() {
  local reg stb p
  reg="$(registered)"; [ $? -ne 124 ] || return 124
  stb="$(stubs)"; [ $? -ne 124 ] || return 124
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    is_installed "$p" && continue
    if is_running "$p"; then printf 'RUNNING\t%s\n' "$p"; else printf 'STILL\t%s\n' "$p"; fi
  done <<< "$reg"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    is_installed "$p" && continue
    printf 'STILL\t%s\n' "$p"
  done <<< "$stb"
  return 0
}

REG="$(registered)"; [ $? -ne 124 ] || timed_out -dump
STB="$(stubs)"; [ $? -ne 124 ] || timed_out -dump
unregister_all "$REG"
unregister_stubs "$STB"
LEFT="$(left)"; [ $? -ne 124 ] || timed_out -dump
if grep -q '^STILL' <<< "$LEFT"; then
  # A record for a path that no longer exists can survive -u; -gc drops such records.
  lsreg -gc >/dev/null 2>&1
  [ $? -ne 124 ] || timed_out -gc
  LEFT="$(left)"; [ $? -ne 124 ] || timed_out -dump
fi
[ -z "$LEFT" ] || printf '%s\n' "$LEFT"
if grep -q '^STILL' <<< "$LEFT"; then exit 1; fi
exit 0
