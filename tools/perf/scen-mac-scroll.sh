#!/bin/bash
# G7: This Mac scroll down, up, down, then a scroll over the right column.
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh "$BIN/drv" scroll 500 450 2 -12
runh sleep 2
runh "$BIN/drv" scroll 500 450 2 12
runh sleep 2
runh "$BIN/drv" scroll 500 450 2 -12
runh sleep 2
runh "$BIN/drv" scroll 800 450 2 12
mark t1
