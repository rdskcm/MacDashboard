# Changelog

All notable changes to this project are documented in this file.

## [2.0] (Krieg) - 2026-08-23

Complete visual and structural rebuild of the interface on a new
design-token system: card-based layout, KPI tiles, an attention summary
with recommendation capsules, and a quiet/loud information hierarchy that
surfaces what needs attention and recedes what doesn't.

New since 1.0:

- Redesigned Settings window (sidebar navigation, General/Monitoring pages,
  configurable process-list length).
- Redesigned battery popover with power, voltage, temperature, capacity and
  health.
- Crash log detection with a 7-day window, collapsed rows and
  own-app/panic severity.
- Confirmation gates before Homebrew upgrades and energy-setting changes.
- Time Machine status distinguishes "unmounted" from "not connected right
  now" and reports the real reason when Full Disk Access is missing.
- Bulk delete for orphaned startup-item plists.
- Live disk/swap verdicts and other readings reported honestly during
  collection rather than only after it finishes.

Numerous layout, animation and accessibility fixes accumulated across the
rebuild (segmented controls, disclosure/collapse behaviour, hover states,
Reduce Motion support, live-resize stability).

Licensed under the MIT License. See LICENSE.

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
