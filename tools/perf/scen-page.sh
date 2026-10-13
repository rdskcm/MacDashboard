#!/bin/bash
# G6 page: iPhone page (chart view) scroll down and back.
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh "$BIN/drv" scroll 500 450 3 -15
runh sleep 3
runh "$BIN/drv" scroll 500 450 3 15
mark t1
