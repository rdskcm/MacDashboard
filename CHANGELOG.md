# Changelog

All notable changes to this project are documented in this file.

## [2.3.2] (Krieg) - 2026-10-10

Three fixes: the Homebrew outdated list when the package index is slow to download, the folder-size
count on large folders, and safer install and cleanup scripts for contributors.

### Fixed

- Homebrew: when downloading the package index took longer than 60 s, the report lost the list of outdated packages. The index is now refreshed as a separate step with its own limit, and the outdated list is read after it even if the refresh fails.
- Folders: the size count now has one 90 s limit for all folders. When it runs out, the sizes already measured are kept and the folders not reached are listed as "not measured in time" on the Home and Service tabs and in the exported report.
- For contributors: `./build_app.sh --install` replaces the installed app through a temporary name and keeps the old copy if the move fails. Each `lsregister` call in `tools/ls-prune.sh` stops after 60 s, and `tools/visual/run.sh` reports `ls=partial` when a running copy stays registered.

## [2.3.1] (Krieg) - 2026-10-09

Six fixes: folder-size counting after a failure, hover text, the attention card layout, the cores
line on newer chips, and removal of system autostart items.

### New

- For contributors: the build goes to `dist.noindex/`, which Spotlight does not index, and `tools/ls-prune.sh` removes stale LaunchServices registrations of the app (build output, test builds, backup copies). Opening the app by its bundle ID now starts the installed copy.

### Fixed

- Folders card: when a size count failed (for example, it ran past its 2-minute limit), the app started a new full count every minute. Automatic counts now wait 1 hour after a failure. The Refresh button still counts at once.
- Autostart: removing a system-level item with administrator rights passed the path to `rm` without ending its options, so a path that began with `-` could be read as an option. Such a path is now always treated as a file name.
- Hover: on the Autostart capsules, the Homebrew upgrade button and the Memory legend, the label text moved ahead of its card and snapped back when the pointer entered. The text now moves with the card.
- Attention card: with 3 or more items, each item was stretched to half the card width. Items are now sized to their text and flow in rows, like the Recommendations capsules. An item too wide for the row is truncated.
- Processor: on a chip whose core layout the app did not know, the cores line could be missing. It now uses the core tier names that macOS reports, or shows the total number of cores.

## [2.3] (Krieg) - 2026-09-30

Faster reports, a History card with a range switch, a warning for programs that keep the Mac awake,
and a Stop button for Homebrew upgrades. Homebrew failures are now reported as failures.

### New

- Sleep: a new attention item names the programs that have kept the Mac awake for 5 minutes or more. Its tooltip lists them and a click opens Activity Monitor. Nothing is ever terminated.
- History card: a range switch above the chart shows the last month, 3 months, a year or all days. The default is month and it is not saved. "All" is thinned to at most 365 points.
- Homebrew upgrade: a Stop button in the progress row stops a running upgrade and lets Homebrew clean up a partial install. The card then re-checks and reports "stopped: K of N upgraded".
- For contributors: new checks for report writing, history storage, command construction and boundary cases, and a deterministic visual baseline.

### Improved

- History is no longer capped at 60 days. Every day is kept, and the History table shows the 10 newest days with a button for the rest.
- The macOS update check runs in the background with a 6-hour cache, so it no longer slows the report. The Updates card shows when it was last checked. Automatic work runs at low priority and the Refresh button at normal priority.
- Folder sizes are counted in the background and cached for 1 hour. The Folders card shows when they were counted, and the Refresh button always counts again.
- Memory alert: its level now follows the system memory pressure (normal, warning, critical) instead of swap size. The text names the 2 or 3 apps using the most memory. The swap tip is removed.
- The top-process lists no longer show the app's own helper processes (du, ps, top, brew).
- The text report has a new "COLLECTION TIMES" section with how long each part of the report took.
- All hints now use the app's own tooltip, and tooltip bubbles fit wrapped text without extra side margins.
- VoiceOver now reads the name of each segment and which one is selected in the segmented controls (History, Processes, Settings).

### Fixed

- Battery on macOS 27: capacity, temperature and the Lifetime section showed dashes or were empty. They are read again from the new locations.
- A history file that cannot be read is renamed aside (`mac_check_state.json.unreadable-<date>`) instead of being overwritten. Unreadable entries and unknown fields are kept on save.
- A Homebrew upgrade that printed progress and then failed, was killed or timed out was shown as success. It is now reported as failed unless the command exited normally.
- A failed `brew outdated` check was shown as "all packages up to date". It now shows a failed-check line and is not cached.
- An installed Homebrew whose `--version` failed was shown as not installed. It now shows "installed, version could not be determined".
- A failed Homebrew upgrade started from the Advice card showed no error there. The Advice card now shows the same error as the Maintenance card.

## [2.2] (Krieg) - 2026-09-25

Apple Silicon only, and a rebuilt way of running the system commands behind every
reading: structured output instead of printed text, honest outcomes, nothing left running.

### New

- When a command's output still cannot be read, the report says so in a new
  section, "Unrecognised command output", with the first lines of that output
  (serial numbers and UUIDs masked) to attach to a bug report, instead of the
  reading silently going missing.
- Building from source: `tools/signing/make-identity.sh` creates a local signing
  identity once per Mac, and builds signed with it keep the privacy permissions
  you granted (Full Disk Access and others) across rebuilds. The release
  download is still ad-hoc signed.
- For contributors: parser checks run against real captured outputs in
  `Tests/Fixtures/`, and `tools/visual/run.sh` compares the real app windows
  against reference screenshots.

### Improved

- More readings — hardware, Time Machine, disk status and SMART — now come from
  the tools' structured output (JSON or property lists) instead of their printed
  text, so a macOS update that rewords that text no longer breaks them.
- Homebrew and smartctl installed under `/usr/local` are used only if the file
  is owned by root or by you and is not writable by others; otherwise they count
  as not installed. Installs under `/opt/homebrew` are unaffected.

### Fixed

- Settings window on macOS 27: the strip across the top of the window is one
  continuous panel again, with no see-through area above the sidebar, and the
  close, minimize and zoom buttons are all shown. The two cards in the General
  section now have the same shadow.
- A command that runs past its time limit is stopped together with every process
  it started, so no stray helper processes are left behind.
- A command that finished normally could, rarely, be reported as timed
  out, so its section showed "not checked" after a delay of up to two minutes;
  more rarely still, a command that hit its time limit could leave the report
  collection waiting forever.

### Before you update

- Apple Silicon only. Version 2.2 and later are built for Apple Silicon (arm64)
  alone; Intel Macs are no longer supported. On an Intel Mac, download
  `MacDashboard.zip` from the
  [v2.1 release](https://github.com/rdskcm/MacDashboard/releases/tag/v2.1) —
  the last version built for Intel.
- smartctl is now run as `smartctl -A -j <disk>`. If you allowed it in sudoers
  with an exact argument list, add `-j` to that rule; a rule without arguments
  needs no change.

## [2.1] (Krieg) - 2026-09-07

A maintenance release: the app is franker about what it could not measure, its
warning thresholds scale with the machine it runs on, and Russian counts read
correctly everywhere.

### Improved

- macOS permission prompts for Desktop, Documents, Downloads and removable
  volumes now carry the app's own explanation of what it measures and why,
  instead of a bare system message.
- Files the app writes — the report, the history and the settings — are created
  readable only by your own account.
- Warning thresholds for disk, memory and battery scale with the machine — RAM
  size, volume size and rated battery cycle life — instead of fixed numbers
  carried over from one Mac.
- The memory warning names both figures behind it, swap and compressed memory,
  instead of showing swap alone.

### Fixed

- An empty result is reported as an empty result. A check that ran and found
  nothing no longer looks like a failure, and Time Machine in particular is no
  longer reported as "not set up" when its status could not be read at all.
- A privileged check that ran and failed is reported as that check failing, not
  as a refused permission.
- Russian counts agree with their numbers everywhere ("3 отчёта", not
  "3 отчётов").
- Disk figures account for purgeable space and local APFS snapshots, so the free
  space shown matches what macOS itself reports.

## [2.0] (Krieg) - 2026-08-28

Complete visual and structural rebuild of the interface on a new
design-token system: card-based layout, KPI tiles, an attention summary
with recommendation capsules, and a quiet/loud information hierarchy that
surfaces what needs attention and recedes what doesn't.

Licensed under the MIT License. See LICENSE.

### New

- Crash log detection with a 7-day window, collapsed rows and
  own-app/panic severity.
- Bulk delete for orphaned startup-item plists.

### Improved

- Redesigned Settings window (sidebar navigation, General/Monitoring pages,
  configurable process-list length).
- Redesigned battery popover with power, voltage, temperature, capacity and
  health.
- Confirmation gates before Homebrew upgrades and energy-setting changes.
- Time Machine status distinguishes "unmounted" from "not connected right
  now" and reports the real reason when Full Disk Access is missing.
- Live disk/swap verdicts and other readings reported honestly during
  collection rather than only after it finishes.
- Process lists are sampled natively from `ps`: lower overhead than the old full `top`
  parse, real pids, and untruncated process names. The memory column reports the same
  physical footprint Activity Monitor's "Memory" column shows — for every process on the
  machine, not just your own — from a single `top` snapshot per refresh.
- Hardened runtime on the app bundle, so no local process can inject code into an
  app that holds Full Disk Access.
- The chart footer's dates follow the Mac's Region setting — day/month/year order
  and separators — independent of the app's own language toggle, so an app set to
  English on a Mac with a German Region still shows German-style dates.

### Fixed

- SMART data for external drives can use the privileged smartctl path again, gated
  on the binary being one a non-root user cannot replace (see SPEC §5).
- Numerous layout, animation and accessibility fixes accumulated across the
  rebuild (segmented controls, disclosure/collapse behaviour, hover states,
  Reduce Motion support, live-resize stability).

### Known limitations

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

### New

- A full system report at launch: disk, memory, security, Time Machine, startup items, disk SMART data, battery, Homebrew and macOS updates, saved as one text file that each run overwrites.
- Live metrics for CPU, memory, swap, disk, battery and top processes, refreshed every 3 seconds.
- Each card switches between Chart and Table view without pausing the updates.
- A local history of disk usage and battery cycles, with import of an existing history file.
- SOC and internal-disk temperatures on Apple Silicon Macs. Intel Macs do not show this tile.
- One-click maintenance, each action explicit and confirmed: clean up orphaned startup entries, install smartmontools, refresh Time Machine, run `brew upgrade`, enable the firewall, empty the Trash.
- Energy-saver settings you can change from the app.
- English and Russian interface, switchable in Settings.

### Fixed

- The v1.0 download was rebuilt on 2026-07-27: Private IOKit temperature symbols are now resolved at runtime via
  `dlopen`/`dlsym` instead of being hard-linked. If a future macOS removes
  them, the temperature tile disappears instead of the app failing to
  launch. The v1.0 release asset was rebuilt from the current `main` to
  include this fix; the `v1.0` tag itself still points at the original
  commit.
