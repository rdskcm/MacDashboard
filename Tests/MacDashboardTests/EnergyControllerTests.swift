// Tests/MacDashboardTests/EnergyControllerTests.swift
// ARCH-MODEL-SPLIT: the Energy state machine through injected closures — no collector, no privileged call,
// no coordinator. Host and clock fakes: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeEnergy {
    var settings: EnergySettings? = EnergySettings(battery: [("displaysleep", "2")], ac: [("displaysleep", "10")])
    var outcome: PrivilegedRunner.Outcome = .success
    private(set) var collectCalls = 0
    private(set) var applied: [String] = []
    /// When set, the first `collect` suspends until `releaseCollect()`.
    var holdFirstCollect = false
    private var collectGate: CheckedContinuation<Void, Never>?
    /// When set, `apply` suspends until `releaseApply()`.
    var holdApply = false
    private var applyGate: CheckedContinuation<Void, Never>?

    func releaseCollect() { collectGate?.resume(); collectGate = nil }
    func releaseApply() { applyGate?.resume(); applyGate = nil }

    var deps: EnergyController.Dependencies {
        EnergyController.Dependencies(
            collect: {
                self.collectCalls += 1
                if self.holdFirstCollect, self.collectCalls == 1 {
                    await withCheckedContinuation { self.collectGate = $0 }
                }
                return self.settings
            },
            apply: { command in
                self.applied.append(command)
                if self.holdApply { await withCheckedContinuation { self.applyGate = $0 } }
                return self.outcome
            })
    }
}

extension SerialTests {
    @MainActor struct EnergyControllerTests {
        private func make() -> (EnergyController, FakeHost, FakeEnergy, VirtualClock) {
            let host = FakeHost(), fake = FakeEnergy(), clock = VirtualClock()
            return (EnergyController(host: host.host, time: clock.source, deps: fake.deps), host, fake, clock)
        }
        private let change = EnergyChange(bucket: .battery, key: "displaysleep", value: "5")   // → "/usr/bin/pmset -b displaysleep 5"
        private let noop = EnergyChange(bucket: .battery, key: "displaysleep", value: "abc")   // pmsetCommand → nil

        // 1 (R5 + D14: an unchanged re-read performs no report mutation)
        @Test func refreshWritesTheSectionAfterThePassEndsAndOnlyWhenChanged() async {
            let (c, host, fake, _) = make()
            await c.refresh()
            #expect(fake.collectCalls == 1 && host.awaitCalls == 1 && host.updateCalls == 1)
            #expect(host.report.energy == fake.settings)
            #expect(c.refreshing == false && host.reassessCalls == 0)
            await c.refresh()                                   // same settings again
            #expect(fake.collectCalls == 2 && host.awaitCalls == 2)
            #expect(host.updateCalls == 1)                      // no mutation for an unchanged value
        }
        // 2
        @Test func refreshDuringARefreshReadsOnceMoreAndReturnsAfterIt() async {
            let (c, host, fake, _) = make()
            fake.holdFirstCollect = true
            let first = Task { await c.refresh() }
            await settle { c.refreshing }
            let second = Task { await c.refresh() }
            await settle { fake.collectCalls == 1 }          // the second caller is waiting, not collecting
            fake.settings = EnergySettings(battery: [("sleep", "1")], ac: [])
            fake.releaseCollect()
            await first.value; await second.value
            #expect(fake.collectCalls == 2)                   // two reads happened…
            #expect(host.report.energy == fake.settings)      // …and the host holds what the last one returned
            #expect(c.refreshing == false)
        }
        // 3
        @Test func applyIgnoresChangesThatProduceNoCommand() async {
            let (c, _, fake, _) = make()
            c.applyChanges([noop])
            #expect(c.applyState == .idle && c.applyTask == nil && fake.applied.isEmpty)
        }
        // 4
        @Test func applySuccessRereadsThenShowsApplied() async {
            let (c, host, fake, _) = make()
            c.applyChanges([change])
            #expect(c.applyState == .applying)
            await c.applyTask?.value
            #expect(fake.applied == ["/usr/bin/pmset -b displaysleep 5"])
            #expect(fake.collectCalls == 1 && host.report.energy == fake.settings)
            #expect(c.applyState == .applied)
        }
        // 5
        @Test func applyCancelledFailsWithoutAReread() async {
            let (c, _, fake, _) = make()
            fake.outcome = .cancelled
            c.applyChanges([change]); await c.applyTask?.value
            #expect(c.applyState == .failed(.cancelled) && fake.collectCalls == 0)
        }
        // 6
        @Test func applyTimedOutRereadsThenFails() async {
            let (c, _, fake, _) = make()
            fake.outcome = .timedOut
            c.applyChanges([change]); await c.applyTask?.value
            #expect(c.applyState == .failed(.timedOut) && fake.collectCalls == 1)
        }
        // 7
        @Test func applyErrorRereadsThenFailsWithTheMessage() async {
            let (c, _, fake, _) = make()
            fake.outcome = .failed("code 1")
            c.applyChanges([change]); await c.applyTask?.value
            #expect(c.applyState == .failed(.error("code 1")) && fake.collectCalls == 1)
        }
        // 8 (B1: the apply Task runs only once the test suspends — settle before the second call)
        @Test func applyWhileApplyingIsIgnored() async {
            let (c, _, fake, _) = make()
            fake.holdApply = true
            c.applyChanges([change])
            await settle { fake.applied.count == 1 }         // the first apply is now parked at the gate
            c.applyChanges([change])
            #expect(fake.applied.count == 1)
            fake.releaseApply(); await c.applyTask?.value
            #expect(c.applyState == .applied)
        }
        // 9 (B1 + R6: cancellation of an apply that is in flight)
        @Test func stopCancelsTheInFlightApplyAndLeavesIdle() async {
            let (c, _, fake, _) = make()
            fake.holdApply = true
            c.applyChanges([change])
            await settle { fake.applied.count == 1 }         // parked at the gate = the privileged dialog is open
            let task = c.applyTask
            c.stop()
            #expect(c.applyTask == nil)
            fake.releaseApply(); await task?.value
            #expect(c.applyState == .idle && fake.collectCalls == 0)
        }
        // 11 (R12: stop() during the apply's re-read ends the re-entrancy wait; the in-flight read still honours readNeeded)
        @Test func stopDuringTheApplyRereadLeavesIdle() async {
            let (c, _, fake, clock) = make()
            fake.holdFirstCollect = true
            c.refreshNow()
            await settle { fake.collectCalls == 1 }
            c.applyChanges([change])
            await settle { fake.applied.count == 1 }
            let task = c.applyTask
            let sleepsBefore = clock.sleeps.count
            c.stop()
            var done = false
            Task { await task?.value; done = true }
            await settle { done }
            #expect(done)
            #expect(clock.sleeps.count - sleepsBefore <= 1)
            fake.releaseCollect()
            await settle { !c.refreshing }
            #expect(c.applyState == .idle)
            #expect(fake.collectCalls == 2)
        }
        // 10
        @Test func dismissAndFixtureSetTheState() {
            let (c, _, _, _) = make()
            c.applyFixture(.failed(.timedOut))
            #expect(c.applyState == .failed(.timedOut))
            c.dismissApplyResult()
            #expect(c.applyState == .idle)
        }
    }
}
