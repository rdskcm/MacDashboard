# Changelog

All notable changes to this project are documented in this file.

## [2.2] (Krieg) - 2026-09-25

Apple Silicon only, and a rebuilt way of running the system commands behind every
reading: structured output instead of printed text, honest outcomes, nothing left running.

- Apple Silicon only. Version 2.2 and later are built for Apple Silicon (arm64)
  alone; Intel Macs are no longer supported. On an Intel Mac, download
  `MacDashboard.zip` from the
  [v2.1 release](https://github.com/rdskcm/MacDashboard/releases/tag/v2.1) —
  the last version built for Intel.
- Settings window on macOS 27: the strip across the top of the window is one
  continuous panel again, with no see-through area above the sidebar, and the
  close, minimize and zoom buttons are all shown. The two cards in the General
  section now have the same shadow.
- More readings — hardware, Time Machine, disk status and SMART — now come from
  the tools' structured output (JSON or property lists) instead of their printed
  text, so a macOS update that rewords that text no longer breaks them.
- When a command's output still cannot be read, the report says so in a new
  section, "Unrecognised command output", with the first lines of that output
  (serial numbers and UUIDs masked) to attach to a bug report, instead of the
  reading silently going missing.
- A command that runs past its time limit is stopped together with every process
  it started, so no stray helper processes are left behind.
- Fixed: a command that finished normally could, rarely, be reported as timed
  out, so its section showed "not checked" after a delay of up to two minutes;
  more rarely still, a command that hit its time limit could leave the report
  collection waiting forever.
- smartctl is now run as `smartctl -A -j <disk>`. If you allowed it in sudoers
  with an exact argument list, add `-j` to that rule; a rule without arguments
  needs no change.
- Homebrew and smartctl installed under `/usr/local` are used only if the file
  is owned by root or by you and is not writable by others; otherwise they count
  as not installed. Installs under `/opt/homebrew` are unaffected.
- Building from source: `tools/signing/make-identity.sh` creates a local signing
  identity once per Mac, and builds signed with it keep the privacy permissions
  you granted (Full Disk Access and others) across rebuilds. The release
  download is still ad-hoc signed.
- For contributors: parser checks run against real captured outputs in
  `Tests/Fixtures/`, and `tools/visual/run.sh` compares the real app windows
  against reference screenshots.

## [2.1] (Krieg) - 2026-09-07

A maintenance release: the app is franker about what it could not measure, its
warning thresholds scale with the machine it runs on, and Russian counts read
correctly everywhere.

- macOS permission prompts for Desktop, Documents, Downloads and removable
  volumes now carry the app's own explanation of what it measures and why,
  instead of a bare system message.
- Files the app writes — the report, the history and the settings — are created
  readable only by your own account.
- An empty result is reported as an empty result. A check that ran and found
  nothing no longer looks like a failure, and Time Machine in particular is no
  longer reported as "not set up" when its status could not be read at all.
- A privileged check that ran and failed is reported as that check failing, not
  as a refused permission.
- Russian counts agree with their numbers everywhere ("3 отчёта", not
  "3 отчётов").
- Disk figures account for purgeable space and local APFS snapshots, so the free
  space shown matches what macOS itself reports.
- Warning thresholds for disk, memory and battery scale with the machine — RAM
  size, volume size and rated battery cycle life — instead of fixed numbers
  carried over from one Mac.
- The memory warning names both figures behind it, swap and compressed memory,
  instead of showing swap alone.

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
