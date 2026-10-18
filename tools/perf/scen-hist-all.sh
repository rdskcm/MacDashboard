#!/bin/bash
# G4: pointer sweep over the History chart at range "all". The scroll to the bottom and the range press
# happen before recording (gate.sh, D14); this script only sweeps (y = $HIST_SWEEP_Y, set by route_hist so the sweep is over the chart plot).
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh "$BIN/drv" move 500 "${HIST_SWEEP_Y:-650}" 5
mark t1
