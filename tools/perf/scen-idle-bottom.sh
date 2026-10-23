#!/bin/bash
# G3: scroll This Mac to the bottom, t0 two seconds after the scroll, nine quiet seconds, t1.
. "$(dirname "$0")/scen-lib.sh"
runh "$BIN/drv" scroll 500 450 3 -15
runh sleep 2
mark t0
runh sleep 9
mark t1
