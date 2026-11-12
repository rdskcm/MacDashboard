#!/bin/bash
# Warning gate (BUILD-WARNINGS). Compiles Moonport and MoonportTests the way CI does
# (debug, `swift build --build-tests`) into an EMPTY scratch directory and fails on any warning:
#   - Swift compiler warnings: -warnings-as-errors makes each one an error.
#   - Linker warnings: -fatal_warnings makes ld exit non-zero.
#   - SwiftPM's own warnings and the Package.swift manifest's: grep of the build log.
# The scratch directory must be empty: SwiftPM caches the compiled manifest and relinks only
# what changed, so an incremental build would not print those warnings again.
# CI (.github/workflows/ci.yml) and this Mac run this same script.
# Usage: tools/check-warnings.sh [scratch-dir]
#   scratch-dir  absent or empty; kept afterwards (CI runs `swift test --skip-build` on it).
#   Without it a new temporary directory is used and removed at exit.
# Swift 6 language mode (SWIFT6-MODE, Package.swift): concurrency violations are compiler errors, so this
# check needs no staging hook; -warnings-as-errors below covers every remaining warning class.
set -euo pipefail

LOG="$(mktemp -t check-warnings)"
REMOVE_SCRATCH=0
if [ $# -ge 1 ]; then
  # A relative scratch-dir is relative to the caller's directory, not the repo root.
  case "$1" in /*) SCRATCH="$1" ;; *) SCRATCH="$PWD/$1" ;; esac
else
  SCRATCH="$(mktemp -d -t check-warnings-build)"
  REMOVE_SCRATCH=1
fi
cd "$(dirname "$0")/.."
cleanup() {
  rm -f "$LOG"
  if [ "$REMOVE_SCRATCH" = 1 ]; then rm -rf "$SCRATCH"; fi
}
trap cleanup EXIT

if [ -e "$SCRATCH" ] && [ -n "$(ls -A "$SCRATCH")" ]; then
  echo "!! $SCRATCH is not empty: the warning check needs a clean build" >&2
  exit 2
fi

echo "== warning check: swift build --build-tests (debug) into $SCRATCH =="
set +e
swift build --build-tests --scratch-path "$SCRATCH" \
  -Xswiftc -warnings-as-errors \
  -Xlinker -fatal_warnings 2>&1 | tee "$LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
  echo "::error::build failed (exit $BUILD_STATUS). Under this check every Swift compiler warning is an error and every linker warning is fatal: see the error lines above" >&2
  exit 1
fi
STRAY="$(grep -E '^(warning: |ld: warning: )|(^|/)Package\.swift:[0-9]+:[0-9]+: warning: ' "$LOG" || true)"
if [ -n "$STRAY" ]; then
  echo "::error::the build printed warnings outside the Swift compiler:" >&2
  echo "$STRAY" >&2
  exit 1
fi
echo "warning check OK: no warnings in Moonport and MoonportTests"
