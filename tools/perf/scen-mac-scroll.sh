#!/bin/bash
# G7 / GP-<page>: four segments of a triangle wave inside the page's real range, the last over the right column.
# Same motion time on every page (drv wave). An idle page (no scroll bar) or too short a range: no events, a quiet window of the same length.
. "$(dirname "$0")/scen-lib.sh"
if [ -n "${SCROLL_RANGE_PT:-}" ]; then
  runm "$BIN/drv" wave "$PID" 500,450,120,2 500,450,120,2 500,450,120,2 800,450,120,0
elif [ "${SCROLL_SHORT:-0}" = 1 ]; then
  mark t0
  runh sleep 17
  mark t1
else
  echo "drv-error scen-mac-scroll: SCROLL_RANGE_PT missing (the range probe set neither a range nor SCROLL_SHORT)" >&2
  exit 1
fi
