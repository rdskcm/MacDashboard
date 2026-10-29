// Engine/BlockState.swift
// REDESIGN-FOUNDATION: per-block loading / ok / failed state (handoff 00 §4.16). Pure value
// logic; AppModel owns one state per block, arms the watchdogs and feeds the results.
import Foundation

/// Data blocks with their own load state. A block is added here by the stage that wires its source.
enum BlockID: String, CaseIterable, Sendable {
    case cpu, memory, folders, scan, battery

    /// Seconds an attempt may run before the block reads as failed (`.timedOut`).
    var timeout: TimeInterval {
        switch self {
        case .cpu, .memory, .battery: return 5                         // 03-cpu, 04-memory, 06-battery (Reading → Read failed at 5 s)
        case .folders: return 10   // 05-storage: the visible Counting wait times out at 10 s; du keeps its own 90 s deadline (D4)
        case .scan: return 30                                          // 02-home first scan, system_profiler
        }
    }
}

enum BlockFailure: Equatable, Sendable {
    /// No result within `BlockID.timeout`.
    case timedOut
    /// The source answered, but with nothing usable.
    case noReading
}

enum BlockPhase: Equatable, Sendable {
    case loading(since: Date)
    case ok(at: Date)
    case failed(BlockFailure, lastGoodAt: Date?)
}

struct BlockState: Equatable, Sendable {
    let timeout: TimeInterval
    private(set) var phase: BlockPhase
    /// Time of the last success, kept through failures («last data hh:mm»).
    private(set) var lastGoodAt: Date?
    /// Start of the attempt in flight; nil when none is.
    private(set) var attemptStartedAt: Date?

    init(_ id: BlockID, createdAt: Date = Date()) {
        timeout = id.timeout
        phase = .loading(since: createdAt)
    }

    /// When the attempt in flight times out; nil when none is in flight.
    var deadline: Date? { attemptStartedAt?.addingTimeInterval(timeout) }

    /// An attempt starts. `showsLoading` (a user-initiated attempt) puts the block into
    /// loading; a background attempt leaves the phase as it is.
    mutating func begin(at now: Date, showsLoading: Bool) {
        attemptStartedAt = now
        if showsLoading { phase = .loading(since: now) }
    }

    mutating func succeed(at now: Date) {
        attemptStartedAt = nil
        lastGoodAt = now
        phase = .ok(at: now)
    }

    mutating func fail(_ failure: BlockFailure) {
        attemptStartedAt = nil
        phase = .failed(failure, lastGoodAt: lastGoodAt)
    }

    /// The attempt returned without a verdict (the CPU counter's priming sample): phase unchanged.
    mutating func endWithoutVerdict() {
        attemptStartedAt = nil
    }

    /// Watchdog: an attempt still in flight at or past its deadline fails as `.timedOut`. The
    /// attempt stays open, so a late result still lands through `succeed` / `fail`.
    mutating func expire(now: Date) {
        guard let deadline, now >= deadline else { return }
        if case .failed(.timedOut, _) = phase { return }
        phase = .failed(.timedOut, lastGoodAt: lastGoodAt)
    }
}
