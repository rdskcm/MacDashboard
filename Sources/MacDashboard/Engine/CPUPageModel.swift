// Engine/CPUPageModel.swift
// REDESIGN-CPU: pure state, texts, tones and thresholds of the CPU page (handoff 03-cpu) and of the
// restyled Processes card. Foundation only; the views render what `CPUPageModel.make` returns.
import Foundation
import CoreGraphics

/// Which ProcEntry field ranks a process list — `.cpu` reads CPU%, `.mem` reads memory bytes (the
/// other field becomes the row's dimmer secondary annotation). `Hashable` so `DSSlidingSegmented<T>`
/// (Views/DesignSystem.swift) can track the current selection. Moved from Views/ProcessCards.swift.
enum Metric: Hashable, Sendable { case cpu, mem }

/// Mac SoC temperature level (HOME-LEFTOVERS): the one classification every SoC temperature display uses.
enum SocTempLevel: Equatable, Sendable { case normal, warm, hot }

/// THERMAL-STATE: macOS's own thermal state (ProcessInfo.thermalState), shown beside the SoC temperature.
/// Never converted into a throttling percentage.
enum ThermalLevel: Equatable, Sendable {
    case nominal, fair, serious, critical
    /// nil for a case added after this code was written (@unknown default).
    init?(_ s: ProcessInfo.ThermalState) {
        switch s {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: return nil
        }
    }
}

enum CPUNoteTone: Equatable { case green, neutral, amber, hot }

/// REDESIGN-CPU thresholds (03-cpu:20) and the high-load run tracker. High = ≥ 85 % for at least 60 s
/// (TRIAGE-THRESHOLDS-REVIEW D4).
enum CPULoad {
    static let highUsagePct: Double = 85
    /// SoC temperature thresholds, user decision 2026-10-19 (HOME-LEFTOVERS, option B): Apple publishes no limit and
    /// M-series chips sit at 90-100 °C under normal heavy load, so warm from 85 °C and hot from 95 °C. The ONLY SoC
    /// temperature rule in the app — the CPU page tile and the Home CPU chip both call `socLevel`.
    static let socWarmC = 85
    static let socHotC = 95
    static func socLevel(_ celsius: Int) -> SocTempLevel {
        celsius >= socHotC ? .hot : (celsius >= socWarmC ? .warm : .normal)
    }
    /// A gap between two successful CPU samples longer than this restarts a high-load run (pause, sleep).
    static let maxSampleGap: TimeInterval = 30

    static func usage(_ c: CPUUsage) -> Double { c.user + c.sys }

    /// usage < highUsagePct → nil. Otherwise `previous` when it is non-nil AND previousSampleAt is non-nil
    /// AND now − previousSampleAt <= maxSampleGap; else `now`.
    static func nextHighSince(previous: Date?, previousSampleAt: Date?, usage: Double, at now: Date) -> Date? {
        guard usage >= highUsagePct else { return nil }
        if let previous, let previousSampleAt, now.timeIntervalSince(previousSampleAt) <= maxSampleGap {
            return previous
        }
        return now
    }

    /// High load as the CPU page and Home decide it: usage at or above the threshold and the run lasted a minute.
    static func isHigh(_ c: CPUUsage, since: Date?, now: Date) -> Bool {
        usage(c) >= highUsagePct && highMinutes(since: since, now: now) != nil
    }

    /// nil when since is nil or now − since < 60 s; else Int((now − since) / 60) (floor).
    static func highMinutes(since: Date?, now: Date) -> Int? {
        guard let since else { return nil }
        let elapsed = now.timeIntervalSince(since)
        guard elapsed >= 60 else { return nil }
        return Int(elapsed / 60)
    }
}

enum CPUPagePhase: Equatable { case loading, live, high, failed(BlockFailure, lastGoodAt: Date?) }
enum CPUTagKind: Equatable { case ok, high, loading, failed }

struct CPUHeroModel: Equatable { var value: String; var fraction: Double; var note: String; var high: Bool; var dimmed: Bool }

struct CPUPageModel: Equatable {
    struct Input {
        var cpu: CPUUsage?; var ncpu: Int; var chip: String?
        var block: BlockPhase; var highSince: Date?; var now: Date; var intervalSeconds: Int
        var gpuUtil: Int? = nil
        /// SOC-DETAILS §7.3: below 1000 pt with the state tag visible the sub line drops "updates every N s".
        var compactSub: Bool = false
    }

    var tag: CPUTagKind
    var tagText: String
    var sub: String
    var subIsFailure: Bool      // true only in .failed
    var caption: String         // CPU card caption
    var failureNote: String?    // non-nil only in .failed
    var hero: CPUHeroModel
    var split: SocSplit         // User / System / Idle (logic 3.3); "—" without a reading
    var gpu: CPUHeroModel       // GPU card hero

    static func make(_ i: Input) -> CPUPageModel {
        let phase: CPUPagePhase
        switch i.block {
        case .failed(let f, let g): phase = .failed(f, lastGoodAt: g)
        case .loading: phase = .loading
        case .ok:
            if let cpu = i.cpu {
                phase = CPULoad.isHigh(cpu, since: i.highSince, now: i.now) ? .high : .live
            } else {
                phase = .loading
            }
        }
        let trimmedChip = i.chip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chipPrefix = trimmedChip.isEmpty ? "" : "\(trimmedChip) · "

        let tag: CPUTagKind
        let tagText: String
        var sub: String
        var caption = L.cpuLiveSnapshot
        var failureNote: String? = nil
        switch phase {
        case .live:
            tag = .ok; tagText = L.commonOK
            sub = chipPrefix + (i.compactSub ? L.homeCoresOnly(i.ncpu) : L.cpuSubLive(i.ncpu, i.intervalSeconds))
        case .high:
            tag = .high; tagText = L.cpuTagHigh
            sub = chipPrefix + (i.compactSub ? L.homeCoresOnly(i.ncpu) : L.cpuSubLive(i.ncpu, i.intervalSeconds))
        case .loading:
            tag = .loading; tagText = L.commonCollectingData
            sub = chipPrefix + L.cpuSubCollecting
        case .failed(let f, let g):
            tag = .failed; tagText = L.cpuTagReadError
            if let g {
                sub = chipPrefix + L.commonLastData(hhmmss(g))
                caption = L.commonLastData(hhmmss(g))
            } else {
                sub = chipPrefix + L.homeCoresOnly(i.ncpu)
            }
            let reason = f == .timedOut ? L.cpuFailTimedOut : L.cpuFailNoReading
            failureNote = reason + " " + L.readRetriesAutomatically
        }

        let gpu: CPUHeroModel
        if let g = i.gpuUtil {
            gpu = CPUHeroModel(value: L.homePercent("\(g)"), fraction: Double(g) / 100, note: L.gpuWholeMac, high: false, dimmed: false)
        } else {
            gpu = CPUHeroModel(value: "—", fraction: 0, note: L.gpuNotAvailable, high: false, dimmed: true)
        }

        let hero: CPUHeroModel
        let split: SocSplit
        let showsReading = phase == .live || phase == .high
        if showsReading, let cpu = i.cpu {
            let usage = CPULoad.usage(cpu)
            let high = phase == .high
            // D18: the load average has its own tile; the note is the core count, or the high-load text.
            let note: String
            if high, let m = CPULoad.highMinutes(since: i.highSince, now: i.now) {
                note = L.cpuHighLoadFor(m)
            } else {
                note = L.homeCoresOnly(i.ncpu)
            }
            hero = CPUHeroModel(value: L.homePercent(fmtFixed(usage, decimals: 1)),
                                fraction: min(max(usage / 100, 0), 1),
                                note: note, high: high, dimmed: false)
            split = SocSplit.make(cpu: cpu)
        } else {
            // D17: the not-yet state is part of the hero ("—" + "collecting data…"), not a replacement of the card.
            let note: String
            if case .failed = phase { note = L.cpuNoReading } else { note = L.cpuSubCollecting }
            hero = CPUHeroModel(value: "—", fraction: 0, note: note, high: false, dimmed: true)
            split = SocSplit.make(cpu: nil)
        }

        var isFailed = false
        if case .failed = phase { isFailed = true }
        return CPUPageModel(tag: tag, tagText: tagText, sub: sub, subIsFailure: isFailed,
                            caption: caption, failureNote: failureNote, hero: hero, split: split, gpu: gpu)
    }

    /// "HH:mm:ss" in the current zone, POSIX digits (pattern of HomeModel.hhmm).
    static func hhmmss(_ d: Date) -> String { hhmmssFormatter.string(from: d) }

    /// One formatter for every call (building one per hover snap is costly).
    private static let hhmmssFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    // MARK: Processes card

    static func procsCaption(metric: Metric, processCount: Int?) -> String {
        (metric == .cpu ? L.procsTopByCPU : L.procsTopByMemory)
            + (processCount.map { " · " + L.procsCount($0) } ?? "")
    }

    static func procTexts(_ row: ProcEntry, metric: Metric) -> (value: String, secondary: String) {
        let cpuText = row.cpu.map { L.homePercent(fmtFixed($0, decimals: 1)) } ?? "—"
        switch metric {
        case .cpu: return (cpuText, fmtBytes(row.memBytes))
        case .mem: return (fmtBytes(row.memBytes), cpuText)
        }
    }

    enum ProcBar: Equatable { case green, accent, series }

    static func procBar(_ row: ProcEntry, metric: Metric) -> ProcBar {
        guard metric == .cpu else { return .series }
        let cpu = row.cpu ?? 0
        if cpu > 8 { return .green }
        return .accent
    }

    static func procBarOpacity(_ metric: Metric) -> Double { metric == .cpu ? 0.20 : 0.18 }

    /// Quit / Force quit are offered only for real processes: pid 0 is kernel_task, pid 1 is launchd.
    static func showsActions(pid: Int32?) -> Bool { pid.map { $0 > 1 } ?? false }

    /// Hero / tiles split (D21), used by HeroSplitLayout on Memory / Battery / Storage (no longer by the SoC page): hero = max(200, (W − 8) × 0.8 / 2.8), at most W − 8.
    static func heroWidths(total: CGFloat) -> (hero: CGFloat, tiles: CGFloat) {
        guard total >= 8 else { return (0, 0) }
        let avail = total - 8
        let hero = min(max(200, avail * 0.8 / 2.8), avail)
        return (hero, avail - hero)
    }
}

extension CPUPageModel {
    /// Note text, tone and tooltip for one state (THERMAL-STATE §4), in `language`.
    static func thermalNote(_ l: ThermalLevel, language: AppLanguage) -> (text: String, tone: CPUNoteTone, help: String) {
        let S = language.strings
        switch l {
        case .nominal: return (S.cpuThermalNominal, .green, S.cpuThermalHelpNominal)
        case .fair: return (S.cpuThermalFair, .neutral, S.cpuThermalHelpFair)
        case .serious: return (S.cpuThermalSerious, .amber, S.cpuThermalHelpSerious)
        case .critical: return (S.cpuThermalCritical, .hot, S.cpuThermalHelpCritical)
        }
    }
}
