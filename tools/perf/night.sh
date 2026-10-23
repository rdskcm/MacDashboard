#!/bin/bash
# tools/perf/night.sh — night runner: builds origin/main while the Mac is idle and runs the perf gate on it.
#
# Usage:
#   tools/perf/night.sh --check [--dry-run]      LaunchAgent entry (every 60 s): start tonight's run if due; --dry-run prints the decision only
#   tools/perf/night.sh --run [--now] [--keep-dark] [--scenarios LIST] [--runs N]
#                                                the run (normally opened in Terminal by --check); --now skips the time window
#                                                and idle checks (a "Mac idle" run started by hand); --keep-dark leaves the
#                                                display dimmed after the run (the user restores it); LIST/N pass to gate.sh
#                                                (default all / 3); a run with --scenarios other than all is marked "partial"
#   tools/perf/night.sh --install | --uninstall  add / remove the user LaunchAgent com.rdskcm.macdashboard.night
#   tools/perf/night.sh --restore-brightness     put back a brightness value a crashed run left saved
# Exit: 0 (also for skips — the reason is in the report) | 64 usage | 70 runtime error
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PERF="$ROOT/tools/perf"
NIGHT="$PERF/out/night.noindex"
DATE="$(date +%Y%m%d)"
LABEL="com.rdskcm.macdashboard.night"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
fatal() { echo "night.sh: $2" >&2; exit "$1"; }

# ---------------------------------------------------------------- argument parsing
MODE=""; DRY=0; NOW=0; KEEP_DARK=0; LIST=""; N=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--run|--install|--uninstall|--restore-brightness) MODE="$1"; shift ;;
    --dry-run) DRY=1; shift ;;
    --now) NOW=1; shift ;;
    --keep-dark) KEEP_DARK=1; shift ;;
    --scenarios) [ $# -ge 2 ] || fatal 64 "--scenarios needs a value"; LIST="$2"; shift 2 ;;
    --runs) [ $# -ge 2 ] || fatal 64 "--runs needs a value"; N="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fatal 64 "unknown argument: $1" ;;
  esac
done
[ -n "$MODE" ] || { usage >&2; exit 64; }
[ "$DRY" = 0 ] || [ "$MODE" = "--check" ] || fatal 64 "--dry-run only with --check"
{ [ "$NOW" = 0 ] && [ "$KEEP_DARK" = 0 ] && [ -z "$LIST" ] && [ -z "$N" ]; } || [ "$MODE" = "--run" ] \
  || fatal 64 "--now/--keep-dark/--scenarios/--runs only with --run"

mkdir -p "$NIGHT/builds" "$NIGHT/runs" "$NIGHT/reports" "$NIGHT/state" "$NIGHT/.bin" || fatal 70 "cannot create $NIGHT"
# first use only; tmutil can take ~10 s here, so it runs detached and never delays --check
if [ ! -e "$NIGHT/state/.excluded" ]; then
  touch "$NIGHT/state/.excluded"
  (tmutil addexclusion "$NIGHT" >/dev/null 2>&1 &)
fi

# ---------------------------------------------------------------- shared checks
power_ok() { "$PERF/power.sh" before "$NIGHT/state/power.log" night >/dev/null 2>&1; }
unlocked() { local r; r="$(ioreg -n Root -d1)"; ! grep -q '"IOConsoleLocked" *= *Yes' <<< "$r"; }
idle_secs() { ioreg -c IOHIDSystem -d 4 | awk '/"HIDIdleTime"/ {print int($NF/1000000000); exit}'; }
idle_threshold() {
  local d t=600
  d="$(pmset -g | awk '$1=="displaysleep"{print $2; exit}')"
  if [ "${d:-0}" -gt 0 ] && [ $((d * 60 - 120)) -lt 600 ]; then
    t=$((d * 60 - 120)); [ "$t" -lt 60 ] && t=60
  fi
  echo "$t"
}
busy() {   # another night run or gate, excluding this shell and its ancestors/children (as gate.sh)
  local anc=" " a=$$ p
  while [ -n "$a" ] && [ "$a" -gt 1 ]; do
    anc="$anc$a "
    a="$(ps -o ppid= -p "$a" 2>/dev/null | tr -d ' ')"
  done
  for p in $(pgrep -f 'tools/perf/(night\.sh --run|gate\.sh)' 2>/dev/null); do
    case "$anc" in *" $p "*) continue ;; esac
    [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$$" ] && continue
    return 0
  done
  return 1
}
brightness_bin() {
  local bin="$NIGHT/.bin/brightness"
  if [ ! -x "$bin" ] || [ "$PERF/brightness.swift" -nt "$bin" ]; then
    swiftc -O "$PERF/brightness.swift" -o "$bin" >"$NIGHT/.bin/brightness-build.log" 2>&1 || return 1
  fi
  return 0
}
REPORTED=0
write_report() {
  printf '%s\n' "$@" > "$NIGHT/reports/$DATE.md"
  cp "$NIGHT/reports/$DATE.md" "$NIGHT/latest.md"
  REPORTED=1
}
log() { [ "$DRY" = 1 ] || echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$NIGHT/agent.log"; }

# Restore the saved brightness; prints a note. Returns 0 when nothing is saved or the restore worked.
BR_NOTE=""
restore_brightness() {
  local f="$NIGHT/state/brightness-saved" v out
  [ -f "$f" ] || return 0
  v="$(awk 'NR==1{print $1}' "$f")"
  if brightness_bin && out="$("$NIGHT/.bin/brightness" set "$v" 2>&1)"; then
    rm -f "$f"; BR_NOTE="$out"; return 0
  fi
  BR_NOTE="restore of $v FAILED (${out:-no binary}); value kept in $f, run night.sh --restore-brightness"
  return 1
}

# ---------------------------------------------------------------- --restore-brightness
if [ "$MODE" = "--restore-brightness" ]; then
  [ -f "$NIGHT/state/brightness-saved" ] || { echo "no saved brightness"; exit 0; }
  if restore_brightness; then echo "restored: $BR_NOTE"; exit 0; fi
  echo "$BR_NOTE" >&2; exit 70
fi

# ---------------------------------------------------------------- --install / --uninstall
if [ "$MODE" = "--install" ]; then
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$PERF/night.sh</string>
    <string>--check</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$NIGHT/agent.log</string>
  <key>StandardErrorPath</key><string>$NIGHT/agent.log</string>
</dict>
</plist>
PL
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST" || fatal 70 "launchctl bootstrap failed"
  echo "installed: checks every 60 s, starts between 00:00 and 03:00 when the Mac is idle; report: $NIGHT/latest.md"
  exit 0
fi
if [ "$MODE" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  rm -f "$PLIST"
  echo "uninstalled $LABEL"
  exit 0
fi

# ---------------------------------------------------------------- --check
if [ "$MODE" = "--check" ]; then
  decide() { echo "$*"; log "$*"; }
  if [ -f "$NIGHT/state/brightness-saved" ] && ! busy; then
    if [ "$DRY" = 1 ]; then echo "would restore the brightness a crashed run left saved"
    else restore_brightness; decide "restored saved brightness: $BR_NOTE"; fi
  fi
  H="$(date +%H)"; H=$((10#$H))
  if [ "$H" -ge 0 ] && [ "$H" -lt 3 ]; then
    :
  else
    if [ "$H" -ge 3 ] && [ "$H" -lt 12 ] && [ ! -f "$NIGHT/reports/$DATE.md" ]; then
      if [ -f "$NIGHT/runs/$DATE/started" ]; then
        V="NIGHT $DATE: INTERRUPTED — the run started at $(cat "$NIGHT/runs/$DATE/started") did not finish (restart, crash or interrupted)"
      else
        R="$(sed 's/^[0-9:]* //' "$NIGHT/state/last-skip-$DATE" 2>/dev/null)"
        V="NIGHT $DATE: SKIPPED — ${R:-the Mac was asleep or never idle between 00:00 and 03:00}"
      fi
      if [ "$DRY" = 1 ]; then echo "would write report: $V"
      else write_report "$V"; decide "report: $V"; fi
    else
      decide "outside window (hour $H): nothing to do"
    fi
    exit 0
  fi
  if [ -f "$NIGHT/runs/$DATE/started" ]; then decide "run already started tonight"; exit 0; fi
  skip() {
    [ "$DRY" = 1 ] || echo "$(date +%H:%M) $1" > "$NIGHT/state/last-skip-$DATE"
    decide "not starting: $1"; exit 0
  }
  power_ok || skip "on battery or Low Power Mode on"
  unlocked || skip "screen locked"
  IS="$(idle_secs)"; T="$(idle_threshold)"
  [ "${IS:-0}" -ge "$T" ] || skip "not idle: ${IS:-0} s < $T s"
  busy && skip "another gate or night run is running"
  if [ "$DRY" = 1 ]; then echo "would start tonight's run (idle ${IS} s >= $T s)"; exit 0; fi
  mkdir -p "$NIGHT/runs/$DATE"; date '+%H:%M' > "$NIGHT/runs/$DATE/started"
  decide "starting run in Terminal (idle $IS s >= $T s)"
  open -a Terminal "$PERF/night.command"
  exit 0
fi

# ---------------------------------------------------------------- --run
mkdir -p "$NIGHT/runs/$DATE"
[ "$NOW" = 1 ] && date '+%H:%M' > "$NIGHT/runs/$DATE/started"
START_EPOCH="$(date +%s)"; START_HM="$(date +%H:%M)"
SRC=""; SIGNAME=""; FINISHED=0
LINES=(); CAF=""; CAF_SEEN="no"
BR_LINE="brightness: not attempted"

finish() {
  local rc=$?
  [ "$FINISHED" = 0 ] || return; FINISHED=1
  if [ -n "$SRC" ]; then rm -rf "$SRC"; fi
  if [ -f "$NIGHT/state/brightness-saved" ] && [ "$KEEP_DARK" = 1 ]; then
    rm -f "$NIGHT/state/brightness-saved"; BR_LINE="$BR_LINE -> left dimmed (--keep-dark)"
  elif [ -f "$NIGHT/state/brightness-saved" ]; then
    if restore_brightness; then BR_LINE="$BR_LINE -> restored ($BR_NOTE)"
    else BR_LINE="$BR_LINE; $BR_NOTE"; fi
  fi
  if [ "$REPORTED" = 0 ]; then
    write_report "NIGHT $DATE: INTERRUPTED — ${SIGNAME:-exit $rc} before the report was written" "$BR_LINE"
  fi
  [ -z "$CAF" ] || kill "$CAF" 2>/dev/null
  osascript -e 'tell application "Terminal" to activate' >/dev/null 2>&1 || true
}
trap_sig() { SIGNAME="$1"; exit 70; }

# 1. preconditions
if ! power_ok; then
  write_report "NIGHT $DATE: SKIPPED — on battery or Low Power Mode on ($(tail -1 "$NIGHT/state/power.log"))"; exit 0
fi
if ! unlocked; then write_report "NIGHT $DATE: SKIPPED — screen locked"; exit 0; fi
IDLE0="$(idle_secs)"; THR="$(idle_threshold)"

# 2. keep-awake
caffeinate -d -i -s -w $$ &
CAF=$!
sleep 1
ASSERTS="$(pmset -g assertions)"   # captured first: grep -q on a pipe would SIGPIPE pmset under pipefail
if grep -qE "pid $CAF\(caffeinate\).*PreventUserIdleDisplaySleep" <<< "$ASSERTS"; then CAF_SEEN="yes"
else write_report "NIGHT $DATE: ERROR — keep-awake assertion not found"; kill "$CAF" 2>/dev/null; exit 70; fi
caffeinate -u -t 2

# 3. trap
trap finish EXIT
trap 'trap_sig INT' INT
trap 'trap_sig TERM' TERM
trap 'trap_sig HUP' HUP

# 4. brightness
if brightness_bin && B0OUT="$("$NIGHT/.bin/brightness" get 2>&1)"; then
  B0="${B0OUT%% *}"; BMETHOD="${B0OUT#* }"
  echo "$B0 $BMETHOD $(date '+%Y-%m-%d %H:%M')" > "$NIGHT/state/brightness-saved"
  if SETOUT="$("$NIGHT/.bin/brightness" set 0 2>&1)"; then
    BR_LINE="brightness: $B0 -> 0.000 ($BMETHOD)"
  else
    BR_LINE="brightness: not settable: $SETOUT"
    rm -f "$NIGHT/state/brightness-saved"
  fi
else
  BR_LINE="brightness: not settable: ${B0OUT:-brightness helper did not compile (see .bin/brightness-build.log)}"
fi

# 5. candidate
OFFLINE=""
GIT_TERMINAL_PROMPT=0 git -C "$ROOT" -c core.sshCommand="ssh -o BatchMode=yes" fetch --quiet origin main >/dev/null 2>&1 || OFFLINE="offline: local origin/main"
SHA="$(git -C "$ROOT" rev-parse --short=10 origin/main)" || { write_report "NIGHT $DATE: ERROR — cannot resolve origin/main"; exit 70; }
if [ -f "$NIGHT/state/last-measured-sha" ] && [ "$(awk '{print $1}' "$NIGHT/state/last-measured-sha")" = "$SHA" ]; then
  write_report "NIGHT $DATE: SKIPPED — main unchanged since $(awk '{print $2}' "$NIGHT/state/last-measured-sha") ($SHA)"; exit 0
fi
if [ ! -f "$NIGHT/builds/$SHA/build.ok" ]; then
  SRC="$(mktemp -d "$NIGHT/src.XXXXXX")"
  git -C "$ROOT" archive --format=tar origin/main | tar -x -C "$SRC"
  if ! (cd "$SRC" && ./build_app.sh) > "$NIGHT/runs/$DATE/build.log" 2>&1; then
    write_report "NIGHT $DATE: ERROR — build of $SHA failed, see runs/$DATE/build.log"; exit 70
  fi
  rm -rf "$NIGHT/builds/$SHA"
  "$ROOT/tools/bench-app.sh" "$SRC/dist.noindex/MacDashboard.app" "$NIGHT/builds/$SHA" >> "$NIGHT/runs/$DATE/build.log" 2>&1 \
    || { write_report "NIGHT $DATE: ERROR — bench copy of $SHA failed, see runs/$DATE/build.log"; exit 70; }
  echo "$SHA $(date '+%Y-%m-%d %H:%M')" > "$NIGHT/builds/$SHA/build.ok"
  rm -rf "$SRC"; SRC=""
fi

# 6. baseline
BASE=""; BASE_SHA=""
while IFS= read -r d; do   # one path per line: the project path contains spaces (S6)
  d="${d%/}"
  [ "$(basename "$d")" = "$SHA" ] && continue
  [ -f "$d/build.ok" ] || continue
  BASE="$d/MacDashboard.app"; BASE_SHA="$(basename "$d")"; break
done < <(ls -1dt "$NIGHT"/builds/*/ 2>/dev/null)

# 7. gate
GOUT="$PERF/out/night-$DATE"
[ ! -e "$GOUT" ] || GOUT="$GOUT-$(date +%H%M%S)"
"$PERF/gate.sh" --app "$NIGHT/builds/$SHA/MacDashboard.app" ${BASE:+--baseline "$BASE"} \
  --scenarios "${LIST:-all}" --runs "${N:-3}" --out "$GOUT" > "$NIGHT/runs/$DATE/gate.out" 2>&1
GRC=$?
GLINE="$(grep '^GATE:' "$NIGHT/runs/$DATE/gate.out" | tail -1)"

# 8. bookkeeping
PRUNE_NOTE=""
# Prune only after a successful full measured run (S6): a failed or partial run keeps every build, and a run that
# found no baseline while another finished build exists keeps them too (that would be a selection bug, not a first night).
if { [ "$GRC" = 0 ] || [ "$GRC" = 1 ]; } && [ "${LIST:-all}" = "all" ]; then
  echo "$SHA $(date '+%Y-%m-%d')" > "$NIGHT/state/last-measured-sha"
  PRUNE_OK=1
  if [ -z "$BASE_SHA" ]; then
    for d in "$NIGHT"/builds/*/; do
      d="${d%/}"
      [ "$(basename "$d")" != "$SHA" ] && [ -f "$d/build.ok" ] && PRUNE_OK=0
    done
  fi
  if [ "$PRUNE_OK" = 1 ]; then
    for d in "$NIGHT"/builds/*/; do
      d="${d%/}"; [ -d "$d" ] || continue
      case "$(basename "$d")" in "$SHA"|"$BASE_SHA") ;; *) rm -rf "$d" ;; esac
    done
  else
    PRUNE_NOTE="builds/ not pruned: no baseline was chosen although another finished build exists"
  fi
fi

# 9. report
NOISY="$(echo "$GLINE" | sed -n 's/.*noisy=\([0-9]*\).*/\1/p')"
NFAILG="$(echo "$GLINE" | sed -n 's/.*fail=\([0-9]*\).*/\1/p')"
NERR="$(echo "$GLINE" | sed -n 's/.*error=\([0-9]*\).*/\1/p')"
case "$GRC" in
  0) if [ "${NOISY:-0}" -gt 0 ]; then VERDICT="PASS, $NOISY noisy"; else VERDICT="PASS"; fi ;;
  1) VERDICT="FAIL" ;;
  3) VERDICT="INVALID" ;;
  4) VERDICT="DEFAULTS-CHANGED" ;;
  5) VERDICT="ERROR in ${NERR:-?} scenario(s)"
     if [ "${NFAILG:-0}" -gt 0 ]; then VERDICT="$VERDICT, $NFAILG FAIL"; fi ;;
  *) VERDICT="ERROR (exit $GRC: $(tail -1 "$NIGHT/runs/$DATE/gate.out"))" ;;
esac
END_EPOCH="$(date +%s)"; DUR=$((END_EPOCH - START_EPOCH))
# brightness is restored here so the report states the real outcome (finish restores again if this fails)
if [ -f "$NIGHT/state/brightness-saved" ] && [ "$KEEP_DARK" = 1 ]; then
  rm -f "$NIGHT/state/brightness-saved"; BR_LINE="${BR_LINE} -> left dimmed (--keep-dark)"
elif [ -f "$NIGHT/state/brightness-saved" ]; then
  if restore_brightness; then BR_LINE="${BR_LINE} -> ${BR_NOTE%% *} (restored)"
  else BR_LINE="$BR_LINE; $BR_NOTE"; fi
fi
REP=("NIGHT $DATE: $VERDICT — main $SHA vs ${BASE_SHA:-no baseline}")
REP+=("time: $START_HM - $(date +%H:%M), $((DUR / 60)) min")
REP+=("idle at start: ${IDLE0:-?} s, threshold $THR s$([ "$NOW" = 1 ] && echo ' (--now: window and idle checks skipped)')")
REP+=("preconditions: AC power and Low Power Mode off, screen unlocked")
REP+=("keep-awake: caffeinate pid $CAF, assertion seen: $CAF_SEEN")
REP+=("$BR_LINE")
[ -z "$BASE" ] && REP+=("no baseline build in builds/: absolute limits only")
[ -z "$OFFLINE" ] || REP+=("$OFFLINE")
REP+=("${GLINE:-GATE: (no GATE line in gate.out)}")
if [ -s "$GOUT/errors.tsv" ]; then
  while IFS= read -r l; do REP+=("$l"); done < <(awk -F'\t' '{print "- ERROR " $1 " (" $2 "): " $3 "; diagnostics: " $4}' "$GOUT/errors.tsv" | head -10)
fi
[ -z "$PRUNE_NOTE" ] || REP+=("$PRUNE_NOTE")
if [ -f "$GOUT/summary.tsv" ]; then
  while IFS= read -r l; do REP+=("$l"); done < <(awk -F'\t' '$2=="cand" && $3=="agg" && ($7=="FAIL" || $7=="NOISY") {print "- " $7 " " $1 " " $4 ": " $5 " (" $6 ")"}' "$GOUT/summary.tsv" | head -15)
  IDLE="$(awk -F'\t' '$4=="scrollable" && $3!="agg" && $5=="0" {print $1 " (" $2 ")"}' "$GOUT/summary.tsv" | sort -u | tr '\n' ' ')"
  [ -z "$IDLE" ] || REP+=("idle page, nothing to scroll (measured as idle, not as a scroll): ${IDLE% }")
fi
[ "${LIST:-all}" = "all" ] || REP+=("partial run (scenarios: $LIST)")
REP+=("report: $GOUT/report.md")
write_report "${REP[@]}"
exit 0
