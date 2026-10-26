#!/bin/bash
# G5: hold the pointer 4 s on the Report sheet's header row (ctrl) and on its «Show in Finder» button (capsule; the label
# dates from before REDESIGN-REPORT, when that button was a rainbow capsule); spots from route_report (G5_SPOTS); one labelled mark pair per window.
. "$(dirname "$0")/scen-lib.sh"
hold_secs="${HOLD_SECS:-4}"
for spot in ${G5_SPOTS:?set by route_report}; do
  label="${spot%%:*}"; rest="${spot#*:}"; x="${rest%%:*}"; y="${rest#*:}"
  mark t0 "$label"
  runh "$BIN/hold" "$x" "$y" "$hold_secs"
  mark t1 "$label"
  runh sleep 1.5
done
