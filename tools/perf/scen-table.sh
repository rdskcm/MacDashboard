#!/bin/bash
# G6 table: iPhone page with the Table toggle on. Scrolls the table's own scroll area inside its range; drv probe inner moved
# the page so the table is fully visible and gave the point over it. The page does not move in the window.
. "$(dirname "$0")/scen-lib.sh"
runm "$BIN/drv" wave "$PID" "$SCROLL_X,$SCROLL_Y,168,2" "$SCROLL_X,$SCROLL_Y,180,3" "$SCROLL_X,$SCROLL_Y,180,0"
