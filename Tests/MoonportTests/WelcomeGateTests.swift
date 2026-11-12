// Tests/MoonportTests/WelcomeGateTests.swift
// MOONPORT-RENAME: launch work that can raise a macOS permission prompt (report pass, folder count, protected-folder
// probes, iPhone transport) waits on `WelcomeGate` while the Welcome panel is up and runs when it closes.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    @MainActor struct WelcomeGateTests {
        @Test func openGateRunsWorkAtOnce() {
            let gate = WelcomeGate()
            var ran = 0
            gate.whenOpen { ran += 1 }
            #expect(ran == 1)
            #expect(!gate.isHolding)
        }

        @Test func heldGateStartsNothingUntilRelease() {
            let gate = WelcomeGate()
            var order: [String] = []
            gate.hold()
            gate.whenOpen { order.append("report") }
            gate.whenOpen { order.append("iphone") }
            #expect(gate.isHolding)
            #expect(order.isEmpty)           // the panel is up: nothing started
            gate.release()
            #expect(order == ["report", "iphone"])   // after it closed: in arrival order
            #expect(!gate.isHolding)
        }

        @Test func workQueuedAfterReleaseRunsImmediately() {
            let gate = WelcomeGate()
            gate.hold(); gate.release()
            var ran = false
            gate.whenOpen { ran = true }
            #expect(ran)
        }

        @Test func releaseRunsQueuedWorkOnlyOnce() {
            let gate = WelcomeGate()
            var ran = 0
            gate.hold()
            gate.whenOpen { ran += 1 }
            gate.release(); gate.release()
            #expect(ran == 1)
        }

        @Test func releaseWithoutHoldIsHarmless() {
            let gate = WelcomeGate()
            gate.release()
            var ran = 0
            gate.whenOpen { ran += 1 }
            #expect(ran == 1)
        }

        @Test func modelStartsWithAnOpenGate() {
            // No panel this launch → `start()` behaves as before: the gate is open unless `MoonportApp.init` held it.
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-welcome-gate-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let m = AppModel(dataDirectory: dir, settings: AppSettings(defaults: d), time: VirtualClock().source)
            #expect(!m.welcome.isHolding)
        }

        @Test func noGateWhenWelcomeWasShownOrNothingMoved() {
            let (d, name) = makeIsolatedDefaults(); defer { removeIsolatedDefaults(d, name) }
            let s = AppSettings(defaults: d)
            let none = FileManager.default.temporaryDirectory.appendingPathComponent("wg-none-\(UUID().uuidString)/welcome-pending.json")
            #expect(!LegacyNotice.willShowAtLaunch(settings: s, pendingURL: none))   // the test process moved nothing, no pending file
            s.welcomeShown = true
            #expect(!LegacyNotice.willShowAtLaunch(settings: s, pendingURL: none))
        }
    }
}
