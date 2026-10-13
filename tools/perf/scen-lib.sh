# tools/perf/scen-lib.sh — sourced by the scen-*.sh scenario scripts (not run on its own).
# Needs $BIN (the helper dir gate.sh compiled drv/hold into). Marks are written to stdout:
#   "t0 <epoch>" / "t1 <epoch>"                  one window per scenario
#   "t0 <label> <epoch>" / "t1 <label> <epoch>"  several labelled windows (G5)
: "${BIN:?scen-lib: BIN (helper dir) must be set}"

mark() { # mark t0|t1 [label]
  perl -MTime::HiRes=time -e 'my $k = shift; my $l = @ARGV ? shift : ""; printf "%s %s%.3f\n", $k, ($l eq "" ? "" : "$l "), time' "$@"
}

# Run a helper (or sleep) in the background and wait on that PID only, so a TERM from gate.sh
# stops the helper instead of waiting for it. Helper output is dropped; marks come from mark().
H=""
trap '[ -n "$H" ] && kill "$H" 2>/dev/null; exit 143' TERM INT
runh() {
  "$@" >/dev/null 2>&1 &
  H=$!
  wait "$H"
  H=""
}
