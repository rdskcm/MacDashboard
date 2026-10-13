#!/bin/bash
# G6 hover: iPhone page (chart view), scroll to the chart, then a pointer sweep over it.
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh "$BIN/drv" scroll 800 200 2 -15
runh "$BIN/drv" scroll 800 200 0.8 8
runh sleep 3
runh "$BIN/drv" move 400 560 4
mark t1
