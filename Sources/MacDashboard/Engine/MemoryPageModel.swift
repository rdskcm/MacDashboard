// Engine/MemoryPageModel.swift
// REDESIGN-MEMORY: pure state, texts, tones and thresholds of the Memory page (handoff 04-memory).
import Foundation

/// Memory thresholds (GAP-2 "thresholds in one place"): the ONLY pressure → tone mapping (Memory page and
/// Home's Now-card chip both call `pressureTone`) and the swap-high rule.
enum MemoryLoad {
    /// Swap is high when used > 50 % of the current swap total (04-memory:14). Strictly greater.
    static let swapHighFraction = 0.5
    static func isSwapHigh(_ s: SwapInfo?) -> Bool {
        guard let s, s.total > 0 else { return false }
        return Double(s.used) > Double(s.total) * swapHighFraction
    }
    /// normal → low, warn → medium, critical → high, unreadable → nil (never guessed).
    static func pressureTone(_ p: MemoryPressureLevel?) -> MemoryPressureTone? {
        switch p {
        case .normal?: return .low
        case .warn?: return .medium
        case .critical?: return .high
        case nil: return nil
        }
    }
}

enum MemoryPressureTone: Equatable, Sendable { case low, medium, high }
enum MemoryPagePhase: Equatable { case loading, live, failed(BlockFailure, lastGoodAt: Date?) }
enum MemoryTagKind: Equatable { case low, medium, high, unknown, loading, failed }
/// Hero tint: accent (low / unknown pressure), amber, hot; neutral = no reading (muted panel, inkSoft label).
enum MemoryHeroTone: Equatable { case accent, amber, hot, neutral }
/// Composition card view; `Hashable` for `DSSlidingSegmented`.
enum MemoryCompView: Hashable, Sendable { case chart, table }
enum MemorySegmentKey: String, CaseIterable, Sendable { case active, wired, other, inactive, speculative, free }

struct MemoryTileModel: Equatable { var label: String; var value: String; var note: String?; var amber: Bool; var dimmed: Bool }

struct MemorySegmentModel: Equatable {
    var key: MemorySegmentKey
    var label: String
    var bytes: Int64          // 0 when there is no reading
    var value: String         // fmtBytes, "—" without a reading
    var share: String         // "38%" / "38 %", "" without a reading
    var barFraction: Double   // bytes / total (Stack bar), 0 without a reading
    var listFraction: Double  // bytes / largest segment (Table share bar), 0 without a reading
}

struct MemoryPageModel: Equatable {
    struct Input {
        var mem: MemSnapshot?; var swap: SwapInfo?; var pressure: MemoryPressureLevel?
        var installedBytes: Int64?          // model.headerSystem?.memBytes
        var block: BlockPhase; var intervalSeconds: Int; var narrow: Bool
    }

    var phase: MemoryPagePhase
    var tag: MemoryTagKind
    var tagText: String
    var sub: String
    var subIsFailure: Bool          // true only in .failed
    var usageCaption: String
    var compCaption: String
    var failureNote: String?        // non-nil only in .failed
    var heroValue: String
    var heroFraction: Double
    var heroNote: String
    var heroTone: MemoryHeroTone
    var tiles: [MemoryTileModel]    // always 4: Compressed, Purgeable, Swap, File cache
    var segments: [MemorySegmentModel]  // always 6, MemorySegmentKey order
    var showsWait: Bool             // phase == .loading

    static func make(_ i: Input) -> MemoryPageModel {
        let mem = i.mem.flatMap { $0.total > 0 ? $0 : nil }
        let phase: MemoryPagePhase
        switch i.block {
        case .failed(let f, let g): phase = .failed(f, lastGoodAt: g)
        case .loading: phase = .loading
        case .ok: phase = mem != nil ? .live : .loading
        }
        let total = fmtBytes(i.installedBytes ?? mem?.total)   // "—" when neither is known
        let tone = MemoryLoad.pressureTone(i.pressure)

        var tag: MemoryTagKind, tagText: String, sub: String
        var usageCaption = L.memUsageCaption(total), compCaption = L.memCompCaption(total)
        var failureNote: String? = nil
        switch phase {
        case .live:
            switch tone {
            case .low?: (tag, tagText) = (.low, L.memTagLow)
            case .medium?: (tag, tagText) = (.medium, L.memTagMedium)
            case .high?: (tag, tagText) = (.high, L.memTagHigh)
            case nil: (tag, tagText) = (.unknown, L.memTagUnknown)
            }
            sub = total + " · " + L.memUpdatesEvery(i.intervalSeconds)
        case .loading:
            (tag, tagText) = (.loading, L.commonCollectingData)
            sub = total + " · " + L.cpuSubCollecting
        case .failed(let f, let g):
            (tag, tagText) = (.failed, L.memTagReadFailed)
            if let g {
                let stale = L.commonLastData(CPUPageModel.hhmmss(g))
                sub = total + " · " + stale
                usageCaption = stale; compCaption = stale
            } else {
                sub = total
            }
            failureNote = f == .timedOut ? L.memFailTimedOut : L.memFailNoReading
        }

        let labels = [L.commonCompressed, L.memPurgeable, L.memSwap, L.memFileCache]
        let otherLabel = i.narrow ? L.memOtherShort : L.memoryLegendOther
        let segLabels: [MemorySegmentKey: String] = [
            .active: L.memoryLegendActive, .wired: L.memoryLegendWired, .other: otherLabel,
            .inactive: L.memoryLegendInactive, .speculative: L.memoryLegendSpeculative, .free: L.memoryLegendFree,
        ]
        var heroValue = "—", heroFraction = 0.0, heroNote = L.cpuNoReading
        var heroTone = MemoryHeroTone.neutral
        var tiles = labels.map { MemoryTileModel(label: $0, value: "—", note: nil, amber: false, dimmed: true) }
        var segments = MemorySegmentKey.allCases.map {
            MemorySegmentModel(key: $0, label: segLabels[$0] ?? "", bytes: 0, value: "—", share: "", barFraction: 0, listFraction: 0)
        }
        if phase == .live, let mem {
            let t = Double(mem.total)
            let used = mem.usedBytes
            heroValue = fmtBytes(used)
            heroFraction = min(max(Double(used) / t, 0), 1)
            heroNote = L.memHeroNote(fmtBytes(mem.total), L.homePercent("\(Int((Double(used) / t * 100).rounded()))"))
            switch tone {
            case .medium?: heroTone = .amber
            case .high?: heroTone = .hot
            case .low?, nil: heroTone = .accent
            }
            let swapTile: MemoryTileModel
            if let s = i.swap {
                if s.total > 0 {
                    let pct = Int((Double(s.used) / Double(s.total) * 100).rounded())
                    swapTile = MemoryTileModel(label: L.memSwap, value: fmtBytes(s.used),
                                               note: L.memSwapOf(L.homePercent("\(pct)"), fmtBytes(s.total)),
                                               amber: MemoryLoad.isSwapHigh(s), dimmed: false)
                } else {
                    swapTile = MemoryTileModel(label: L.memSwap, value: fmtBytes(s.used), note: nil, amber: false, dimmed: false)
                }
            } else {
                swapTile = MemoryTileModel(label: L.memSwap, value: "—", note: nil, amber: false, dimmed: true)
            }
            tiles = [
                MemoryTileModel(label: L.commonCompressed, value: fmtBytes(mem.compressor), note: nil, amber: false, dimmed: false),
                MemoryTileModel(label: L.memPurgeable, value: fmtBytes(mem.purgeable), note: nil, amber: false, dimmed: false),
                swapTile,
                MemoryTileModel(label: L.memFileCache, value: fmtBytes(mem.fileBacked), note: nil, amber: false, dimmed: false),
            ]
            let bytes: [MemorySegmentKey: Int64] = [
                .active: mem.active, .wired: mem.wired, .other: mem.otherBytes,
                .inactive: mem.inactive, .speculative: mem.speculative, .free: mem.free,
            ]
            let largest = Double(max(bytes.values.max() ?? 1, 1))
            segments = MemorySegmentKey.allCases.map { k in
                let b = max(bytes[k] ?? 0, 0)
                return MemorySegmentModel(key: k, label: segLabels[k] ?? "", bytes: b, value: fmtBytes(b),
                                          share: L.homePercent("\(Int((Double(b) / t * 100).rounded()))"),
                                          barFraction: Double(b) / t, listFraction: Double(b) / largest)
            }
        }

        var isFailed = false
        if case .failed = phase { isFailed = true }
        return MemoryPageModel(phase: phase, tag: tag, tagText: tagText, sub: sub, subIsFailure: isFailed,
                               usageCaption: usageCaption, compCaption: compCaption, failureNote: failureNote,
                               heroValue: heroValue, heroFraction: heroFraction, heroNote: heroNote, heroTone: heroTone,
                               tiles: tiles, segments: segments, showsWait: phase == .loading)
    }

    // MARK: Processes card (memory-page variant of ProcessListCard)

    /// "top 8 · 412 processes"; without a count just "top 8".
    static func procsCaption(processCount: Int?) -> String {
        L.memProcsTop(LiveCollector.topProcessCount) + (processCount.map { " · " + L.procsCount($0) } ?? "")
    }

    /// Row secondary text on the Memory page: "7.5% CPU" / "7,5 % CPU"; "—" when the CPU share is unknown.
    static func procSecondary(_ row: ProcEntry) -> String {
        row.cpu.map { L.memProcCPU(L.homePercent(fmtFixed($0, decimals: 1))) } ?? "—"
    }
}
