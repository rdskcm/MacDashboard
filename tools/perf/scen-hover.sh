#!/bin/bash
# G6 hover: iPhone page (chart view), a wave inside the real range ending at 0.37 of it, with the chart under y=560, then a pointer sweep.
. "$(dirname "$0")/scen-lib.sh"
export SCROLL_END_FRAC=0.37
runm "$BIN/drv" wave "$PID" 800,200,168,0
runh sleep 3
runh "$BIN/drv" move 400 560 4
mark t1
