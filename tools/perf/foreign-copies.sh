#!/bin/bash
# tools/perf/foreign-copies.sh — MacDashboard processes the perf tools did not start (GATE-AX-MISS).
# A second MacDashboard process made the 2026-10-30 night gate press buttons in the wrong app, and any copy loads
# the CPU and GPU the gate measures. gate.sh refuses to start while one runs (list); night.sh closes them (close).
#
# Usage:
#   foreign-copies.sh list
#       one line per running MacDashboard process (zombies skipped), "pid ppid started command" from
#       ps -ww -o pid=,ppid=,lstart=,command=; nothing when there is none. Exit 0.
#   foreign-copies.sh close [--dry-run] [--only PID]
#       closes them. First every copy that is not the installed app (bench copies, dist.noindex builds, scratchpad
#       copies): SIGTERM, SIGKILL after 5 s. Then the installed app (a bundle directly in /Applications or
#       ~/Applications with bundle id com.rdskcm.mac-dashboard): one AppleScript quit, 15 s limit, never killed.
#       Prints "found: <list line>" per process, then "closed: <pid> (<how>)" or "left: <pid> <path> (<why>)".
#       --dry-run prints "would close: ..." / "would quit: ..." instead and touches nothing.
#       --only PID (test seam) acts on that one process; it must be a running MacDashboard process, else exit 64.
# Exit: 0 nothing left | 1 at least one "left:" line | 64 usage
set -uo pipefail

BUNDLE_ID="com.rdskcm.mac-dashboard"
TERM_GRACE=5     # s from SIGTERM to SIGKILL
QUIT_LIMIT=15    # s the installed app gets after the AppleScript quit

usage() { sed -n '2,/^set -uo/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//'; }
bad() { echo "foreign-copies.sh: $*" >&2; exit 64; }

alive() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"; [ -n "$s" ] && [ "${s#Z}" = "$s" ]; }
pids() { local p; for p in $(pgrep -x MacDashboard 2>/dev/null); do alive "$p" && echo "$p"; done; return 0; }
line() { ps -ww -o pid=,ppid=,lstart=,command= -p "$1" 2>/dev/null | sed 's/^ *//'; }
exe() { ps -ww -o comm= -p "$1" 2>/dev/null; }
gone() { local t=0; while alive "$1" && [ "$t" -lt $(( $2 * 10 )) ]; do sleep 0.1; t=$((t + 1)); done; ! alive "$1"; }
installed() {   # pid -> 0 when it runs the installed app
  local x b; x="$(exe "$1")"; b="${x%/Contents/MacOS/*}"
  [ -n "$x" ] && [ "$b" != "$x" ] || return 1
  case "$(dirname "$b")" in /Applications|"$HOME/Applications") ;; *) return 1 ;; esac
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$b/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ]
}

[ $# -ge 1 ] || { usage >&2; exit 64; }
case "$1" in
  list) [ $# = 1 ] || bad "list takes no arguments"; for p in $(pids); do line "$p"; done; exit 0 ;;
  close) shift ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac
DRY=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --only) [ $# -ge 2 ] || bad "--only needs a pid"; ONLY="$2"; shift 2 ;;
    *) bad "unknown argument: $1" ;;
  esac
done
ALL="$(pids)"
if [ -n "$ONLY" ]; then
  [[ "$ONLY" =~ ^[0-9]+$ ]] || bad "--only needs a pid"
  grep -qx "$ONLY" <<< "$ALL" || bad "--only $ONLY is not a running MacDashboard process"
  ALL="$ONLY"
fi
OTHER=""; INST=""
for p in $ALL; do
  echo "found: $(line "$p")"
  if installed "$p"; then INST="$INST $p"; else OTHER="$OTHER $p"; fi
done
LEFT=0
for p in $OTHER; do
  if [ "$DRY" = 1 ]; then echo "would close: $p (SIGTERM, SIGKILL after $TERM_GRACE s)"; continue; fi
  kill -TERM "$p" 2>/dev/null
  if gone "$p" "$TERM_GRACE"; then echo "closed: $p (SIGTERM)"; continue; fi
  kill -KILL "$p" 2>/dev/null
  if gone "$p" 2; then echo "closed: $p (SIGKILL after $TERM_GRACE s)"
  else echo "left: $p $(exe "$p") (survived SIGKILL)"; LEFT=1; fi
done
# The installed app last: dist.noindex builds share its bundle id, so a quit by bundle id reaches only it once they are gone.
for p in $INST; do
  if [ "$DRY" = 1 ]; then echo "would quit: $p (AppleScript quit of $BUNDLE_ID, $QUIT_LIMIT s limit, never killed)"; continue; fi
  if [ "$LEFT" = 1 ]; then echo "left: $p $(exe "$p") (not asked to quit: another copy survived, a quit by bundle id could reach it)"; continue; fi
  alive "$p" || { echo "closed: $p (had quit by itself)"; continue; }
  osascript -e "with timeout of $QUIT_LIMIT seconds" -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" -e "end timeout" >/dev/null 2>&1 &
  q=$!
  if gone "$p" "$QUIT_LIMIT"; then echo "closed: $p (AppleScript quit)"
  else echo "left: $p $(exe "$p") (still running $QUIT_LIMIT s after an AppleScript quit; the installed app is never killed)"; LEFT=1; fi
  kill "$q" 2>/dev/null; wait "$q" 2>/dev/null
done
exit "$LEFT"
