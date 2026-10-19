#!/bin/bash
# Opened by `night.sh --check` through `open -a Terminal` so the run inherits Terminal's Accessibility,
# Screen Recording and Automation grants (a launchd job would run as /bin/bash, which has none).
exec "$(cd "$(dirname "$0")" && pwd)/night.sh" --run
