// Tests/MacDashboardTests/SocLiveSamplerTests.swift
// SOC-DETAILS 1.8 (no-unseen-work, parts 1-3): the page tick reads only while it runs and the app is not paused, and
// stops on cancellation (the page unmounting). Virtual clock, counting fake readers. Part 4 (Stage 3) walks the hosted
// window: the chart hover and the core bars exist only while the SoC page is shown.
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MacDashboard

/// Counting fake readers. Called from a background queue, so every counter sits behind a lock.
private final class FakeSocReaders: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String: Int] = [:]
    private var tickValue: UInt64 = 0
    var ticksResult = true
    var clients: [GPUClientSample]? = []
    var power: Double? = 6.8
    var frequency: [CoreGroupKey: FrequencyReading?]? = [.performance: FrequencyReading(mhz: 3950, activeShare: 0.99),
                                                         .efficiency: FrequencyReading(mhz: 1270, activeShare: 0.03)]
    var groups = [CoreGroup(name: "Performance", count: 2, coreIndices: [2, 3]),
                  CoreGroup(name: "Efficiency", count: 2, coreIndices: [0, 1])]
    var clientTime: UInt64 = 0
    /// GPU time every client accumulates per read (default: 100 ms).
    var clientStep: UInt64 = 100_000_000

    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return _calls[name] ?? 0 }
    var total: Int { lock.lock(); defer { lock.unlock() }; return _calls.values.reduce(0, +) }
    private func hit(_ name: String) { lock.lock(); _calls[name, default: 0] += 1; lock.unlock() }

    var readers: SocReaders {
        SocReaders(
            topology: { self.hit("topology"); return self.groups },
            ticks: {
                self.hit("ticks")
                guard self.ticksResult else { return nil }
                self.lock.lock(); self.tickValue += 50; let v = self.tickValue; self.lock.unlock()
                return Array(repeating: CoreTicks(user: v, system: 0, idle: v, nice: 0), count: 4)   // 50 % busy per window
            },
            frequency: { self.hit("frequency"); return self.frequency },
            gpuClients: {
                self.hit("gpuClients")
                self.lock.lock(); self.clientTime += self.clientStep; let t = self.clientTime; self.lock.unlock()
                return self.clients.map { $0.map { GPUClientSample(pid: $0.pid, name16: $0.name16, gpuTimeNs: t) } }
            },
            gpuCoreCount: { self.hit("gpuCoreCount"); return 8 },
            power: { self.hit("power"); return self.power },
            processName: { _ in nil })
    }
}

/// A window hosting one view, as `HiddenContentTests` does: the view tree is walked.
@MainActor
private final class SocHost {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1150, height: 700), styleMask: .borderless,
                          backing: .buffered, defer: false)
    init<V: View>(_ view: V) {
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.frame(width: 1150, height: 700))
        hosting.frame = NSRect(x: 0, y: 0, width: 1150, height: 700)
        window.contentView = hosting
        settle()
    }
    func settle(_ s: TimeInterval = 0.6) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: s))
        window.contentView?.layoutSubtreeIfNeeded()
    }
    private func count(_ v: NSView, _ match: (NSView) -> Bool) -> Int {
        (match(v) ? 1 : 0) + v.subviews.reduce(0) { $0 + count($1, match) }
    }
    var hoverViews: Int { window.contentView.map { count($0) { $0 is SocChartHoverView } } ?? 0 }
    /// Every `BarFillLayer` view in the window. The core bars carry `soc-core-bar`, but SwiftUI identifiers are not
    /// reachable through the accessibility tree of a test window (no AX client), so the bars are counted by type.
    var barViews: Int { window.contentView.map { count($0) { $0 is BarFillLayerView } } ?? 0 }
    func close() { window.contentView = nil; window.close(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
}

extension SerialTests {
    @MainActor struct SocLiveSamplerTests {
        private func make(_ fake: FakeSocReaders, clock: VirtualClock, paused: @escaping @MainActor () -> Bool = { false },
                          interval: Int = 2) -> SocLiveSampler {
            SocLiveSampler(interval: { interval }, isPaused: paused, time: clock.source, readers: fake.readers)
        }

        /// Runs `s.run()` as a task; `clock.onSleep` gets the sleep ordinal and may cancel through the returned box.
        private final class Runner { var task: Task<Void, Never>? }

        // MARK: (1) readings follow the clock

        @Test func firstReadingAfterOneSecondThenEveryInterval() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            let s = make(fake, clock: clock)
            let runner = Runner()
            var counts: [Int: Int] = [:]
            var running: [Bool] = []
            clock.onSleep = { n in
                counts[n] = s.readCount
                running.append(s.isRunning)
                if n == 4 { runner.task?.cancel() }
            }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(clock.sleeps == [.seconds(1), .seconds(2), .seconds(2), .seconds(2)])
            #expect(counts[1] == 0, "the baseline pass does not count")
            #expect(counts[2] == 1, "after 1 s virtual: the first reading")
            #expect(counts[3] == 2, "after + interval: the second")
            #expect(counts[4] == 3)
            #expect(s.readCount == 3, "cancelled in the sleep: no further read")
            #expect(running.allSatisfy { $0 })
            #expect(!s.isRunning)
            // One setup, one baseline pass and three readings of every per-pass reader.
            #expect(fake.count("topology") == 1 && fake.count("gpuCoreCount") == 1)
            #expect(fake.count("ticks") == 4 && fake.count("frequency") == 4 && fake.count("gpuClients") == 4 && fake.count("power") == 4)
        }

        @Test func intervalSettingIsReadEveryTime() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            var interval = 2
            let s = SocLiveSampler(interval: { interval }, isPaused: { false }, time: clock.source, readers: fake.readers)
            let runner = Runner()
            clock.onSleep = { n in
                if n == 2 { interval = 10 }
                if n == 3 { runner.task?.cancel() }
            }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(clock.sleeps == [.seconds(1), .seconds(2), .seconds(10)])
        }

        // MARK: (2) paused

        @Test func pausedReadsNothingAndResumesWithABaseline() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            var paused = false
            let s = make(fake, clock: clock, paused: { paused })
            let runner = Runner()
            var callsWhenPaused = -1, callsAfterFiveIntervals = -1
            var countAtResume = -1, ticksAtResume = -1
            var countAfterFirstReading = -1, ticksAfterBaseline = -1
            clock.onSleep = { n in
                switch n {
                case 2: paused = true; callsWhenPaused = fake.total    // read 1 done at sleep 1; sleep 2 is the interval; the pass after it is skipped
                case 7: callsAfterFiveIntervals = fake.total; countAtResume = s.readCount; ticksAtResume = fake.count("ticks"); paused = false
                case 8: ticksAfterBaseline = fake.count("ticks")
                case 9: countAfterFirstReading = s.readCount; runner.task?.cancel()
                default: break
                }
            }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(callsAfterFiveIntervals == callsWhenPaused, "no reader call while paused")
            #expect(countAtResume == 1)
            #expect(ticksAfterBaseline == ticksAtResume + 1, "the first pass after the pause is a baseline")
            #expect(countAfterFirstReading == 2, "baseline, 1 s, then one reading")
            // Paused iterations sleep 1 s each.
            #expect(clock.sleeps[2...6].allSatisfy { $0 == .seconds(1) })
            #expect(clock.sleeps[7] == .seconds(1), "the baseline is followed by 1 s, not the interval")
        }

        @Test func pausedFromTheStartNeverReads() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            let s = make(fake, clock: clock, paused: { true })
            let runner = Runner()
            clock.onSleep = { n in if n == 5 { runner.task?.cancel() } }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(s.readCount == 0)
            #expect(fake.count("ticks") == 0 && fake.count("frequency") == 0 && fake.count("gpuClients") == 0 && fake.count("power") == 0)
        }

        // MARK: (3) cancellation

        @Test func cancelFreezesTheCountAndDropsTheBaseline() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            let s = make(fake, clock: clock)
            let runner = Runner()
            clock.onSleep = { n in if n == 3 { runner.task?.cancel() } }
            runner.task = Task { await s.run() }
            await runner.task?.value
            let frozen = s.readCount, calls = fake.total
            #expect(frozen == 2 && !s.isRunning)
            for _ in 0..<20 { await Task.yield() }
            #expect(s.readCount == frozen && fake.total == calls, "nothing reads after the page unmounted")

            // A reopened page starts from the not-yet state and a new baseline, never from the earlier visit.
            let second = Runner()
            var loadsAfterBaseline: [[Int?]] = []
            var ticksBefore = fake.count("ticks"), ticksAfterBaseline = -1
            clock.onSleep = { n in
                if n == 4 {                      // first sleep of the second run (3 earlier ones)
                    ticksAfterBaseline = fake.count("ticks")
                    loadsAfterBaseline = (s.cores ?? []).map(\.loads).flatMap { $0 }.map { [$0] }
                    #expect(s.gpuRows == .notYet && (s.cores ?? []).allSatisfy { $0.frequency == .notYet })
                    second.task?.cancel()
                }
            }
            ticksBefore = fake.count("ticks")
            second.task = Task { await s.run() }
            await second.task?.value
            #expect(ticksAfterBaseline == ticksBefore + 1)
            #expect(loadsAfterBaseline.allSatisfy { $0 == [nil] })
            #expect(s.readCount == frozen, "the reopened page has not read yet")
            #expect(fake.count("topology") == 1, "setup runs once per sampler")
        }

        // MARK: published values

        @Test func readingPublishesLoadsFrequencyRowsAndPower() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            fake.clients = [GPUClientSample(pid: 5, name16: "Dock", gpuTimeNs: 0)]
            let s = make(fake, clock: clock)
            let runner = Runner()
            var atBaselineSleep: (power: Double?, rows: GPURowsState, cores: Int?)?
            // The unmount resets the state (D1), so the published values are read before the cancel.
            var shown: (cores: [CoreGroupLoad], rows: GPURowsState, power: Double?, count: Int?, failed: Bool)?
            clock.onSleep = { n in
                if n == 1 { atBaselineSleep = (s.powerW, s.gpuRows, s.cores?.count) }
                if n == 2 {
                    shown = (s.cores ?? [], s.gpuRows, s.powerW, s.gpuCoreCount, s.coreLoadsFailed)
                    runner.task?.cancel()
                }
            }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(atBaselineSleep?.power == 6.8, "power shows from the baseline pass")
            #expect(atBaselineSleep?.rows == .notYet && atBaselineSleep?.cores == 2)
            guard let shown else { Issue.record("no reading captured"); return }
            #expect(shown.count == 8 && shown.power == 6.8 && !shown.failed)
            let cores = shown.cores
            #expect(cores.map(\.group.name) == ["Performance", "Efficiency"])
            #expect(cores[0].loads == [50, 50] && cores[1].loads == [50, 50])
            #expect(cores[0].frequency == .mhz(3950))
            #expect(cores[1].frequency == .idle, "3 % active is under the 5 % idle share")
            guard case .rows(let rows) = shown.rows else { Issue.record("expected rows, got \(shown.rows)"); return }
            #expect(rows.count == 1 && rows[0].id == 5 && rows[0].name == "Dock")
            // 100 ms of GPU time over the 1 s virtual window.
            #expect(abs((rows[0].sharePct ?? 0) - 10) < 1e-6)
        }

        // MARK: Stage 5a: writes follow the shown precision

        /// Records which tracked property changed. `withObservationTracking` fires `onChange` once, on the first change
        /// of anything it read, so each property gets its own registration.
        private final class ChangeLog: @unchecked Sendable {
            private let lock = NSLock()
            private var names: [String] = []
            func add(_ n: String) { lock.lock(); names.append(n); lock.unlock() }
            var all: Set<String> { lock.lock(); defer { lock.unlock() }; return Set(names) }
        }

        /// One GPU client (pid 5), two readings published (the share changes once, 10 % to 5 %), then one registration
        /// per property, `mutate` on the fake, one more reading. Returns the names that changed during that reading.
        private func changesDuringOneReading(mutate: @escaping (FakeSocReaders) -> Void) async -> Set<String> {
            let clock = VirtualClock(), fake = FakeSocReaders()
            fake.clients = [GPUClientSample(pid: 5, name16: "Dock", gpuTimeNs: 0)]
            let s = make(fake, clock: clock)
            let runner = Runner()
            let log = ChangeLog()
            var result: Set<String> = []
            func track(_ name: String, _ read: @escaping () -> Void) {
                withObservationTracking { read() } onChange: { log.add(name) }
            }
            clock.onSleep = { n in
                if n == 3 {
                    // Reading 2 is published: the screen is settled.
                    guard let slot = s.gpuRowSlots[5], let groups = s.coreSlots, groups.count == 2 else {
                        Issue.record("slots missing after two readings"); runner.task?.cancel(); return
                    }
                    #expect(abs((slot.row.sharePct ?? 0) - 5) < 1e-6)
                    track("gpuShape") { _ = s.gpuShape }
                    track("rowSlot") { _ = slot.row }
                    track("coreSlots") { _ = s.coreSlots }
                    for g in groups {
                        track("freq:\(g.group.name ?? "")") { _ = g.frequency }
                        for c in g.cells { track("cell:\(c.id)") { _ = c.load } }
                    }
                    track("powerW") { _ = s.powerW }
                    track("cores") { _ = s.cores }
                    track("gpuRows") { _ = s.gpuRows }
                    mutate(fake)
                }
                if n == 4 {
                    result = log.all
                    runner.task?.cancel()
                }
            }
            runner.task = Task { await s.run() }
            await runner.task?.value
            return result
        }

        @Test func unchangedScreenWritesNothing() async {
            let changed = await changesDuringOneReading { fake in
                fake.power = 6.83                                                     // 6.8 W either way
                fake.frequency = [.performance: FrequencyReading(mhz: 3951, activeShare: 0.99),   // 3.95 GHz either way
                                  .efficiency: FrequencyReading(mhz: 1270, activeShare: 0.03)]
                fake.clientStep = 100_000_100                                         // 5.0 % either way
            }
            #expect(changed.isEmpty, "nothing observed may be written, got \(changed.sorted())")
        }

        @Test func shownChangeWritesOnlyItsLeaf() async {
            let changed = await changesDuringOneReading { fake in
                fake.power = 7.0
                fake.frequency = [.performance: FrequencyReading(mhz: 4000, activeShare: 0.99),
                                  .efficiency: FrequencyReading(mhz: 1270, activeShare: 0.03)]
            }
            #expect(changed == ["powerW", "freq:Performance", "cores"], "got \(changed.sorted())")
        }

        @Test func failedReadsPublishUnavailableNotTheLastValue() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            fake.clients = [GPUClientSample(pid: 5, name16: "Dock", gpuTimeNs: 0)]
            let s = make(fake, clock: clock)
            let runner = Runner()
            var shown: (Bool, [CoreGroupLoad]?, GPURowsState, Double?)?
            clock.onSleep = { n in
                if n == 2 {                       // after the first good reading: break every source
                    #expect(s.powerW == 6.8)
                    fake.ticksResult = false; fake.clients = nil; fake.power = nil; fake.frequency = nil
                }
                if n == 3 {
                    shown = (s.coreLoadsFailed, s.cores, s.gpuRows, s.powerW)
                    runner.task?.cancel()
                }
            }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(shown?.0 == true)
            #expect(shown?.1?.flatMap(\.loads).allSatisfy { $0 == nil } == true)
            #expect(shown?.1?.allSatisfy { $0.frequency == .unavailable } == true)
            #expect(shown?.2 == .unavailable)
            #expect(shown?.3 == nil)
        }

        @Test func noGpuClientAtAllIsEmptyNotUnavailable() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            fake.clients = []
            let s = make(fake, clock: clock)
            let runner = Runner()
            var rows: GPURowsState?
            clock.onSleep = { n in if n == 2 { rows = s.gpuRows; runner.task?.cancel() } }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(rows == .empty)
        }

        @Test func thirdCoreTypeAndTypeUnknownHaveNoFrequency() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            fake.groups = [CoreGroup(name: "Super", count: 2, coreIndices: [0, 1]),
                           CoreGroup(name: "Efficiency", count: 2, coreIndices: [2, 3])]
            let s = make(fake, clock: clock)
            let runner = Runner()
            var frequencies: [FrequencyState]?
            clock.onSleep = { n in if n == 2 { frequencies = s.cores?.map(\.frequency); runner.task?.cancel() } }
            runner.task = Task { await s.run() }
            await runner.task?.value
            #expect(frequencies == [.unavailable, .idle])
        }

        // MARK: fixture

        @Test func fixtureLocksTheSamplerAgainstThePageTask() async {
            let clock = VirtualClock(), fake = FakeSocReaders()
            let s = make(fake, clock: clock)
            s.applyFixture(SocLiveFixture(cores: nil, gpuRows: .empty, powerW: 12.5, gpuCoreCount: 10))
            await s.run()   // returns at once: a fixture build starts no tick
            #expect(fake.total == 0 && clock.sleeps.isEmpty && !s.isRunning)
            #expect(s.powerW == 12.5 && s.gpuRows == .empty && s.gpuCoreCount == 10)
        }

        // MARK: (4) the views exist only on the SoC page

        @Test func chartHoverAndBarsAreMountedOnlyOnTheSoCPage() throws {
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-soc-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let m = AppModel(dataDirectory: dir)
            m.applyVisualFixture()
            let width = LiveWindowWidth(1150)
            let tier = WidthTier.initial(width: 1150)
            let r = NavigationRouter()
            let h = SocHost(MacContentView(model: m, router: r, width: width, tier: tier, breakpoints: PageBreakpoints(width: 1150)))
            let homeBars = h.barViews
            #expect(h.hoverViews == 0, "Home: no chart hover view")
            r.navigate(to: Destination(.cpu))
            h.settle()
            #expect(h.hoverViews >= 1, "SoC page: the chart's hover view is mounted")
            // The fixture has 4P + 4E: eight core bars on top of the heroes, split and GPU rows.
            #expect(h.barViews >= 8, "SoC page: the core bars are mounted (\(h.barViews) bar views)")
            // Same page with the cores card absent: the difference is the cores card's bars (fails if they are not mounted).
            let socBars = h.barViews
            let m2 = AppModel(dataDirectory: dir)
            m2.applyVisualFixture()
            let f = m2.socLive
            m2.socLive.applyFixture(SocLiveFixture(cores: nil, gpuRows: f.gpuRows, powerW: f.powerW, gpuCoreCount: f.gpuCoreCount))
            let r2 = NavigationRouter()
            let h2 = SocHost(MacContentView(model: m2, router: r2, width: width, tier: tier, breakpoints: PageBreakpoints(width: 1150)))
            r2.navigate(to: Destination(.cpu))
            h2.settle()
            #expect(socBars - h2.barViews >= 8, "SoC page: 8 core bars more than without the cores card (\(socBars) vs \(h2.barViews))")
            h2.close()
            r.back()
            h.settle()
            #expect(h.hoverViews == 0, "Back at Home: the chart hover view is gone")
            #expect(h.barViews == homeBars, "Back at Home: no SoC bar is left (\(h.barViews) vs \(homeBars))")
            h.close()
        }
    }
}
