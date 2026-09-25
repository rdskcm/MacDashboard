#!/bin/bash
# tools/visual/run.sh — capture every real MacDashboard window state, check it
# for alpha holes, and diff it against the stored reference set.
#
# Usage:
#   tools/visual/run.sh [--app PATH] [--out DIR] [--reference DIR] [--allow-old-sdk]
#   tools/visual/run.sh --bless RUN_DIR [STATE ...]
#   tools/visual/run.sh --selftest
#   tools/visual/run.sh -h | --help
#
# See tools/visual/README.md for the full contract (exit codes, permissions,
# thresholds, side effects). This script drives the real GUI: it moves the
# cursor and sends AX actions (no synthetic keystrokes). Do not use the Mac
# while it runs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="com.rdskcm.mac-dashboard"
APPSUPPORT_DIR="$HOME/Library/Application Support/MacDashboard"
SAVEDSTATE_DIR="$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState"

HELP="tools/visual/run.sh [--app PATH] [--out DIR] [--reference DIR] [--allow-old-sdk]
tools/visual/run.sh --bless RUN_DIR [STATE ...]
tools/visual/run.sh --selftest
tools/visual/run.sh -h | --help

Exit codes: 0 all alpha ok and every diff <= threshold. 1 at least one alpha
FAIL (wins over 2). 2 no alpha FAIL, but >=1 state is CHANGED, SIZE-CHANGED or
NO-REF. 64 usage error. 65 precondition refused. 70 runtime error (restoration
still ran). --bless and --selftest exit 0 on success, 1 on refusal/failure."

usage_error() { echo "usage error: $1" >&2; echo "$HELP" >&2; exit 64; }
precondition_refused() { echo "REFUSED: $1" >&2; exit 65; }
runtime_error() { echo "RUNTIME ERROR: $1" >&2; exit 70; }

STATE_ORDER="main-dark settings-general-dark settings-monitoring-dark settings-titlebar-hover-dark main-light settings-general-light settings-monitoring-light settings-titlebar-hover-light"

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
APP="$ROOT/dist/MacDashboard.app"
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
  swiftc -O -o "$TMPBIN/vbtool" "$ROOT/tools/visual/vbtool.swift" -framework AppKit
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
    alpha_v="$(printf '%s' "$line" | awk -F'\t' '{print $2}')"
    if [ "$alpha_v" != "ok" ]; then
      FAILED_STATES="$FAILED_STATES $st(alpha=$alpha_v)"
    fi
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

mkdir -p "$OUT/raw" "$OUT/norm" "$OUT/diff" "$OUT/.bin" "$OUT/.restore"

PIXEL_TOLERANCE="$(awk '$1=="pixel_tolerance"{print $2}' "$ROOT/tools/visual/thresholds.txt")"

# Precondition 2: no running instance
if pgrep -x MacDashboard >/dev/null 2>&1; then
  precondition_refused "quit MacDashboard first"
fi

# Precondition 3: SDK gate
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
VBTOOL="$OUT/.bin/vbtool"
if ! swiftc -O -o "$VBTOOL" "$ROOT/tools/visual/vbtool.swift" -framework AppKit; then
  runtime_error "vbtool compile failed"
fi

# Precondition 4: Screen Recording
if ! "$VBTOOL" preflight >/dev/null 2>&1; then
  precondition_refused "grant Screen Recording to the terminal running this tool"
fi

# Precondition 5: Accessibility
AX_ENABLED="$(osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null || echo false)"
if [ "$AX_ENABLED" != "true" ]; then
  precondition_refused "Accessibility is needed (System Events UI elements enabled = $AX_ENABLED)"
fi

# Precondition 6: cliclick
CLICLICK="$(command -v cliclick || true)"
if [ -z "$CLICLICK" ] && [ -x /opt/homebrew/bin/cliclick ]; then
  CLICLICK=/opt/homebrew/bin/cliclick
fi
if [ -z "$CLICLICK" ]; then
  precondition_refused "cliclick not found"
fi

# Precondition 7: staleness warning (default dist app only)
if [ "$APP" = "$ROOT/dist/MacDashboard.app" ]; then
  STALE="$(find "$ROOT/Sources" -newer "$APP_BIN" -print -quit 2>/dev/null || true)"
  if [ -n "$STALE" ]; then
    echo "WARNING: dist build is older than Sources/ — run ./build_app.sh"
  fi
fi

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
DARK0="$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2>/dev/null || echo false)"
AUTO0="$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo 0)"
REDUCE_TRANSPARENCY="$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo 0)"
INCREASE_CONTRAST="$(defaults read com.apple.universalaccess increaseContrast 2>/dev/null || echo 0)"
ACCENT_COLOR="$(defaults read -g AppleAccentColor 2>/dev/null || echo multicolor)"
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
  echo "appearance_dark0: $DARK0"
  echo "appearance_auto0: $AUTO0"
  echo "reduce_transparency: $REDUCE_TRANSPARENCY"
  echo "increase_contrast: $INCREASE_CONTRAST"
  echo "accent_color: $ACCENT_COLOR"
  echo "language: en (pinned via argument domain)"
  echo "alpha_params: corner_pt=32 edge_inset_px=0"
  echo "--- thresholds.txt ---"
  echo "$THRESHOLDS_CONTENTS"
  echo "--- sw_vers ---"
  echo "$SWVERS_OUT"
  echo "--- vtool -show-build ---"
  echo "$VTOOL_OUT"
} > "$OUT/build-info.txt"

# ---------------------------------------------------------------------------
# Machine-state snapshot + restore trap
# ---------------------------------------------------------------------------
RESTORE_DIR="$OUT/.restore"
LAUNCHED_PID=""
MAIN_ID=""
SET_ID=""
RESTORED=0

CURSOR0="$("$VBTOOL" cursor)"
FRONT_BUNDLE0="$(osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true' 2>/dev/null || echo "")"

# A snapshot that did not complete must stop the run HERE, before the restore trap exists:
# restore() replaces live data with the snapshot (defaults delete + import, rsync --delete),
# so restoring from a partial copy would delete the user's files. Nothing is changed yet.
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
  defaults export "$BUNDLE_ID" "$RESTORE_DIR/defaults.plist" \
    || precondition_refused "could not snapshot the app's defaults ($BUNDLE_ID) — nothing was changed"
else
  touch "$RESTORE_DIR/defaults.absent"
fi

if [ -d "$SAVEDSTATE_DIR" ]; then
  mkdir -p "$RESTORE_DIR/savedState"
  ditto "$SAVEDSTATE_DIR" "$RESTORE_DIR/savedState" \
    || precondition_refused "could not snapshot $SAVEDSTATE_DIR — nothing was changed"
else
  touch "$RESTORE_DIR/savedState.absent"
fi

if [ -d "$APPSUPPORT_DIR" ]; then
  mkdir -p "$RESTORE_DIR/appsupport"
  ditto "$APPSUPPORT_DIR" "$RESTORE_DIR/appsupport" \
    || precondition_refused "could not snapshot $APPSUPPORT_DIR — nothing was changed"
else
  touch "$RESTORE_DIR/appsupport.absent"
fi

restore() {
  if [ "$RESTORED" = "1" ]; then return 0; fi
  RESTORED=1

  local app_status="ok"
  if [ -n "$LAUNCHED_PID" ] && ps -p "$LAUNCHED_PID" >/dev/null 2>&1; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    local waited=0
    while ps -p "$LAUNCHED_PID" >/dev/null 2>&1 && [ "$waited" -lt 10 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if ps -p "$LAUNCHED_PID" >/dev/null 2>&1; then
      kill -TERM "$LAUNCHED_PID" 2>/dev/null || true
      sleep 3
      if ps -p "$LAUNCHED_PID" >/dev/null 2>&1; then
        kill -KILL "$LAUNCHED_PID" 2>/dev/null || true
      fi
    fi
    if ps -p "$LAUNCHED_PID" >/dev/null 2>&1; then app_status="partial"; fi
  fi

  local defaults_status="ok"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [ -f "$RESTORE_DIR/defaults.plist" ]; then
    defaults import "$BUNDLE_ID" "$RESTORE_DIR/defaults.plist" 2>/dev/null || defaults_status="partial"
  fi

  local savedstate_status="ok"
  case "$SAVEDSTATE_DIR" in
    "$HOME"/Library/Saved\ Application\ State/*.savedState) ;;
    *) savedstate_status="partial" ;;
  esac
  if [ "$savedstate_status" = "ok" ]; then
    rm -rf "$SAVEDSTATE_DIR" 2>/dev/null || savedstate_status="partial"
    if [ -d "$RESTORE_DIR/savedState" ]; then
      ditto "$RESTORE_DIR/savedState" "$SAVEDSTATE_DIR" 2>/dev/null || savedstate_status="partial"
    fi
  fi

  local appsupport_status="ok"
  case "$APPSUPPORT_DIR" in
    "$HOME"/Library/Application\ Support/MacDashboard) ;;
    *) appsupport_status="partial" ;;
  esac
  if [ "$appsupport_status" = "ok" ]; then
    if [ -d "$RESTORE_DIR/appsupport" ]; then
      rsync -a --delete "$RESTORE_DIR/appsupport/" "$APPSUPPORT_DIR/" 2>/dev/null || appsupport_status="partial"
    else
      rm -rf "$APPSUPPORT_DIR" 2>/dev/null || appsupport_status="partial"
    fi
  fi

  local appearance_status="ok"
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $DARK0" >/dev/null 2>&1 || appearance_status="partial"
  local auto_now
  auto_now="$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo 0)"
  if [ "$AUTO0" = "1" ] && { [ "$auto_now" = "0" ] || [ -z "$auto_now" ]; }; then
    defaults write -g AppleInterfaceStyleSwitchesAutomatically -bool true 2>/dev/null || true
    appearance_status="partial"
    echo "WARNING: Auto appearance was re-written via defaults — check System Settings > Appearance shows Auto"
  fi

  local cursor_status="ok"
  IFS=' ' read -r cx0 cy0 <<EOF_CUR
$CURSOR0
EOF_CUR
  "$CLICLICK" "m:${cx0%.*},${cy0%.*}" >/dev/null 2>&1 || cursor_status="partial"

  local front_status="ok"
  if [ -n "$FRONT_BUNDLE0" ]; then
    osascript -e "tell application id \"$FRONT_BUNDLE0\" to activate" >/dev/null 2>&1 || front_status="partial"
  fi

  echo "RESTORE: app=$app_status defaults=$defaults_status savedstate=$savedstate_status appsupport=$appsupport_status appearance=$appearance_status cursor=$cursor_status front=$front_status"

  if [ "$app_status" = "ok" ] && [ "$defaults_status" = "ok" ] && [ "$savedstate_status" = "ok" ] \
     && [ "$appsupport_status" = "ok" ] && { [ "$appearance_status" = "ok" ] || [ "$appearance_status" = "partial" ]; } \
     && [ "$cursor_status" = "ok" ] && [ "$front_status" = "ok" ]; then
    rm -rf "$RESTORE_DIR"
  else
    echo "RESTORE: kept backup at $RESTORE_DIR"
  fi
}

trap 'restore' EXIT
trap 'echo "INTERRUPTED"; restore; exit 130' INT
trap 'restore; exit 143' TERM

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
open -F "$APP" --args -appLanguage en -AppleLanguages "(en)"

waited=0
PID=""
while [ "$waited" -lt 20 ]; do
  PID="$(pgrep -x MacDashboard | head -1 || true)"
  if [ -n "$PID" ]; then break; fi
  sleep 1
  waited=$((waited + 1))
done
if [ -z "$PID" ]; then runtime_error "MacDashboard did not launch within 20s"; fi
LAUNCHED_PID="$PID"

ACTUAL_COMM="$(ps -o comm= -p "$PID" 2>/dev/null || true)"
if [ "$ACTUAL_COMM" != "$APP_BIN" ]; then
  runtime_error "launched process comm ($ACTUAL_COMM) does not match $APP_BIN"
fi

waited=0
WINDOWS_OUT=""
while [ "$waited" -lt 20 ]; do
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

osascript <<OSA
tell application "System Events"
  tell (first process whose unix id is $PID)
    set position of window 1 to {$POS_X, $POS_Y}
    set size of window 1 to {1150, $H}
  end tell
end tell
OSA

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
  osascript -e "tell application id \"$BUNDLE_ID\" to activate" >/dev/null 2>&1 || true
  local waited_ms=0
  local printed=0
  while true; do
    local wb
    wb="$(window_bounds "$wid")"
    if [ -n "$wb" ]; then
      local out
      out="$(osascript <<OSA
tell application "System Events"
  set procs to (processes whose unix id is $PID)
  if (count of procs) = 0 then return "no"
  set proc to item 1 of procs
  if not (frontmost of proc) then return "no"
  tell proc
    if not (value of attribute "AXMain" of window 1) then return "no"
    set p to position of window 1
    set sz to size of window 1
    return ((item 1 of p) as string) & " " & ((item 2 of p) as string) & " " & ((item 1 of sz) as string) & " " & ((item 2 of sz) as string)
  end tell
end tell
OSA
)"
      if [ "$out" != "no" ]; then
        local px py pw ph bx by bw bh
        read -r px py pw ph <<< "$out"
        read -r bx by bw bh <<< "$wb"
        if within "$px" "$bx" && within "$py" "$by" && within "$pw" "$bw" && within "$ph" "$bh"; then
          return 0
        fi
      fi
    fi
    if [ "$printed" -eq 0 ]; then
      local fname
      fname="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "?")"
      echo "waiting for MacDashboard to become key (front app: $fname) — answer any system prompt"
      printed=1
    fi
    sleep 0.5
    waited_ms=$((waited_ms + 500))
    if [ "$waited_ms" -ge 30000 ]; then
      local fname2
      fname2="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "?")"
      runtime_error "assert_key timeout waiting for MacDashboard to become key (front app: $fname2)"
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

# Coordinate-click contingency (block spec, tools/visual/run.sh design section,
# "press_section"): a real run proved that System Events' `entire contents of
# window 1` for the Settings window never exposes the sidebar rows as AXButton
# elements at all (only the traffic lights and the detail-pane controls show
# up; the sidebar List is accessibility-invisible to System Events on this
# macOS). The AX press route in the block spec cannot work here, so this uses
# the spec's documented fallback: a coordinate click at (x+98, y+T+29) for
# General and (x+98, y+T+65) for Monitoring, from the Settings window's
# current bounds (x, y) and titlebar height T = h - 420.
press_section() {
  local label="$1" setx="$2" sety="$3" t="$4"
  local off
  case "$label" in
    General) off=29 ;;
    Monitoring) off=65 ;;
    *) runtime_error "press_section: unknown section label '$label'" ;;
  esac
  local cx cy
  cx="$(awk -v x="$setx" 'BEGIN{printf "%d", x+98}')"
  cy="$(awk -v y="$sety" -v t="$t" -v o="$off" 'BEGIN{printf "%d", y+t+o}')"
  "$CLICLICK" "c:$cx,$cy" >/dev/null 2>&1 || runtime_error "press_section: cliclick failed for $label"
}

# Open Settings via an AX press on the app-menu item (block spec, Design
# section, amended 2026-09-24: synthetic keystrokes proved intermittent on
# this bench — Cmd+, sometimes not delivered — so the tool targets the menu
# item directly through AX and sends no keystrokes at all). Searches menu bar
# item 2 (the application menu) of the process for the first menu item whose
# name starts with "Settings" and performs "AXPress" on it. If none is found,
# reports the menu items it saw and exits 70 (never falls back to keystrokes).
open_settings() {
  local out
  out="$(osascript - "$PID" <<'EOF'
on run argv
  set thePID to (item 1 of argv) as integer
  tell application "System Events"
    tell (first process whose unix id is thePID)
      set appMenu to menu 1 of menu bar item 2 of menu bar 1
      set settingsItem to missing value
      set namesStr to ""
      repeat with mi in menu items of appMenu
        set miName to ""
        try
          set miName to name of mi
        end try
        if namesStr is "" then
          set namesStr to miName
        else
          set namesStr to namesStr & "|" & miName
        end if
        if settingsItem is missing value and miName starts with "Settings" then
          set settingsItem to mi
        end if
      end repeat
      if settingsItem is missing value then
        return "NOTFOUND:" & namesStr
      end if
      perform action "AXPress" of settingsItem
      return "OK"
    end tell
  end tell
end run
EOF
)" || runtime_error "open_settings: osascript failed"
  case "$out" in
    OK) ;;
    NOTFOUND:*) runtime_error "Settings menu item not found via AX; menu items seen: ${out#NOTFOUND:}" ;;
    *) runtime_error "open_settings: unexpected osascript output: $out" ;;
  esac
}

# Close Settings via an AX press on its AXCloseButton (block spec, Design
# section, amended 2026-09-24; same rationale as open_settings — Cmd+W
# sometimes left Settings open). Finds the process window whose position and
# size match the Settings window's last-known bounds (±1 pt, same tolerance
# as assert_key's `within`), then presses the button with subrole
# "AXCloseButton" on it.
close_settings() {
  local wid="$1"
  local wb
  wb="$(window_bounds "$wid")"
  [ -n "$wb" ] || runtime_error "close_settings: no bounds for window $wid"
  local bx by bw bh
  read -r bx by bw bh <<< "$wb"
  local out
  out="$(osascript - "$PID" "$bx" "$by" "$bw" "$bh" <<'EOF'
on run argv
  set thePID to (item 1 of argv) as integer
  set bx to (item 2 of argv) as real
  set boundsY to (item 3 of argv) as real
  set bw to (item 4 of argv) as real
  set bh to (item 5 of argv) as real
  tell application "System Events"
    tell (first process whose unix id is thePID)
      set targetWindow to missing value
      repeat with w in windows
        try
          set p to position of w
          set sz to size of w
          set dx to (item 1 of p) - bx
          if dx < 0 then set dx to -dx
          set dy to (item 2 of p) - boundsY
          if dy < 0 then set dy to -dy
          set dw to (item 1 of sz) - bw
          if dw < 0 then set dw to -dw
          set dh to (item 2 of sz) - bh
          if dh < 0 then set dh to -dh
          if dx <= 1 and dy <= 1 and dw <= 1 and dh <= 1 then
            set targetWindow to w
            exit repeat
          end if
        end try
      end repeat
      if targetWindow is missing value then
        return "NOWINDOW"
      end if
      set closeBtn to missing value
      repeat with b in buttons of targetWindow
        try
          if (subrole of b) is "AXCloseButton" then
            set closeBtn to b
            exit repeat
          end if
        end try
      end repeat
      if closeBtn is missing value then
        return "NOBUTTON"
      end if
      perform action "AXPress" of closeBtn
      return "OK"
    end tell
  end tell
end run
EOF
)" || runtime_error "close_settings: osascript failed"
  case "$out" in
    OK) ;;
    NOWINDOW) runtime_error "close_settings: no AX window matching Settings bounds ($bx,$by,$bw,$bh)" ;;
    NOBUTTON) runtime_error "close_settings: AXCloseButton not found on Settings window" ;;
    *) runtime_error "close_settings: unexpected osascript output: $out" ;;
  esac
}

SIDEBAR_ROUTE="coordinate click (AX press proved unavailable in a real run: no AXButton for the sidebar rows; see README section 9)"

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

# ---------------------------------------------------------------------------
# Capture sequence
# ---------------------------------------------------------------------------
for mode in dark light; do
  if [ "$mode" = "dark" ]; then DARK_BOOL=true; else DARK_BOOL=false; fi
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $DARK_BOOL" >/dev/null 2>&1 || true
  sleep 2

  assert_key "$MAIN_ID"
  park_cursor
  sleep 1.5
  capture_state "main-$mode" "$MAIN_ID"

  assert_key "$MAIN_ID"
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

  press_section "General" "$SETX" "$SETY" "$T"
  park_cursor
  sleep 1.5
  assert_key "$SET_ID"
  capture_state "settings-general-$mode" "$SET_ID"

  press_section "Monitoring" "$SETX" "$SETY" "$T"
  park_cursor
  sleep 1.5
  assert_key "$SET_ID"
  capture_state "settings-monitoring-$mode" "$SET_ID"

  THALF="$(awk -v t="$T" 'BEGIN{v=t/2; if(v<8)v=8; printf "%.2f", v}')"
  HOVER_X="$(awk -v x="$SETX" 'BEGIN{printf "%d", x+98}')"
  HOVER_Y="$(awk -v y="$SETY" -v th="$THALF" 'BEGIN{printf "%d", y+th}')"
  "$CLICLICK" "m:$HOVER_X,$HOVER_Y" >/dev/null 2>&1 || runtime_error "cliclick hover failed"
  sleep 1.5
  assert_key "$SET_ID"
  capture_state "settings-titlebar-hover-$mode" "$SET_ID"
  park_cursor

  assert_key "$SET_ID"
  close_settings "$SET_ID"
  waited=0
  while [ "$waited" -lt 5 ]; do
    wl="$("$VBTOOL" windows --pid "$PID" || true)"
    if ! printf '%s\n' "$wl" | awk '{print $1}' | grep -qx "$SET_ID"; then break; fi
    sleep 1
    waited=$((waited + 1))
  done
done

# ---------------------------------------------------------------------------
# Per-state processing
# ---------------------------------------------------------------------------
RESULTS="$OUT/results.tsv"
printf 'state\talpha\thole_px\tbbox_pt\tregions\tdiff_pct\tthreshold\tverdict\n' > "$RESULTS"

ANY_ALPHA_FAIL=0
ANY_CHANGE=0

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
  else
    VERDICT="NO-REF"
    DIFF_PCT="n/a"
    ANY_CHANGE=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "$ALPHA_OK" "$HOLE_PX" "$BBOX_PT" "$REGIONS" "$DIFF_PCT" "$THRESH" "$VERDICT" >> "$RESULTS"
done

# ---------------------------------------------------------------------------
# Sanity guards
# ---------------------------------------------------------------------------
GD_LINE="$("$VBTOOL" diff "$OUT/norm/settings-general-dark.png" "$OUT/norm/settings-monitoring-dark.png" --tol "$PIXEL_TOLERANCE" --mask "$OUT/diff/.sanity-section.png" 2>&1 || true)"
GD_PCT="$(printf '%s\n' "$GD_LINE" | sed -n 's/.*pct=\([0-9.]*\).*/\1/p')"
rm -f "$OUT/diff/.sanity-section.png"
if [ -n "$GD_PCT" ] && awk -v p="$GD_PCT" 'BEGIN{exit !(p<=1.0)}'; then
  runtime_error "sanity: section switch had no visible effect (diff ${GD_PCT}%)"
fi

MM_LINE="$("$VBTOOL" diff "$OUT/norm/main-dark.png" "$OUT/norm/main-light.png" --tol "$PIXEL_TOLERANCE" --mask "$OUT/diff/.sanity-appearance.png" 2>&1 || true)"
MM_PCT="$(printf '%s\n' "$MM_LINE" | sed -n 's/.*pct=\([0-9.]*\).*/\1/p')"
rm -f "$OUT/diff/.sanity-appearance.png"
if [ -n "$MM_PCT" ] && awk -v p="$MM_PCT" 'BEGIN{exit !(p<=5.0)}'; then
  runtime_error "sanity: appearance switch had no effect (diff ${MM_PCT}%)"
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
  if [ -f "$REFERENCE/manifest.txt" ]; then
    cat "$REFERENCE/manifest.txt"
  else
    echo "(no manifest at $REFERENCE)"
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
