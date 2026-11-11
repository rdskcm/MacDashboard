// Engine/IPhoneWifiLane.swift
// IPHONE-WIFI D14 (ND2 = A): one Wi-Fi device's own job lane. Its jobs run one at a time on a private serial queue, in
// urgency order (IPhoneJobQueue), so a call stuck on a dead Wi-Fi link holds only this device's jobs: never USB jobs,
// never another device's. Closing the lane fails every waiting and running job at once and the lane is never used
// again; a call that is stuck keeps its worker until the framework returns, and its results are dropped by its ticket.
// Tests: IPhoneWifiTests (ticket order, lane close) and the live tests V3, V3b, V3c.
import Foundation

/// One queued phone job's completion guard: the job's own end (`finish`) or its failure (`abandon`) reaches main,
/// never both, and nothing after either.
final class IPhoneJobTicket: @unchecked Sendable {
    // @unchecked Sendable: `lock` and `fail` are immutable; `open` and `sent` are read and written only under `lock`.
    private let lock = NSLock()
    private var open = true
    private var sent = false
    private let fail: @MainActor (IPhoneReadError, _ sentBefore: Bool) -> Void

    init(fail: @escaping @MainActor (IPhoneReadError, _ sentBefore: Bool) -> Void) { self.fail = fail }

    /// An intermediate result (listing, type batch, progress, onStart): posted only while the job is open. Posting under
    /// the lock keeps send, finish and abandon in order on the main queue.
    func send(_ body: @escaping @MainActor () -> Void) {
        lock.withLock {
            guard open else { return }
            sent = true
            Self.post(body)
        }
    }

    /// The job's end: posted when still open, then the ticket is closed. Every job calls it exactly once.
    func finish(_ body: @escaping @MainActor () -> Void) {
        lock.withLock {
            guard open else { return }
            open = false
            Self.post(body)
        }
    }

    /// Not queued, or the lane closed under the job: `fail` is posted once instead of the job's end.
    func abandon(_ e: IPhoneReadError) {
        lock.withLock {
            guard open else { return }
            open = false
            let f = fail, s = sent
            Self.post { f(e, s) }
        }
    }

    private static func post(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}

final class IPhoneWifiLane: @unchecked Sendable {
    typealias Ptr = UnsafeMutableRawPointer
    private struct Job {
        let ticket: IPhoneJobTicket
        let work: (IPhoneJobTicket) -> Void
    }

    // @unchecked Sendable: `raw`, `dev`, `watchdog`, `queue`, `lock` are immutable; `jobs`, `running`, `closed` are read
    // and written only under `lock`.
    let raw: Int
    /// The AMDevice. The lane owns one +1 on it for its whole life (released in deinit): a job, even an abandoned one
    /// that returns late, never runs on a freed device.
    let dev: Ptr
    let watchdog = IPhoneWifiWatchdog()
    private let queue = DispatchQueue(label: "com.macdashboard.mobiledevice.wifi", qos: .userInitiated)
    private let lock = NSLock()
    private var jobs = IPhoneJobQueue<Job>()
    private var running: IPhoneJobTicket?
    private var closed = false

    /// `retainedDev` already carries the +1 this lane owns. `onDead` runs on the watchdog's queue.
    init(raw: Int, retainedDev: Ptr, onDead: @escaping @Sendable (IPhoneWifiLane) -> Void) {
        self.raw = raw
        self.dev = retainedDev
        watchdog.setOnDead { [weak self] in if let self { onDead(self) } }
    }

    deinit { Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(dev)).release() }

    var isClosed: Bool { lock.withLock { closed } }

    func hasPending(moreUrgentThan p: IPhoneJobPriority) -> Bool {
        lock.withLock { jobs.hasPending(moreUrgentThan: p) }
    }

    /// Queues a job; false (nothing queued) when the lane is closed. One drain per job, as `IPhoneJobRunner` does.
    func enqueue(_ p: IPhoneJobPriority, _ ticket: IPhoneJobTicket,
                 _ work: @escaping (IPhoneJobTicket) -> Void) -> Bool {
        let ok = lock.withLock { () -> Bool in
            guard !closed else { return false }
            _ = jobs.push(p, Job(ticket: ticket, work: work))
            return true
        }
        if ok { queue.async { [self] in runNext() } }
        return ok
    }

    private func runNext() {
        let job: Job? = lock.withLock {
            guard !closed, let j = jobs.pop() else { return nil }
            running = j.ticket
            return j
        }
        guard let job else { return }
        watchdog.begin()
        job.work(job.ticket)
        watchdog.end()
        lock.withLock { if running === job.ticket { running = nil } }
    }

    /// Closes the lane for good (D14). The running job and every waiting one are abandoned with `.gone` now, then the
    /// watchdog stops and cuts a watched socket so a blocked service call returns early. Idempotent.
    func close() {
        let tickets: [IPhoneJobTicket] = lock.withLock {
            guard !closed else { return [] }
            closed = true
            var all = running.map { [$0] } ?? []
            while let j = jobs.pop() { all.append(j.ticket) }
            running = nil
            return all
        }
        tickets.forEach { $0.abandon(.gone) }
        watchdog.stop()
    }
}
