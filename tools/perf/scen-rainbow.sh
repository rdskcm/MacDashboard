#!/bin/bash
# G5: hold the pointer 4 s on the Battery tile (control) and on its rainbow Details capsule; spots from
# route_battery (G5_SPOTS); one labelled mark pair per window.
. "$(dirname "$0")/scen-lib.sh"
hold_secs="${HOLD_SECS:-4}"
for spot in ${G5_SPOTS:?set by route_battery}; do
  label="${spot%%:*}"; rest="${spot#*:}"; x="${rest%%:*}"; y="${rest#*:}"
  mark t0 "$label"
  runh "$BIN/hold" "$x" "$y" "$hold_secs"
  mark t1 "$label"
  runh sleep 1.5
done
