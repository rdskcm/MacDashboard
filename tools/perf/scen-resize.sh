#!/bin/bash
# G10: live-resize sweep across the 1000 pt tier boundary on Home (RESIZE-MOTION): the pinned 1000 x 733 window
# goes 1060 -> 940 -> 1060 twice at 60 Hz (2 s per leg, four crossings), then 2 s quiet. Needs PID from gate.sh.
# t0/t1 bracket the whole scenario (Time Profiler, Hitches); s0/s1 bracket the sweep only (gate.sh: sweep wall time
# and the app / WindowServer CPU-s). s0/s1 are not read by analyze.py's mark parser.
. "$(dirname "$0")/scen-lib.sh"
: "${PID:?scen-resize: PID must be set}"
mark t0
mark s0
runh "$BIN/drv" resize "$PID" 1060 940 2 2
mark s1
runh sleep 2
mark t1
