#!/bin/bash
# G6 page: iPhone page (chart view), two segments of a triangle wave inside the page's real range.
. "$(dirname "$0")/scen-lib.sh"
runm "$BIN/drv" wave "$PID" 500,450,180,3 500,450,180,0
