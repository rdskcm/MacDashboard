#!/bin/bash
# G3: move the page to the lower margin of its real range (drv goto end), t0 two seconds after the move, nine quiet seconds, t1.
# The preparation move runs before t0 and stops inside the range, never at the hard bottom; the window has no scrolling
# (SCROLL-BENCH-EDGES keeps it). With no bar or a too-short range (SCROLL_SHORT) there is no move, only the same quiet window.
. "$(dirname "$0")/scen-lib.sh"
[ "${SCROLL_SHORT:-0}" = 1 ] || [ -z "${SCROLL_RANGE_PT:-}" ] || runh "$BIN/drv" goto "$PID" 500 450 end
runh sleep 2
mark t0
runh sleep 9
mark t1
