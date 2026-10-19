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

/// REDESIGN-CPU thresholds (03-cpu:20) and the high-load run tracker.
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
enum CPUDot: Equatable { case green, amber, hot }

struct CPUHeroModel: Equatable { var value: String; var fraction: Double; var note: String; var high: Bool; var dimmed: Bool }
struct CPUTileModel: Equatable { var label: String; var value: String; var note: String?; var dot: CPUDot?; var hot: Bool; var dimmed: Bool }

struct CPUPageModel: Equatable {
    struct Input {
        var cpu: CPUUsage?; var load: [Double]?; var ncpu: Int; var chip: String?; var socTempC: Int?
        var block: BlockPhase; var highSince: Date?; var now: Date; var intervalSeconds: Int
    }

    var phase: CPUPagePhase
    var tag: CPUTagKind
    var tagText: String
    var sub: String
    var subIsFailure: Bool      // true only in .failed
    var caption: String         // CPU card caption
    var failureNote: String?    // non-nil only in .failed
    var hero: CPUHeroModel
    var tiles: [CPUTileModel]   // always 3: User, System, SoC temperature
    var showsWait: Bool         // phase == .loading

    static func make(_ i: Input) -> CPUPageModel {
        let phase: CPUPagePhase
        switch i.block {
        case .failed(let f, let g): phase = .failed(f, lastGoodAt: g)
        case .loading: phase = .loading
        case .ok:
            if let cpu = i.cpu {
                phase = CPULoad.usage(cpu) >= CPULoad.highUsagePct ? .high : .live
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
            sub = chipPrefix + L.cpuSubLive(i.ncpu, i.intervalSeconds)
        case .high:
            tag = .high; tagText = L.cpuTagHigh
            sub = chipPrefix + L.cpuSubLive(i.ncpu, i.intervalSeconds)
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
            switch f {
            case .timedOut: failureNote = L.cpuFailTimedOut
            case .noReading: failureNote = L.cpuFailNoReading
            }
        }

        let hero: CPUHeroModel
        var tiles: [CPUTileModel]
        let showsReading = phase == .live || phase == .high
        if showsReading, let cpu = i.cpu {
            let usage = CPULoad.usage(cpu)
            let high = phase == .high
            let note: String
            if high, let m = CPULoad.highMinutes(since: i.highSince, now: i.now) {
                note = L.cpuHighLoadFor(m)
            } else if let l = i.load, l.count == 3 {
                note = L.cpuLoadNote(fmtFixed(l[0], decimals: 2), fmtFixed(l[1], decimals: 2), fmtFixed(l[2], decimals: 2), i.ncpu)
            } else {
                note = L.homeCoresOnly(i.ncpu)
            }
            hero = CPUHeroModel(value: L.homePercent(fmtFixed(usage, decimals: 1)),
                                fraction: min(max(usage / 100, 0), 1),
                                note: note, high: high, dimmed: false)
            let soc: CPUTileModel
            if let t = i.socTempC {
                switch CPULoad.socLevel(t) {
                case .hot:
                    soc = CPUTileModel(label: L.cpuSocTemperature, value: "\(t) °C", note: L.cpuSocHot, dot: .hot, hot: true, dimmed: false)
                case .warm:
                    soc = CPUTileModel(label: L.cpuSocTemperature, value: "\(t) °C", note: L.cpuSocWarm, dot: .amber, hot: false, dimmed: false)
                case .normal:
                    soc = CPUTileModel(label: L.cpuSocTemperature, value: "\(t) °C", note: L.commonNormal, dot: .green, hot: false, dimmed: false)
                }
            } else {
                soc = CPUTileModel(label: L.cpuSocTemperature, value: "—", note: nil, dot: nil, hot: false, dimmed: true)
            }
            tiles = [
                CPUTileModel(label: L.cpuUser, value: L.homePercent(fmtFixed(cpu.user, decimals: 1)), note: nil, dot: nil, hot: false, dimmed: false),
                CPUTileModel(label: L.cpuSystem, value: L.homePercent(fmtFixed(cpu.sys, decimals: 1)), note: nil, dot: nil, hot: false, dimmed: false),
                soc,
            ]
        } else {
            hero = CPUHeroModel(value: "—", fraction: 0, note: L.cpuNoReading, high: false, dimmed: true)
            tiles = [L.cpuUser, L.cpuSystem, L.cpuSocTemperature].map {
                CPUTileModel(label: $0, value: "—", note: nil, dot: nil, hot: false, dimmed: true)
            }
        }

        var isFailed = false
        if case .failed = phase { isFailed = true }
        return CPUPageModel(phase: phase, tag: tag, tagText: tagText, sub: sub, subIsFailure: isFailed,
                            caption: caption, failureNote: failureNote, hero: hero, tiles: tiles,
                            showsWait: phase == .loading)
    }

    /// "HH:mm:ss" in the current zone, POSIX digits (pattern of HomeModel.hhmm).
    static func hhmmss(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "HH:mm:ss"
        return df.string(from: d)
    }

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

    enum ProcBar: Equatable { case amber, green, accent, series }

    static func procBar(_ row: ProcEntry, metric: Metric) -> ProcBar {
        guard metric == .cpu else { return .series }
        let cpu = row.cpu ?? 0
        if cpu > 15 { return .amber }
        if cpu > 8 { return .green }
        return .accent
    }

    static func procBarOpacity(_ metric: Metric) -> Double { metric == .cpu ? 0.20 : 0.18 }

    /// Quit / Force quit are offered only for real processes: pid 0 is kernel_task, pid 1 is launchd.
    static func showsActions(pid: Int32?) -> Bool { pid.map { $0 > 1 } ?? false }

    /// Hero / tiles split of the CPU card (D21): hero = max(200, (W − 8) × 0.8 / 2.8), at most W − 8.
    static func heroWidths(total: CGFloat) -> (hero: CGFloat, tiles: CGFloat) {
        guard total >= 8 else { return (0, 0) }
        let avail = total - 8
        let hero = min(max(200, avail * 0.8 / 2.8), avail)
        return (hero, avail - hero)
    }
}
