#!/bin/bash
# G4: pointer sweep over the History chart at range "all". The scroll to the bottom and the range press
# happen before recording (gate.sh, D14); this script only sweeps.
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh "$BIN/drv" move 500 650 5
mark t1
