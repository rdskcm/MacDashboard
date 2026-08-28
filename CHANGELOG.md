# Changelog

All notable changes to this project are documented in this file.

## [2.0] (Krieg) - 2026-08-28

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
- Process lists are sampled natively from `ps`: lower overhead than the old full `top`
  parse, real pids, and untruncated process names. The memory column reports the same
  physical footprint Activity Monitor's "Memory" column shows — for every process on the
  machine, not just your own — from a single `top` snapshot per refresh.
- Hardened runtime on the app bundle, so no local process can inject code into an
  app that holds Full Disk Access.
- SMART data for external drives can use the privileged smartctl path again, gated
  on the binary being one a non-root user cannot replace (see SPEC §5).
- The chart footer's dates follow the Mac's Region setting — day/month/year order
  and separators — independent of the app's own language toggle, so an app set to
  English on a Mac with a German Region still shows German-style dates.

Numerous layout, animation and accessibility fixes accumulated across the
rebuild (segmented controls, disclosure/collapse behaviour, hover states,
Reduce Motion support, live-resize stability).

Known limitations:

- kernel_task is not listed in the process tables (macOS does not expose pid 0 to
  an unentitled app; use Activity Monitor or "top" when a kernel-side CPU spike
  needs explaining). A host-busy/kernel-CPU-attribution estimate was built and
  measured against real "top" output during v2.0's pre-release review; it showed a
  systematic bias (~8pp) and was reverted rather than ship a misleading number.
- The process list can briefly show a double-exposure render glitch (stale and fresh row
  content compositing in one frame, sometimes bleeding slightly past the card edge) during
  rapid resorts — a long-standing structural issue present since v1.0, deferred post-release
  by explicit decision, not a v2.0 regression.
- At narrow window widths, the Процессы/Папки two-column pair doesn't always split exactly
  50/50 — cosmetic, accepted after two fix attempts made it worse.

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
