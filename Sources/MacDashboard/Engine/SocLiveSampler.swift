// Engine/SocLiveSampler.swift
// SOC-DETAILS 1.5 (D1, D16, D20, D22, D23): the SoC page tick. A model object the page starts from its `.task`
// (SwiftUI cancels that task when the page unmounts), so nothing here runs while another page is shown, while the
// app is in the background or while the window is hidden (logic section 5, `no-unseen-work`).
//
// Each pass reads off the main actor and publishes once on it, with per-field equality guards so a view observing
// one field redraws only when that field changed (the AppModel fast-task pattern). The guards compare at the
// precision the page shows (`SocDisplay`, Stage 5a) and the per-leaf slots below carry the values that change per
// tick, so a change re-evaluates only the view that shows it. A failed read publishes the unavailable state for its
// item, never the last good value (D16).
import Foundation
import Observation

/// Frequency of one core group.
enum FrequencyState: Equatable {
    case notYet
    case idle
    case mhz(Double)
    case unavailable
}

/// One core group with the latest per-core loads and its frequency.
struct CoreGroupLoad: Equatable {
    let group: CoreGroup
    /// Whole percent per core of the group, in `group.coreIndices` order. nil: no reading yet, or no elapsed ticks.
    let loads: [Int?]
    let frequency: FrequencyState
}

/// State of the top-GPU-processes list.
enum GPURowsState: Equatable {
    case notYet
    case unavailable
    case empty
    case rows([GPUProcessRow])
}

// MARK: - Per-leaf slots (Stage 5a, D34)

/// One core's shown load. Observed by its own cell only.
@MainActor
@Observable
final class SocCoreCellSlot: Identifiable {
    let id: String                       // "P1"; "1" in a group of unknown type (SocCoresCardModel.cellID)
    fileprivate(set) var load: Int?
    init(id: String, load: Int?) {
        self.id = id
        self.load = load
    }
}

/// One core group. `frequency` is observed by the group heading only; `cells` never change for a shape.
@MainActor
@Observable
final class SocCoreGroupSlot: Identifiable {
    let id: Int                          // index in perflevel order
    let group: CoreGroup
    let cells: [SocCoreCellSlot]
    fileprivate(set) var frequency: FrequencyState
    init(id: Int, group: CoreGroup, cells: [SocCoreCellSlot], frequency: FrequencyState) {
        self.id = id
        self.group = group
        self.cells = cells
        self.frequency = frequency
    }

    /// Cell ids from `SocCoresCardModel.cellID`.
    static func make(_ cores: [CoreGroupLoad]) -> [SocCoreGroupSlot] {
        cores.enumerated().map { index, item in
            let cells = item.group.coreIndices.indices.map { n in
                SocCoreCellSlot(id: SocCoresCardModel.cellID(groupName: item.group.name, index: n),
                                load: n < item.loads.count ? item.loads[n] : nil)
            }
            return SocCoreGroupSlot(id: index, group: item.group, cells: cells, frequency: item.frequency)
        }
    }
}

/// One GPU row, keyed by pid. Observed by its own row view only.
@MainActor
@Observable
final class SocGPURowSlot {
    fileprivate(set) var row: GPUProcessRow
    init(row: GPUProcessRow) {
        self.row = row
    }
}

/// What the GPU list container observes: the state and the pid order on screen.
enum SocGPUListShape: Equatable {
    case notYet, unavailable, empty
    case rows([Int32])                   // [] = clients exist but none has a previous sample yet (still collecting)

    init(_ state: GPURowsState) {
        switch state {
        case .notYet: self = .notYet
        case .unavailable: self = .unavailable
        case .empty: self = .empty
        case .rows(let rows): self = .rows(rows.map(\.id))
        }
    }

    /// [] for every non-rows case.
    var pids: [Int32] {
        if case .rows(let pids) = self { return pids }
        return []
    }
}

/// The readers one pass calls, injectable so tests count calls and need no hardware. `.live` wires the real ones.
struct SocReaders: Sendable {
    /// Core topology, read once per setup.
    var topology: @Sendable () -> [CoreGroup]
    var ticks: @Sendable () -> [CoreTicks]?
    /// Frequency delta since the previous call (nil on the first call or on failure; a call also advances the
    /// reader's own baseline, so the baseline pass simply calls it and drops the result).
    var frequency: @Sendable () -> [CoreGroupKey: FrequencyReading?]?
    var gpuClients: @Sendable () -> [GPUClientSample]?
    /// Read once per setup.
    var gpuCoreCount: @Sendable () -> Int?
    var power: @Sendable () -> Double?
    /// Full executable name for a pid (D12); nil → the 16-character name as read.
    var processName: @Sendable (Int32) -> String?

    static var live: SocReaders {
        SocReaders(
            topology: { CoreTopology.cached },
            ticks: { CoreLoadReader.readTicks() },
            frequency: {
                guard let setup = CPUFrequencyReader.shared else { return nil }
                return CPUFrequencyReader.sample(setup)
            },
            gpuClients: { GPUStats.readClients() },
            gpuCoreCount: { GPUStats.cachedCoreCount },
            power: { SMCReader.readSystemPowerW() },
            processName: { GPUClientRanking.executableName(pid: $0) })
    }
}

/// Fixture-only values for `SocLiveSampler.applyFixture(_:)` (the visual fixture defines the dataset).
struct SocLiveFixture {
    var cores: [CoreGroupLoad]?
    var coreLoadsFailed = false
    /// False = the page just opened and no reading has been published (cells show no value).
    var hasCoreReading = true
    var gpuRows: GPURowsState = .notYet
    var powerW: Double?
    var gpuCoreCount: Int?
}

@MainActor
@Observable
final class SocLiveSampler {
    /// Core groups with loads and frequency. nil until the setup (topology) has run: a few milliseconds after the
    /// page opens, before the first baseline.
    private(set) var cores: [CoreGroupLoad]? = nil
    /// True when the tick call failed: the card shows the group headings with empty tracks and the note (3.1).
    private(set) var coreLoadsFailed = false
    /// True once a reading has been published since the page opened (a baseline pass does not count): tells "no reading
    /// yet" from "a reading where every core has no elapsed ticks" (3.1).
    private(set) var hasCoreReading = false
    private(set) var gpuRows: GPURowsState = .notYet
    /// Stage 5a: the same loads and frequencies as `cores`, one observable object per cell and per group. Observed by
    /// the cores card body; replaced only when the shape (`map(\.group)`) changes.
    private(set) var coreSlots: [SocCoreGroupSlot]? = nil
    /// Stage 5a: what the GPU list container observes (state and pid order).
    private(set) var gpuShape: SocGPUListShape = .notYet
    /// Stage 5a: looked up by the container, never tracked as a collection.
    @ObservationIgnored private(set) var gpuRowSlots: [Int32: SocGPURowSlot] = [:]
    /// nil = unavailable or not yet.
    private(set) var powerW: Double? = nil
    private(set) var gpuCoreCount: Int? = nil
    /// Number of published readings (a baseline pass does not count). The no-unseen-work test reads it.
    @ObservationIgnored private(set) var readCount = 0
    @ObservationIgnored private(set) var isRunning = false

    @ObservationIgnored private let interval: @MainActor () -> Int
    @ObservationIgnored private let isPaused: @MainActor () -> Bool
    @ObservationIgnored private let time: TimeSource
    @ObservationIgnored private let readers: SocReaders

    /// Everything one pass reads.
    private struct Pass {
        var ticks: [CoreTicks]?
        var frequency: [CoreGroupKey: FrequencyReading?]?
        var clients: [GPUClientSample]?
        var power: Double?
        /// Full executable names of the GPU clients' pids, resolved off the main actor (D12).
        var names: [Int32: String] = [:]
    }

    @ObservationIgnored private var baseline: (pass: Pass, at: Date)? = nil
    @ObservationIgnored private var groups: [CoreGroup]? = nil

    init(interval: @escaping @MainActor () -> Int, isPaused: @escaping @MainActor () -> Bool,
         time: TimeSource, readers: SocReaders = .live) {
        self.interval = interval
        self.isPaused = isPaused
        self.time = time
        self.readers = readers
    }

    /// The page tick. Run it from the page's `.task`; cancelling it (page unmount) ends it and drops the baselines.
    func run() async {
        guard !isFixtureLocked else { return }
        isRunning = true
        // D1: a reopened page never shows one frame of the previous visit (resetToNotYet in the exit path).
        defer { isRunning = false; baseline = nil; resetToNotYet() }
        await setup()
        resetToNotYet()
        while !Task.isCancelled {
            if isPaused() {
                // D1: the last values stay on screen until the fresh reading; the baselines do not.
                baseline = nil
                await time.sleep(.seconds(1))
                continue
            }
            if baseline == nil {
                let pass = await readPass()
                baseline = (pass, time.now())
                publishBaseline(pass)
                await time.sleep(.seconds(1))
            } else {
                await time.sleep(.seconds(max(1, interval())))
            }
            guard !Task.isCancelled else { break }
            if isPaused() { continue }   // the top of the loop drops the baseline
            let pass = await readPass()
            let at = time.now()
            guard !Task.isCancelled else { break }
            if let base = baseline { publish(pass, since: base.pass, dt: at.timeIntervalSince(base.at)) }
            baseline = (pass, at)
        }
    }

    // MARK: - Setup (once per sampler; the live readers cache their own results per process)

    @ObservationIgnored private var didSetup = false
    /// Set by `applyFixture`: a fixture build shows fixed values and the page's `.task` must not overwrite them.
    @ObservationIgnored private var isFixtureLocked = false

    private func setup() async {
        guard !didSetup else { return }
        let readers = self.readers
        let (topology, coreCount) = await offMain { (readers.topology(), readers.gpuCoreCount()) }
        guard !Task.isCancelled else { return }
        didSetup = true
        groups = topology
        if gpuCoreCount != coreCount { gpuCoreCount = coreCount }
    }

    /// What the cores card draws. While `cores` is nil (the off-main setup has not finished) it is the not-yet shape
    /// built from the topology, so the card has its final height on the first frame. Non-mutating: it only reads the
    /// per-process cached topology (the card is only built while the page is open), so a view body can call it
    /// without "modifying state during view update". A fixture build shows exactly what the fixture set.
    var displayCores: [CoreGroupLoad]? {
        if let cores { return cores }
        guard !isFixtureLocked else { return nil }
        return Self.notYetGroups(readers.topology())
    }

    private static func notYetGroups(_ groups: [CoreGroup]) -> [CoreGroupLoad] {
        groups.map { CoreGroupLoad(group: $0, loads: Array(repeating: nil, count: $0.count), frequency: .notYet) }
    }

    // MARK: - Reading

    private func readPass() async -> Pass {
        let readers = self.readers
        return await offMain {
            let clients = readers.gpuClients()
            var names: [Int32: String] = [:]
            for pid in Set((clients ?? []).map(\.pid)) { if let n = readers.processName(pid) { names[pid] = n } }
            return Pass(ticks: readers.ticks(), frequency: readers.frequency(), clients: clients, power: readers.power(),
                        names: names)
        }
    }

    private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    /// A reopened page starts from the not-yet state, never from numbers of an earlier visit (D1).
    private func resetToNotYet() {
        guard let groups else { return }
        let initial = Self.notYetGroups(groups)
        if !SocDisplay.sameOnScreen(cores, initial) { setCores(initial) }
        if coreLoadsFailed { coreLoadsFailed = false }
        if hasCoreReading { hasCoreReading = false }
        if gpuRows != .notYet { setGPURows(.notYet) }
        if powerW != nil { powerW = nil }
    }

    /// The only writer of `cores` and `coreSlots` (D35). A write that keeps the shape touches only the slots whose
    /// shown value changed.
    private func setCores(_ next: [CoreGroupLoad]?) {
        cores = next
        guard let next else {
            if coreSlots != nil { coreSlots = nil }
            return
        }
        if let slots = coreSlots, slots.map(\.group) == next.map(\.group) {
            for (slot, item) in zip(slots, next) {
                if !SocDisplay.sameOnScreen(slot.frequency, item.frequency) { slot.frequency = item.frequency }
                for (n, cell) in slot.cells.enumerated() {
                    let load: Int? = n < item.loads.count ? item.loads[n] : nil
                    if cell.load != load { cell.load = load }
                }
            }
        } else {
            coreSlots = SocCoreGroupSlot.make(next)
        }
    }

    /// The only writer of `gpuRows`, the row slots and `gpuShape` (D35). Row slots are written before the shape, so
    /// the container finds a new pid's slot; slots of pids that just left stay until the next publish (D37).
    private func setGPURows(_ next: GPURowsState) {
        gpuRows = next
        if case .rows(let rows) = next {
            for r in rows {
                if let slot = gpuRowSlots[r.id] {
                    if !SocDisplay.sameOnScreen(slot.row, r) { slot.row = r }
                } else {
                    gpuRowSlots[r.id] = SocGPURowSlot(row: r)
                }
            }
            let keep = Set(rows.map(\.id)).union(gpuShape.pids)
            for pid in gpuRowSlots.keys where !keep.contains(pid) { gpuRowSlots[pid] = nil }
        } else if !gpuRowSlots.isEmpty {
            gpuRowSlots = [:]
        }
        let shape = SocGPUListShape(next)
        if gpuShape != shape { gpuShape = shape }
    }

    /// Power needs no second sample: it shows as soon as the baseline pass has read it (logic 3.6).
    private func publishBaseline(_ pass: Pass) {
        if !SocDisplay.sameOnScreen(powerW, pass.power, decimals: SocDisplay.powerDecimals) { powerW = pass.power }
    }

    private func publish(_ pass: Pass, since base: Pass, dt: Double) {
        readCount += 1

        // Per-core load. A failed call on either side is a failed call (3.1), shown as empty tracks.
        var failed = false
        var loads: [Int?] = []
        if let prev = base.ticks, let cur = pass.ticks {
            loads = CoreLoadReader.usage(prev: prev, cur: cur)
        } else {
            failed = true
        }
        let next: [CoreGroupLoad]? = groups.map { groups in
            groups.map { group in
                CoreGroupLoad(group: group,
                              loads: group.coreIndices.map { $0 < loads.count ? loads[$0] : nil },
                              frequency: frequencyState(for: group, in: pass.frequency))
            }
        }
        if coreLoadsFailed != failed { coreLoadsFailed = failed }
        if !hasCoreReading { hasCoreReading = true }
        if !SocDisplay.sameOnScreen(cores, next) { setCores(next) }

        // Top GPU processes.
        let rows: GPURowsState
        if let cur = pass.clients, let prev = base.clients {
            if cur.isEmpty {
                rows = .empty
            } else {
                rows = .rows(GPUClientRanking.rows(prev: prev, cur: cur, dtSeconds: dt, names: { pass.names[$0] }))
            }
        } else {
            rows = .unavailable
        }
        if !SocDisplay.sameOnScreen(gpuRows, rows) { setGPURows(rows) }

        // Power: a failed read is "—" on this update, not the last value (D16).
        if !SocDisplay.sameOnScreen(powerW, pass.power, decimals: SocDisplay.powerDecimals) { powerW = pass.power }
    }

    /// `.unavailable` for a group with no channel (a third core type, type unknown), a failed reading or a failed setup.
    private func frequencyState(for group: CoreGroup, in readings: [CoreGroupKey: FrequencyReading?]?) -> FrequencyState {
        guard let readings, let key = CoreGroupKey(groupName: group.name),
              let reading = readings[key] else { return .unavailable }
        return CPUFrequency.state(from: reading)
    }

    // MARK: - Visual fixture

    /// Fixture only (`-visualFixture`): publishes the given state without running the tick.
    func applyFixture(_ f: SocLiveFixture) {
        isFixtureLocked = true
        setCores(f.cores)
        coreLoadsFailed = f.coreLoadsFailed
        hasCoreReading = f.hasCoreReading
        setGPURows(f.gpuRows)
        powerW = f.powerW
        gpuCoreCount = f.gpuCoreCount
    }
}
