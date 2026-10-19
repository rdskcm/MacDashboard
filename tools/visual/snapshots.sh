#!/bin/bash
# tools/visual/snapshots.sh — offscreen snapshot suite (HARNESS-REDESIGN-RETARGET).
# Renders every state of Tests/MacDashboardTests/ContentSnapshotTests.swift (dark + light) inside `swift test`,
# compares each PNG with Tests/Snapshots/<state>.png (`vbtool snap-compare`, built -O) and writes a run directory.
#
#   tools/visual/snapshots.sh [--out DIR]
#   tools/visual/snapshots.sh --bless RUN_DIR [STATE ...]
#   tools/visual/snapshots.sh -h
#
# Exit (run):   0 every state same | 2 any CHANGED, SIZE-CHANGED, NO-REF, ORPHAN-REF (contact-sheet.png written) |
#               64 usage | 65 main display backing scale is not 2 | 70 build, test or runtime error.
# Exit (bless): 0 blessed | 1 refused.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REF_DIR="$ROOT/Tests/Snapshots"
MANIFEST="$REF_DIR/manifest.txt"

usage() { sed -n 2,12p "$0" | sed 's/^# \{0,1\}//'; }

OUT=""
BLESS_DIR=""
BLESS_STATES=()
MODE=run

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --out) [ $# -ge 2 ] || { usage >&2; exit 64; }; OUT="$2"; shift 2 ;;
    --bless)
      [ $# -ge 2 ] || { usage >&2; exit 64; }
      MODE=bless; BLESS_DIR="$2"; shift 2
      while [ $# -gt 0 ]; do BLESS_STATES+=("$1"); shift; done ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

# ---------------------------------------------------------------------------
# --bless
# ---------------------------------------------------------------------------
if [ "$MODE" = bless ]; then
  RES="$BLESS_DIR/results.tsv"
  if [ ! -f "$RES" ] || ! grep -q '^# complete ' "$RES"; then
    echo "REFUSED: bless: $RES missing or incomplete (no '# complete' line)" >&2; exit 1
  fi
  if [ ${#BLESS_STATES[@]} -eq 0 ]; then
    while IFS= read -r st; do BLESS_STATES+=("$st"); done < <(
      awk -F'\t' 'NR>1 && $1 !~ /^#/ && ($8=="CHANGED"||$8=="SIZE-CHANGED"||$8=="NO-REF"||$8=="ORPHAN-REF"){print $1}' "$RES")
  fi
  for st in ${BLESS_STATES[@]+"${BLESS_STATES[@]}"}; do
    if ! awk -F'\t' -v s="$st" 'NR>1 && $1==s{f=1} END{exit !f}' "$RES"; then
      echo "REFUSED: bless: state not found in results.tsv: $st" >&2; exit 1
    fi
  done
  INFO="$BLESS_DIR/build-info.txt"
  GIT_COMMIT="$(awk -F': ' '/^git_commit:/{print $2}' "$INFO" | head -1)"
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

VBTOOL="$OUT/.bin/vbtool"
if ! swiftc -O -o "$VBTOOL" "$ROOT/tools/visual/vbtool.swift" -framework AppKit -framework Vision >"$OUT/vbtool-build.log" 2>&1; then
  echo "ERROR: vbtool compile failed" >&2; tail -20 "$OUT/vbtool-build.log" >&2; exit 70
fi

SCREEN_LINE="$("$VBTOOL" screen)"
SCALE="$(echo "$SCREEN_LINE" | awk '{print $3}')"
if [ "$SCALE" != "2.0" ] && [ "$SCALE" != "2" ]; then
  echo "main display is ${SCALE}x; references are 2x — make a Retina display the main display" >&2; exit 65
fi

GIT_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then GIT_COMMIT="${GIT_COMMIT}-dirty"; fi
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
  echo "rule: channel_tolerance=24 max_changed_pixels=0"
} > "$OUT/build-info.txt"

if ! (cd "$ROOT" && swift build --build-tests) > "$OUT/build.log" 2>&1; then
  echo "ERROR: swift build --build-tests failed" >&2; tail -20 "$OUT/build.log" >&2; exit 70
fi

HOME_BENCH="$ROOT/tools/visual/out/snapshot-home"
case "$HOME_BENCH" in
  "$HOME"/Library/*) echo "ERROR: bench home is inside ~/Library: $HOME_BENCH" >&2; exit 70 ;;
esac
rm -rf "$HOME_BENCH"; mkdir -p "$HOME_BENCH" || exit 70

(cd "$ROOT" && MACDASH_SNAPSHOTS="$OUT" CFFIXED_USER_HOME="$HOME_BENCH" swift test --skip-build --filter SnapshotTests) > "$OUT/swift-test.log" 2>&1
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
if [ "$rc" -ne 0 ] && [ "$SAME" -eq "$TOTAL" ]; then
  echo "ERROR: swift test failed (rc=$rc) although every state is same" >&2; tail -30 "$OUT/swift-test.log" >&2; exit 70
fi
if [ "$((TOTAL - SAME))" -gt 0 ]; then
  { head -1 "$OUT/results.tsv"; awk -F'\t' 'NR>1 && $1 !~ /^#/ && $8!="same"' "$OUT/results.tsv"; } > "$OUT/sheet-results.tsv"
  "$VBTOOL" sheet --results "$OUT/sheet-results.tsv" --ref "$REF_DIR" --norm "$OUT/current" --diff "$OUT/diff" \
    --title "snapshots $(date '+%Y-%m-%d %H:%M') $GIT_COMMIT" --out "$OUT/contact-sheet.png" \
    || { echo "ERROR: contact sheet failed" >&2; exit 70; }
  echo "contact sheet: $OUT/contact-sheet.png"
  echo "SNAPSHOTS: same=$SAME changed=$CHANGED size=$SIZE noref=$NOREF orphan=$ORPHAN run=$OUT"
  exit 2
fi
echo "SNAPSHOTS: same=$SAME changed=$CHANGED size=$SIZE noref=$NOREF orphan=$ORPHAN run=$OUT"
exit 0
