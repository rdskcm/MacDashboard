# Changelog

All notable changes to this project are documented in this file.

## [1.0] (Cadia) - 2026-07-20

First public release.

MacDashboard is a native SwiftUI Mac diagnostics app: it collects a full system
report on launch, shows live metrics that keep refreshing while the window is
open, keeps a local history of past reports, and offers one-click maintenance
actions for common cleanup and upkeep tasks. The UI is bilingual (English and
Russian), switchable in Settings.

Privacy: the app makes no telemetry or analytics calls of any kind. The only
network activity is `softwareupdate -l` when a report is collected (to check
for pending macOS updates) and, if you explicitly click an upgrade/install
action, Homebrew's own downloads. The optional AI assistant feature is not
compiled into the default build.

Licensed under the MIT License. See LICENSE.

### Binary rebuilt — 2026-07-27

- Private IOKit temperature symbols are now resolved at runtime via
  `dlopen`/`dlsym` instead of being hard-linked. If a future macOS removes
  them, the temperature tile disappears instead of the app failing to
  launch. The v1.0 release asset was rebuilt from the current `main` to
  include this fix; the `v1.0` tag itself still points at the original
  commit.
