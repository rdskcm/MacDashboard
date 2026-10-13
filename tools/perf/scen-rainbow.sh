#!/bin/bash
# G5: hold the pointer 4 s on a plain KPI card (control), the battery-card "Details" ring button and the
# memory-card "Table" ring button; one labelled mark pair per window.
. "$(dirname "$0")/scen-lib.sh"
hold_secs="${HOLD_SECS:-4}"
for spot in ctrl:300:330 details:936:311 table:928:517; do
  label="${spot%%:*}"; rest="${spot#*:}"; x="${rest%%:*}"; y="${rest#*:}"
  mark t0 "$label"
  runh "$BIN/hold" "$x" "$y" "$hold_secs"
  mark t1 "$label"
  runh sleep 1.5
done
