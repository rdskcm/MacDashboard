// Engine/IPhoneJobQueue.swift
// IPHONE-LOAD-SPEED: priority queue in front of the one MobileDevice thread. Foundation only,
// no app symbols (the rig compiles this file). Internal, not private (checks-helper-visibility).

import Foundation

/// Urgency of a phone job; lower raw value runs first (R1).
enum IPhoneJobPriority: Int, Comparable {
    case interactive = 0   // readSnapshot, readIdentity
    case user = 1          // listLogs (walk + inline type reads), copyFile
    case background = 2    // remaining type reads after a yield
    case last = 3          // readStorage
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Pure queue: most urgent first, FIFO within one priority.
struct IPhoneJobQueue<Job> {
    private var items: [(priority: IPhoneJobPriority, seq: Int, job: Job)] = []
    private var nextSeq = 0
    var count: Int { items.count }

    /// Returns the job's sequence number (for `remove`).
    mutating func push(_ p: IPhoneJobPriority, _ job: Job) -> Int {
        let seq = nextSeq
        nextSeq += 1
        items.append((p, seq, job))
        return seq
    }

    /// The most urgent job (lowest priority raw value, then lowest seq), removed; nil when empty.
    mutating func pop() -> Job? {
        guard let i = items.indices.min(by: { a, b in
            let x = items[a], y = items[b]
            return x.priority != y.priority ? x.priority < y.priority : x.seq < y.seq
        }) else { return nil }
        return items.remove(at: i).job
    }

    /// Removes the job with `seq` (a post that failed); no-op when absent.
    mutating func remove(seq: Int) {
        items.removeAll { $0.seq == seq }
    }

    /// True when a job strictly more urgent than `p` is waiting.
    func hasPending(moreUrgentThan p: IPhoneJobPriority) -> Bool {
        items.contains { $0.priority < p }
    }
}

/// Thread-safe wrapper the transport uses: one drain block is posted per enqueued job and each
/// drain runs the most urgent waiting job, so posting order does not decide running order.
final class IPhoneJobRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var queue = IPhoneJobQueue<() -> Void>()

    /// Pushes `job`, then posts one drain through `post`. When `post` returns false the job is
    /// removed again and false is returned (the caller reports `.unavailable`).
    @discardableResult
    func enqueue(_ p: IPhoneJobPriority, _ job: @escaping () -> Void,
                 post: (@escaping () -> Void) -> Bool) -> Bool {
        lock.lock()
        let seq = queue.push(p, job)
        lock.unlock()
        let ok = post { [self] in runNext() }
        if !ok {
            lock.lock()
            queue.remove(seq: seq)
            lock.unlock()
        }
        return ok
    }

    /// Called on the owning thread between units of work (the type-read loop).
    func hasPending(moreUrgentThan p: IPhoneJobPriority) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return queue.hasPending(moreUrgentThan: p)
    }

    /// The drain block: pops under the lock, runs the job outside it.
    func runNext() {
        lock.lock()
        let job = queue.pop()
        lock.unlock()
        job?()
    }
}
