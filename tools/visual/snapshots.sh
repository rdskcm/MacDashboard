#!/bin/bash
# tools/visual/snapshots.sh — offscreen snapshot suite (HARNESS-REDESIGN-RETARGET).
# Renders every state of Tests/MacDashboardTests/ContentSnapshotTests.swift (dark + light) in the SwiftPM test process,
# compares each PNG with Tests/Snapshots/<state>.png (`vbtool snap-compare`, built -O) and writes a run directory.
#
#   tools/visual/snapshots.sh [--out DIR] [--process-name MacDashboardTests.NAME]
#   tools/visual/snapshots.sh --bless RUN_DIR [STATE ...] [--allow-dirty]
#   tools/visual/snapshots.sh -h
#
# --bless refuses a run whose build-info.txt git_commit ends in -dirty (rendered from uncommitted changes);
# --allow-dirty overrides that, only for a change the block's spec names as intended.
# --process-name (verification only) runs the test process under that name, so its defaults domain is that isolated
# domain instead of the shared swiftpm-testing-helper one.
#
# Exit (run):   0 every state same | 2 any CHANGED, SIZE-CHANGED, NO-REF, ORPHAN-REF, MANIFEST-ORPHAN
#               (contact-sheet.png written when a state differs) | 64 usage |
#               65 main display backing scale is not 2 | 70 build, test or runtime error.
# Exit (bless): 0 blessed | 1 refused (incomplete results, dirty run without --allow-dirty, no build-info
#               git_commit, unknown state, RENDER-FAILED state).
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REF_DIR="$ROOT/Tests/Snapshots"
MANIFEST="$REF_DIR/manifest.txt"

usage() { sed -n 2,19p "$0" | sed 's/^# \{0,1\}//'; }

OUT=""
BLESS_DIR=""
BLESS_STATES=()
MODE=run
ALLOW_DIRTY=0
PROC_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --out) [ $# -ge 2 ] || { usage >&2; exit 64; }; OUT="$2"; shift 2 ;;
    --process-name) [ $# -ge 2 ] || { usage >&2; exit 64; }; PROC_NAME="$2"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --bless)
      [ $# -ge 2 ] || { usage >&2; exit 64; }
      MODE=bless; BLESS_DIR="$2"; shift 2
      while [ $# -gt 0 ]; do
        if [ "$1" = --allow-dirty ]; then ALLOW_DIRTY=1; else BLESS_STATES+=("$1"); fi
        shift
      done ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done
if [ "$ALLOW_DIRTY" = 1 ] && [ "$MODE" != bless ]; then
  echo "--allow-dirty applies only to --bless" >&2; usage >&2; exit 64
fi
if [ -n "$PROC_NAME" ]; then
  if [ "$MODE" != run ]; then echo "--process-name applies only to a run" >&2; usage >&2; exit 64; fi
  if ! [[ "$PROC_NAME" =~ ^MacDashboardTests\.[A-Za-z0-9._-]+$ ]]; then
    echo "--process-name must be MacDashboardTests.<letters, digits, . _ ->: $PROC_NAME" >&2; exit 64
  fi
fi

# ---------------------------------------------------------------------------
# --bless
# ---------------------------------------------------------------------------
if [ "$MODE" = bless ]; then
  RES="$BLESS_DIR/results.tsv"
  if [ ! -f "$RES" ] || ! grep -q '^# complete ' "$RES"; then
    echo "REFUSED: bless: $RES missing or incomplete (no '# complete' line)" >&2; exit 1
  fi
  INFO="$BLESS_DIR/build-info.txt"
  GIT_COMMIT="$(awk -F': ' '/^git_commit:/{print $2}' "$INFO" 2>/dev/null | head -1 | tr -d ' \r')"
  if [ -z "$GIT_COMMIT" ]; then
    echo "REFUSED: bless: $INFO missing or has no git_commit line (not a snapshots.sh run directory)" >&2; exit 1
  fi
  case "$GIT_COMMIT" in
    *-dirty)
      if [ "$ALLOW_DIRTY" != 1 ]; then
        echo "REFUSED: bless: $INFO records git_commit $GIT_COMMIT: the run was rendered from uncommitted changes, so its PNGs may match no commit. Commit the change and run tools/visual/snapshots.sh again, or add --allow-dirty when the block's spec names this change as intended." >&2
        exit 1
      fi
      echo "WARNING: bless: run rendered from uncommitted changes ($GIT_COMMIT), allowed by --allow-dirty" >&2 ;;
  esac
  if [ ${#BLESS_STATES[@]} -eq 0 ]; then
    while IFS= read -r st; do BLESS_STATES+=("$st"); done < <(
      awk -F'\t' 'NR>1 && $1 !~ /^#/ && ($8=="CHANGED"||$8=="SIZE-CHANGED"||$8=="NO-REF"||$8=="ORPHAN-REF"){print $1}' "$RES")
  fi
  for st in ${BLESS_STATES[@]+"${BLESS_STATES[@]}"}; do
    if ! awk -F'\t' -v s="$st" 'NR>1 && $1==s{f=1} END{exit !f}' "$RES"; then
      echo "REFUSED: bless: state not found in results.tsv: $st" >&2; exit 1
    fi
    v="$(awk -F'\t' -v s="$st" 'NR>1 && $1==s{print $8}' "$RES")"
    if [ "$v" = RENDER-FAILED ]; then
      echo "REFUSED: bless: $st is RENDER-FAILED in results.tsv (no usable current/$st.png)" >&2; exit 1
    fi
  done
  MACOS_V="$(awk -F': ' '/^macos:/{print $2}' "$INFO" | head -1)"
  XCODE_V="$(awk -F': ' '/^xcodebuild_version:/{print $2}' "$INFO" | head -1)"
  TODAY="$(date +%Y-%m-%d)"
  mkdir -p "$REF_DIR"
  [ -f "$MANIFEST" ] || printf '# state\tblessed\tmacos\txcode\tcommit\n' > "$MANIFEST"
  for st in ${BLESS_STATES[@]+"${BLESS_STATES[@]}"}; do
    verdict="$(awk -F'\t' -v s="$st" 'NR>1 && $1==s{print $8}' "$RES")"
    if [ "$verdict" = "ORPHAN-REF" ]; then
      rm -f "$REF_DIR/$st.png"
      TMPM="$(mktemp)"
      awk -v s="$st" -F'\t' '$1!=s{print}' "$MANIFEST" > "$TMPM"; mv "$TMPM" "$MANIFEST"
    else
      cp "$BLESS_DIR/current/$st.png" "$REF_DIR/$st.png"
      NEWLINE="$(printf '%s\t%s\t%s\t%s\t%s' "$st" "$TODAY" "$MACOS_V" "$XCODE_V" "$GIT_COMMIT")"
      if grep -q "^$st"$'\t' "$MANIFEST" 2>/dev/null; then
        TMPM="$(mktemp)"
        awk -v s="$st" -v nl="$NEWLINE" -F'\t' 'BEGIN{OFS="\t"} $1==s{print nl; next} {print}' "$MANIFEST" > "$TMPM"
        mv "$TMPM" "$MANIFEST"
      else
        echo "$NEWLINE" >> "$MANIFEST"
      fi
    fi
    echo "blessed: $st"
  done
  exit 0
fi

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
[ -n "$OUT" ] || OUT="$ROOT/tools/visual/out/snap-$(date +%Y%m%d-%H%M%S)"
if [ -e "$OUT" ]; then echo "output directory already exists: $OUT" >&2; exit 64; fi
mkdir -p "$OUT/.bin" || exit 70
OUT="$(cd "$OUT" && pwd)"
"$ROOT/tools/keep-latest.sh" --exclude "$OUT" "$ROOT/tools/visual/out" '^snap-[0-9]{8}-[0-9]{6}$' 5 > "$OUT/prune.log" 2>&1 || true   # NIGHT-STANDING-JOBS retention

VBTOOL="$OUT/.bin/vbtool"
if ! swiftc -O -o "$VBTOOL" "$ROOT/tools/visual/vbtool.swift" -framework AppKit >"$OUT/vbtool-build.log" 2>&1; then
  echo "ERROR: vbtool compile failed" >&2; tail -20 "$OUT/vbtool-build.log" >&2; exit 70
fi

SCREEN_LINE="$("$VBTOOL" screen)"
SCALE="$(echo "$SCREEN_LINE" | awk '{print $3}')"
if [ "$SCALE" != "2.0" ] && [ "$SCALE" != "2" ]; then
  echo "main display is ${SCALE}x; references are 2x — make a Retina display the main display" >&2; exit 65
fi

GIT_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then GIT_COMMIT="${GIT_COMMIT}-dirty"; fi
# SNAPSHOT-DRIFT-HUNT: formatting pins on the test process's command line (argument domain, in place before any code
# runs; an in-process pin is too late because Foundation resolves the locale first). They override every host Region
# setting and reproduce the references: en_US, 12-hour, short date dd.MM.y, default week and number symbols.
# Keep in step with SnapshotEnv.formattingLocaleIsPinned().
PIN_ARGS=(
  -AppleLocale en_US
  -AppleLanguages '(en-US)'
  -AppleICUDateFormatStrings '{ 1 = "dd.MM.y"; }'
  -AppleICUTimeFormatStrings '{ }'
  -AppleICUForce24HourTime NO
  -AppleICUForce12HourTime NO
  -AppleFirstWeekday '{ }'
  -AppleMinDaysInFirstWeek '{ }'
  -AppleICUNumberSymbols '{ }'
)
# `swift test` cannot pass arguments to the test process, so the script starts what it starts: swiftpm-testing-helper
# of the active toolchain with the test bundle (SwiftPM's current .build layout).
SWIFT_BIN="$(xcrun --find swift 2>/dev/null || true)"
HELPER="${SWIFT_BIN%/bin/swift}/libexec/swift/pm/swiftpm-testing-helper"
BUNDLE="$ROOT/.build/out/Products/Debug/MacDashboardTests.xctest/Contents/MacOS/MacDashboardTests"
PLAT="$(xcrun --show-sdk-platform-path 2>/dev/null || true)/Developer"
DATEFMT_GLOBAL="$(defaults read -g AppleICUDateFormatStrings 2>/dev/null | tr -s ' \n' ' ' || true)"
[ -n "$DATEFMT_GLOBAL" ] || DATEFMT_GLOBAL=unset
SCROLLBARS_GLOBAL="$(defaults read -g AppleShowScrollBars 2>/dev/null || echo unset)"
LOCALE_GLOBAL="$(defaults read -g AppleLocale 2>/dev/null || echo unset)"
XCODEBUILD_V="$(xcodebuild -version 2>/dev/null | head -1 || true)"
[ -n "$XCODEBUILD_V" ] || XCODEBUILD_V="none (CLT only)"
{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_commit: $GIT_COMMIT"
  echo "macos: $(sw_vers -productVersion)"
  echo "xcodebuild_version: $XCODEBUILD_V"
  echo "swift_version: $(swift --version 2>&1 | head -1)"
  echo "screen_wh_scale_vx_vy_vw_vh: $SCREEN_LINE"
  echo "reduce_transparency: $(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo 0)"
  echo "increase_contrast: $(defaults read com.apple.universalaccess increaseContrast 2>/dev/null || echo 0)"
  echo "accent_color: $(defaults read -g AppleAccentColor 2>/dev/null || echo multicolor)"
  echo "scrollbars: WhenScrolling (pinned in-process via argument domain; global=$SCROLLBARS_GLOBAL)"
  echo "locale: pinned on the test command line: ${PIN_ARGS[*]} (global AppleLocale=$LOCALE_GLOBAL; global AppleICUDateFormatStrings=$DATEFMT_GLOBAL)"
  echo "process_name: ${PROC_NAME:-swiftpm-testing-helper}"
  echo "rule: channel_tolerance=24 max_changed_pixels=0"
} > "$OUT/build-info.txt"

# Two steps on purpose: a build failure exits 70 with build.log; the test step must compile nothing (--skip-build).
if ! (cd "$ROOT" && swift build --build-tests) > "$OUT/build.log" 2>&1; then
  echo "ERROR: swift build --build-tests failed" >&2; tail -20 "$OUT/build.log" >&2; exit 70
fi

HOME_BENCH="$ROOT/tools/visual/out/snapshot-home"
case "$HOME_BENCH" in
  "$HOME"/Library/*) echo "ERROR: bench home is inside ~/Library: $HOME_BENCH" >&2; exit 70 ;;
esac
rm -rf "$HOME_BENCH"; mkdir -p "$HOME_BENCH" || exit 70
for f in "$HELPER" "$BUNDLE"; do
  [ -x "$f" ] || { echo "ERROR: not found: $f (SwiftPM or Xcode layout changed; update snapshots.sh)" >&2; exit 70; }
done
TEST_EXE="$HELPER"
if [ -n "$PROC_NAME" ]; then
  TEST_EXE="$OUT/.bin/$PROC_NAME"
  ln -s "$HELPER" "$TEST_EXE" || { echo "ERROR: cannot link $TEST_EXE" >&2; exit 70; }
fi

(cd "$ROOT" || exit 70
 export MACDASH_SNAPSHOTS="$OUT" CFFIXED_USER_HOME="$HOME_BENCH"
 export DYLD_FRAMEWORK_PATH="$PLAT/Library/Frameworks:$PLAT/Library/PrivateFrameworks" DYLD_LIBRARY_PATH="$PLAT/usr/lib"
 exec -a "$(basename "$TEST_EXE")" "$TEST_EXE" --test-bundle-path "$BUNDLE" --skip-build --filter SnapshotTests "$BUNDLE" \
   --testing-library swift-testing "${PIN_ARGS[@]}") > "$OUT/swift-test.log" 2>&1
rc=$?

if ! grep -q '^# complete ' "$OUT/rendered.tsv" 2>/dev/null; then
  echo "ERROR: no complete rendered.tsv (test rc=$rc)" >&2; tail -30 "$OUT/swift-test.log" >&2; exit 70
fi
CMP_START=$(date +%s)
"$VBTOOL" snap-compare --out "$OUT" --ref "$REF_DIR" || { echo "ERROR: snap-compare failed" >&2; exit 70; }
echo "compare_seconds: $(( $(date +%s) - CMP_START ))" >> "$OUT/timing.txt"
if ! grep -q '^# complete ' "$OUT/results.tsv" 2>/dev/null; then
  echo "ERROR: no complete results.tsv" >&2; exit 70
fi

count() { awk -F'\t' -v v="$1" 'NR>1 && $1 !~ /^#/ && $8==v{n++} END{print n+0}' "$OUT/results.tsv"; }
SAME=$(count same); CHANGED=$(count CHANGED); SIZE=$(count SIZE-CHANGED); NOREF=$(count NO-REF); ORPHAN=$(count ORPHAN-REF)
TOTAL=$(awk -F'\t' 'NR>1 && $1 !~ /^#/{n++} END{print n+0}' "$OUT/results.tsv")
[ "$TOTAL" -gt 0 ] || { echo "ERROR: results.tsv has no state rows" >&2; exit 70; }
# manifest rows without a state in this run (a renamed or removed state whose PNG is already gone)
awk -F'\t' 'NR==FNR { if (FNR>1 && $1 !~ /^#/) seen[$1]=1; next } FNR>1 && $1 !~ /^#/ && !($1 in seen) { print $1 }' \
  "$OUT/results.tsv" "$MANIFEST" > "$OUT/manifest-orphans.txt"
MORPHAN=$(wc -l < "$OUT/manifest-orphans.txt" | tr -d ' ')
while IFS= read -r st; do
  echo "MANIFEST-ORPHAN: $st (in Tests/Snapshots/manifest.txt, not rendered by the suite)"
done < "$OUT/manifest-orphans.txt"
if [ "$rc" -ne 0 ] && [ "$SAME" -eq "$TOTAL" ]; then
  echo "ERROR: swift test failed (rc=$rc) although every state is same" >&2; tail -30 "$OUT/swift-test.log" >&2; exit 70
fi
if [ "$((TOTAL - SAME + MORPHAN))" -gt 0 ]; then
  if [ "$((TOTAL - SAME))" -gt 0 ]; then
    { head -1 "$OUT/results.tsv"; awk -F'\t' 'NR>1 && $1 !~ /^#/ && $8!="same"' "$OUT/results.tsv"; } > "$OUT/sheet-results.tsv"
    "$VBTOOL" sheet --results "$OUT/sheet-results.tsv" --ref "$REF_DIR" --norm "$OUT/current" --diff "$OUT/diff" \
      --title "snapshots $(date '+%Y-%m-%d %H:%M') $GIT_COMMIT" --out "$OUT/contact-sheet.png" \
      || { echo "ERROR: contact sheet failed" >&2; exit 70; }
    echo "contact sheet: $OUT/contact-sheet.png"
  fi
  echo "SNAPSHOTS: same=$SAME changed=$CHANGED size=$SIZE noref=$NOREF orphan=$ORPHAN morphan=$MORPHAN run=$OUT"
  exit 2
fi
echo "SNAPSHOTS: same=$SAME changed=$CHANGED size=$SIZE noref=$NOREF orphan=$ORPHAN morphan=$MORPHAN run=$OUT"
exit 0
