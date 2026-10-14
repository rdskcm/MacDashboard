#!/bin/bash
# G6 table: iPhone page with the Table toggle on; scrolls in the page and the table.
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh "$BIN/drv" scroll 800 200 2 -15
runh "$BIN/drv" scroll 800 200 0.8 8
runh sleep 2
runh "$BIN/drv" scroll 400 560 3 -10
runh sleep 3
runh "$BIN/drv" scroll 800 380 3 10
mark t1
