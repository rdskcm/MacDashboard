#!/bin/bash
# tools/harness/render.sh — compile & run a headless UI render scenario.
#
# Usage:  tools/harness/render.sh <scenario.swift> <output.png> [light|dark|both]
#
# Compiles: full app source tree (minus MacDashboardApp.swift) + HarnessKit.swift
# + the scenario (copied to main.swift — top-level statements require that name),
# then runs the binary, passing <output.png> as argv[1] for harnessRender().
# Optional 3rd arg pins the theme (exported to the binary as HARNESS_APPEARANCE):
#   light|dark -> one PNG at <output.png>;  both -> one compile, <output>-light.png
#   and <output>-dark.png;  omitted -> unpinned (system theme), env var stripped.
# See tools/harness/README.md for the scenario template and rules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
USAGE="usage: render.sh <scenario.swift> <output.png> [light|dark|both]"
SCENARIO="${1:?$USAGE}"
OUT="${2:?$USAGE}"
MODE="${3:-}"
case "$MODE" in
  ""|light|dark|both) ;;
  *) echo "$USAGE" >&2; exit 2 ;;
esac

BUILD="$(mktemp -d /tmp/macdash-harness.XXXXXX)"
trap 'rm -rf "$BUILD"' EXIT
cp "$SCENARIO" "$BUILD/main.swift"

# Collect app sources except the @main entry (bash 3.2: no mapfile).
SRCS=()
while IFS= read -r f; do SRCS+=("$f"); done < <(
  find "$ROOT/Sources/MacDashboard" -name '*.swift' ! -name 'MacDashboardApp.swift' | sort
)

# NOTE: no `-framework Observation` — it's an SDK Swift module, linking it fails.
swiftc -o "$BUILD/harness" "${SRCS[@]}" "$ROOT/tools/harness/HarnessKit.swift" "$BUILD/main.swift" \
  -framework AppKit -framework SwiftUI -framework IOKit

case "$MODE" in
  "")   env -u HARNESS_APPEARANCE "$BUILD/harness" "$OUT" ;;
  both) HARNESS_APPEARANCE=light "$BUILD/harness" "${OUT%.png}-light.png"
        HARNESS_APPEARANCE=dark  "$BUILD/harness" "${OUT%.png}-dark.png" ;;
  *)    HARNESS_APPEARANCE="$MODE" "$BUILD/harness" "$OUT" ;;
esac
