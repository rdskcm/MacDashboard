// Models.swift
// Data contracts — scaffold owns this file. FROZEN once scaffolded (SPEC §3, §4):
// if downstream work genuinely requires changing it, STOP and report the conflict
// instead of editing. Copied verbatim from SPEC §4.

import Foundation

enum Severity: String, Codable { case good, info, warn, serious, crit }

struct CPUUsage: Equatable { var user: Double; var sys: Double; var idle: Double }
struct ProcEntry: Identifiable, Equatable {
    // "p<pid>" when a pid is known (stable across re-sorts/ticks — lets a card
    // track "this same process" across live updates); falls back to the old
    // rank-based id (keeps ids unique when top truncates two processes to the
    // same name) when pid is unavailable.
    var id: String { pid.map { "p\($0)" } ?? "\(rank)-\(name)" }
    var rank: Int = 0
    var name: String            // human app/process name, as `/bin/ps -o comm=` reports it
    var cpu: Double?            // percent
    var memBytes: Int64?
    var pid: Int32? = nil       // new; default keeps existing initializers compiling
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

/// Why the last-backup date could not be obtained. A case, never a localized
/// sentence: the Time Machine card used to detect "no Full Disk Access" by comparing
/// the stored string against the current language's translation, so right after a
/// language switch the comparison stopped matching and the row lost its alarm colour
/// until the next report refresh (V2-HONEST-READINGS).
enum TMBackupUnavailableReason: Equatable {
    /// `tmutil latestbackup` answered "no backup…".
    case noBackupsYet
    /// The destination has no mount point — the disk is not connected.
    case diskNotConnected
    /// `diskutil` ran fine and listed zero completed snapshots.
    case noCompletedBackups
    /// Mounted, but the date is unreadable — the only case that is a real problem.
    case dateUnavailableNoFDA

    /// Rendered in the language current at READ time, so a language switch updates the
    /// card immediately instead of waiting for the next collect.
    var localizedText: String {
        switch self {
        case .noBackupsYet:         return L.reportCollectorNoBackupsYet
        case .diskNotConnected:     return L.reportCollectorDiskNotConnected
        case .noCompletedBackups:   return L.reportCollectorNoCompletedBackups
        case .dateUnavailableNoFDA: return L.reportCollectorDateUnavailableNoFDA
        }
    }
}

struct TMDestination: Equatable {
    var name: String?; var kind: String?; var mountPoint: String?; var quotaBytes: Int64?; var lastBackup: String?
    // nil when lastBackup is set (or destination not yet checked); otherwise an
    // honest reason no date could be obtained (e.g. disk unmounted, or backup
    // date unreadable without Full Disk Access) — shown instead of a bare "—".
    // Stored as a case, not a sentence — see TMBackupUnavailableReason.
    var lastBackupUnavailableReason: TMBackupUnavailableReason? = nil
}
struct AutostartInfo: Equatable {
    var loginItems: [String]?   // nil = no permission
    var userAgents: [LaunchdPlistInfo] = []; var systemAgents: [LaunchdPlistInfo] = []; var systemDaemons: [LaunchdPlistInfo] = []
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

/// One row of the crash section: every crash report a single process produced
/// inside the collection window, collapsed into one entry with a count
/// (V2-CRASH-SIGNAL). `process` is parsed off the report filename — the only
/// data source available without reading report contents. `isPanic` is true when
/// at least one of the collapsed reports is a `.panic` (kernel panic): those
/// raise attention whatever process logged them. `directory` is the absolute path
/// of the DiagnosticReports directory the group's first surviving report was
/// listed in (V2-CRASH-REVEAL); it is what the reveal action opens.
struct CrashGroup: Identifiable, Equatable {
    var process: String         // "diffscore"
    var count: Int              // reports from that process inside the window
    var isPanic: Bool = false   // at least one of them a kernel panic (.panic)
    var directory: String       // "/Library/Logs/DiagnosticReports" — where its first report was found
    var id: String { process }
}

struct FullReport {
    var createdAt: Date?
    var system: SystemInfo?
    var snapshots: [String]?            // TM local snapshot names
    var homeDirs: [DirSize]?            // top-20 of $HOME (depth 1)
    var serviceDirs: [DirSize]?         // caches etc.
    // Absolute paths of directories the collector could see but not read (no Full
    // Disk Access) — the same idea as TMDestination.lastBackupUnavailableReason:
    // an honest reason parked next to the value it explains. `[]` = nothing was
    // hidden. Orthogonal to homeDirs/serviceDirs == nil, which still means "not
    // collected yet".
    var homeDirsUnreadable: [String] = []
    var serviceDirsUnreadable: [String] = []
    var security: SecurityState?
    var tmDest: TMDestination??         // .some(nil) = checked & not configured; nil = not checked yet
    var spotlight: String?
    var crashes: [CrashGroup]?          // grouped, ≤7 days old (V2-CRASH-SIGNAL)
    var brewVersion: String??           // .some(nil) = brew not installed
    var brewOutdated: [String]?
    var updates: [String]?              // pending macOS updates ([] = up to date)
    var smart: [SmartDisk]?
    var autostart: AutostartInfo?
    var energy: EnergySettings?
    var battery: BatteryInfo?           // report-time merge: pmset + system_profiler (cycles/condition/capacity)
    var progress: [String: Bool] = [:]  // sectionKey -> done (for UI spinners)
    var smartctlPresent: Bool = true    // whether smartctl was found on last collectSmartDisks() run (Block N8)
}

struct Problem: Identifiable, Equatable {
    var id: String { text }; var sev: Severity; var text: String
    var action: AdviceAction? = nil     // advice block AR: clickable follow-up
}
struct Tip: Identifiable, Equatable {
    var id: String { text }; var text: String
    var action: AdviceAction? = nil     // advice block AR: clickable follow-up
}
struct Assessment: Equatable {
    var problems: [Problem] = []        // sorted crit > serious > warn
    var tips: [Tip] = []
    var items: [AttentionItem] = []       // v2 attention model — mirrors `problems`
    var capsules: [TipCapsule] = []       // v2 attention model — mirrors `tips`
    var summarySev: Severity = .good
    var summaryText: String = L.recommendationsAllGood
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
