#!/bin/bash
# G4: pointer sweep over the History chart at range "all". The scroll to the bottom and the range press
# happen before recording (gate.sh, D14); this script only sweeps (x/y = centre of the history-chart AX frame, set by route_hist).
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh "$BIN/drv" move "${HIST_SWEEP_X:?set by route_hist}" "${HIST_SWEEP_Y:?set by route_hist}" 5
mark t1
