#!/bin/bash
# tools/harness/render.sh — compile & run a headless UI render scenario.
#
# Usage:  tools/harness/render.sh <scenario.swift> <output.png>
#
# Compiles: full app source tree (minus MacDashboardApp.swift) + HarnessKit.swift
# + the scenario (copied to main.swift — top-level statements require that name),
# then runs the binary, passing <output.png> as argv[1] for harnessRender().
# See tools/harness/README.md for the scenario template and rules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIO="${1:?usage: render.sh <scenario.swift> <output.png>}"
OUT="${2:?usage: render.sh <scenario.swift> <output.png>}"

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

"$BUILD/harness" "$OUT"
