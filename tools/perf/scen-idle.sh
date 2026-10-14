#!/bin/bash
# G2 idle scenario: marks around a quiet stretch. usage: scen-idle.sh [seconds=15]
. "$(dirname "$0")/scen-lib.sh"
mark t0
runh sleep "${1:-15}"
mark t1
