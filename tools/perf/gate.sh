#!/bin/bash
# tools/perf/gate.sh — the perf gate (GPU-RENDER-AUDIT): scenarios G1-G9 against an app bundle,
# optionally against a baseline bundle too. Moves the real pointer and sends AX actions: do not use
# the Mac while it runs. See tools/perf/README.md.
#
# Usage: gate.sh [--app PATH] [--baseline PATH] [--scenarios G1,G2,...] [--runs N] [--out DIR]
#                [--orphan] [--keep-traces] [--g1-max PCT]
#   --app        bundle under test (default dist.noindex/MacDashboard.app)
#   --baseline   pre-block bundle; candidate and baseline runs alternate A,B,A,B,...
#   --scenarios  G1..G9, GP:<page> (pages: cpu memory storage battery security backups system history), or
#                all (= every G item incl. G8, plus GP for all pages; implies --orphan);
#                default G1,G2,G3,G4,G5,G6,G7,G9. G8 needs --orphan.
#   --runs       runs per scenario and arm, 1-7 (default 3)
#   --out        run directory, must be inside tools/perf/out/ (default tools/perf/out/<stamp>)
#   --orphan     G8 builds its bench home with an orphan launchd plist
#   --keep-traces  keep .trace bundles and exported XML (10-60 MB each)
#   --g1-max     absolute G1 app CPU limit in % (default 5.6, the level before C7; 2.5 after Step 7)
#   -h, --help   this text
# Exit: 0 pass (noisy rows do not fail) | 1 any FAIL | 3 INVALID run (power changed) | 4 defaults domain changed
#       during the run | 5 ERROR: at least one scenario not measured (an AX element was still missing after one
#       retry; the other scenarios ran and are reported) | 64 usage | 65 precondition refused | 70 runtime error.
#       When several apply: 3 over 4 over 5 over 1.
#       Last line: GATE: exit=<n> pass=<k> fail=<m> noisy=<j> invalid=<0|1> error=<e>
# Data safety: runs bench copies (bundle id com.rdskcm.mac-dashboard.bench); synthetic fixtures only; never touches ~/Library/Application Support/MacDashboard;
# kills only the PIDs it started (never by name); never writes or restores the defaults domain.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PERF="$ROOT/tools/perf"
BUNDLE_ID="com.rdskcm.mac-dashboard"
BENCH_ID="com.rdskcm.mac-dashboard.bench"
GP_PAGES="cpu memory storage battery security backups system history"

APP="$ROOT/dist.noindex/MacDashboard.app"
BASELINE=""
SCENARIOS=""
RUNS=""
OUT=""
ORPHAN=0
KEEP=0
G1_MAX="5.6"

NPASS=0; NFAIL=0; NNOISY=0; INVALID=0; NERROR=0; QUIET_EXIT=0; LS_DIRTY=0; STARTED=0
PIDS=""; HOMEDIR=""; BIN=""; PID=""; CAND_APP=""; BASE_APP=""; CUR_PREFIX=""

usage() { sed -n '2,/^[^#]/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//'; }
log() { echo "[$(date +%T)] $*" | tee -a "${OUT:-/dev/null}/gate.log" 2>/dev/null; }
fatal() { local code=$1; shift; echo "gate: $*" >&2; exit "$code"; }

# ---------------------------------------------------------------- process tracking
track()   { [ -n "$PIDS" ] && echo "$1" >> "$PIDS"; }
untrack() { [ -n "$PIDS" ] && [ -f "$PIDS" ] && { grep -vx "$1" "$PIDS" > "$PIDS.new"; mv "$PIDS.new" "$PIDS"; }; return 0; }

# Kill only PIDs this script recorded, and only while they are still its own children (PID reuse guard).
kill_tracked() {
  [ -n "$PIDS" ] && [ -f "$PIDS" ] || return 0
  local p pp
  while read -r p; do
    [ -n "$p" ] || continue
    pp="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    [ "$pp" = "$$" ] || continue
    kill "$p" 2>/dev/null
  done < "$PIDS"
  sleep 1
  while read -r p; do
    [ -n "$p" ] || continue
    pp="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    [ "$pp" = "$$" ] || continue
    kill -9 "$p" 2>/dev/null
  done < "$PIDS"
  : > "$PIDS"
}

on_exit() {
  local rc=$?
  trap - EXIT INT TERM
  [ "$QUIET_EXIT" = 1 ] && exit "$rc"
  kill_tracked
  [ -n "${OUT:-}" ] && rm -rf "$OUT/apps"
  if [ "$LS_DIRTY" = 1 ]; then
    # The run opened bundles by path; drop their LaunchServices registrations (tools/ls-prune.sh).
    local ls_out
    ls_out="$("$ROOT/tools/ls-prune.sh" 2>/dev/null)" || echo "gate: warning: ls-prune.sh exited non-zero" >&2
    if grep -q '^RUNNING' <<< "$ls_out"; then echo "gate: warning: a copy is still running (ls-prune RUNNING)" >&2; fi
  fi
  local line="GATE: exit=$rc pass=$NPASS fail=$NFAIL noisy=$NNOISY invalid=$INVALID error=$NERROR"
  [ "$STARTED" = 1 ] && [ -d "$OUT" ] && echo "$line" >> "$OUT/report.md"
  echo "$line"
  exit "$rc"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------- arguments
need() { [ $# -ge 2 ] && [ -n "$2" ] || { usage >&2; fatal 64 "$1 needs a value"; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --app)        need "$@"; APP="$2"; shift 2 ;;
    --baseline)   need "$@"; BASELINE="$2"; shift 2 ;;
    --scenarios)  need "$@"; SCENARIOS="$2"; shift 2 ;;
    --runs)       need "$@"; RUNS="$2"; shift 2 ;;
    --out)        need "$@"; OUT="$2"; shift 2 ;;
    --g1-max)     need "$@"; G1_MAX="$2"; shift 2 ;;
    --orphan)     ORPHAN=1; shift ;;
    --keep-traces) KEEP=1; shift ;;
    -h|--help)    QUIET_EXIT=1; usage; exit 0 ;;
    *)            usage >&2; fatal 64 "unknown argument: $1" ;;
  esac
done

abspath() { python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

[ -d "$APP" ] || fatal 64 "--app is not a directory: $APP"
APP="$(abspath "$APP")"
[ -x "$APP/Contents/MacOS/MacDashboard" ] || fatal 64 "--app binary is not executable: $APP/Contents/MacOS/MacDashboard"
if [ -n "$BASELINE" ]; then
  [ -d "$BASELINE" ] || fatal 64 "--baseline is not a directory: $BASELINE"
  BASELINE="$(abspath "$BASELINE")"
  [ -x "$BASELINE/Contents/MacOS/MacDashboard" ] || fatal 64 "--baseline binary is not executable: $BASELINE/Contents/MacOS/MacDashboard"
fi
case "$RUNS" in ""|[1-7]) ;; *) fatal 64 "--runs must be 1-7" ;; esac
case "$G1_MAX" in *[!0-9.]*|"") fatal 64 "--g1-max must be a number" ;; esac

# scenario list -> work items
[ -n "$SCENARIOS" ] || SCENARIOS="G1,G2,G3,G4,G5,G6,G7,G9"
ITEMS=""
add_item() { case " $ITEMS " in *" $1 "*) ;; *) ITEMS="$ITEMS $1" ;; esac; }
for t in $(echo "$SCENARIOS" | tr ',' ' '); do   # "all" implies --orphan, whatever its position in the list
  case "$t" in all|ALL) ORPHAN=1 ;; esac
done
for t in $(echo "$SCENARIOS" | tr ',' ' '); do
  case "$t" in
    all|ALL)
      for s in G1 G2 G3 G4 G5 G5-top G6-page G6-table G6-hover G7 G8 G9; do add_item "$s"; done
      for p in $GP_PAGES; do add_item "GP-$p"; done ;;
    [Gg][Pp]:*)
      p="$(echo "${t#*:}" | tr 'A-Z' 'a-z')"
      case " $GP_PAGES " in *" $p "*) add_item "GP-$p" ;; *) fatal 64 "unknown page in $t" ;; esac ;;
    *)
      s="$(echo "$t" | tr 'a-z' 'A-Z')"
      case "$s" in
        G1|G2|G3|G4|G7|G9) add_item "$s" ;;
        G5) add_item G5; add_item G5-top ;;
        G6) add_item G6-page; add_item G6-table; add_item G6-hover ;;
        G8) [ "$ORPHAN" = 1 ] || fatal 64 "G8 needs --orphan"; add_item G8 ;;
        *) fatal 64 "unknown scenario: $t (G1..G9, GP:<page>, all)" ;;
      esac ;;
  esac
done

OUT_DEFAULT="$PERF/out/$(date +%Y%m%d-%H%M%S)"
OUT="$(abspath "${OUT:-$OUT_DEFAULT}")"
OUT_ROOT="$(abspath "$PERF/out")"
case "$OUT/" in "$OUT_ROOT"/?*) ;; *) fatal 64 "--out must be inside $OUT_ROOT (got $OUT)" ;; esac

# ---------------------------------------------------------------- preconditions (exit 65)
refuse() { fatal 65 "precondition refused: $*"; }

IOREG_ROOT="$(ioreg -n Root -d1 2>/dev/null || true)"
LOCK_RE='"IOConsoleLocked" *= *Yes'
if [[ "$IOREG_ROOT" =~ $LOCK_RE ]]; then refuse "the screen is locked — unlock it and run again"; fi

SCREEN="$(osascript -l JavaScript -e "ObjC.import('AppKit'); var f = \$.NSScreen.screens.objectAtIndex(0).frame; Math.round(f.size.width) + ' ' + Math.round(f.size.height)" 2>/dev/null || echo "0 0")"
read -r SW SH <<< "$SCREEN"
if [ "${SW:-0}" -lt 1280 ] || [ "${SH:-0}" -lt 800 ]; then refuse "main display is ${SW}x${SH} pt, need at least 1280x800"; fi

AX_ENABLED="$(osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null || echo false)"
[ "$AX_ENABLED" = "true" ] || refuse "Accessibility is not enabled for the terminal app (System Events refuses UI scripting)"

xcrun xctrace version >/dev/null 2>&1 || refuse "xcrun xctrace version failed"

# no other gate.sh: ignore this shell, its children and its ancestors (the wrapper that started it)
ANCESTORS=" "
a=$$
while [ -n "$a" ] && [ "$a" -gt 1 ]; do
  ANCESTORS="$ANCESTORS$a "
  a="$(ps -o ppid= -p "$a" 2>/dev/null | tr -d ' ')"
done
for p in $(pgrep -f 'tools/perf/gate\.sh' 2>/dev/null); do
  case "$ANCESTORS" in *" $p "*) continue ;; esac
  [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$$" ] && continue
  refuse "another gate.sh is running (pid $p)"
done

mkdir -p "$OUT" || fatal 70 "cannot create $OUT"
STARTED=1
G5_NOTE=""
# REDESIGN-BATTERY: G5 hovered the battery popover's rainbow «Details» capsule (`battery-details`), which no longer
# exists; the scenario is parked (definitions kept) until HARNESS-REDESIGN-RETARGET retargets it.
case " $ITEMS " in *" G5 "*|*" G5-top "*)
  ITEMS="$(for i in $ITEMS; do case "$i" in G5|G5-top) ;; *) echo -n " $i" ;; esac; done)"
  G5_NOTE="G5 parked: its target (battery-details) was removed in REDESIGN-BATTERY; retarget in HARNESS-REDESIGN-RETARGET"
  log "$G5_NOTE" ;;
esac
# Bench copies: own bundle id, so the gate never touches the real defaults domain (R11); removed on exit.
CAND_APP="$("$ROOT/tools/bench-app.sh" "$APP" "$OUT/apps/cand")" || fatal 70 "bench copy of --app failed"
[ -n "$BASELINE" ] && { BASE_APP="$("$ROOT/tools/bench-app.sh" "$BASELINE" "$OUT/apps/base")" || fatal 70 "bench copy of --baseline failed"; }
PIDS="$OUT/pids"; : > "$PIDS"
HOMEDIR="$OUT/home"
REAL_HOME="$(abspath "$HOMEDIR")"
REAL_LIB="$(abspath "$HOME/Library")"
case "$REAL_HOME/" in "$REAL_LIB"/*) refuse "bench home $REAL_HOME is inside $REAL_LIB" ;; esac

for f in summary.tsv report.md runs.tsv; do   # a reused --out keeps the previous invocation's tables
  [ -f "$OUT/$f" ] && mv "$OUT/$f" "$OUT/${f%.*}-$(date +%H%M%S).${f##*.}"
done
: > "$OUT/runs.tsv"; : > "$OUT/invalid.log"; : > "$OUT/gate.log"; : > "$OUT/errors.tsv"; : > "$OUT/error-runs.tsv"
"$PERF/power.sh" before "$OUT/power.log" "gate start" || refuse "power: need AC power and Low Power Mode off ($(tail -1 "$OUT/power.log"))"

# ---------------------------------------------------------------- helpers (compiled fresh every run)
BIN="$OUT/.bin"
mkdir -p "$BIN"
for h in drv hold; do
  swiftc -O "$PERF/$h.swift" -o "$BIN/$h" -module-cache-path "$BIN/modcache" >"$BIN/$h.build.log" 2>&1 \
    || fatal 70 "swiftc failed for $h.swift (see $BIN/$h.build.log)"
done
export BIN

# ---------------------------------------------------------------- defaults snapshot (D18, read-only)
snap_defaults() { defaults export "$BUNDLE_ID" "$1" >/dev/null 2>&1 || : > "$1"; }
snap_defaults "$OUT/defaults-before.plist"

# ---------------------------------------------------------------- app + UI primitives
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
mark_now() { perl -MTime::HiRes=time -e 'printf "%s %.3f\n", $ARGV[0], time' "$1" >> "$2"; }
mark_val() { awk -v k="$1" '$1==k && NF==2 {print $2; exit}' "$2"; }   # first unlabelled mark of kind k

ax() { osascript "$PERF/ui.applescript" "$PID" "$@" 2>&1; }
# AX misses (S6). The one retry after re-activating the app is ROBUSTNESS, not a cause fix: on the first night
# (2026-10-20) this app's AX tree listed 6 of 8 Home tiles while all 8 are drawn (cause open). A second miss writes
# diagnostics (ax_miss) and returns 1; attempt() then marks the scenario ERROR and the gate goes on.
# Never a coordinate fallback. The helpers log to stderr: ax_frame runs inside $(...), whose stdout is the result.
ax_reactivate() {   # kind value: frontmost again; a Home tile also gets a fresh Home press
  osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is '"$PID"') to true' >/dev/null 2>&1 || true
  sleep 1
  if [ "$1" = id ] && [[ "$2" == home-tile-* ]]; then
    log "re-pressing main-mode-mac before the retry of '$2'" >&2
    ax id main-mode-mac >/dev/null; sleep 2
  fi
  return 0
}
ax_miss() {   # label -> $CUR_PREFIX-axdiag/ {miss.txt ax-dump.txt winfo.txt screen.png display.txt}; never exits
  local d="${CUR_PREFIX:-$OUT/unknown}-axdiag" b="$PERF/out/night.noindex/.bin/brightness"
  rm -rf "$d"; mkdir -p "$d"
  echo "$1" > "$d/miss.txt"
  ax dump > "$d/ax-dump.txt"
  "$BIN/drv" winfo "$PID" > "$d/winfo.txt" 2>&1
  screencapture -x "$d/screen.png" > "$d/screencapture.err" 2>&1
  {
    echo "time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "app pid $PID alive: $(kill -0 "$PID" 2>/dev/null && echo yes || echo no)"
    echo "frontmost pid: $(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true' 2>&1)"
    if [ -x "$b" ]; then echo "brightness: $("$b" get 2>&1)"; else echo "brightness: n/a (no helper at $b)"; fi
    echo "session locked: $(ioreg -n Root -d1 | grep -q '"IOConsoleLocked" *= *Yes' && echo yes || echo no)"
    echo "HID idle s: $(ioreg -c IOHIDSystem -d 4 | awk '/"HIDIdleTime"/ {print int($NF/1000000000); exit}')"
    echo "display power (pmset -g powerstate IODisplayWrangler):"; pmset -g powerstate IODisplayWrangler 2>&1
    echo "display power (ioreg IODisplayWrangler):"
    ioreg -r -d 1 -n IODisplayWrangler 2>&1 | grep -E '"(CurrentPowerState|DevicePowerState)"' || echo "  not found"
    echo "display assertions:"; pmset -g assertions 2>&1 | grep -i 'display' || echo "  none"
  } > "$d/display.txt" 2>&1
  log "AX miss: $1 (diagnostics: $d)" >&2
}
ax_press() {   # kind value -> 0 pressed | 1 missed twice (diagnostics written)
  local out; out="$(ax "$1" "$2")"
  [ "$out" = "pressed" ] && return 0
  log "AX press missed for $1 '$2' (got: $out); re-activating, one retry" >&2
  ax_reactivate "$1" "$2"
  out="$(ax "$1" "$2")"
  [ "$out" = "pressed" ] && { log "AX press retry ok for $1 '$2'" >&2; return 0; }
  ax_miss "AX press failed for $1 '$2' after one retry (got: $out)"
  return 1
}

pin_window() {
  local out; out="$(ax pin)"
  [ "$out" = "pinned" ] || fatal 70 "window pin failed: $out"
  sleep 1
  local frame; frame="$("$BIN/drv" winfo "$PID" | python3 -I -c '
import re, sys
t = sys.stdin.read()
for m in re.finditer(r"Height = ([0-9.]+);\s*Width = ([0-9.]+);\s*X = (-?[0-9.]+);\s*Y = (-?[0-9.]+);\s*\}\s*(\d+)", t):
    h, w, x, y, layer = map(float, m.groups())
    if layer == 0 and abs(w - 1000) <= 2 and abs(h - 733) <= 2 and abs(x) <= 2 and abs(y - 29) <= 2:
        print("ok"); sys.exit(0)
print(" ".join(t.split())); sys.exit(1)')" || fatal 70 "window frame is not 1000x733 at (0,29): $frame"
}

is_frame() { [[ "$1" =~ ^-?[0-9]+\ -?[0-9]+\ [0-9]+\ [0-9]+$ ]]; }
ax_frame() {   # AXIdentifier -> "x y w h" (global points, top-left origin) | 1 after a miss and one retry (diagnostics written)
  local out; out="$(ax frame "$1")"
  if ! is_frame "$out"; then
    log "AX frame missed for '$1' (got: $out); re-activating, one retry" >&2
    ax_reactivate frame "$1"
    out="$(ax frame "$1")"
    is_frame "$out" || { ax_miss "AX frame failed for '$1' after one retry (got: $out)"; return 1; }
  fi
  echo "$out"
}

park_pointer() { "$BIN/hold" 1100 500 0.4 >/dev/null 2>&1; }   # drv move with 0 s is a no-op

launch_app() {   # app tag -> PID
  defaults delete "$BENCH_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Saved Application State/$BENCH_ID.savedState"
  CFFIXED_USER_HOME="$HOMEDIR" "$1/Contents/MacOS/MacDashboard" -appLanguage en -AppleLanguages "(en)" -ApplePersistenceIgnoreState YES >"$OUT/$2-app.log" 2>&1 &
  PID=$!
  track "$PID"; LS_DIRTY=1
  sleep 7
  kill -0 "$PID" 2>/dev/null || fatal 70 "app exited at launch (see $OUT/$2-app.log)"
  osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is '"$PID"') to true' >/dev/null 2>&1 || true
  sleep 1
  pin_window
}

stop_app() {
  [ -n "$PID" ] || return 0
  if [ "$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')" = "$$" ]; then
    kill "$PID" 2>/dev/null; sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
  fi
  wait "$PID" 2>/dev/null
  untrack "$PID"; PID=""
}

route_mac()    { ax_press id main-mode-mac || return 1; sleep 2; }
route_iphone() { ax_press id main-mode-iphone || return 1; sleep 2; ax_press id iphone-tile-0 || return 1; sleep 3; }
route_table()  { route_iphone || return 1; ax_press title 'Таблица|Table' || return 1; sleep 2; }
# History page (Home -> History tile), range All; the G4 sweep is centred on the chart's AX frame (D16).
route_hist() {
  route_mac || return 1; ax_press id home-tile-history || return 1; sleep 2
  "$BIN/drv" scroll 500 450 3 -15 >/dev/null 2>&1; sleep 1; ax_press id history-range-all || return 1; sleep 3
  local fr fx fy fw fh; fr="$(ax_frame history-chart)" || return 1; read -r fx fy fw fh <<< "$fr"
  HIST_SWEEP_X=$((fx + fw / 2)); HIST_SWEEP_Y=$((fy + fh / 2))
  { [ "$HIST_SWEEP_X" -ge 150 ] && [ "$HIST_SWEEP_X" -le 850 ] && [ "$HIST_SWEEP_Y" -ge 29 ] && [ "$HIST_SWEEP_Y" -le 762 ]; } \
    || fatal 70 "G4: history chart centre ($HIST_SWEEP_X,$HIST_SWEEP_Y) is outside the pinned window"
  export HIST_SWEEP_X HIST_SWEEP_Y
}
# Battery page; G5 holds on the rainbow "Details" capsule and on the same tile 300 pt to its left (D17).
route_battery() {
  route_mac || return 1; ax_press id home-tile-battery || return 1; sleep 2
  local fr fx fy fw fh; fr="$(ax_frame battery-details)" || return 1; read -r fx fy fw fh <<< "$fr"
  local dx=$((fx + fw / 2)) dy=$((fy + fh / 2)) cx=$((fx - 300))
  [ "$cx" -ge 40 ] || fatal 70 "G5: control spot x=$cx is outside the window"
  G5_SPOTS="ctrl:$cx:$dy details:$dx:$dy"; export G5_SPOTS
}
route_system() { route_mac || return 1; ax_press id home-tile-system || return 1; sleep 2; }
route_page()   { route_mac || return 1; ax_press id "home-tile-$1" || return 1; sleep 2; }

topsamp() {   # N pid -> "S <epoch>" per sample, "P <epoch> <pid> <cmd> <cpu>" for the app and WindowServer
  # exec: always called as a background job, so the tracked PID is perl itself (it forwards TERM to top)
  exec perl -e '
    use Time::HiRes qw(time); $| = 1;
    my ($n, $app) = @ARGV;
    my $pid = open(my $p, "-|", "top", "-l", $n, "-s", "1", "-stats", "pid,command,cpu") or die "top: $!";
    $SIG{TERM} = sub { kill "TERM", $pid; exit 0 };
    my $t = 0;
    while (<$p>) {
      if (/^Processes:/) { $t = time; printf "S %.3f\n", $t; next }
      if (/^\s*(\d+)\s+(\S+)\s+([0-9.]+)\s*$/ && ($1 == $app || $2 eq "WindowServer")) { printf "P %.3f %d %s %s\n", $t, $1, $2, $3 }
    }' "$@"
}

# ---------------------------------------------------------------- per-item definitions
# CPU page (REDESIGN-CPU): Home -> CPU tile.
route_cpu() { route_mac || return 1; ax_press id home-tile-cpu || return 1; sleep 2; }

# Sets S_ROUTE S_PRE (extra wait after the route, s) S_SECS (record length) S_SCEN S_ARGS S_TABLES S_INSTR.
TP_INSTR=(--instrument 'Time Profiler' --instrument Hitches)
CA_INSTR=(--instrument 'Core Animation Commits' --instrument 'Core Animation Server' --instrument 'Time Profiler')
define_item() {
  S_ROUTE=mac; S_PRE=3; S_ARGS=""; S_TABLES="time-profile hitches"; S_INSTR=("${TP_INSTR[@]}"); S_ORPHAN=0
  case "$1" in
    G1) S_PRE=22 ;;
    G9) S_ROUTE=cpu; S_PRE=22 ;;
    G5-top) S_ROUTE=battery; S_PRE=22 ;;
    G2) S_PRE=30; S_SECS=20; S_SCEN=scen-idle.sh; S_ARGS=15
        S_TABLES="coreanimation-commit-interval coreanimation-server-interval"; S_INSTR=("${CA_INSTR[@]}") ;;
    G3) S_PRE=5; S_SECS=22; S_SCEN=scen-idle-bottom.sh ;;
    G8) S_ROUTE=system; S_PRE=5; S_SECS=22; S_SCEN=scen-idle-bottom.sh; S_ORPHAN=1 ;;
    G4) S_ROUTE=hist; S_PRE=0; S_SECS=22; S_SCEN=scen-hist-all.sh ;;
    G5) S_ROUTE=battery; S_PRE=22; S_SECS=22; S_SCEN=scen-rainbow.sh
        S_TABLES="coreanimation-commit-interval coreanimation-server-interval"
        S_INSTR=(--instrument 'Time Profiler' --instrument Hitches --instrument 'Core Animation Commits' --instrument 'Core Animation Server') ;;
    G6-page)  S_ROUTE=iphone; S_PRE=2; S_SECS=17; S_SCEN=scen-page.sh ;;
    G6-table) S_ROUTE=table;  S_PRE=2; S_SECS=24; S_SCEN=scen-table.sh ;;
    G6-hover) S_ROUTE=iphone; S_PRE=2; S_SECS=20; S_SCEN=scen-hover.sh ;;
    G7) S_SECS=21; S_SCEN=scen-mac-scroll.sh ;;
    GP-*) S_ROUTE="page:${1#GP-}"; S_SECS=21; S_SCEN=scen-mac-scroll.sh ;;
  esac
}

do_route() {
  case "$S_ROUTE" in
    mac) route_mac ;; hist) route_hist ;; iphone) route_iphone ;; table) route_table ;; cpu) route_cpu ;;
    battery) route_battery ;; system) route_system ;; page:*) route_page "${S_ROUTE#page:}" ;;
  esac
}

# ---------------------------------------------------------------- one measured run
# attempt ITEM ARM RUN APP -> 0 valid (metrics appended to runs.tsv) | 1 invalid (power changed; nothing recorded) | 2 ERROR (AX miss after one retry; nothing recorded, line in errors.tsv)
attempt() {
  local item=$1 arm=$2 run=$3 app=$4
  local tag="$item-$arm$run" prefix="$OUT/$item-$arm$run"
  local buf="$prefix-metrics.tmp"
  CUR_PREFIX="$prefix"; rm -rf "$prefix-axdiag"
  : > "$buf"; : > "$prefix-drv.txt"; : > "$prefix-analysis.txt"
  log "$tag: start ($app)"
  local pstart; pstart="$(date +%s)"
  if ! "$PERF/power.sh" before "$OUT/power.log" "$tag before"; then
    echo "$tag: power check failed before the run" >> "$OUT/invalid.log"; rm -f "$buf"; return 1
  fi
  local fixture_args=("$HOMEDIR"); [ "$item" = "G8" ] && fixture_args+=(--orphan)
  python3 -I "$PERF/mkfixture.py" "${fixture_args[@]}" >"$prefix-fixture.log" 2>&1 \
    || fatal 70 "mkfixture failed (see $prefix-fixture.log)"

  define_item "$item"
  launch_app "$app" "$tag"
  if ! do_route; then   # S6: an AX element still missing after one retry -> this scenario is ERROR, the gate goes on
    stop_app
    local why; why="$(head -1 "$prefix-axdiag/miss.txt" 2>/dev/null)"
    printf '%s\t%s\t%s\t%s\n' "$item" "$tag" "${why:-route failed}" "$prefix-axdiag" >> "$OUT/errors.tsv"
    log "$tag: ERROR (${why:-route failed})"
    rm -f "$buf"; cleanup_run "$prefix"; return 2
  fi
  if [ "$S_ORPHAN" = 1 ]; then   # D18: the Autostart card exists only after the report pass
    local waited=0
    until [ "$(ax exists autostart-outdated)" = present ]; do
      waited=$((waited + 2))
      [ "$waited" -ge 60 ] && fatal 70 "G8: autostart-outdated did not appear on the System page within 60 s (bench orphan not shown)"
      sleep 2
    done
    echo "orphan_visible 1" >> "$buf"
  fi
  park_pointer
  sleep "$S_PRE"

  local pend
  if [ "$item" = "G1" ] || [ "$item" = "G9" ]; then
    mark_now t0 "$prefix-drv.txt"
    topsamp 41 "$PID" > "$prefix-top.txt" & local tp=$!; track "$tp"
    wait "$tp"; untrack "$tp"
    mark_now t1 "$prefix-drv.txt"
  elif [ "$item" = "G5-top" ]; then
    topsamp 20 "$PID" > "$prefix-top.txt" & local tp=$!; track "$tp"
    sleep 1
    bash "$PERF/scen-rainbow.sh" > "$prefix-drv.txt" 2>&1 & local sp=$!; track "$sp"
    wait "$sp"; untrack "$sp"
    wait "$tp"; untrack "$tp"
  else
    rm -rf "$prefix.trace"
    xcrun xctrace record "${S_INSTR[@]}" --attach "$PID" --time-limit "${S_SECS}s" --output "$prefix.trace" --no-prompt >"$prefix-rec.txt" 2>&1 &
    local xp=$!; track "$xp"
    topsamp $((S_SECS + 1)) "$PID" > "$prefix-top.txt" & local tp=$!; track "$tp"
    bash -c 'sleep 3; exec bash "$@"' _ "$PERF/$S_SCEN" $S_ARGS > "$prefix-drv.txt" 2>&1 & local sp=$!; track "$sp"
    wait "$xp"; untrack "$xp"
    wait "$tp"; untrack "$tp"
    wait "$sp"; untrack "$sp"
  fi
  pend="$(date +%s)"
  PID_LAST="$PID"
  stop_app

  local valid=1
  "$PERF/power.sh" after "$OUT/power.log" "$tag after" || valid=0
  "$PERF/power.sh" between "$pstart" "$pend" 2>>"$OUT/power.log" || valid=0
  if [ "$valid" = 0 ]; then
    echo "$tag: power changed during the run (after-check or Using Batt in [$pstart,$pend])" >> "$OUT/invalid.log"
    log "$tag: INVALID (power)"
    rm -f "$buf"; cleanup_run "$prefix"; return 1
  fi

  analyze_item "$item" "$prefix" "$buf"
  awk -v s="$item" -v a="$arm" -v r="$run" '{print s "\t" a "\t" r "\t" $1 "\t" $2}' "$buf" >> "$OUT/runs.tsv"
  rm -f "$buf"
  cleanup_run "$prefix"
  log "$tag: ok"
  return 0
}

cleanup_run() {
  local prefix="${1:?}"
  [ "$KEEP" = 1 ] && return 0
  rm -rf "$prefix.trace" "$prefix-toc.xml" "$prefix-time-profile.xml" "$prefix-hitches.xml" \
         "$prefix-coreanimation-commit-interval.xml" "$prefix-coreanimation-server-interval.xml"
}

export_tables() {
  local prefix=$1 t
  [ -d "$prefix.trace" ] || fatal 70 "xctrace produced no trace (see $prefix-rec.txt: $(head -c 300 "$prefix-rec.txt" | tr '\n' ' '))"
  xcrun xctrace export --input "$prefix.trace" --toc > "$prefix-toc.xml" 2>"$prefix-export.err" || fatal 70 "xctrace export --toc failed (see $prefix-export.err)"
  for t in $S_TABLES; do
    xcrun xctrace export --input "$prefix.trace" --xpath "/trace-toc/run/data/table[@schema=\"$t\"]" > "$prefix-$t.xml" 2>>"$prefix-export.err" \
      || fatal 70 "xctrace export $t failed (see $prefix-export.err)"
  done
}

# run an analyze.py command: output to the analysis file, METRIC lines (with optional name prefix) to the buffer
az() {   # buf prefix-for-names analysis-file -- args...
  local buf=$1 pre=$2 an=$3; shift 4
  local out; out="$(python3 -I "$PERF/analyze.py" "$@" 2>&1)" || fatal 70 "analyze.py $* failed: $out"
  echo "$out" >> "$an"
  echo "$out" | sed -n "s/^METRIC /$pre/p" >> "$buf"
}

analyze_item() {
  local item=$1 prefix=$2 buf=$3 an="$prefix-analysis.txt"
  local t0 t1
  case "$item" in
    G1|G9) az "$buf" "" "$an" -- top "$prefix-top.txt" "$PID_LAST" ;;
    G5-top)
      local label l0 l1
      while read -r label l0; do
        l1="$(awk -v L="$label" '$1=="t1" && $2==L && NF==3 {print $3; exit}' "$prefix-drv.txt")"
        [ -n "$l1" ] || fatal 70 "G5-top: no t1 mark for $label"
        az "$buf.top" "" "$an" -- top "$prefix-top.txt" "$PID_LAST" "$l0" "$l1"
        grep -E '^(app_pct|ws_pct) ' "$buf.top" | sed "s/^/$label./" >> "$buf"; rm -f "$buf.top"
      done < <(awk '$1=="t0" && NF==3 {print $2, $3}' "$prefix-drv.txt") ;;
    G2)
      export_tables "$prefix"
      az "$buf" "" "$an" -- ca "$prefix" ;;
    G5)
      export_tables "$prefix"
      az "$buf" "" "$an" -- ca "$prefix" ;;
    G3|G8)
      export_tables "$prefix"
      t0="$(mark_val t0 "$prefix-drv.txt")"
      [ -n "$t0" ] || fatal 70 "$item: no t0 mark in $prefix-drv.txt"
      az "$buf" "" "$an" -- tp "$prefix" --win $G3_WIN_LO $G3_WIN_HI
      az "$buf.top" "" "$an" -- top "$prefix-top.txt" "$PID_LAST" "$(awk -v a="$t0" -v o="$G3_WIN_LO" 'BEGIN{printf "%.3f", a+o}')" "$(awk -v a="$t0" -v o="$G3_WIN_HI" 'BEGIN{printf "%.3f", a+o}')"
      grep -E '^(app_pct|ws_pct) ' "$buf.top" >> "$buf"; rm -f "$buf.top" ;;
    G4)
      export_tables "$prefix"
      az "$buf" "" "$an" -- tp "$prefix"
      t0="$(mark_val t0 "$prefix-drv.txt")"; t1="$(mark_val t1 "$prefix-drv.txt")"
      az "$buf.top" "" "$an" -- top "$prefix-top.txt" "$PID_LAST" "$t0" "$t1"
      grep -E '^(app_pct|ws_pct) ' "$buf.top" >> "$buf"; rm -f "$buf.top" ;;
    G6-*)
      export_tables "$prefix"
      az "$buf" "" "$an" -- tp "$prefix" rgba64_shade_conic ;;
    G7|GP-*)
      export_tables "$prefix"
      az "$buf" "" "$an" -- tp "$prefix" ;;
  esac
}
# G3/G8 post-scroll window, seconds after t0. t0 is written 2 s after the scroll ends, so [0, 7) is the
# "2-9 s after the scroll ends" of R5 (see README: the table's [t0+2, t0+9) would be 4-11 s after it).
G3_WIN_LO=0; G3_WIN_HI=7

# the sampler lines carry the app pid; remember it past stop_app
PID_LAST=""

# ---------------------------------------------------------------- run loop
default_runs() { echo "${RUNS:-3}"; }

{
  echo "# Perf gate report"
  echo
  echo "- date: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- candidate: \`$APP\`"
  echo "- baseline: \`${BASELINE:-none}\`"
  echo "- scenarios: $(echo $ITEMS)"
  echo "- run directory: \`$OUT\`"
  echo "- macOS: $(sw_vers -productVersion)"
  echo
} > "$OUT/report.md"

for item in $ITEMS; do
  n="$(default_runs "$item")"
  r=1; ERRORED=0
  while [ "$r" -le "$n" ] && [ "$INVALID" = 0 ] && [ "$ERRORED" = 0 ]; do
    arms="cand"; [ -n "$BASELINE" ] && arms="cand base"
    for arm in $arms; do
      app="$CAND_APP"; [ "$arm" = "base" ] && app="$BASE_APP"
      attempt "$item" "$arm" "$r" "$app"; arc=$?
      if [ "$arc" = 1 ]; then
        log "$item-$arm$r: re-recording once"
        sleep 5
        attempt "$item" "$arm" "$r" "$app"; arc=$?
        if [ "$arc" = 1 ]; then INVALID=1; break; fi
      fi
      if [ "$arc" = 2 ]; then ERRORED=1; break; fi
    done
    r=$((r + 1))
  done
  if [ "$ERRORED" = 1 ]; then   # S6: no verdict on a scenario stopped mid-way; its recorded runs move aside
    NERROR=$((NERROR + 1))
    awk -F'\t' -v s="$item" '$1==s' "$OUT/runs.tsv" >> "$OUT/error-runs.tsv"
    awk -F'\t' -v s="$item" '$1!=s' "$OUT/runs.tsv" > "$OUT/runs.tsv.new" && mv "$OUT/runs.tsv.new" "$OUT/runs.tsv"
    log "$item: ERROR, remaining runs skipped (see errors.tsv)"
  fi
  [ "$INVALID" = 1 ] && break
done

# ---------------------------------------------------------------- defaults compare, verdict, report
snap_defaults "$OUT/defaults-after.plist"
DEFAULTS_CHANGED=0
DEFAULTS_DIFF=""
if ! cmp -s "$OUT/defaults-before.plist" "$OUT/defaults-after.plist"; then
  DEFAULTS_CHANGED=1
  DEFAULTS_DIFF="$(diff <(plutil -p "$OUT/defaults-before.plist" 2>&1) <(plutil -p "$OUT/defaults-after.plist" 2>&1))"
fi

if [ -s "$OUT/runs.tsv" ]; then
  COUNTS="$(python3 -I "$PERF/analyze.py" verdict "$OUT" --g1-max "$G1_MAX" | sed -n 's/^COUNTS //p')" || fatal 70 "analyze.py verdict failed"
  NPASS="$(sed -n 's/.*pass=\([0-9]*\).*/\1/p' <<< "$COUNTS")"
  NFAIL="$(sed -n 's/.*fail=\([0-9]*\).*/\1/p' <<< "$COUNTS")"
  NNOISY="$(sed -n 's/.*noisy=\([0-9]*\).*/\1/p' <<< "$COUNTS")"
fi
{
  echo "## Power"
  echo
  echo '```'
  cat "$OUT/power.log"
  echo '```'
  echo
  if [ -s "$OUT/invalid.log" ]; then
    echo "INVALID attempts (numbers discarded, never averaged in):"
    echo
    sed 's/^/- /' "$OUT/invalid.log"
    echo
  fi
  if [ -s "$OUT/errors.tsv" ]; then
    echo "ERROR scenarios (an AX element was still missing after one retry; not measured, no verdict; their earlier runs are in error-runs.tsv):"
    echo
    awk -F'\t' '{print "- " $1 " (" $2 "): " $3 " — diagnostics: `" $4 "`"}' "$OUT/errors.tsv"
    echo
  fi
  if [ -n "$G5_NOTE" ]; then echo "$G5_NOTE"; echo; fi
  echo "## Defaults domain \`$BUNDLE_ID\`"
  echo
  if [ "$DEFAULTS_CHANGED" = 1 ]; then
    echo "CHANGED during the run (the gate never writes it; another process did):"
    echo
    echo '```'
    echo "$DEFAULTS_DIFF"
    echo '```'
  else
    echo "unchanged"
  fi
  echo
} >> "$OUT/report.md"

FINAL=0
[ "${NFAIL:-0}" -gt 0 ] && FINAL=1
[ "$NERROR" -gt 0 ] && FINAL=5
[ "$DEFAULTS_CHANGED" = 1 ] && FINAL=4
[ "$INVALID" = 1 ] && FINAL=3
if [ "$DEFAULTS_CHANGED" = 1 ]; then
  echo "gate: the defaults domain $BUNDLE_ID changed during the run:" >&2
  echo "$DEFAULTS_DIFF" >&2
fi
echo "report: $OUT/report.md"
echo "summary: $OUT/summary.tsv"
exit "$FINAL"
