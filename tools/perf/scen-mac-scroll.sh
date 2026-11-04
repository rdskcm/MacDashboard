#!/bin/bash
# G7 / GP-<page>: four segments of a triangle wave inside the page's real range, the last over the right column.
# Same motion time on every page (drv wave). Idle page: today's events, nothing moves. Too short a range: no events.
. "$(dirname "$0")/scen-lib.sh"
if [ -n "${SCROLL_RANGE_PT:-}" ]; then
  runm "$BIN/drv" wave "$PID" 500,450,120,2 500,450,120,2 500,450,120,2 800,450,120,0
elif [ "${SCROLL_SHORT:-0}" = 1 ]; then
  mark t0
  runh sleep 17
  mark t1
else
  mark t0
  runh "$BIN/drv" scroll 500 450 2 -12
  runh sleep 2
  runh "$BIN/drv" scroll 500 450 2 12
  runh sleep 2
  runh "$BIN/drv" scroll 500 450 2 -12
  runh sleep 2
  runh "$BIN/drv" scroll 800 450 2 12
  mark t1
fi
