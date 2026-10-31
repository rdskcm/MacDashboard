#!/bin/bash
# tools/visual/smoke.sh — capture the real-window smoke states (STATE_ORDER) of a bench copy of
# MacDashboard, check them for alpha holes, and diff them against tools/visual/reference/.
#
# Usage:
#   tools/visual/smoke.sh [--app PATH] [--out DIR] [--reference DIR] [--allow-old-sdk]
#   tools/visual/smoke.sh --bless RUN_DIR [STATE ...]
#   tools/visual/smoke.sh --selftest
#   tools/visual/smoke.sh -h | --help
#
# See tools/visual/README.md for the full contract (exit codes, permissions,
# thresholds, side effects). This script drives the real GUI: it moves the
# cursor and sends AX actions (no synthetic keystrokes). Do not use the Mac
# while it runs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH_ID="com.rdskcm.mac-dashboard.bench"

HELP="tools/visual/smoke.sh [--app PATH] [--out DIR] [--reference DIR] [--allow-old-sdk]
tools/visual/smoke.sh --bless RUN_DIR [STATE ...]
tools/visual/smoke.sh --selftest
tools/visual/smoke.sh -h | --help

Exit codes: 0 all alpha ok, every diff <= threshold and no text change. 1 at
least one alpha FAIL (wins over 2). 2 no alpha FAIL, but >=1 state is CHANGED,
SIZE-CHANGED, TEXT-CHANGED NO-REF or ORPHAN-REF (or its text column reads changed). 64
usage error. 65 precondition refused. 70 runtime error (the bench copy
was stopped and its state removed). --bless and --selftest exit 0 on success, 1 on refusal/failure."

usage_error() { echo "usage error: $1" >&2; echo "$HELP" >&2; exit 64; }
precondition_refused() { echo "REFUSED: $1" >&2; exit 65; }
runtime_error() { echo "RUNTIME ERROR: $1" >&2; exit 70; }

STATE_ORDER="main-dark main-glass-clear-dark main-glass-tinted-dark main-glass-rt-dark main-report-dark settings-general-dark settings-glass-rt-dark main-light main-glass-clear-light main-glass-tinted-light main-glass-rt-light main-report-light settings-general-light settings-glass-rt-light"

# edge_inset_px is 0 by default (see README §5); only changed with measured
# evidence, in a separate documented commit.
EDGE_INSET_PX=0

threshold_for_state() {
  awk -v s="$1" '
    $1 ~ /^#/ { next }
    $1 == s { print $2; found = 1; exit }
    $1 == "default" { def = $2 }
    END { if (!found) print def }
  ' "$ROOT/tools/visual/thresholds.txt"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE="run"
APP="$ROOT/dist.noindex/MacDashboard.app"
OUT=""
REFERENCE="$ROOT/tools/visual/reference"
ALLOW_OLD_SDK=0
BLESS_RUN_DIR=""
BLESS_STATES=""

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "$HELP"
  exit 0
fi
if [ "${1:-}" = "--selftest" ]; then
  MODE="selftest"
  shift
elif [ "${1:-}" = "--bless" ]; then
  MODE="bless"
  shift
  [ $# -ge 1 ] || usage_error "--bless needs RUN_DIR"
  BLESS_RUN_DIR="$1"
  shift
  BLESS_STATES="$*"
else
  while [ $# -gt 0 ]; do
    case "$1" in
      --app) [ $# -ge 2 ] || usage_error "--app needs a value"; APP="$2"; shift 2 ;;
      --out) [ $# -ge 2 ] || usage_error "--out needs a value"; OUT="$2"; shift 2 ;;
      --reference) [ $# -ge 2 ] || usage_error "--reference needs a value"; REFERENCE="$2"; shift 2 ;;
      --allow-old-sdk) ALLOW_OLD_SDK=1; shift ;;
      -h|--help) echo "$HELP"; exit 0 ;;
      *) usage_error "unknown argument: $1" ;;
    esac
  done
fi

DATESTAMP="$(date +%Y%m%d-%H%M%S)"
if [ -z "$OUT" ]; then OUT="$ROOT/tools/visual/out/$DATESTAMP"; fi

# ---------------------------------------------------------------------------
# --selftest: no GUI, no permissions, no OUT dir needed
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  TMPBIN="$(mktemp -d /tmp/vbtool-selftest.XXXXXX)"
  trap 'rm -rf "$TMPBIN"' EXIT
  swiftc -O -o "$TMPBIN/vbtool" "$ROOT/tools/visual/vbtool.swift" -framework AppKit -framework Vision
  "$TMPBIN/vbtool" selftest
  exit $?
fi

# ---------------------------------------------------------------------------
# --bless RUN_DIR [STATE...]
# ---------------------------------------------------------------------------
if [ "$MODE" = "bless" ]; then
  RUN_DIR="$BLESS_RUN_DIR"
  [ -d "$RUN_DIR" ] || usage_error "bless: not a directory: $RUN_DIR"
  [ -f "$RUN_DIR/results.tsv" ] || usage_error "bless: missing results.tsv in $RUN_DIR"
  [ -f "$RUN_DIR/build-info.txt" ] || usage_error "bless: missing build-info.txt in $RUN_DIR"

  if grep -q '^sdk_gate: overridden$' "$RUN_DIR/build-info.txt"; then
    echo "REFUSED: bless: this run's SDK gate was overridden (sdk_gate: overridden)" >&2
    exit 1
  fi
  if grep -q '^foreign_copies: TEST ONLY' "$RUN_DIR/build-info.txt"; then
    echo "REFUSED: bless: this run ran beside foreign MacDashboard processes (foreign_copies: TEST ONLY)" >&2
    exit 1
  fi

  # Collect candidate states with their alpha verdict from results.tsv (skip header).
  BLESS_LIST="$BLESS_STATES"
  if [ -z "$BLESS_LIST" ]; then
    BLESS_LIST="$STATE_ORDER"
  fi

  # Refuse (read-only check, nothing written yet) if any candidate fails the alpha check.
  # Collect ALL failing states before refusing, so the caller sees the whole set at once.
  FAILED_STATES=""
  for st in $BLESS_LIST; do
    line="$(awk -F'\t' -v s="$st" 'NR>1 && $1==s{print}' "$RUN_DIR/results.tsv")"
    if [ -z "$line" ]; then
      echo "REFUSED: bless: state not found in results.tsv: $st" >&2
      exit 1
    fi
    [ "$(printf '%s' "$line" | awk -F'\t' '{print $8}')" = "ORPHAN-REF" ] && continue
    alpha_v="$(printf '%s' "$line" | awk -F'\t' '{print $2}')"
    [ "$alpha_v" = "ok" ] || FAILED_STATES="$FAILED_STATES $st(alpha=$alpha_v)"
  done
  if [ -n "$FAILED_STATES" ]; then
    echo "REFUSED: bless: states with alpha != ok:$FAILED_STATES" >&2
    exit 1
  fi

  # Only now, having refused any bad candidate, create/touch the reference dir.
  REF_DIR="$ROOT/tools/visual/reference"
  mkdir -p "$REF_DIR"
  MANIFEST="$REF_DIR/manifest.txt"
  if [ ! -f "$MANIFEST" ]; then
    printf '# state\tblessed\tmacos\tsdk\tcommit\n' > "$MANIFEST"
  fi

  GIT_COMMIT="$(awk -F': ' '/^git_commit:/{print $2}' "$RUN_DIR/build-info.txt" | head -1)"
  MACOS_V="$(awk -F': ' '/^macos:/{print $2}' "$RUN_DIR/build-info.txt" | head -1)"
  SDK_V="$(awk -F': ' '/^sdk_major:/{print $2}' "$RUN_DIR/build-info.txt" | head -1)"
  TODAY="$(date +%Y-%m-%d)"

  for st in $BLESS_LIST; do
    if [ "$(awk -F'\t' -v s="$st" 'NR>1 && $1==s{print $8}' "$RUN_DIR/results.tsv")" = "ORPHAN-REF" ]; then
      rm -f "$REF_DIR/$st.png"
      TMPM="$(mktemp)"
      awk -v s="$st" -F'\t' '$1!=s{print}' "$MANIFEST" > "$TMPM"; mv "$TMPM" "$MANIFEST"
      echo "blessed: $st (reference deleted)"
      continue
    fi
    cp "$RUN_DIR/norm/$st.png" "$REF_DIR/$st.png"
    NEWLINE="$(printf '%s\t%s\t%s\t%s\t%s' "$st" "$TODAY" "$MACOS_V" "$SDK_V" "$GIT_COMMIT")"
    if grep -q "^$st"$'\t' "$MANIFEST" 2>/dev/null; then
      TMPM="$(mktemp)"
      awk -v s="$st" -v nl="$NEWLINE" -F'\t' 'BEGIN{OFS="\t"} $1==s{print nl; next} {print}' "$MANIFEST" > "$TMPM"
      mv "$TMPM" "$MANIFEST"
    else
      echo "$NEWLINE" >> "$MANIFEST"
    fi
    echo "blessed: $st"
  done
  exit 0
fi

# ---------------------------------------------------------------------------
# Full run
# ---------------------------------------------------------------------------

# Precondition 1: --app
if [ ! -d "$APP" ]; then
  usage_error "--app is not a directory: $APP"
fi
APP_BIN="$APP/Contents/MacOS/MacDashboard"
if [ ! -x "$APP_BIN" ]; then
  usage_error "--app binary is not executable: $APP_BIN"
fi

PIXEL_TOLERANCE="$(awk '$1=="pixel_tolerance"{print $2}' "$ROOT/tools/visual/thresholds.txt")"

# Precondition 2: screen not locked. A locked session puts no app window on
# screen, so the window lookup would fail later with "got 0". IOConsoleLocked
# absent, or ioreg failing, counts as unlocked.
IOREG_ROOT="$(ioreg -n Root -d1 2>/dev/null || true)"
LOCK_RE='"IOConsoleLocked" *= *Yes'
if [[ "$IOREG_ROOT" =~ $LOCK_RE ]]; then
  precondition_refused "the screen is locked — unlock it and run again"
fi

# Precondition 3: no MacDashboard process this run did not start (tools/perf/foreign-copies.sh list, as gate.sh;
# GATE-AX-MISS): a window behind the bench window changes the glass backdrop, and a leftover bench copy is what took
# the 2026-10-30 night gate's presses. smoke never closes one (night.sh does). SMOKE_TEST_ALLOW_FOREIGN=1 runs beside
# them instead — for the SMOKE-AX-PID verification only; --bless refuses such a run.
FOREIGN="$("$ROOT/tools/perf/foreign-copies.sh" list)" || runtime_error "tools/perf/foreign-copies.sh list failed"
FOREIGN_NOTE="none"
if [ -n "$FOREIGN" ]; then
  FOREIGN_ONE="$(paste -sd ';' - <<< "$FOREIGN" | sed 's/;/; /g')"
  if [ "${SMOKE_TEST_ALLOW_FOREIGN:-0}" = 1 ]; then
    FOREIGN_NOTE="TEST ONLY (SMOKE_TEST_ALLOW_FOREIGN=1): running beside MacDashboard process(es) this run did not start (pid ppid started command): $FOREIGN_ONE"
    echo "smoke: $FOREIGN_NOTE" >&2
  else
    precondition_refused "MacDashboard process(es) this run did not start are running (pid ppid started command): $FOREIGN_ONE — quit them and run again (smoke never closes them)"
  fi
fi

# Precondition 4: SDK gate
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
SDK_MAJOR="$(vtool -show-build "$APP_BIN" 2>/dev/null | awk '$1=="sdk"{print $2}' | cut -d. -f1 | sort -n | head -1)"
SDK_GATE="passed"
if [ -z "$SDK_MAJOR" ]; then
  runtime_error "vtool -show-build produced no sdk line for $APP_BIN"
fi
if [ "$SDK_MAJOR" -lt "$OS_MAJOR" ]; then
  if [ "$ALLOW_OLD_SDK" -eq 1 ]; then
    SDK_GATE="overridden"
  else
    precondition_refused "app SDK major ($SDK_MAJOR) is lower than running macOS major ($OS_MAJOR); pass --allow-old-sdk to override"
  fi
fi

# Compile the helper (also needed for preflight / accessibility checks below).
# Built into a scratch dir first — R7: no run directory exists yet, so a
# precondition refusal below leaves nothing behind. Moved into $OUT/.bin once
# every precondition has passed (after precondition 8).
TMPBIN="$(mktemp -d /tmp/vbtool-run.XXXXXX)"
trap 'rm -rf "$TMPBIN"' EXIT
VBTOOL="$TMPBIN/vbtool"
if ! swiftc -O -o "$VBTOOL" "$ROOT/tools/visual/vbtool.swift" -framework AppKit -framework Vision; then
  runtime_error "vbtool compile failed"
fi
# The AX helper of the perf gate (tools/perf/ax.swift, native AX by pid), compiled fresh with gate.sh's flags.
AXHELPER="$TMPBIN/ax"
if ! swiftc -O "$ROOT/tools/perf/ax.swift" -o "$AXHELPER" -module-cache-path "$TMPBIN/modcache" > "$TMPBIN/ax.build.log" 2>&1; then
  runtime_error "ax.swift compile failed: $(tail -5 "$TMPBIN/ax.build.log")"
fi

# Precondition 5: Screen Recording
if ! "$VBTOOL" preflight >/dev/null 2>&1; then
  precondition_refused "grant Screen Recording to the terminal running this tool"
fi

# Precondition 6: Accessibility (the grant of the terminal app; the AX calls are made by the ax helper)
if [ "$("$AXHELPER" 0 trusted 2>&1)" != trusted ]; then
  precondition_refused "Accessibility is not enabled for the terminal app (AXIsProcessTrusted is false)"
fi

# Precondition 7: cliclick
CLICLICK="$(command -v cliclick || true)"
if [ -z "$CLICLICK" ] && [ -x /opt/homebrew/bin/cliclick ]; then
  CLICLICK=/opt/homebrew/bin/cliclick
fi
if [ -z "$CLICLICK" ]; then
  precondition_refused "cliclick not found"
fi

# Precondition 8: staleness warning (default dist app only)
if [ "$APP" = "$ROOT/dist.noindex/MacDashboard.app" ]; then
  STALE="$(find "$ROOT/Sources" -newer "$APP_BIN" -print -quit 2>/dev/null || true)"
  if [ -n "$STALE" ]; then
    echo "WARNING: dist build is older than Sources/ — run ./build_app.sh"
  fi
fi

# Every precondition passed: now it is safe to create the run directory and
# hand vbtool over to it (R7).
mkdir -p "$OUT/raw" "$OUT/norm" "$OUT/diff" "$OUT/text" "$OUT/.bin"
mv "$TMPBIN/vbtool" "$OUT/.bin/vbtool"
VBTOOL="$OUT/.bin/vbtool"
mv "$TMPBIN/ax" "$OUT/.bin/ax"
AXHELPER="$OUT/.bin/ax"
ax() { "$AXHELPER" "$PID" "$@" 2>&1; }   # native AX by pid (tools/perf/ax.swift), never a process lookup by name (GATE-AX-MISS)
is_frame() { [[ "$1" =~ ^-?[0-9]+\ -?[0-9]+\ [0-9]+\ [0-9]+$ ]]; }
# "pid <n> (<executable>)" of the frontmost application, for diagnostics.
focused_app() { local p; p="$("$AXHELPER" 0 focused 2>&1)"; echo "pid $p ($(ps -o comm= -p "$p" 2>/dev/null || echo "?"))"; }
rm -rf "$TMPBIN"

# ---------------------------------------------------------------------------
# build-info.txt
# ---------------------------------------------------------------------------
GIT_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then GIT_COMMIT="${GIT_COMMIT}-dirty"; fi
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
VTOOL_OUT="$(vtool -show-build "$APP_BIN" 2>&1 || true)"
SWVERS_OUT="$(sw_vers)"
XCODEBUILD_V="$(xcodebuild -version 2>/dev/null | head -1 || true)"
if [ -z "$XCODEBUILD_V" ]; then XCODEBUILD_V="none (CLT only)"; fi
XCODE_SELECT_P="$(xcode-select -p 2>&1 || true)"
SDK_VERSION="$(xcrun --show-sdk-version 2>&1 || true)"
SWIFT_V="$(swift --version 2>&1 | head -1 || true)"

SCREEN_LINE="$("$VBTOOL" screen)"
REDUCE_TRANSPARENCY="$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo 0)"
INCREASE_CONTRAST="$(defaults read com.apple.universalaccess increaseContrast 2>/dev/null || echo 0)"
ACCENT_COLOR="$(defaults read -g AppleAccentColor 2>/dev/null || echo multicolor)"
SCROLLBARS_GLOBAL="$(defaults read -g AppleShowScrollBars 2>/dev/null || echo unset)"
THRESHOLDS_CONTENTS="$(cat "$ROOT/tools/visual/thresholds.txt")"

{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_commit: $GIT_COMMIT"
  echo "app_path: $APP"
  echo "app_version: $SHORT_VERSION"
  echo "sdk_major: $SDK_MAJOR"
  echo "os_major: $OS_MAJOR"
  echo "sdk_gate: $SDK_GATE"
  echo "macos: $(sw_vers -productVersion)"
  echo "xcodebuild_version: $XCODEBUILD_V"
  echo "xcode_select_p: $XCODE_SELECT_P"
  echo "sdk_shown_version: $SDK_VERSION"
  echo "swift_version: $SWIFT_V"
  echo "screen_wh_scale_vx_vy_vw_vh: $SCREEN_LINE"
  echo "reduce_transparency: $REDUCE_TRANSPARENCY"
  echo "increase_contrast: $INCREASE_CONTRAST"
  echo "accent_color: $ACCENT_COLOR"
  echo "language: en (pinned via argument domain)"
  echo "scrollbars: WhenScrolling (pinned via argument domain; global=$SCROLLBARS_GLOBAL)"
  echo "fixture: visualFixture"
  echo "bench: $BENCH_ID copy at $OUT/app, home $OUT/home"
  echo "foreign_copies: $FOREIGN_NOTE"
  echo "appearance: in-app (visualAppearance fixture key)"
  echo "alpha_params: corner_pt=32 edge_inset_px=0"
  echo "--- thresholds.txt ---"
  echo "$THRESHOLDS_CONTENTS"
  echo "--- sw_vers ---"
  echo "$SWVERS_OUT"
  echo "--- vtool -show-build ---"
  echo "$VTOOL_OUT"
} > "$OUT/build-info.txt"

# ---------------------------------------------------------------------------
# Bench state (nothing of the user's is touched)
# ---------------------------------------------------------------------------
LAUNCHED_PID=""; MAIN_ID=""; SET_ID=""; CLEANED=0
CURSOR0="$("$VBTOOL" cursor)"
FRONT_PID0="$("$AXHELPER" 0 focused 2>&1 || echo none)"   # restored by pid in cleanup (never by bundle id or name)
BENCH_SAVED_STATE="$HOME/Library/Saved Application State/$BENCH_ID.savedState"

# Nothing of the user's is changed by this run, so cleanup only stops the bench copy and removes bench-only state.
cleanup() {
  [ "$CLEANED" = 1 ] && return 0
  CLEANED=1
  if [ -n "$LAUNCHED_PID" ] && kill -0 "$LAUNCHED_PID" 2>/dev/null; then
    kill -TERM "$LAUNCHED_PID" 2>/dev/null; sleep 2
    kill -0 "$LAUNCHED_PID" 2>/dev/null && kill -KILL "$LAUNCHED_PID" 2>/dev/null
  fi
  defaults delete "$BENCH_ID" >/dev/null 2>&1 || true
  rm -rf "$BENCH_SAVED_STATE" "$OUT/app"
  # Running the bench binary registered the copy with LaunchServices (LS-PRUNE-MISSES); drop the record of
  # the copy just deleted. A prune failure only warns: it never changes this script's exit code.
  if [ -n "$LAUNCHED_PID" ]; then
    "$ROOT/tools/ls-prune.sh" >/dev/null 2>&1 || echo "WARNING: tools/ls-prune.sh exited $? — a bench copy may still be registered" >&2
  fi
  IFS=' ' read -r cx0 cy0 <<< "$CURSOR0"
  "$CLICLICK" "m:${cx0%.*},${cy0%.*}" >/dev/null 2>&1 || true
  case "$FRONT_PID0" in ''|none|"$LAUNCHED_PID") ;; *) "$AXHELPER" "$FRONT_PID0" front >/dev/null 2>&1 || true ;; esac
}
trap cleanup EXIT
trap 'echo "INTERRUPTED"; cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
BENCH_APP="$("$ROOT/tools/bench-app.sh" "$APP" "$OUT/app")" || runtime_error "bench copy of $APP failed"
mkdir -p "$OUT/home"
defaults delete "$BENCH_ID" >/dev/null 2>&1 || true
rm -rf "$BENCH_SAVED_STATE"
defaults write "$BENCH_ID" visualAppearance -string dark
# Overlay scrollers, language and no state restoration for this process only (argument domain, never persisted).
CFFIXED_USER_HOME="$OUT/home" "$BENCH_APP/Contents/MacOS/MacDashboard" -appLanguage en -AppleLanguages "(en)" \
  -AppleShowScrollBars WhenScrolling -ApplePersistenceIgnoreState YES -visualFixture 1 > "$OUT/app.log" 2>&1 &
PID=$!
LAUNCHED_PID="$PID"

waited=0
WINDOWS_OUT=""
# A binary started directly (not through LaunchServices) opens its window only once it is activated.
while [ "$waited" -lt 20 ]; do
  ax front >/dev/null || true
  WINDOWS_OUT="$("$VBTOOL" windows --pid "$PID" || true)"
  COUNT="$(printf '%s\n' "$WINDOWS_OUT" | grep -c . || true)"
  if [ "$COUNT" -eq 1 ]; then break; fi
  sleep 1
  waited=$((waited + 1))
done
COUNT="$(printf '%s\n' "$WINDOWS_OUT" | grep -c . || true)"
if [ "$COUNT" -ne 1 ]; then runtime_error "expected exactly one window for pid $PID, got $COUNT"; fi
MAIN_ID="$(printf '%s\n' "$WINDOWS_OUT" | awk '{print $1}')"

SCREEN_NOW="$("$VBTOOL" screen)"
read -r SW SH SSCALE SVX SVY SVW SVH <<EOF_SCR
$SCREEN_NOW
EOF_SCR
# Main window height: H = min(780, screen_frame_h - 150) (amended 2026-09-24,
# twice: the original fixed 780 pt cannot fit the bench Mac's 1280x741 pt
# visible frame; and the visible frame height (vh) drifts 1-2 pt between
# runs, which made H non-deterministic and produced false SIZE-CHANGED -- so
# H is derived from the full screen frame height (SH), which is stable).
H="$(awk -v sh="$SH" 'BEGIN{h=sh-150; if(h>780)h=780; printf "%d", h}')"
if awk -v w="$SVW" -v h="$H" -v vh="$SVH" 'BEGIN{exit !(w<1260 || h<620 || h>vh-40)}'; then
  runtime_error "screen too small (visible frame ${SVW}x${SVH} pt, screen frame h ${SH} pt, need vw>=1260, H>=620, H<=vh-40)"
fi
echo "main_window_pt: 1150x${H}" >> "$OUT/build-info.txt"
POS_X="$(awk -v v="$SVX" 'BEGIN{printf "%d", v+20}')"
POS_Y="$(awk -v v="$SVY" 'BEGIN{printf "%d", v+20}')"

# The window is listed by CGWindowList before AX can address it: retry for up to 10 tries (ax place itself polls 2 s).
sized=0; PLACE_OUT=""
for _try in 1 2 3 4 5 6 7 8 9 10; do
  ax front >/dev/null || true
  PLACE_OUT="$(ax place "$POS_X,$POS_Y,1150,$H")" || true
  case "$PLACE_OUT" in
    placed) sized=1; break ;;
    off\ *) echo "WARNING: the bench window settled at ${PLACE_OUT#off } instead of $POS_X $POS_Y 1150 $H" >&2; sized=1; break ;;
  esac
  sleep 1
done
[ "$sized" = 1 ] || runtime_error "could not position and size the bench window by AX (last answer: $PLACE_OUT)"

LAUNCH_SETTLE=10
sleep "$LAUNCH_SETTLE"

# ---------------------------------------------------------------------------
# Helpers used during capture
# ---------------------------------------------------------------------------
window_bounds() {
  # $1 = window id -> echoes "x y w h" from a fresh vbtool windows listing
  "$VBTOOL" windows --pid "$PID" | awk -v id="$1" '$1==id{print $2, $3, $4, $5}'
}

within() {
  awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=1)}'
}

assert_key() {
  local wid="$1"
  local context="$2"
  ax front >/dev/null || true
  local waited_ms=0
  local printed=0
  local last_reason="no window bounds yet"
  while true; do
    local wb
    wb="$(window_bounds "$wid")"
    if [ -n "$wb" ]; then
      local fp out
      fp="$("$AXHELPER" 0 focused 2>&1)"
      if [ "$fp" != "$PID" ]; then
        last_reason="notfront (focused pid $fp)"
      else
        out="$(ax main)"
        if ! is_frame "$out"; then
          last_reason="$out"
        else
          local px py pw ph bx by bw bh
          read -r px py pw ph <<< "$out"
          read -r bx by bw bh <<< "$wb"
          if within "$px" "$bx" && within "$py" "$by" && within "$pw" "$bw" && within "$ph" "$bh"; then
            return 0
          fi
          last_reason="bounds AX=$px $py $pw $ph CG=$bx $by $bw $bh"
        fi
      fi
    else
      last_reason="no window bounds for wid=$wid"
    fi
    if [ "$printed" -eq 0 ]; then
      echo "waiting for MacDashboard to become key (front app: $(focused_app)) — answer any system prompt"
      printed=1
    fi
    sleep 0.5
    waited_ms=$((waited_ms + 500))
    if [ "$waited_ms" -ge 30000 ]; then
      runtime_error "assert_key timeout: wid=$wid context=$context reason=$last_reason front app: $(focused_app)"
    fi
  done
}

park_cursor() {
  # $* = window ids to avoid (current windows of the PID)
  local avoid_args=()
  local wl
  wl="$("$VBTOOL" windows --pid "$PID" || true)"
  local IFS_OLD="$IFS"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local wx wy ww wh
    read -r _ wx wy ww wh <<< "$line"
    avoid_args+=(--avoid "$wx,$wy,$ww,$wh")
  done <<< "$wl"
  IFS="$IFS_OLD"
  local pt
  pt="$("$VBTOOL" park-point "${avoid_args[@]}")" || runtime_error "park-point failed"
  "$CLICLICK" "m:$pt" >/dev/null 2>&1 || runtime_error "cliclick park failed"
}

# Drive the main window via an AX press on a button (VISUAL-COVERAGE, R4; Amendment 1; REDESIGN-HOME) — never a
# coordinate click or keystroke. `AXIdentifier` (set via `.accessibilityIdentifier`) is the language-independent
# handle. All AX goes through tools/perf/ax.swift addressed by $PID (SMOKE-AX-PID): a lookup by process (System
# Events `first process whose unix id is`) returned another MacDashboard process's windows when two ran (GATE-AX-MISS).
# On a miss the tree of the pid's window 1 is written to $OUT/ax-dump-<id>.txt.
press_main_tab() {
  local axid="$1" out
  out="$(ax id "$axid")"
  case "$out" in
    pressed) ;;
    "NOT FOUND")
      ax dump > "$OUT/ax-dump-$axid.txt"
      runtime_error "press_main_tab: AXIdentifier '$axid' not found in pid $PID; identifiers seen: $OUT/ax-dump-$axid.txt" ;;
    *) runtime_error "press_main_tab: ax id '$axid' answered: $out" ;;
  esac
}

# wait_ax_id present|absent AXIDENTIFIER SECONDS — polls window 1 of $PID every 0.5 s for an element of any role with
# that AXIdentifier (ax exists); 0 when the wanted state is reached, 1 on timeout (D12).
wait_ax_id() {
  local want="$1" axid="$2" secs="$3" n=0 state
  while :; do
    state="$(ax exists "$axid")"
    [ "$state" = "$want" ] && return 0
    n=$((n + 1)); [ "$n" -ge $((secs * 2)) ] && return 1
    sleep 0.5
  done
}

# Open Settings via an AX press on the app-menu item whose title starts with "Settings" (amended 2026-09-24:
# synthetic keystrokes proved intermittent, so no keystrokes at all). Never falls back to keystrokes.
open_settings() {
  local out
  out="$(ax appmenu Settings)"
  case "$out" in
    pressed) ;;
    "NOT FOUND"*) runtime_error "Settings menu item not found via AX; menu items seen: ${out#NOT FOUND: }" ;;
    *) runtime_error "open_settings: ax appmenu answered: $out" ;;
  esac
}

# Close Settings via an AX press on the AXCloseButton of the pid's window whose frame matches the Settings window's
# CG bounds (amended 2026-09-24; Cmd+W sometimes left Settings open).
close_settings() {
  local wid="$1" wb bx by bw bh out
  wb="$(window_bounds "$wid")"
  [ -n "$wb" ] || runtime_error "close_settings: no bounds for window $wid"
  read -r bx by bw bh <<< "$wb"
  out="$(ax closewin "$bx,$by,$bw,$bh")"
  case "$out" in
    pressed) ;;
    "no window") runtime_error "close_settings: no AX window of pid $PID matching Settings bounds ($bx,$by,$bw,$bh)" ;;
    "NOT FOUND") runtime_error "close_settings: AXCloseButton not found on Settings window" ;;
    *) runtime_error "close_settings: ax closewin answered: $out" ;;
  esac
}



STATE_NAMES=()
STATE_BOUNDS=()

capture_state() {
  local name="$1"
  local wid="$2"
  local wb
  wb="$(window_bounds "$wid")"
  [ -n "$wb" ] || runtime_error "capture_state: no bounds for window $wid ($name)"
  if ! screencapture -x -o -l "$wid" "$OUT/raw/$name.png"; then
    runtime_error "screencapture failed for $name"
  fi
  if [ ! -f "$OUT/raw/$name.png" ]; then
    runtime_error "screencapture produced no file for $name"
  fi
  STATE_NAMES+=("$name")
  STATE_BOUNDS+=("$wb")
}

# Captures the window's screen rectangle instead of the window itself: a sheet is a separate NSWindow, so
# `screencapture -l <main id>` would not include it. The region is opaque, so `vbtool alpha-check` reads "ok"
# trivially for these states; the glass-alpha guard concerns the window's own surface, which every other
# main-* state still checks.
capture_region_state() {
  local name="$1"
  local wid="$2"
  local wb x y w h
  wb="$(window_bounds "$wid")"
  [ -n "$wb" ] || runtime_error "capture_region_state: no bounds for window $wid ($name)"
  read -r x y w h <<<"$wb"
  if ! screencapture -x -o -R "$x,$y,$w,$h" "$OUT/raw/$name.png"; then
    runtime_error "screencapture failed for $name"
  fi
  if [ ! -f "$OUT/raw/$name.png" ]; then
    runtime_error "screencapture produced no file for $name"
  fi
  STATE_NAMES+=("$name")
  STATE_BOUNDS+=("$wb")
}

# ---------------------------------------------------------------------------
# Capture sequence
# ---------------------------------------------------------------------------
for mode in dark light; do
  defaults write "$BENCH_ID" visualAppearance -string "$mode"
  sleep 2

  assert_key "$MAIN_ID" "main-$mode"
  park_cursor
  sleep 1.5
  capture_state "main-$mode" "$MAIN_ID"

  # Glass at the Liquid Glass slider's two ends and under Reduce Transparency (fixture-only keys, live via KVO).
  for gs in clear tinted rt; do
    case "$gs" in
      clear)  defaults write "$BENCH_ID" visualGlassTintAmount -float 0 ;;
      tinted) defaults write "$BENCH_ID" visualGlassTintAmount -float 1 ;;
      rt)     defaults delete "$BENCH_ID" visualGlassTintAmount >/dev/null 2>&1 || true
              defaults write "$BENCH_ID" visualReduceTransparency -bool true ;;
    esac
    sleep 1.5
    assert_key "$MAIN_ID" "main-glass-$gs-$mode"
    capture_state "main-glass-$gs-$mode" "$MAIN_ID"
  done
  defaults delete "$BENCH_ID" visualGlassTintAmount >/dev/null 2>&1 || true
  defaults delete "$BENCH_ID" visualReduceTransparency >/dev/null 2>&1 || true
  sleep 1.5

  # Report: one press opens the sheet (its own window), verified by the sheet's identifier and by a second CGWindow
  # for the pid; the capture is the main window's screen rect, which the sheet lies inside (R6). Never a second blind press.
  assert_key "$MAIN_ID" "main-report-$mode"
  press_main_tab main-report
  wait_ax_id present report-sheet 5 || runtime_error "report sheet did not open within 5 s of pressing main-report ($mode)"
  SHEET_COUNT="$("$VBTOOL" windows --pid "$PID" | grep -c . || true)"
  [ "$SHEET_COUNT" -eq 2 ] || runtime_error "expected the main window and the report sheet (2 windows), got $SHEET_COUNT ($mode)"
  park_cursor
  sleep 1.5
  assert_key "$MAIN_ID" "main-report-$mode"
  capture_region_state "main-report-$mode" "$MAIN_ID"
  press_main_tab report-done
  wait_ax_id absent report-sheet 5 || runtime_error "report sheet still open 5 s after pressing report-done ($mode); not pressing again"
  sleep 1

  # Settings window: General (the pane it opens on).
  assert_key "$MAIN_ID" "open-settings-$mode"
  open_settings

  waited=0
  SET_ID=""
  while [ "$waited" -lt 5 ]; do
    wl="$("$VBTOOL" windows --pid "$PID" || true)"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      wid="$(printf '%s' "$line" | awk '{print $1}')"
      if [ "$wid" != "$MAIN_ID" ]; then SET_ID="$wid"; fi
    done <<< "$wl"
    if [ -n "$SET_ID" ]; then break; fi
    sleep 1
    waited=$((waited + 1))
  done
  [ -n "$SET_ID" ] || runtime_error "Settings window did not appear"
  sleep 1.5

  SETB="$(window_bounds "$SET_ID")"
  read -r SETX SETY SETW SETH <<< "$SETB"
  if ! awk -v w="$SETW" 'BEGIN{d=w-680; if(d<0)d=-d; exit !(d<=2)}'; then
    runtime_error "unexpected Settings window width: $SETW"
  fi
  T="$(awk -v h="$SETH" 'BEGIN{printf "%.2f", h-420}')"

  park_cursor
  sleep 1.5
  assert_key "$SET_ID" "settings-general-$mode"
  capture_state "settings-general-$mode" "$SET_ID"
  # Settings cards under Reduce Transparency (fixture-only key, live via KVO; CARD-GLASS-LEFTOVERS).
  defaults write "$BENCH_ID" visualReduceTransparency -bool true
  sleep 1.5
  assert_key "$SET_ID" "settings-glass-rt-$mode"
  capture_state "settings-glass-rt-$mode" "$SET_ID"
  defaults delete "$BENCH_ID" visualReduceTransparency >/dev/null 2>&1 || true
  sleep 1.5

  assert_key "$SET_ID" "close-settings-$mode"
  close_settings "$SET_ID"
  waited=0
  while [ "$waited" -lt 5 ]; do
    wl="$("$VBTOOL" windows --pid "$PID" || true)"
    if ! printf '%s\n' "$wl" | awk '{print $1}' | grep -qx "$SET_ID"; then break; fi
    sleep 1
    waited=$((waited + 1))
  done
  if printf '%s\n' "$wl" | awk '{print $1}' | grep -qx "$SET_ID"; then
    runtime_error "Settings window $SET_ID still open 5 s after close_settings"
  fi
done

# ---------------------------------------------------------------------------
# Per-state processing
# ---------------------------------------------------------------------------
RESULTS="$OUT/results.tsv"
printf 'state\talpha\thole_px\tbbox_pt\tregions\tdiff_pct\tthreshold\tverdict\ttext\n' > "$RESULTS"

ANY_ALPHA_FAIL=0
ANY_CHANGE=0

EXPECTED_STATES=$(printf '%s\n' $STATE_ORDER | grep -c .)
[ "${#STATE_NAMES[@]}" -eq "$EXPECTED_STATES" ] || runtime_error "captured ${#STATE_NAMES[@]} states, STATE_ORDER has $EXPECTED_STATES"

i=0
while [ "$i" -lt "${#STATE_NAMES[@]}" ]; do
  st="${STATE_NAMES[$i]}"
  wb="${STATE_BOUNDS[$i]}"
  i=$((i + 1))
  read -r bx by bw bh <<< "$wb"

  ALPHA_LINE="$("$VBTOOL" alpha-check "$OUT/raw/$st.png" --points "${bw}x${bh}" --corner-pt 32 --edge-inset-px "$EDGE_INSET_PX" || true)"
  ALPHA_OK="ok"
  if ! printf '%s\n' "$ALPHA_LINE" | grep -q '^ALPHA ok'; then ALPHA_OK="FAIL"; ANY_ALPHA_FAIL=1; fi
  HOLE_PX="$(printf '%s\n' "$ALPHA_LINE" | grep '^ALPHA' | sed -n 's/.*hole_px=\([0-9]*\).*/\1/p')"
  BBOX_PT="$(printf '%s\n' "$ALPHA_LINE" | grep '^ALPHA' | sed -n 's/.*bbox_pt=\([^ ]*\).*/\1/p')"
  REGIONS="$(printf '%s\n' "$ALPHA_LINE" | grep '^ALPHA' | sed -n 's/.*regions=\([^ ]*\).*/\1/p')"

  "$VBTOOL" downscale "$OUT/raw/$st.png" "$OUT/norm/$st.png" --size "${bw}x${bh}" || runtime_error "downscale failed for $st"

  DIFF_PCT="0.00"
  VERDICT="same"
  THRESH="$(threshold_for_state "$st")"
  TEXT="n/a"

  if [ -f "$REFERENCE/$st.png" ]; then
    DIFF_LINE="$("$VBTOOL" diff "$REFERENCE/$st.png" "$OUT/norm/$st.png" --tol "$PIXEL_TOLERANCE" --mask "$OUT/diff/$st.png")"
    if printf '%s\n' "$DIFF_LINE" | grep -q 'size=ref'; then
      VERDICT="SIZE-CHANGED"
      DIFF_PCT="100.00"
      ANY_CHANGE=1
    else
      DIFF_PCT="$(printf '%s\n' "$DIFF_LINE" | sed -n 's/.*pct=\([0-9.]*\).*/\1/p')"
      if awk -v p="$DIFF_PCT" -v t="$THRESH" 'BEGIN{exit !(p>t)}'; then
        VERDICT="CHANGED"
        ANY_CHANGE=1
      else
        VERDICT="same"
      fi
    fi
    # Text check (VISUAL-TEXT-DRIFT): OCR of reference vs capture, independent of diff_pct.
    TEXT_LINE="$("$VBTOOL" text-diff "$REFERENCE/$st.png" "$OUT/norm/$st.png" --out "$OUT/text/$st.txt")" \
      || runtime_error "text-diff failed for $st"
    printf '%s\t%s\n' "$st" "$TEXT_LINE" >> "$OUT/text/summary.txt"
    case "$TEXT_LINE" in
      "TEXT same"*) TEXT="same" ;;
      "TEXT changed"*)
        TEXT="changed"
        ANY_CHANGE=1
        if [ "$VERDICT" = "same" ]; then VERDICT="TEXT-CHANGED"; fi
        ;;
      *) runtime_error "text-diff printed no TEXT line for $st: $TEXT_LINE" ;;
    esac
  else
    VERDICT="NO-REF"
    DIFF_PCT="n/a"
    ANY_CHANGE=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "$ALPHA_OK" "$HOLE_PX" "$BBOX_PT" "$REGIONS" "$DIFF_PCT" "$THRESH" "$VERDICT" "$TEXT" >> "$RESULTS"
done

# A reference whose state is no longer in STATE_ORDER is an ORPHAN-REF (R7); --bless of it deletes the file.
for f in "$REFERENCE"/*.png; do
  [ -e "$f" ] || continue
  ost="$(basename "$f" .png)"
  case " $STATE_ORDER " in *" $ost "*) continue ;; esac
  printf '%s\tn/a\t-\t-\t-\tn/a\t-\tORPHAN-REF\tn/a\n' "$ost" >> "$RESULTS"
  ANY_CHANGE=1
done

# ---------------------------------------------------------------------------
# Sanity guards
# ---------------------------------------------------------------------------
MM_LINE="$("$VBTOOL" diff "$OUT/norm/main-dark.png" "$OUT/norm/main-light.png" --tol "$PIXEL_TOLERANCE" --mask "$OUT/diff/.sanity-appearance.png" 2>&1 || true)"
MM_PCT="$(printf '%s\n' "$MM_LINE" | sed -n 's/.*pct=\([0-9.]*\).*/\1/p')"
rm -f "$OUT/diff/.sanity-appearance.png"
if [ -n "$MM_PCT" ] && awk -v p="$MM_PCT" 'BEGIN{exit !(p<=5.0)}'; then
  runtime_error "sanity: appearance switch had no effect (diff ${MM_PCT}%)"
fi

RD_LINE="$("$VBTOOL" diff "$OUT/norm/main-report-dark.png" "$OUT/norm/main-dark.png" --tol "$PIXEL_TOLERANCE" --mask "$OUT/diff/.sanity-tab.png" 2>&1 || true)"
RD_PCT="$(printf '%s\n' "$RD_LINE" | sed -n 's/.*pct=\([0-9.]*\).*/\1/p')"
rm -f "$OUT/diff/.sanity-tab.png"
if [ -n "$RD_PCT" ] && awk -v p="$RD_PCT" 'BEGIN{exit !(p<=1.0)}'; then
  runtime_error "sanity: report sheet had no visible effect (diff ${RD_PCT}%)"
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
{
  echo "MacDashboard visual baseline report"
  echo "run: $OUT"
  cat "$RESULTS" | column -t -s "$(printf '\t')"
  echo
  echo "reference provenance (manifest vs. current):"
  CUR_MACOS="$(sw_vers -productVersion)"
  CUR_MACOS_MAJOR="${CUR_MACOS%%.*}"
  awk -F'\t' -v ref="$REFERENCE/manifest.txt" -v cur_macos="$CUR_MACOS" \
      -v cur_macos_major="$CUR_MACOS_MAJOR" -v cur_sdk="$SDK_MAJOR" '
    BEGIN {
      while ((getline line < ref) > 0) {
        if (line ~ /^#/ || line == "") continue
        split(line, f, "\t")
        blessed[f[1]] = f[2]; refmacos[f[1]] = f[3]; refsdk[f[1]] = f[4]
        seen[f[1]] = 1
      }
      close(ref)
    }
    NR == 1 { next }  # header row
    {
      st = $1
      if (!(st in seen)) { print st"  (no manifest entry)"; next }
      rm = refmacos[st]; rs = refsdk[st]
      rmajor = rm; sub(/\..*/, "", rmajor)
      same = (rmajor == cur_macos_major && rs == cur_sdk) ? "same" : "DIFFERS"
      print st"  blessed="blessed[st]"  ref="rm"/"rs"  current="cur_macos"/"cur_sdk"  "same
    }
  ' "$RESULTS"
  echo
  echo "text differences (OCR; - only in reference, + only in capture):"
  TEXT_CHANGED_STATES="$(awk -F'\t' 'NR>1 && $9=="changed"{print $1}' "$RESULTS")"
  if [ -z "$TEXT_CHANGED_STATES" ]; then
    echo "none"
  else
    for tst in $TEXT_CHANGED_STATES; do
      echo "$tst:"
      sed 's/^/  /' "$OUT/text/$tst.txt"
    done
  fi
} | tee "$OUT/report.txt"

TITLE="current: macOS $(sw_vers -productVersion) / SDK $SDK_MAJOR / commit $GIT_COMMIT — reference: $REFERENCE"
"$VBTOOL" sheet --results "$RESULTS" --ref "$REFERENCE" --norm "$OUT/norm" --diff "$OUT/diff" --title "$TITLE" --out "$OUT/contact-sheet.png" || runtime_error "sheet generation failed"

echo "contact sheet: $OUT/contact-sheet.png"
echo "run directory: $OUT"

if [ "$ANY_ALPHA_FAIL" -eq 1 ]; then
  exit 1
elif [ "$ANY_CHANGE" -eq 1 ]; then
  exit 2
else
  exit 0
fi
