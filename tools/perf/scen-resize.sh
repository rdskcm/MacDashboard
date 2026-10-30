#!/bin/bash
# G10: live-resize sweep across the 1000 pt tier boundary on Home (RESIZE-MOTION): the pinned 1000 x 733 window
# goes 1060 -> 940 -> 1060 twice at 60 Hz (2 s per leg, four crossings), then 2 s quiet. Needs PID from gate.sh.
# t0/t1 bracket the whole scenario (Time Profiler, Hitches); s0/s1 bracket the sweep only (gate.sh: sweep wall time
# and the app / WindowServer CPU-s). s0/s1 are not read by analyze.py's mark parser. When drv exits non-zero its
# "drv-error resize: ..." line goes to stdout (= <prefix>-drv.txt), s1 is not written and t1 closes the window.
. "$(dirname "$0")/scen-lib.sh"
: "${PID:?scen-resize: PID must be set}"
mark t0
mark s0
ERRF="${TMPDIR:-/tmp}/scen-resize-drv.$$"
"$BIN/drv" resize "$PID" 1060 940 2 2 >/dev/null 2>"$ERRF" & H=$!; wait "$H"; rc=$?; H=""
if [ "$rc" -ne 0 ]; then cat "$ERRF"; rm -f "$ERRF"; mark t1; exit 1; fi
rm -f "$ERRF"
mark s1
runh sleep 2
mark t1
