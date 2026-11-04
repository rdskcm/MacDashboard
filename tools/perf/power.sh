#!/bin/bash
# tools/perf/power.sh — power precondition for the perf gate (R3).
#
# Usage: power.sh before|after <logfile> [label]
#          Appends "HH:MM:SS <label> | <pmset -g batt line 1> | <charge> | lowpowermode=<n>" to <logfile>
#          (label defaults to the mode). Exit 0 only if Low Power Mode is 0, on AC or on battery.
#          A Mac without a lowpowermode key counts as 0 and logs "lowpowermode=n/a".
#        power.sh ac <logfile> [label]
#          Same log line. Exit 0 only if line 1 contains "AC Power" and Low Power Mode is 0 (night runs).
#        power.sh source
#          Prints AC or Batt from line 1 of `pmset -g batt`.
#        power.sh between <start-epoch> <end-epoch> <AC|Batt>
#          Exit 1 if `pmset -g log` has a "Using AC" or "Using Batt" summary stamped inside [start, end]
#          that differs from the given source, or if the current source differs. Else 0.
#        power.sh longrun <minutes>
#          On battery with minutes >= 15 prints one WARNING line. Prints nothing otherwise. Always exit 0.
#        Exit 64 on a usage error.
set -uo pipefail

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

cur_source() {
  case "$(pmset -g batt | head -1)" in *"AC Power"*) echo AC ;; *) echo Batt ;; esac
}

mode="${1:-}"
case "$mode" in
  before|after|ac)
    log="${2:-}"; [ -n "$log" ] || usage
    label="${3:-$mode}"
    line1="$(pmset -g batt | head -1 | tr -d '\n')"
    charge="$(pmset -g batt | sed -n 2p | awk '{print $3,$4}' | tr -d '\n')"
    lpm="$(pmset -g | awk '/lowpowermode/{print $2}')"
    echo "$(date +%T) $label | $line1 | $charge | lowpowermode=${lpm:-n/a}" >> "$log"
    if [ "$mode" = "ac" ]; then
      case "$line1" in *"AC Power"*) ;; *) exit 1 ;; esac
    fi
    [ "${lpm:-0}" = "0" ] || exit 1
    exit 0
    ;;
  source)
    cur_source
    exit 0
    ;;
  between)
    start="${2:-}"; end="${3:-}"; want="${4:-}"
    [ -n "$start" ] && [ -n "$end" ] || usage
    case "$want" in AC|Batt) ;; *) usage ;; esac
    [ "$(cur_source)" = "$want" ] || { echo "power source is now $(cur_source), expected $want" >&2; exit 1; }
    pmset -g log 2>/dev/null | python3 -I -c '
import re, sys
from datetime import datetime
lo, hi, want = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
for line in sys.stdin:
    m = re.search(r"Summary.*\bUsing (AC|Batt)\b", line)
    if not m or m.group(1) == want:
        continue
    try:
        ts = datetime.strptime(line[:25], "%Y-%m-%d %H:%M:%S %z").timestamp()
    except ValueError:
        continue
    if lo <= ts <= hi:
        print("Using", m.group(1), "at", line[:25], file=sys.stderr)
        sys.exit(1)
' "$start" "$end" "$want"
    exit $?
    ;;
  longrun)
    minutes="${2:-}"
    case "$minutes" in ''|*[!0-9]*) usage ;; esac
    if [ "$(cur_source)" = "Batt" ] && [ "$minutes" -ge 15 ]; then
      echo "WARNING: on battery, this run takes about $minutes min; connect the power adapter so the Mac does not shut down midway"
    fi
    exit 0
    ;;
  *) usage ;;
esac
