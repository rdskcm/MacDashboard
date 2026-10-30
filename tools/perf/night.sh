#!/bin/bash
# tools/perf/night.sh — night launcher: on an idle Mac it runs the perf gate on origin/main when main changed, then the
# queued night jobs one at a time until 09:00, and writes one morning report for the whole night.
#
# Usage:
#   tools/perf/night.sh --check [--dry-run]      LaunchAgent entry (every 60 s): start tonight's run if due and write a
#                                                pending morning report; --dry-run prints the decisions and changes nothing
#   tools/perf/night.sh --run [--now] [--keep-dark] [--scenarios LIST] [--runs N] [--stop HH:MM] [--no-gate]
#                                                the run (normally opened in Terminal by --check): gate, then jobs until
#                                                09:00. --now skips the window and idle checks (hand run) and runs the gate
#                                                only, unless --stop HH:MM is given (then jobs run until that time);
#                                                --no-gate (with --now --stop) skips the gate; --keep-dark leaves display and
#                                                keyboard dark; LIST/N pass to gate.sh (default all / 3), LIST != all is "partial"
#   tools/perf/night.sh --queue-add --name NAME --minutes M --dir DIR --cmd 'COMMAND'
#                                                queue a night job: COMMAND runs in the foreground with bash -c in DIR; M = the
#                                                minutes it needs before the 09:00 stop to be worth starting (1-540)
#   tools/perf/night.sh --queue-list | --queue-remove ID
#   tools/perf/night.sh --install | --uninstall  add / remove the user LaunchAgent com.rdskcm.macdashboard.night
#   tools/perf/night.sh --restore-brightness     put back display / keyboard values a crashed run left saved
# Test seams: NIGHT_OUT=<absolute dir> replaces tools/perf/out/night.noindex (state, queue, builds, reports) in every mode
# but --install/--uninstall; NIGHT_CLAUDE_PROJECTS with --dry-run or NIGHT_OUT; NIGHT_HOUR, NIGHT_DATE with --check --dry-run;
# NIGHT_FOREIGN_ONLY=<pid> with NIGHT_OUT (the close step acts on that MacDashboard process only).
# Exit: 0 (also for skips — the reason is in the report) | 64 usage | 70 runtime error
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PERF="$ROOT/tools/perf"
NIGHT="$PERF/out/night.noindex"
DATE="$(date +%Y%m%d)"
LABEL="com.rdskcm.macdashboard.night"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

usage() { sed -n '2,/^set -uo/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//'; }
fatal() { echo "night.sh: $2" >&2; exit "$1"; }
if [ -n "${NIGHT_OUT:-}" ]; then
  case "$NIGHT_OUT" in /*) NIGHT="${NIGHT_OUT%/}" ;; *) fatal 64 "NIGHT_OUT must be an absolute path" ;; esac
fi

# ---------------------------------------------------------------- argument parsing
MODE=""; DRY=0; NOW=0; KEEP_DARK=0; LIST=""; N=""
STOP=""; NO_GATE=0; JNAME=""; JMIN=""; JDIR=""; JCMD=""; JID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--run|--install|--uninstall|--restore-brightness|--queue-add|--queue-list) MODE="$1"; shift ;;
    --queue-remove) [ $# -ge 2 ] || fatal 64 "--queue-remove needs a job id"; MODE="$1"; JID="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --now) NOW=1; shift ;;
    --keep-dark) KEEP_DARK=1; shift ;;
    --no-gate) NO_GATE=1; shift ;;
    --scenarios) [ $# -ge 2 ] || fatal 64 "--scenarios needs a value"; LIST="$2"; shift 2 ;;
    --runs) [ $# -ge 2 ] || fatal 64 "--runs needs a value"; N="$2"; shift 2 ;;
    --stop) [ $# -ge 2 ] || fatal 64 "--stop needs a value"; STOP="$2"; shift 2 ;;
    --name) [ $# -ge 2 ] || fatal 64 "--name needs a value"; JNAME="$2"; shift 2 ;;
    --minutes) [ $# -ge 2 ] || fatal 64 "--minutes needs a value"; JMIN="$2"; shift 2 ;;
    --dir) [ $# -ge 2 ] || fatal 64 "--dir needs a value"; JDIR="$2"; shift 2 ;;
    --cmd) [ $# -ge 2 ] || fatal 64 "--cmd needs a value"; JCMD="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fatal 64 "unknown argument: $1" ;;
  esac
done
[ -n "$MODE" ] || { usage >&2; exit 64; }
[ "$DRY" = 0 ] || [ "$MODE" = "--check" ] || fatal 64 "--dry-run only with --check"
{ [ "$NOW" = 0 ] && [ "$KEEP_DARK" = 0 ] && [ -z "$LIST" ] && [ -z "$N" ] && [ -z "$STOP" ] && [ "$NO_GATE" = 0 ]; } || [ "$MODE" = "--run" ] \
  || fatal 64 "--now/--keep-dark/--scenarios/--runs/--stop/--no-gate only with --run"
{ [ -z "$STOP" ] && [ "$NO_GATE" = 0 ]; } || [ "$NOW" = 1 ] || fatal 64 "--stop/--no-gate only with --run --now"
[ -z "$STOP" ] || [[ "$STOP" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || fatal 64 "--stop must be HH:MM"
[ "$NO_GATE" = 0 ] || [ -n "$STOP" ] || fatal 64 "--no-gate needs --stop (a run with neither gate nor jobs does nothing)"
{ [ -z "$JNAME$JMIN$JDIR$JCMD" ]; } || [ "$MODE" = "--queue-add" ] || fatal 64 "--name/--minutes/--dir/--cmd only with --queue-add"
case "$MODE" in --install|--uninstall) [ -z "${NIGHT_OUT:-}" ] || fatal 64 "NIGHT_OUT is a test seam; unset it for $MODE" ;; esac

if [ "$DRY" = 0 ]; then
  mkdir -p "$NIGHT/builds" "$NIGHT/runs" "$NIGHT/reports" "$NIGHT/state" "$NIGHT/queue" "$NIGHT/.bin" || fatal 70 "cannot create $NIGHT"
fi
# Time Machine exclusion of $NIGHT, once; synchronous (~10 s on first use). Only --install and --run call it: under --check
# launchd killed the detached tmutil with the job's process group, after the marker had already been written.
ensure_excluded() {
  [ -e "$NIGHT/state/.excluded" ] && return 0
  tmutil addexclusion "$NIGHT" >/dev/null 2>&1 || return 1
  touch "$NIGHT/state/.excluded"
}

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
# Claude Code at work (NIGHT-WORK-AWARE): a main or subagent transcript (*.jsonl at any depth under ~/.claude/projects)
# written in the last WORK_QUIET_MIN minutes. HID idle alone let the 2026-10-26 run start while agents worked with the
# user away. Test seams, honoured only with --dry-run or NIGHT_OUT: NIGHT_CLAUDE_PROJECTS (another folder), NIGHT_HOUR (--check) and
# NIGHT_DATE (a night with no started marker).
WORK_QUIET_MIN=15
CLAUDE_PROJECTS="$HOME/.claude/projects"
{ [ "$DRY" = 1 ] || [ -n "${NIGHT_OUT:-}" ]; } && [ -n "${NIGHT_CLAUDE_PROJECTS:-}" ] && CLAUDE_PROJECTS="$NIGHT_CLAUDE_PROJECTS"
if [ "$DRY" = 1 ] && [ -n "${NIGHT_DATE:-}" ]; then [[ "$NIGHT_DATE" =~ ^[0-9]{8}$ ]] || fatal 64 "NIGHT_DATE must be YYYYMMDD"; DATE="$NIGHT_DATE"; fi
FOREIGN_ONLY=""; [ -z "${NIGHT_OUT:-}" ] || FOREIGN_ONLY="${NIGHT_FOREIGN_ONLY:-}"   # test seam: close only that pid
claude_working() {   # 0 + one-line reason on stdout when a transcript was written in the window; 1 when quiet or no folder
  local list n last t f
  list="$(find "$CLAUDE_PROJECTS" -type f -name '*.jsonl' -mmin -"$WORK_QUIET_MIN" -exec stat -f '%m %N' {} + 2>/dev/null | sort -n)"
  [ -n "$list" ] || return 1
  n="$(find "$CLAUDE_PROJECTS" -type f -name '*.jsonl' -mmin -"$WORK_QUIET_MIN" -print0 2>/dev/null | tr -cd '\0' | wc -c | tr -d ' ')"
  last="${list##*$'\n'}"; t="${last%% *}"; f="${last#* }"
  echo "Claude Code working: $n transcript(s) written in the last $WORK_QUIET_MIN min, newest at $(date -r "$t" +%H:%M): ${f#"$CLAUDE_PROJECTS"/}"
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
write_report() {   # date line... -> reports/<date>.md, or <date>-2.md, -3 … when that date already has a report (a second
  # run the same date never overwrites the first, GATE-AX-MISS); latest.md = this report unless a later date has one
  local d="$1" f n=2 newest; shift
  f="$NIGHT/reports/$d.md"
  while [ -e "$f" ]; do f="$NIGHT/reports/$d-$n.md"; n=$((n + 1)); done
  printf '%s\n' "$@" > "$f"
  newest="$(ls -1 "$NIGHT/reports" | grep -E '^[0-9]{8}(-[0-9]+)?\.md$' | cut -c1-8 | sort | tail -1)"
  [ "$newest" = "$d" ] && cp "$f" "$NIGHT/latest.md"
  REPORTED=1
}
log() { [ "$DRY" = 1 ] || echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$NIGHT/agent.log"; }

# ---- lights: display (DisplayServices/IOKit) and keyboard backlight (CoreBrightness), both through brightness.swift
light_file() { case "$1" in display) echo "$NIGHT/state/brightness-saved" ;; kbd) echo "$NIGHT/state/kbd-saved" ;; esac; }
light_verb() { case "$1" in display) echo "$2" ;; kbd) echo "kbd-$2" ;; esac; }
LIGHT_NOTE=""; LIGHT_LINE=""
restore_light() {   # kind -> 0 when nothing is saved or the restore worked; LIGHT_NOTE says what happened
  local f v out=""; f="$(light_file "$1")"
  [ -f "$f" ] || { LIGHT_NOTE="nothing saved"; return 0; }
  v="$(awk 'NR==1{print $1}' "$f")"
  if brightness_bin && out="$("$NIGHT/.bin/brightness" "$(light_verb "$1" set)" "$v" 2>&1)"; then
    rm -f "$f"; LIGHT_NOTE="restored ${out%% *}"; return 0
  fi
  LIGHT_NOTE="restore of $v FAILED (${out:-no helper}); value kept in $f, run night.sh --restore-brightness"
  return 1
}
dim_light() {   # kind label -> LIGHT_LINE
  local k="$1" l="$2" f out v m setout; f="$(light_file "$k")"
  brightness_bin || { LIGHT_LINE="$l: not settable: brightness helper did not compile (see .bin/brightness-build.log)"; return; }
  out="$("$NIGHT/.bin/brightness" "$(light_verb "$k" get)" 2>&1)" || { LIGHT_LINE="$l: not settable: $out"; return; }
  v="${out%% *}"; m="${out#* }"
  # D19: never save a near-zero start value — after a system idle dim it would be "restored" as a black screen
  if awk -v v="$v" 'BEGIN { exit !(v < 0.05) }'; then LIGHT_LINE="$l: already $v at start ($m): not dimmed, nothing to restore"; return; fi
  echo "$v $m $(date '+%Y-%m-%d %H:%M')" > "$f"
  if setout="$("$NIGHT/.bin/brightness" "$(light_verb "$k" set)" 0 2>&1)"; then LIGHT_LINE="$l: $v -> 0.000 ($m)"
  elif restore_light "$k"; then LIGHT_LINE="$l: not settable: $setout ($LIGHT_NOTE)"     # D17
  else LIGHT_LINE="$l: not settable: $setout; $LIGHT_NOTE"; fi
}
end_light() {   # kind -> suffix for the report line (runs in $(…); the saved file is the shared state)
  [ -f "$(light_file "$1")" ] || return 0
  if [ "$KEEP_DARK" = 1 ]; then rm -f "$(light_file "$1")"; echo " -> left dark (--keep-dark)"
  elif restore_light "$1"; then echo " -> $LIGHT_NOTE"
  else echo "; $LIGHT_NOTE"; fi
}

# ---- queue: one file per job in $NIGHT/queue/<id>-<name>.job, "key: value" lines, never sourced
jf() { sed -n "s/^$2: //p" "$1" | head -1; }
requeue_hint() {
  printf 'tools/perf/night.sh --queue-add --name %q --minutes %q --dir %q --cmd %q' \
    "$(jf "$1" name)" "$(jf "$1" minutes)" "$(jf "$1" dir)" "$(jf "$1" cmd)"
}
queue_list() {
  local f n=0 l
  for f in "$NIGHT"/queue/*.job; do
    [ -f "$f" ] || continue; n=$((n + 1))
    echo "$n. #$(jf "$f" id) $(jf "$f" name) — $(jf "$f" minutes) min, added $(jf "$f" added), dir $(jf "$f" dir)"
    echo "   cmd: $(jf "$f" cmd)"
    l="$(jf "$f" last)"; [ -z "$l" ] || echo "   last night: $l"
    l="$(jf "$f" started)"; [ -z "$l" ] || echo "   started $l (running, or its night run died)"
  done
  [ "$n" -gt 0 ] || echo "queue empty"
  [ ! -f "$NIGHT/state/last-measured-sha" ] || echo "gate: last full measurement $(cat "$NIGHT/state/last-measured-sha")"
}
waiting_line() {   # -> REP += one "queue: …" line
  local f n=0 s=""
  for f in "$NIGHT"/queue/*.job; do
    [ -f "$f" ] || continue; grep -q '^started: ' "$f" && continue
    n=$((n + 1)); s="$s #$(jf "$f" id) $(jf "$f" name) ($(jf "$f" minutes) min),"
  done
  if [ "$n" = 0 ]; then REP+=("queue: empty"); else REP+=("queue: $n job(s) waiting:${s%,}"); fi
}
interrupted_jobs() {   # date-regex -> queue files whose "started: <date>" line matches were running when their night run died
  local f d id name
  for f in "$NIGHT"/queue/*.job; do
    [ -f "$f" ] || continue
    d="$(sed -nE "s/^started: ($1) .*/\1/p" "$f" | head -1)"; [ -n "$d" ] || continue
    id="$(jf "$f" id)"; name="$(jf "$f" name)"
    REP+=("- #$id $name: INTERRUPTED on night $d — it was running when the night run ended; log runs/$d/job-$id-$name.out")
    REP+=("    re-queue: $(requeue_hint "$f")")
    [ "$DRY" = 1 ] && continue
    echo "result: INTERRUPTED (the night run ended while it ran)" >> "$f"
    mkdir -p "$NIGHT/runs/$d"; mv "$f" "$NIGHT/runs/$d/job-$(basename "$f")"
  done
}
pending_report() {   # date -> SKIPPED / INTERRUPTED report of that night when it has none (caller checked !busy)
  local d="$1" v r
  [ -f "$NIGHT/reports/$d.md" ] && return 0
  if [ -f "$NIGHT/runs/$d/started" ]; then
    v="NIGHT $d: INTERRUPTED — the run started at $(cat "$NIGHT/runs/$d/started") did not finish (restart, crash or interrupted)"
  else
    r="$(sed 's/^[0-9:]* //' "$NIGHT/state/last-skip-$d" 2>/dev/null)"
    v="NIGHT $d: SKIPPED — ${r:-the Mac was asleep or never idle between 00:00 and 03:00}"
  fi
  REP=("$v"); interrupted_jobs "$d"; waiting_line
  if [ "$DRY" = 1 ]; then printf 'would write report %s:\n' "$d"; printf '  %s\n' "${REP[@]}"
  else write_report "$d" "${REP[@]}"; decide "report $d: $v"; fi
}
decide() {   # --check decision: stdout with --dry-run; otherwise agent.log, only when it differs from the previous one
  if [ "$DRY" = 1 ]; then echo "$*"; return; fi
  [ "$*" = "$(cat "$NIGHT/state/last-decision" 2>/dev/null)" ] && return
  echo "$*" > "$NIGHT/state/last-decision"; log "$*"
}

# ---------------------------------------------------------------- --restore-brightness
if [ "$MODE" = "--restore-brightness" ]; then
  any=0; rc=0
  for k in display kbd; do
    [ -f "$(light_file "$k")" ] || continue; any=1
    if restore_light "$k"; then echo "$k: $LIGHT_NOTE"; else echo "$k: $LIGHT_NOTE" >&2; rc=70; fi
  done
  [ "$any" = 1 ] || echo "no saved brightness"
  exit "$rc"
fi

# ---------------------------------------------------------------- --install / --uninstall
if [ "$MODE" = "--install" ]; then
  ensure_excluded || echo "warning: tmutil addexclusion $NIGHT failed; the next run retries"
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
  echo "installed: checks every 60 s; between 00:00 and 03:00, when the Mac is idle and no Claude Code transcript was written for $WORK_QUIET_MIN min, it runs the gate (when main changed) and then the queued jobs until 09:00; report: $NIGHT/latest.md"
  exit 0
fi
if [ "$MODE" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  rm -f "$PLIST"
  echo "uninstalled $LABEL"
  exit 0
fi

# ---------------------------------------------------------------- --queue-add / --queue-list / --queue-remove
if [ "$MODE" = "--queue-add" ]; then
  [[ "$JNAME" =~ ^[A-Za-z0-9._-]{1,40}$ ]] || fatal 64 "--name: 1-40 characters from A-Z a-z 0-9 . _ -"
  { [[ "$JMIN" =~ ^[0-9]{1,3}$ ]] && [ "$((10#$JMIN))" -ge 1 ] && [ "$((10#$JMIN))" -le 540 ]; } || fatal 64 "--minutes: 1-540"
  case "$JDIR" in /*) ;; *) fatal 64 "--dir must be an absolute path" ;; esac
  [ -d "$JDIR" ] || fatal 64 "--dir does not exist: $JDIR"
  [ -n "$JCMD" ] || fatal 64 "--cmd is empty"
  case "$JCMD" in *$'\n'*) fatal 64 "--cmd must be one line" ;; esac
  n="$(cat "$NIGHT/state/next-job-id" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=1
  id="$(printf '%04d' "$((10#$n))")"; f="$NIGHT/queue/$id-$JNAME.job"
  { printf 'id: %s\nname: %s\nminutes: %s\ndir: %s\ncmd: %s\nadded: %s\n' "$id" "$JNAME" "$((10#$JMIN))" "$JDIR" "$JCMD" \
      "$(date '+%Y-%m-%d %H:%M')" > "$f.tmp" && mv "$f.tmp" "$f"; } || fatal 70 "cannot write $f"
  echo "$((10#$n + 1))" > "$NIGHT/state/next-job-id"
  echo "queued #$id $JNAME (needs $((10#$JMIN)) min before 09:00)"; queue_list; exit 0
fi
if [ "$MODE" = "--queue-list" ]; then queue_list; exit 0; fi
if [ "$MODE" = "--queue-remove" ]; then
  [[ "$JID" =~ ^[0-9]{1,4}$ ]] || fatal 64 "job id: the number shown by --queue-list"
  id="$(printf '%04d' "$((10#$JID))")"; f="$(ls -1 "$NIGHT/queue/$id"-*.job 2>/dev/null | head -1)"
  [ -n "$f" ] || fatal 64 "no queued job #$id"
  if grep -q '^started: ' "$f" && busy; then fatal 64 "job #$id is running; stop the night run first (Ctrl-C in its Terminal window)"; fi
  rm -f "$f"; echo "removed #$id"; queue_list; exit 0
fi

# ---------------------------------------------------------------- --check
if [ "$MODE" = "--check" ]; then
  if { [ -f "$(light_file display)" ] || [ -f "$(light_file kbd)" ]; } && ! busy; then
    if [ "$DRY" = 1 ]; then echo "would restore the light values a crashed run left saved"
    else for k in display kbd; do [ -f "$(light_file "$k")" ] || continue; restore_light "$k"; decide "restored saved $k: $LIGHT_NOTE"; done; fi
  fi
  H="$(date +%H)"
  if [ "$DRY" = 1 ] && [ -n "${NIGHT_HOUR:-}" ]; then
    { [[ "$NIGHT_HOUR" =~ ^[0-9]{1,2}$ ]] && [ $((10#$NIGHT_HOUR)) -le 23 ]; } || fatal 64 "NIGHT_HOUR must be 0-23"
    H="$NIGHT_HOUR"
  fi
  H=$((10#$H))
  if ! busy; then   # never while a night run or gate is alive: that run writes its own report
    pending_report "$(date -j -v-1d -f '%Y%m%d' "$DATE" +%Y%m%d)"
    [ "$H" -lt 3 ] || pending_report "$DATE"
  fi
  if [ "$H" -ge 3 ]; then decide "outside window (hour $H): nothing to do"; exit 0; fi
  if [ -f "$NIGHT/runs/$DATE/started" ]; then decide "run already started tonight"; exit 0; fi
  skip() {
    [ "$DRY" = 1 ] || echo "$(date +%H:%M) $1" > "$NIGHT/state/last-skip-$DATE"
    decide "not starting: $1"; exit 0
  }
  CC="$(claude_working)" && skip "$CC"
  power_ok || skip "on battery or Low Power Mode on"
  unlocked || skip "screen locked"
  IS="$(idle_secs)"; T="$(idle_threshold)"
  [ "${IS:-0}" -ge "$T" ] || skip "not idle: ${IS:-0} s < $T s"
  busy && skip "another gate or night run is running"
  if [ "$DRY" = 1 ]; then echo "would start tonight's run (idle ${IS} s >= $T s); queue: $(ls -1 "$NIGHT"/queue/*.job 2>/dev/null | wc -l | tr -d ' ') job(s)"; exit 0; fi
  mkdir -p "$NIGHT/runs/$DATE"; date '+%H:%M' > "$NIGHT/runs/$DATE/started"
  decide "starting run in Terminal (idle $IS s >= $T s)"
  open -a Terminal "$PERF/night.command"
  exit 0
fi

# ---------------------------------------------------------------- --run
busy && fatal 70 "another night run or gate is running"   # a second run would reap the first one's job as interrupted
mkdir -p "$NIGHT/runs/$DATE"
[ "$NOW" = 1 ] && date '+%H:%M' > "$NIGHT/runs/$DATE/started"
START_EPOCH="$(date +%s)"; START_HM="$(date +%H:%M)"
SRC=""; SIGNAME=""; FINISHED=0; CAF=""; CAF_SEEN="no"; IDLE0="?"; THR="?"
NIGHT_VERDICT=""   # only for a whole-night outcome (SKIPPED / ERROR); otherwise line 1 = gate verdict + job counts
GATE_VERDICT=""; GATE_LINES=(); JOB_LINES=(); NOTES=(); REP=()
NDONE=0; NFAILED=0; NSTOPPED=0; NINT=0; NNOT=0
JPID=""; JF=""; JOUT=""; JSTART=""; JRC=""; JSTOPPED=""; JLEFT=""
CLOSE_LINES=(); CLOSE_WHY=""
DISP_LINE="display: not attempted"; KBD_LINE="keyboard: not attempted"
JOBS=1; STOP_HM="09:00"                                   # D12: a hand run runs jobs only with --stop
if [ "$NOW" = 1 ]; then if [ -n "$STOP" ]; then STOP_HM="$STOP"; else JOBS=0; fi; fi
STOP_EPOCH="$(date -j -f '%Y%m%d %H:%M:%S' "$(date +%Y%m%d) $STOP_HM:00" +%s)"
[ "$STOP_EPOCH" -gt "$START_EPOCH" ] || STOP_EPOCH="$(date -j -v+1d -f '%Y%m%d %H:%M:%S' "$(date +%Y%m%d) $STOP_HM:00" +%s)"
SOFT_HM="$(date -r $((STOP_EPOCH - 900)) +%H:%M)"        # D7: STOP_AT for self-stopping jobs

# GATE-AX-MISS: every MacDashboard process is closed before the gate and before each job (tools/perf/foreign-copies.sh:
# copies SIGTERM then SIGKILL, the installed app by a polite AppleScript quit, never killed).
close_copies() {   # what -> 0 nothing left | 1 some left or the close failed (CLOSE_WHY); CLOSE_LINES = report lines, empty when none was found
  local out rc l
  CLOSE_LINES=(); CLOSE_WHY=""
  out="$("$PERF/foreign-copies.sh" close ${FOREIGN_ONLY:+--only "$FOREIGN_ONLY"} 2>&1)"; rc=$?
  if [ -n "$out" ]; then
    CLOSE_LINES+=("MacDashboard processes before $1 (found: pid ppid started command):")
    while IFS= read -r l; do CLOSE_LINES+=("    | $l"); done <<< "$out"
  fi
  [ "$rc" = 0 ] && return 0
  l="$(sed -n 's/^left: //p' <<< "$out" | paste -sd ';' - | sed 's/;/; /g')"
  if [ -n "$l" ]; then CLOSE_WHY="MacDashboard process(es) still running after the close: $l"
  else CLOSE_WHY="closing MacDashboard processes failed (foreign-copies.sh exit $rc: $(tail -1 <<< "$out"))"; fi
  return 1
}
stop_job() {   # reason grace -> TERM the job's process group, KILL after grace; no-op when no job runs
  [ -n "$JPID" ] || return 0
  local t=0 how="had already exited"
  if kill -0 -- "-$JPID" 2>/dev/null; then
    kill -TERM -- "-$JPID" 2>/dev/null
    while kill -0 -- "-$JPID" 2>/dev/null && [ "$t" -lt "$2" ]; do sleep 2; t=$((t + 2)); done
    if kill -0 -- "-$JPID" 2>/dev/null; then kill -KILL -- "-$JPID" 2>/dev/null; how="SIGKILL after $2 s"
    else how="exited $t s after SIGTERM"; fi
  fi
  wait "$JPID" 2>/dev/null; JRC=$?
  JSTOPPED="$1|$how"
}
job_done() {   # records the finished/stopped job: report lines, result line, file moved to runs/<date>/
  local id name res l
  id="$(jf "$JF" id)"; name="$(jf "$JF" name)"
  case "$JSTOPPED" in
    stopped\|*)     res="STOPPED AT $STOP_HM (${JSTOPPED#*|})"; NSTOPPED=$((NSTOPPED + 1)) ;;
    interrupted\|*) res="INTERRUPTED — ${SIGNAME:-the night run ended} (${JSTOPPED#*|})"; NINT=$((NINT + 1)) ;;
    *) if [ "$JRC" = 0 ]; then res="DONE"; NDONE=$((NDONE + 1)); else res="FAILED exit $JRC"; NFAILED=$((NFAILED + 1)); fi ;;
  esac
  [ -z "$JLEFT" ] || res="$res; $JLEFT"
  JOB_LINES+=("- #$id $name: $res, $(date -r "$JSTART" +%H:%M)-$(date +%H:%M) ($(( ($(date +%s) - JSTART) / 60 )) min); log runs/$DATE/job-$id-$name.out")
  while IFS= read -r l; do JOB_LINES+=("    | $l"); done < <(tail -3 "$JOUT" 2>/dev/null | cut -c1-200)
  [ "$res" = DONE ] || JOB_LINES+=("    re-queue: $(requeue_hint "$JF")")
  echo "result: $res" >> "$JF"
  mv "$JF" "$NIGHT/runs/$DATE/job-$(basename "$JF")"
  JPID=""; JF=""; JSTOPPED=""; JLEFT=""
}
run_jobs() {   # D4-D10: queue order, fit check, re-checks, one at a time
  local f c tried=" " id name min dir cmd now why halt="" t
  while :; do
    f=""
    for c in "$NIGHT"/queue/*.job; do
      [ -f "$c" ] || continue; case "$tried" in *" $c "*) continue ;; esac; f="$c"; break
    done
    [ -n "$f" ] || break
    tried="$tried$f "
    id="$(jf "$f" id)"; name="$(jf "$f" name)"; min="$(jf "$f" minutes)"; dir="$(jf "$f" dir)"; cmd="$(jf "$f" cmd)"
    now="$(date +%s)"; why="$halt"
    if [ -z "$why" ]; then
      if [ $((now + min * 60)) -gt "$STOP_EPOCH" ]; then why="needs $min min, $(( (STOP_EPOCH - now) / 60 )) min left before $STOP_HM"
      elif CC="$(claude_working)"; then halt="$CC"; why="$halt"
      elif ! power_ok; then halt="on battery or Low Power Mode on"; why="$halt"
      elif ! unlocked; then halt="screen locked"; why="$halt"; fi
    fi
    if [ -z "$why" ]; then
      close_copies "job #$id $name" || why="$CLOSE_WHY"
      [ "${#CLOSE_LINES[@]}" = 0 ] || JOB_LINES+=("${CLOSE_LINES[@]}")
    fi
    if [ -n "$why" ]; then
      NNOT=$((NNOT + 1)); JOB_LINES+=("- #$id $name: NOT STARTED — $why; stays queued")
      sed -i '' '/^last: /d' "$f"; echo "last: $DATE not started, $why" >> "$f"
      continue
    fi
    echo "started: $DATE $(date +%H:%M)" >> "$f"
    JF="$f"; JOUT="$NIGHT/runs/$DATE/job-$id-$name.out"; JSTART="$(date +%s)"; JSTOPPED=""; JLEFT=""
    if [ ! -d "$dir" ]; then echo "night.sh: job directory missing: $dir" > "$JOUT"; JRC=66; job_done; continue; fi
    ( cd "$dir" || exit 66
      export STOP_AT="$SOFT_HM" NIGHT_STOP_EPOCH="$STOP_EPOCH" NIGHT_JOB_DATE="$DATE" NIGHT_JOB_ID="$id"
      exec /usr/bin/perl -e 'setpgrp(0,0) or die "setpgrp: $!\n"; exec @ARGV or die "exec: $!\n"' /bin/bash -c "$cmd"
    ) < /dev/null > "$JOUT" 2>&1 &
    JPID=$!
    while kill -0 "$JPID" 2>/dev/null; do
      if [ "$(date +%s)" -ge "$STOP_EPOCH" ]; then stop_job stopped 120; break; fi
      sleep 5
    done
    if [ -z "$JSTOPPED" ]; then
      wait "$JPID"; JRC=$?
      t=0; while kill -0 -- "-$JPID" 2>/dev/null && [ "$t" -lt 10 ]; do sleep 2; t=$((t + 2)); done
      if kill -0 -- "-$JPID" 2>/dev/null; then   # a job must run in the foreground; whatever it left behind is ended
        kill -TERM -- "-$JPID" 2>/dev/null; sleep 3; kill -KILL -- "-$JPID" 2>/dev/null
        JLEFT="left processes behind after its exit: killed"
      fi
    fi
    job_done
  done
}

# A finished night build: build.ok and the bench copy tools/bench-app.sh writes (MacDashboardBench.app since
# LS-PRUNE-MISSES). A build directory from before holds MacDashboard.app and counts as unfinished: the candidate
# is rebuilt, and such a directory is never a baseline and is removed by the bookkeeping prune.
night_built() { [ -f "$1/build.ok" ] && [ -d "$1/MacDashboardBench.app" ]; }
run_gate() {
  local OFFLINE="" SHA BASE="" BASE_SHA="" GOUT GRC GLINE NOISY NFAILG NERR PRUNE_OK PRUNE_NOTE="" VERDICT IDLE d l crc
  # 5. candidate
  GIT_TERMINAL_PROMPT=0 git -C "$ROOT" -c core.sshCommand="ssh -o BatchMode=yes" fetch --quiet origin main >/dev/null 2>&1 || OFFLINE="offline: local origin/main"
  SHA="$(git -C "$ROOT" rev-parse --short=10 origin/main)" || { GATE_VERDICT="ERROR — cannot resolve origin/main"; return; }
  if [ -f "$NIGHT/state/last-measured-sha" ] && [ "$(awk '{print $1}' "$NIGHT/state/last-measured-sha")" = "$SHA" ]; then
    GATE_VERDICT="SKIPPED (main unchanged since $(awk '{print $2}' "$NIGHT/state/last-measured-sha"), $SHA)"; return
  fi
  if ! night_built "$NIGHT/builds/$SHA"; then
    SRC="$(mktemp -d "$NIGHT/src.XXXXXX")"
    git -C "$ROOT" archive --format=tar origin/main | tar -x -C "$SRC"
    if ! (cd "$SRC" && ./build_app.sh) > "$NIGHT/runs/$DATE/build.log" 2>&1; then
      rm -rf "$SRC"; SRC=""
      GATE_VERDICT="ERROR — build of $SHA failed, see runs/$DATE/build.log"; return
    fi
    rm -rf "$NIGHT/builds/$SHA"
    "$ROOT/tools/bench-app.sh" "$SRC/dist.noindex/MacDashboard.app" "$NIGHT/builds/$SHA" >> "$NIGHT/runs/$DATE/build.log" 2>&1 \
      || { GATE_VERDICT="ERROR — bench copy of $SHA failed, see runs/$DATE/build.log"; return; }
    echo "$SHA $(date '+%Y-%m-%d %H:%M')" > "$NIGHT/builds/$SHA/build.ok"
    rm -rf "$SRC"; SRC=""
  fi

  # 6. baseline
  while IFS= read -r d; do   # one path per line: the project path contains spaces (S6)
    d="${d%/}"
    [ "$(basename "$d")" = "$SHA" ] && continue
    night_built "$d" || continue
    BASE="$d/MacDashboardBench.app"; BASE_SHA="$(basename "$d")"; break
  done < <(ls -1dt "$NIGHT"/builds/*/ 2>/dev/null)

  # 6b. MacDashboard processes (GATE-AX-MISS): closed before the gate; one that survives skips it (gate.sh would refuse)
  close_copies "the gate"; crc=$?
  [ "${#CLOSE_LINES[@]}" = 0 ] || GATE_LINES+=("${CLOSE_LINES[@]}")
  [ "$crc" = 0 ] || { GATE_VERDICT="SKIPPED — $CLOSE_WHY — main $SHA"; return; }

  # 7. gate
  GOUT="$PERF/out/night-$DATE"
  [ ! -e "$GOUT" ] || GOUT="$GOUT-$(date +%H%M%S)"
  env -u GATE_TEST_ALLOW_FOREIGN "$PERF/gate.sh" --app "$NIGHT/builds/$SHA/MacDashboardBench.app" ${BASE:+--baseline "$BASE"} \
    --scenarios "${LIST:-all}" --runs "${N:-3}" --out "$GOUT" > "$NIGHT/runs/$DATE/gate.out" 2>&1
  GRC=$?
  GLINE="$(grep '^GATE:' "$NIGHT/runs/$DATE/gate.out" | tail -1)"
  NOISY="$(echo "$GLINE" | sed -n 's/.*noisy=\([0-9]*\).*/\1/p')"
  NFAILG="$(echo "$GLINE" | sed -n 's/.*fail=\([0-9]*\).*/\1/p')"
  NERR="$(echo "$GLINE" | sed -n 's/.*error=\([0-9]*\).*/\1/p')"

  # 8. bookkeeping
  # Prune only after a successful full measured run (S6): a failed or partial run keeps every build, and a run that
  # found no baseline while another finished build exists keeps them too (that would be a selection bug, not a first night).
  if { [ "$GRC" = 0 ] || { [ "$GRC" = 1 ] && [ "${NFAILG:-0}" -gt 0 ]; }; } && [ "${LIST:-all}" = "all" ]; then
    echo "$SHA $(date '+%Y-%m-%d')" > "$NIGHT/state/last-measured-sha"
    PRUNE_OK=1
    if [ -z "$BASE_SHA" ]; then
      for d in "$NIGHT"/builds/*/; do
        d="${d%/}"
        [ "$(basename "$d")" != "$SHA" ] && night_built "$d" && PRUNE_OK=0
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

  # 9. report lines
  case "$GRC" in
    0) if [ "${NOISY:-0}" -gt 0 ]; then VERDICT="PASS, $NOISY noisy"; else VERDICT="PASS"; fi ;;
    1) if [ "${NFAILG:-0}" -gt 0 ]; then VERDICT="FAIL"; else VERDICT="ERROR (gate exit 1 without a measured FAIL: shell error in gate.sh?)"; fi ;;
    3) VERDICT="INVALID" ;;
    4) VERDICT="DEFAULTS-CHANGED" ;;
    65) VERDICT="SKIPPED — gate refused to start: $(grep '^gate: precondition refused: ' "$NIGHT/runs/$DATE/gate.out" | tail -1 | sed 's/^gate: precondition refused: //')" ;;
    5) VERDICT="ERROR in ${NERR:-?} scenario(s)"
       if [ "${NFAILG:-0}" -gt 0 ]; then VERDICT="$VERDICT, $NFAILG FAIL"; fi ;;
    *) VERDICT="ERROR (exit $GRC: $(grep -v '^GATE:' "$NIGHT/runs/$DATE/gate.out" | tail -1))" ;;
  esac
  [ -z "$BASE" ] && GATE_LINES+=("no baseline build in builds/: absolute limits only")
  [ -z "$OFFLINE" ] || GATE_LINES+=("$OFFLINE")
  GATE_LINES+=("${GLINE:-GATE: (no GATE line in gate.out)}")
  if [ -s "$GOUT/errors.tsv" ]; then
    while IFS= read -r l; do GATE_LINES+=("$l"); done < <(awk -F'\t' '{print "- ERROR " $1 " (" $2 "): " $3 "; diagnostics: " $4}' "$GOUT/errors.tsv" | head -10)
  fi
  [ -z "$PRUNE_NOTE" ] || GATE_LINES+=("$PRUNE_NOTE")
  if [ -f "$GOUT/summary.tsv" ]; then
    while IFS= read -r l; do GATE_LINES+=("$l"); done < <(awk -F'\t' '$2=="cand" && $3=="agg" && ($7=="FAIL" || $7=="NOISY") {print "- " $7 " " $1 " " $4 ": " $5 " (" $6 ")"}' "$GOUT/summary.tsv" | head -15)
    IDLE="$(awk -F'\t' '$4=="scrollable" && $3!="agg" && $5=="0" {print $1 " (" $2 ")"}' "$GOUT/summary.tsv" | sort -u | tr '\n' ' ')"
    [ -z "$IDLE" ] || GATE_LINES+=("idle page, nothing to scroll (measured as idle, not as a scroll): ${IDLE% }")
  fi
  [ "${LIST:-all}" = "all" ] || GATE_LINES+=("partial run (scenarios: $LIST)")
  GATE_LINES+=("report: $GOUT/report.md")
  GATE_VERDICT="$VERDICT — main $SHA vs ${BASE_SHA:-no baseline}"
}

finish() {
  local rc=$? first jobs
  [ "$FINISHED" = 0 ] || return; FINISHED=1
  if [ -n "$JPID" ]; then stop_job interrupted 30; job_done; fi
  [ -z "$SRC" ] || rm -rf "$SRC"
  DISP_LINE="$DISP_LINE$(end_light display)"; KBD_LINE="$KBD_LINE$(end_light kbd)"   # D18: before the report
  if [ "$JOBS" = 1 ]; then jobs="jobs: $NDONE done, $NFAILED failed, $NSTOPPED stopped at $STOP_HM, $NINT interrupted, $NNOT not started"
  else jobs="jobs: not run (hand run without --stop)"; fi
  if [ -n "$SIGNAME" ] || { [ "$rc" != 0 ] && [ -z "$NIGHT_VERDICT" ]; }; then
    first="NIGHT $DATE: INTERRUPTED — ${SIGNAME:-exit $rc}; ${GATE_VERDICT:-gate not reached}; $jobs"
  elif [ -n "$NIGHT_VERDICT" ]; then first="NIGHT $DATE: $NIGHT_VERDICT"
  else first="NIGHT $DATE: ${GATE_VERDICT:-gate not reached}; $jobs"; fi
  REP=("$first")
  case "$NIGHT_VERDICT" in
    SKIPPED*) ;;   # a skipped night stays a short report
    *) REP+=("time: $START_HM - $(date +%H:%M), $(( ($(date +%s) - START_EPOCH) / 60 )) min; job stop $STOP_HM (jobs get STOP_AT=$SOFT_HM)")
       REP+=("idle at start: $IDLE0 s, threshold $THR s$([ "$NOW" = 1 ] && echo ' (--now: window and idle checks skipped)')")
       REP+=("preconditions: AC power and Low Power Mode off, screen unlocked")
       REP+=("keep-awake: caffeinate pid ${CAF:-none}, assertion seen: $CAF_SEEN" "$DISP_LINE" "$KBD_LINE")
       [ "${#NOTES[@]}" = 0 ] || REP+=("${NOTES[@]}")
       REP+=("## gate"); [ "${#GATE_LINES[@]}" = 0 ] || REP+=("${GATE_LINES[@]}")
       REP+=("## jobs"); [ "${#JOB_LINES[@]}" = 0 ] || REP+=("${JOB_LINES[@]}") ;;
  esac
  waiting_line
  write_report "$DATE" "${REP[@]}"
  [ -z "$CAF" ] || kill "$CAF" 2>/dev/null
  if [ -t 1 ]; then clear; fi
  printf 'Mac свободен\n%s\nreport: %s\n' "$first" "$NIGHT/latest.md"   # D27
  osascript -e 'tell application "Terminal" to activate' >/dev/null 2>&1 || true
}
trap_sig() { SIGNAME="$1"; exit 70; }

trap finish EXIT
trap 'trap_sig INT' INT
trap 'trap_sig TERM' TERM
trap 'trap_sig HUP' HUP
ensure_excluded || NOTES+=("Time Machine exclusion of $NIGHT failed (tmutil addexclusion); the next run retries")
if ! power_ok; then NIGHT_VERDICT="SKIPPED — on battery or Low Power Mode on ($(tail -1 "$NIGHT/state/power.log"))"; exit 0; fi
if ! unlocked; then NIGHT_VERDICT="SKIPPED — screen locked"; exit 0; fi
IDLE0="$(idle_secs)"; THR="$(idle_threshold)"
caffeinate -d -i -s -w $$ &
CAF=$!
sleep 1
ASSERTS="$(pmset -g assertions)"   # captured first: grep -q on a pipe would SIGPIPE pmset under pipefail
if grep -qE "pid $CAF\(caffeinate\).*PreventUserIdleDisplaySleep" <<< "$ASSERTS"; then CAF_SEEN="yes"
else NIGHT_VERDICT="ERROR — keep-awake assertion not found"; exit 70; fi
caffeinate -u -t 2
dim_light display display; DISP_LINE="$LIGHT_LINE"
dim_light kbd keyboard; KBD_LINE="$LIGHT_LINE"
REP=(); interrupted_jobs '[0-9]{8}'; [ "${#REP[@]}" = 0 ] || JOB_LINES+=("${REP[@]}")   # jobs a dead earlier run left "started"
if [ "$NO_GATE" = 1 ]; then GATE_VERDICT="gate not run (--no-gate)"; else run_gate; fi
[ "$JOBS" = 1 ] && run_jobs
exit 0
