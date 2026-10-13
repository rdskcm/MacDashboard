#!/bin/bash
# tools/perf/power.sh — power precondition for the perf gate (R3).
#
# Usage: power.sh before|after <logfile> [label]
#          Appends "HH:MM:SS <label> | <pmset -g batt line 1> | <charge> | lowpowermode=<n>" to <logfile>
#          (label defaults to the mode). Exit 0 only if line 1 contains "AC Power" and Low Power Mode is 0.
#          A Mac without a lowpowermode key counts as 0 and logs "lowpowermode=n/a".
#        power.sh between <start-epoch> <end-epoch>
#          Exit 1 if `pmset -g log` has a "Using Batt" summary stamped inside [start, end], else 0.
#        Exit 64 on a usage error.
set -uo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

mode="${1:-}"
case "$mode" in
  before|after)
    log="${2:-}"; [ -n "$log" ] || usage
    label="${3:-$mode}"
    line1="$(pmset -g batt | head -1 | tr -d '\n')"
    charge="$(pmset -g batt | sed -n 2p | awk '{print $3,$4}' | tr -d '\n')"
    lpm="$(pmset -g | awk '/lowpowermode/{print $2}')"
    echo "$(date +%T) $label | $line1 | $charge | lowpowermode=${lpm:-n/a}" >> "$log"
    case "$line1" in *"AC Power"*) ;; *) exit 1 ;; esac
    [ "${lpm:-0}" = "0" ] || exit 1
    exit 0
    ;;
  between)
    start="${2:-}"; end="${3:-}"
    [ -n "$start" ] && [ -n "$end" ] || usage
    pmset -g log 2>/dev/null | python3 -I -c '
import sys
from datetime import datetime
lo, hi = float(sys.argv[1]), float(sys.argv[2])
for line in sys.stdin:
    if "Using Batt" not in line:
        continue
    try:
        ts = datetime.strptime(line[:25], "%Y-%m-%d %H:%M:%S %z").timestamp()
    except ValueError:
        continue
    if lo <= ts <= hi:
        print("Using Batt at", line[:25], file=sys.stderr)
        sys.exit(1)
' "$start" "$end"
    exit $?
    ;;
  *) usage ;;
esac
