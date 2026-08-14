# SPEC — «Дашборд Mac» native SwiftUI app (MacDashboard)

Rewrite of the web pipeline (mac_checkup.sh → mac_report.txt → mac_dashboard.py →
HTML + mac_live_server.py SSE) as ONE native macOS app. No browser, no HTTP server,
no Python.

## Status of this document — read this before using it as a contract

This was the **build-out brief**: the ТЗ handed to the agents that constructed the app
from nothing in July 2026. Its phases (§11) are complete and its per-agent file
ownership (§3) describes a construction crew that no longer exists. The app has since
been rebuilt visually on the `v2` branch, and this file was not part of that work.

Its sections therefore have **two different lifetimes**, and they are labelled:

| Still binding | Historical — describes the v1.0 build, not today's code |
|---|---|
| §1 Goals & hard constraints, §2 Locations, §4 Data contracts, §5 Collectors, §6 Assessment, §7 Report text, §9 Packaging, §12 AI_ENABLED flag | §3 Package layout & file ownership, §8 UI, §10 Testing, §11 Phases |

**For anything in the right-hand column the code is the source of truth, not this file.**
Do not "restore" something it describes; do not update it to match a refactor either —
it is a record of how the app was built, and it is useful as that.

Verified against the tree on 2026-08-14 (branch `v2`). §1.6 and §2's output path were
wrong and were corrected then; the historical sections were labelled rather than
rewritten.

## 1. Goals & hard constraints

1. Native SwiftUI macOS app; single window. No network listeners of any kind.
2. **Portable to any Mac** (Apple Silicon or Intel, laptop or desktop):
   - NO hardcoded hardware names (no "Samsung SSD 9100 PRO"), usernames, or absolute
     paths outside standard APIs (`FileManager`, `NSHomeDirectory()`).
   - Absent hardware/feature ⇒ section shows a calm info state or hides; NEVER crash,
     NEVER show an error tone for "not present" (battery on desktops, Time Machine not
     configured, no external disks, no smartctl, no Homebrew).
3. **Report on launch**: app start triggers full report generation in background.
   Report is written to ONE fixed path, atomically overwritten each run — reports must
   not accumulate.
4. **Live metrics**: refresh every 3 s while app is frontmost/visible (pause timer when
   window closed / app hidden to save energy). Chart AND table representations render
   from the SAME observable state — switching a card to table view must keep updating
   (this fixes the old dashboard's bug).
5. UI language: **bilingual (English/Russian)**, switchable in Settings, via the
   `L10n` protocol with `StringsEN`/`StringsRU` witness files (see §8). Code +
   comments: English only, regardless of UI language.
6. **Read-only by default, with an enumerated set of user-initiated exceptions.**
   Collection never mutates anything: every collector and parser only reads. On top of
   that the app offers repair actions, each reachable ONLY by an explicit click. The
   list below is the complete set as of 2026-08-14 — **adding an entry to it is a spec
   change**, and no code path may mutate system state without appearing here.

   | # | Action | Call site | Privileges | Confirmed before running? |
   |---|---|---|---|---|
   | 1 | Empty the Trash | `Views/AdviceActionRunner.swift` (`NSAppleScript`, Finder) | user + TCC | yes — `Views/AdviceActionDispatch.swift:87` |
   | 2 | Enable the Application Firewall | `Engine/DashboardModel.swift:623` (`socketfilterfw --setglobalstate on`) | admin | yes — `Views/AdviceActionDispatch.swift:93` |
   | 3 | Delete an orphaned system launchd plist | `Engine/DashboardModel.swift:696` (`/bin/rm -f`, bulk at `:773`) | admin | yes — inline ask→confirm, `Views/AutostartCard.swift:604`/`:619` |
   | 4 | Delete an orphaned user launchd plist | `Engine/DashboardModel.swift:704` (`trashItem`, bulk at `:762`) | user | yes — same gate as 3 |
   | 5 | `brew upgrade` | `Engine/BrewUpgrader.swift:17` | user | **no** |
   | 6 | Install `smartmontools` via Homebrew | `Engine/DashboardModel.swift:583` | user | **no** |
   | 7 | Apply energy settings | `Views/EnergyCard.swift:311,320` (`pmset -b`/`-c`) | admin | **no** |

   Row 1 needs a second, separate macOS grant beyond the confirmation dialog: TCC
   Automation control of Finder, which the system asks for the first time the action
   actually runs (observed 2026-08-14 during the end-to-end verification). Declining it
   surfaces as a failure carrying Finder's own message. Row 1 also depends on Full Disk
   Access to be *offered* at all — see the `V2-FDA-DEGRADE` block in `PLAN.md`.

   Rows 5–7 run immediately on the button press. That is the current state, recorded
   here deliberately rather than papered over; whether to gate them is an open product
   decision, not an invariant this file may assert. Note that 3 is irreversible (a
   permanent `rm`, not a move to the Trash — see the reasoning at
   `DashboardModel.swift:668-677`) and that 7 escalates privileges without asking first.

   Two further boundaries hold with no exceptions: the app writes file **content** only
   inside `~/Library/Application Support/MacDashboard/` (rows 1, 3, 4 delete or move
   files elsewhere but never author them), and a default build contains no networking
   at all — see §12.
7. min deployment: **macOS 14** (needed for @Observable + Swift Charts). Build:
   SwiftPM, universal binary (arm64 + x86_64), hand-rolled .app bundle, ad-hoc codesign.

## 2. Locations

- Sources: `<project>/MacDashboard/` (SwiftPM package, this file lives there).
- App data dir: `~/Library/Application Support/MacDashboard/`
  (create on first run via `FileManager.urls(for: .applicationSupportDirectory…)`).
  - `mac_report.txt` — the single report file (overwritten).
  - `mac_check_state.json` — history (same schema as legacy file, see §6).
- Built app: `MacDashboard/dist/MacDashboard.app` — `APP_NAME="MacDashboard"` /
  `DIST="dist/$APP_NAME.app"` at `build_app.sh:20-21`. (`--install` copies it to
  `~/Applications/MacDashboard.app`, removing any stale bundle under the old
  «Дашборд Mac» name first. The bundle's *display* name is still «Дашборд Mac» via the
  localized InfoPlist.strings — that is what §9 means, and it is not the directory
  name.)

## 3. Package layout & file ownership

> **HISTORICAL — the v1.0 build-out layout.** The "owner" column assigned files to the
> parallel agents of §11 phase 2; those agents finished long ago. The tree has since
> grown to 30 files under `Engine/` and 26 under `Views/`, and none of
> `ContentView.swift`, `Components.swift`, `Cards.swift` still exist. The real test
> target is `Checks/` (an executable target, see §10's fallback), and
> `Tests/MacDashboardTests/` was never created. Read the tree, not this block.
>
> One rule below **is** still live and is repeated here so it does not get lost with
> the rest: `Models.swift` and `Package.swift` are frozen — if work genuinely requires
> changing them, stop and report the conflict instead of editing.

```
MacDashboard/
  Package.swift                 # scaffold owns
  SPEC.md
  build_app.sh                  # packaging phase owns
  Sources/MacDashboard/
    MacDashboardApp.swift       # scaffold
    Models.swift                # scaffold — FROZEN contract (below)
    Engine/DashboardModel.swift # scaffold (stubs) → collectors agent wires real data
    Engine/CommandRunner.swift  # collectors agent
    Engine/LiveCollector.swift  # collectors agent
    Engine/ReportCollector.swift# collectors agent
    Engine/Parsers.swift        # collectors agent
    Engine/Assessment.swift     # collectors agent
    Engine/ReportWriter.swift   # report agent
    Engine/HistoryStore.swift   # report agent
    Views/ContentView.swift     # UI agent
    Views/Components.swift      # UI agent (tiles, meters, ChartOrTableCard, Severity colors)
    Views/Cards.swift           # UI agent (all cards)
    Views/ReportTab.swift       # UI agent
  Tests/MacDashboardTests/      # integration phase (parsers + assessment fixtures)
```

Rule for agents: `Models.swift` and `Package.swift` are read-only once scaffolded.
If your work genuinely requires changing them — STOP and report the conflict in your
final message instead of editing.

## 4. Data contracts (Models.swift — verbatim)

```swift
import Foundation

enum Severity: String, Codable { case good, info, warn, serious, crit }

struct CPUUsage: Equatable { var user: Double; var sys: Double; var idle: Double }
struct ProcEntry: Identifiable, Equatable {
    var id: String { name }
    var name: String            // human app/process name (top truncates at 16 chars — keep raw)
    var cpu: Double?            // percent
    var memBytes: Int64?
}
struct MemSnapshot: Equatable {
    var total: Int64            // sysctl hw.memsize
    var pageSize: Int64
    // pages already multiplied to bytes:
    var free: Int64; var active: Int64; var inactive: Int64; var speculative: Int64
    var wired: Int64; var compressor: Int64; var purgeable: Int64; var fileBacked: Int64
    var usedBytes: Int64 { active + wired + compressor }   // ~Activity Monitor
    var otherBytes: Int64 {                                 // legacy dashboard "Прочее"
        let known = active + wired + inactive + speculative + free + compressor
        return Swift.max(0, total - known) + compressor
    }
}
struct SwapInfo: Equatable { var total: Int64; var used: Int64; var free: Int64 }
struct DiskInfo: Equatable {
    var size: Int64; var avail: Int64
    var usedTotal: Int64 { size - avail }
    var pct: Double { size > 0 ? Double(usedTotal) / Double(size) : 0 }
    var dataUsed: Int64?        // /System/Volumes/Data df "Used" if distinguishable
    var sysUsed: Int64?
}
struct BatteryInfo: Equatable {
    var source: String?         // "от сети" | "от батареи"
    var charge: Int?            // %
    var state: String?          // localized: заряжается/разряжается/заряжена/дозаряд/не заряжается
    var cycles: Int?
    var condition: String?      // raw pmset/system_profiler value, e.g. "Normal"
    var maxCapacity: Int?       // %
}

struct LiveSnapshot {
    var t: Date = .init()
    var load: [Double]?         // getloadavg 1/5/15
    var ncpu: Int = ProcessInfo.processInfo.activeProcessorCount
    var cpu: CPUUsage?
    var topCPU: [ProcEntry] = []
    var topMem: [ProcEntry] = []
    var mem: MemSnapshot?
    var swap: SwapInfo?
    var disk: DiskInfo?
    var battery: BatteryInfo?
}

// ---- Full report (sections nil until collected; nil ⇒ "недоступно") ----
struct SystemInfo: Equatable {
    var osName: String?; var osVersion: String?; var osBuild: String?
    var modelName: String?; var modelId: String?
    var chip: String?           // "Apple M3" | Intel brand string
    var cores: String?          // "8 (4 performance and 4 efficiency)" | "8"
    var memBytes: Int64?
    var uptime: String?         // human, Russian ("2 дня 3 мин")
    var hostName: String?
}
struct DirSize: Identifiable, Equatable { var id: String { path }; var path: String; var bytes: Int64 }
struct SecurityState: Equatable {
    // nil = unknown/no permission; true = enabled
    var fileVault: Bool?; var gatekeeper: Bool?; var sip: Bool?; var firewall: Bool?
}
struct TMDestination: Equatable {
    var name: String?; var kind: String?; var mountPoint: String?; var quotaBytes: Int64?; var lastBackup: String?
    // nil when lastBackup is set (or destination not yet checked); otherwise an
    // honest reason no date could be obtained (e.g. disk unmounted, or backup
    // date unreadable without Full Disk Access) — shown instead of a bare "—".
    var lastBackupUnavailableReason: String? = nil
}
struct AutostartInfo: Equatable {
    var loginItems: [String]?   // nil = no permission
    var userAgents: [String] = []; var systemAgents: [String] = []; var systemDaemons: [String] = []
    var background: [(pid: String, label: String)] = []
    static func == (l: Self, r: Self) -> Bool {
        l.loginItems == r.loginItems && l.userAgents == r.userAgents &&
        l.systemAgents == r.systemAgents && l.systemDaemons == r.systemDaemons &&
        l.background.elementsEqual(r.background, by: { $0 == $1 })
    }
}
struct SmartDisk: Identifiable, Equatable {
    var id: String { device }
    var device: String          // "/dev/disk4" or "internal"
    var title: String           // model/name for display
    var status: String          // "OK" | "VERIFIED" | "NO ACCESS" | "NOT SUPPORTED" | free text
    var attrs: [(String, String)] = []   // ordered SMART attributes (already human labels)
    var severity: Severity = .good
    static func == (l: Self, r: Self) -> Bool {
        l.device == r.device && l.title == r.title && l.status == r.status &&
        l.severity == r.severity && l.attrs.elementsEqual(r.attrs, by: { $0 == $1 })
    }
}
struct EnergySettings: Equatable { var battery: [(String, String)]; var ac: [(String, String)]
    static func == (l: Self, r: Self) -> Bool {
        l.battery.elementsEqual(r.battery, by: { $0 == $1 }) && l.ac.elementsEqual(r.ac, by: { $0 == $1 })
    }
}

struct FullReport {
    var createdAt: Date?
    var system: SystemInfo?
    var snapshots: [String]?            // TM local snapshot names
    var homeDirs: [DirSize]?            // top-20 of $HOME (depth 1)
    var serviceDirs: [DirSize]?         // caches etc.
    var security: SecurityState?
    var tmDest: TMDestination??         // .some(nil) = checked & not configured; nil = not checked yet
    var spotlight: String?
    var crashes: [String]?
    var brewVersion: String??           // .some(nil) = brew not installed
    var brewOutdated: [String]?
    var updates: [String]?              // pending macOS updates ([] = up to date)
    var smart: [SmartDisk]?
    var autostart: AutostartInfo?
    var energy: EnergySettings?
    var progress: [String: Bool] = [:]  // sectionKey -> done (for UI spinners)
}

struct Problem: Identifiable, Equatable {
    var id: String { text }; var sev: Severity; var text: String
    var action: AdviceAction? = nil     // advice block AR: clickable follow-up
}
struct Tip: Identifiable, Equatable {
    var id: String { text }; var text: String
    var action: AdviceAction? = nil     // advice block AR: clickable follow-up
}
struct Assessment {
    var problems: [Problem] = []        // sorted crit > serious > warn
    var tips: [Tip] = []
    var summarySev: Severity = .good
    var summaryText: String = L.recommendationsAllGood  // i18n S2: was "Всё в порядке"
    var diskSev: Severity = .good; var swapSev: Severity = .good
    var battSev: Severity = .good; var smartSev: Severity = .good
}

// ---- History (schema-compatible with legacy mac_check_state.json) ----
struct MacHistoryEntry: Codable, Equatable {
    var date: String            // "YYYY-MM-DD"
    var disk_used_gb: Int?; var disk_free_gb: Int?
    var battery_pct: Int?; var cycles: Int?
    var swap: String?; var macos: String?
}
struct HistoryState: Codable {
    var last_run: String?
    var mac_history: [MacHistoryEntry] = []
    // legacy keys preserved on round-trip via generic container (see HistoryStore)
}
```

`DashboardModel` (scaffold, `@MainActor @Observable final class`):
```swift
var live: LiveSnapshot            // replaced whole each tick
var cpuHistory: [(Date, Double)]  // last 60 points of user+sys for sparkline
var report: FullReport            // sections fill in as collected
var assessment: Assessment
var history: HistoryState
var reportText: String?           // rendered text report (for Отчёт tab)
var reportURL: URL                // fixed file path
var isCollectingReport: Bool
var lastError: String?
func start()                      // begin live timer + launch report generation
func refreshReport()              // re-run full report (single-flight; ignore if running)
```

## 5. Collectors

### 5.1 LiveCollector (every 3 s; runs off-main, publishes to model on main)
- CPU %: `host_processor_info`/`host_statistics64(HOST_CPU_LOAD_INFO)` — diff ticks
  between samples (user+sys+idle). NO subprocess.
- mem: `host_statistics64(HOST_VM_INFO64)` × `vm_kernel_page_size`; total `sysctl hw.memsize`.
- swap: `sysctl vm.swapusage` (struct xsw_usage via sysctlbyname).
- disk: `URL(fileURLWithPath:"/System/Volumes/Data")` (fallback "/")
  `.volumeTotalCapacity` + `.volumeAvailableCapacityForImportantUsage`.
- battery: IOKit `IOPSCopyPowerSourcesInfo` (+ cycles/condition only in full report).
  Desktop Mac ⇒ nil, tile hidden.
- load: `getloadavg`.
- top processes: `top -l 2 -s 1 -o cpu -n 12 -stats pid,cpu,mem,command` subprocess,
  parse LAST sample only (first is since-boot garbage). From it also build topMem?
  NO — separate cheap `top -l 1 -o mem -n 12 -stats pid,mem,cpu,command` like legacy.
  Both via CommandRunner with 12 s timeout. Use `pid,` in stats to get full names?
  top truncates COMMAND anyway; acceptable (legacy did the same). Keep order parsing
  tolerant: split by whitespace, columns per requested stats order.
- Cadence guard: if a tick's collection takes > interval, skip next tick (single-flight).

### 5.2 ReportCollector (on launch + «Обновить» button; async, per-section)
Each section = independent async step with its own timeout; failure ⇒ section value
stays nil + progress marked done. Run sections concurrently (TaskGroup) EXCEPT the
du-heavy ones which run serially after the quick ones. Commands (all read-only):
- system: `sw_vers`, `system_profiler SPHardwareDataType` (Model Name/Identifier,
  Chip OR "Processor Name" on Intel, Cores, Memory), `sysctl -n machdep.cpu.brand_string`
  fallback for chip, `uptime` (parse → Russian human form).
- snapshots: `tmutil listlocalsnapshots /`.
- homeDirs: `du -xk -d 1 $HOME` (120 s timeout) → top-20 by size. NOTE: first run on a
  fresh Mac triggers TCC prompts (Desktop/Documents/Downloads) — that's OK; on denial
  du prints errors to stderr, still use what it returns; never fail the section.
- serviceDirs: `du -xsk` over: ~/Library/Caches, ~/Library/Application Support,
  ~/Library/Containers, ~/Library/Group Containers, ~/Library/Developer, ~/.Trash,
  /Library/Caches, /private/var/log, /Applications (90 s total).
- security: `fdesetup status`, `spctl --status`, `csrutil status`,
  `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` (fallback
  `defaults read /Library/Preferences/com.apple.alf globalstate`; 1/2 ⇒ on).
- tmDest: `tmutil destinationinfo` (absent ⇒ .some(nil) — "не настроен", calm info);
  `tmutil latestbackup` best-effort for lastBackup (may need FDA ⇒ nil).
- spotlight: `mdutil -s /`.
- crashes: newest 15 of `~/Library/Logs/DiagnosticReports` (FileManager, no shell).
- brew: resolve from /opt/homebrew/bin/brew, /usr/local/bin/brew, PATH; absent ⇒
  brewVersion = .some(nil). Else `brew --version` + `brew outdated` (60 s).
- updates: `softwareupdate -l` (120 s timeout; on timeout ⇒ nil = "не проверено").
- autostart: `osascript -e 'tell application "System Events" to get the name of every
  login item'` (no permission ⇒ loginItems = nil, show "(нет разрешения)"); ls of
  ~/Library/LaunchAgents, /Library/LaunchAgents, /Library/LaunchDaemons via FileManager;
  `launchctl list` filtered: label NOT starting with "com.apple." (keep legacy cleanup:
  strip "application." prefix and trailing ".NNN.NNN").
- smart (GENERIC, replaces Samsung-specific block):
  1) Internal: `diskutil info disk0` → "SMART Status: Verified/Not Supported" ⇒
     SmartDisk(device:"internal", title:"Встроенный накопитель" + model if present).
  2) External physical disks: `diskutil list` → identifiers marked "external, physical".
     For each: `diskutil info <dev>` for model/name + SMART status line.
  3) If smartctl exists (search /opt/homebrew/{bin,sbin}, /usr/local/{bin,sbin}) —
     try `sudo -n smartctl -A <dev>` (then plain `smartctl -A` without sudo);
     on success attach NVMe attrs (Critical Warning, Temperature, Available Spare,
     Percentage Used, Power Cycles, Power On Hours, Unsafe Shutdowns,
     Media and Data Integrity Errors, Error Information Log Entries).
     `sudo -n` MUST use stdin </dev/null; nonzero exit ⇒ just skip attrs, status from
     diskutil stands. No smartctl ⇒ still list disks with diskutil info only.
  No external disks ⇒ smart = internal only. NOTHING here may error the report.
- energy: `pmset -g custom` (fallback `pmset -g`); parse Battery Power/AC Power buckets.
- battery full: `pmset -g batt` + `system_profiler SPPowerDataType` grep Cycle Count/
  Condition/Maximum Capacity → merged into model.live.battery AND report for assessment.

CommandRunner: Process + DispatchSourceTimer kill on timeout; captures stdout+stderr;
returns String? (nil on any failure). Absolute paths for binaries (/usr/bin/…,
/usr/sbin/…) where knowable; PATH lookup via /usr/bin/env otherwise.

## 6. Assessment (port of assess() — same thresholds)

- disk: pct ≥ .85 ⇒ crit "Диск заполнен на N% — срочно освободите место."; ≥ .70 ⇒ warn "… — пора освобождать место."
- swap used ≥ 2 GiB ⇒ serious problem; ≥ 1 GiB ⇒ warn tip (wording from legacy).
- battery: maxCapacity < 70 ⇒ serious; < 80 ⇒ warn tip; condition != "Normal" ⇒ serious.
- security: each of FileVault/Gatekeeper/SIP/Firewall == false ⇒ serious "X выключен — стоит включить." (nil ⇒ silent).
- updates: count > 0 ⇒ warn "Доступны обновления macOS: N шт."
- brew outdated > 0 ⇒ tip.
- crashes > 0 ⇒ warn "Свежие крэш-репорты: N — посмотрите в Console.app."
- tmDest == .some(nil) ⇒ warn "Time Machine не настроен — бэкапов нет."
- smart: any disk with Critical Warning != 0x00 or Media Errors > 0 ⇒ crit;
  Percentage Used ≥ 80 ⇒ warn; SMART "NO ACCESS" on external ⇒ tip (переподключите кабель / установите smartmontools).
- homeDirs: Downloads > 10 GiB ⇒ tip («Загрузки» занимают X — стоит разобрать);
  .Trash > 1 GiB ⇒ tip; ~/Library/Caches > 3 GiB ⇒ tip.
- summary: worst severity; "Замечаний: N" | "Всё в порядке".
Assessment recomputed when report sections change AND lightly on live ticks
(disk/swap tiles reflect live values).

## 7. Report text (ReportWriter)

Mirror legacy layout so the file stays familiar:
first line `Отчёт создан: <date>`, sections `\n===== NAME =====\n` in the same order
as mac_checkup.sh (СИСТЕМА, ДИСК, ЛОКАЛЬНЫЕ СНАПШОТЫ TIME MACHINE, ДОМАШНЯЯ ПАПКА…,
ТЯЖЁЛЫЕ СЛУЖЕБНЫЕ ПАПКИ, ПАМЯТЬ, ТОП-10 ПО ПАМЯТИ, ТОП-10 ПО CPU, АВТОЗАГРУЗКА…,
ФОНОВЫЕ ЗАДАЧИ, БАТАРЕЯ, НАСТРОЙКИ ЭНЕРГИИ, БЕЗОПАСНОСТЬ, TIME MACHINE, SPOTLIGHT,
НЕДАВНИЕ КРАШИ, HOMEBREW, ОБНОВЛЕНИЯ macOS, ВНЕШНИЕ ДИСКИ: SMART, ГОТОВО).
Unavailable section ⇒ `(недоступно)` / `(нет)` lines, as legacy did.
Values rendered from structured data (not raw command dumps) is fine, but keep df-like
disk line and vm_stat-like memory block human-readable.
Write: to temp file in same dir + atomic replace (`FileManager.replaceItemAt` or
Data.write(.atomic)). Path: App Support/mac_report.txt. ALWAYS the same path ⇒ no
accumulation. Menu/button «Показать отчёт в Finder» (NSWorkspace.activateFileViewerSelecting).

HistoryStore: load legacy-compatible JSON; after each completed report upsert TODAY's
MacHistoryEntry (replace same-date), cap 60 entries, save atomically. Preserve unknown
JSON keys (decode into [String: JSONValue] passthrough or merge on save) so the legacy
file schema (nvme_history etc.) survives an import. Import button: «Импортировать
историю…» (NSOpenPanel) merges mac_history by date.

## 8. UI (bilingual EN/RU; tone = old dashboard)

> **HISTORICAL — this is the v1.0 interface.** The whole UI was rebuilt on the `v2`
> branch: the two-tab «Обзор | Отчёт» shell, the card inventory and the layout below no
> longer match what ships. Treat this as a record of the original design brief.
>
> Three things in it are still accurate and load-bearing: the window geometry
> (`MacDashboardApp.swift:20,25` — default 1150×780, min 900×620), the bilingual `L10n`
> protocol with `StringsEN`/`StringsRU` witnesses, and the `ChartOrTableCard` rule that
> chart and table must read the SAME observable state — that last one is the regression
> the original dashboard had, and it is still the reason the component exists.

Window ~1150×780 (min 900×620). Every user-facing label below is illustrated in
Russian for concreteness (matching the legacy dashboard's tone), but each one is a
`L10n` key with an entry in both `StringsRU.swift` and `StringsEN.swift` — the UI
renders whichever locale is selected in Settings, defaulting to the system language.
Structure:
- Header: «Диагностика Mac» + sub "MacBook Air · Apple M3 · 8 ГБ · macOS 26.5.2" (from
  report; placeholders while collecting) + chips: uptime, load, состояние
  («Всё в порядке» green / «Замечаний: N» tinted by severity) + «Обновить отчёт»
  button with spinner while collecting.
- KPI tiles (live, 3 s): Процессор (value % + sparkline of cpuHistory + "load … · N ядер"),
  Память (used of total + meter + "сжатая X · выгружаемая Y"), Подкачка (used of total,
  meter, sev), Диск (свободно X из Y, meter, sev, "занято …%"), Батарея (ёмкость %,
  "N циклов · состояние · сейчас X%, заряжается (от сети)", meter) — tile hidden if
  battery == nil. SMART tile only if an external disk with attrs present (temp/wear).
- Cards grid (2 columns adaptive):
  - «Рекомендации» (problems list with sev dots + tips) — full width.
  - «Память» stacked bar (segments legacy: Активная/Связанная (ядро)/Прочее (вкл.
    сжатую)/Неактивная/Спекулятивная/Свободно) + table toggle (Категория/Объём/Доля +
    справочно Выгружаемая, Файловый кэш). LIVE.
  - «Процессы по CPU» bar chart + table (Процесс/CPU/Память). LIVE.
  - «Процессы по памяти» bar chart + table (Процесс/Память/CPU). LIVE.
  - «Диск» (bar: данные/система/свободно if known) + «Домашняя папка» top dirs bar
    chart/table. Report-time.
  - «Служебные папки» table. «Безопасность» (4 rows ✓/✗). «Time Machine» (dest, quota,
    last backup, local snapshots). «Автозагрузка» (login items + agents/daemons +
    background non-Apple). «Диски (SMART)» per-disk status + attrs table. «Настройки
    энергии» (двухколоночная таблица батарея/сеть, collapsed by default via
    DisclosureGroup). «История» line chart (disk_used_gb over dates; batt cycles) +
    table — from HistoryState. «Homebrew», «Обновления», «Крэши» compact cards.
- Tabs (Picker or TabView): «Обзор» | «Отчёт» (monospaced scrollable reportText +
  «Показать в Finder», «Скопировать»).
- ChartOrTableCard component: header (title, caption, toggle button «Таблица»/«График»)
  + content switches @State isTable; BOTH subviews read the same model data — live
  updates flow regardless of view. This is the regression test target for the old bug.
- Colors: system semantic + severity palette from legacy CSS (good #0ca30c,
  warn #fab219, serious #ec835a, crit #d03b3b; s1 #2a78d6 / dark #3987e5 etc.).
  Support light+dark via dynamic NSColor(name:) or Color(light:dark:) helper.
- Charts: Swift Charts (BarMark horizontal for processes/dirs, LineMark for sparkline
  and history). Tables: plain SwiftUI `Table` or Grid — Grid preferred (lighter).

## 9. Packaging (build_app.sh)

```
swift build -c release --triple <arch>-apple-macosx   # per-arch, then `lipo` into a universal binary
dist/MacDashboard.app/Contents/{MacOS/MacDashboard, Info.plist, Resources/AppIcon.icns, Resources/{en,ru}.lproj/InfoPlist.strings}
```
`--arch` universal builds require Xcode's xcbuild and aren't available under bare
Command Line Tools, so build_app.sh instead builds arm64 and x86_64 separately via
`--triple`, then combines them with `lipo`. If only one arch's toolchain is available,
it falls back to a native-arch-only build (either direction) and records that in the
build output.

Info.plist: CFBundleIdentifier=com.rdskcm.mac-dashboard, CFBundleName=MacDashboard,
CFBundleDisplayName=MacDashboard, LSMinimumSystemVersion=14.0, NSHighResolutionCapable,
CFBundleShortVersionString/CFBundleVersion: version is defined solely by `VERSION`/`CODENAME` in `build_app.sh`. LSApplicationCategoryType=public.app-category.utilities,
NSHumanReadableCopyright, NSAppleEventsUsageDescription. NO LSUIElement (normal Dock app).
Localized `en.lproj`/`ru.lproj` InfoPlist.strings are generated for the display name.
Icon: reuse legacy generator idea — render simple pulse-line icon via CoreGraphics
swift script into iconset → iconutil (best-effort; skip icon on failure).
codesign --force --deep --sign - "dist/MacDashboard.app".
`--install` flag: copies the built bundle to `~/Applications/MacDashboard.app`, removing
any stale bundle under an old app name first.
README-install note: on another Mac after copying, if Gatekeeper complains:
`xattr -dr com.apple.quarantine "MacDashboard.app"` or right-click → Open.

## 10. Testing

> **HISTORICAL — the plan, not the outcome.** The `import Testing` route in the first
> bullet was tried and failed under bare Command Line Tools; the fallback it names is
> what actually exists, as `Checks/` (target `MacDashboardChecks`, sources symlinked
> into `Sources/MacDashboard/` so the checks exercise the same files as the app). See
> the note in `Package.swift:17-23` and `Checks/README.md`.

- Unit tests (swift-testing `import Testing`; if unavailable with CLT, make a separate
  `MacDashboardChecks` executable target run via `swift run` that asserts and exits
  nonzero on failure — DO NOT depend on XCTest).
- Headless UI screenshot harness (`tools/harness/`, dev tool, not part of the
  pass/fail Checks target): renders a SwiftUI scenario file off-screen to a PNG via
  `render.sh <scenario.swift> <out.png>` for visual verification of Views.
- Parser fixtures (inline string-literal fixtures in Checks/main.swift): top output (both stats
  orders, with +/- suffixes), vm.swapusage line, pmset -g batt (laptop AC/battery,
  desktop = no battery lines), system_profiler hardware (M3 Mac AND Intel with
  "Processor Name"/"Processor Speed"), tmutil destinationinfo (configured / "No
  destinations configured"), diskutil SMART lines (Verified / Not Supported), smartctl
  -A NVMe output, launchctl list, pmset -g custom, uptime lines (days/hours/mins forms).
- Assessment tests: thresholds table (§6) — one test per rule incl. "absent ⇒ good/silent".
- Portability tests = fixtures above with absent pieces (nil battery, no TM, no
  external disks, no smartctl, Intel).
- E2E (tester agent): build universal; verify `lipo -archs` shows both; assemble .app;
  launch via `open`; poll App Support for mac_report.txt (≤3 min); check window exists
  (`osascript`/`lsappinfo`); relaunch → file mtime changes, still exactly ONE report
  file; app quits cleanly; Console shows no crash for bundle id. Live-table bug: covered
  by unit test on DashboardModel (tick mutates model → both chart & table read same
  source) + manual note for user.

## 11. Phases

> **HISTORICAL — all four phases completed in v1.0.** This was the construction
> schedule for the parallel agents of §3. Current work is tracked in the project's
> `PLAN.md`, not here.

1. Scaffold (Package.swift, Models.swift, App entry, DashboardModel with stub/random
   data, minimal ContentView showing stub KPI) — must `swift build` clean.
2. Parallel: collectors agent (§5, §6) | UI agent (§8 against stub model) | report
   agent (§7). File ownership per §3.
3. Integration: wire real collectors into model, tests (§10), fix build.
4. Packaging + E2E + install to ~/Applications.

## 12. AI assistant compile flag (AI_ENABLED)

The optional AI assistant feature is gated behind the Swift compile-time flag
`AI_ENABLED`, OFF by default:

- `Package.swift` defines `AI_ENABLED` unconditionally for the `MacDashboardChecks`
  SPM target only, so the AI-related pure-logic files (`AIRedaction.swift`,
  `AIPayload.swift`, `AIRequest.swift`, etc.) keep building and running under
  `swift run MacDashboardChecks` regardless of how the app itself is built.
- The `MacDashboard` app target does NOT get `AI_ENABLED` by default. It is only
  passed in when building with `MACDASHBOARD_AI=1 ./build_app.sh`, which adds
  `-Xswiftc -DAI_ENABLED` to both the arm64 and x86_64 slice builds (see
  `build_app.sh`).
- A default build (`./build_app.sh` with no environment override) therefore ships
  zero AI/networking code: no AI request/redaction/payload logic is compiled into
  the app binary at all, not merely hidden behind a UI toggle.
