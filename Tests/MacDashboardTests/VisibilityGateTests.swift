// Tests/MacDashboardTests/VisibilityGateTests.swift
// SAMPLER-OCCLUSION-GATE Stage A: the pure gate (resolve matrix, transitions, parking, cancellation) and ResumePolicy.
import Foundation
import Testing
@testable import MacDashboard

struct VisibilityGateTests {
    static let V = [WindowFacts(isPanel: false, isVisible: true, isOnScreen: true)]
    static let T = Date(timeIntervalSince1970: 1_000_000)

    @Test func resolveMatrix() {
        let panel = WindowFacts(isPanel: true, isVisible: true, isOnScreen: true)
        let offScreen = WindowFacts(isPanel: false, isVisible: true, isOnScreen: false)
        let minimised = WindowFacts(isPanel: false, isVisible: false, isOnScreen: true)
        #expect(VisibilityGate.resolve([], appActive: true) == .hidden)
        #expect(VisibilityGate.resolve([panel], appActive: true) == .hidden)
        #expect(VisibilityGate.resolve([offScreen], appActive: true) == .hidden)
        #expect(VisibilityGate.resolve([minimised], appActive: true) == .hidden)
        let mixed = Self.V + [panel, offScreen]
        #expect(VisibilityGate.resolve(mixed, appActive: true) == .visible)
        #expect(VisibilityGate.resolve(mixed, appActive: false) == .hidden)
    }

    @Test @MainActor func updateTransitions() {
        let T = Self.T, V = Self.V
        let gate = VisibilityGate()
        #expect(gate.update(windows: V, appActive: true) == nil)
        #expect(gate.state == .visible)
        #expect(gate.update(windows: V, appActive: false, now: T) == nil)
        #expect(gate.state == .hidden)
        #expect(gate.hiddenSince == T)
        #expect(gate.update(windows: V, appActive: true, now: T.addingTimeInterval(120)) == 120)
        #expect(gate.state == .visible)
        #expect(gate.lastHiddenFor == 120)
        #expect(gate.hiddenSince == nil)
        #expect(gate.update(windows: V, appActive: true, now: T.addingTimeInterval(130)) == nil)
        #expect(gate.lastHiddenFor == 120)
        #expect(gate.state == .visible)
        #expect(gate.update(windows: [], appActive: true) == nil)
        #expect(gate.state == .hidden)
    }

    @Test @MainActor func waitReturnsAtOnceWhenVisible() async {
        let gate = VisibilityGate()
        let clock = ContinuousClock()
        let start = clock.now
        let r = await gate.waitUntilVisible()
        #expect(r == 0)
        #expect(clock.now - start < .milliseconds(100))
    }

    @Test @MainActor func waitParksWhileHiddenAndReturnsHiddenLength() async throws {
        let T = Self.T, V = Self.V
        let gate = VisibilityGate()
        gate.update(windows: V, appActive: false, now: T)
        var result: TimeInterval?
        let task = Task { @MainActor in result = await gate.waitUntilVisible() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(result == nil)
        gate.update(windows: V, appActive: true, now: T.addingTimeInterval(45))
        await task.value
        #expect(result == 45)
    }

    @Test @MainActor func waitSumsSpansWhenGateHidesAgainBeforeWake() async throws {
        let T = Self.T, V = Self.V
        let gate = VisibilityGate()
        gate.update(windows: V, appActive: false, now: T)
        var result: TimeInterval?
        let task = Task { @MainActor in result = await gate.waitUntilVisible() }
        try await Task.sleep(for: .milliseconds(50))
        gate.update(windows: V, appActive: true, now: T.addingTimeInterval(120))
        gate.update(windows: V, appActive: false, now: T.addingTimeInterval(120))
        try await Task.sleep(for: .milliseconds(50))
        #expect(result == nil)
        gate.update(windows: V, appActive: true, now: T.addingTimeInterval(125))
        await task.value
        #expect(result == 125)
    }

    @Test @MainActor func cancellationUnparks() async throws {
        let gate = VisibilityGate()
        gate.update(windows: [], appActive: false)
        let t = Task { @MainActor in await gate.waitUntilVisible() }
        try await Task.sleep(for: .milliseconds(50))
        t.cancel()
        let finished = await withTaskGroup(of: TimeInterval?.self) { group in
            group.addTask { await t.value }
            group.addTask { try? await Task.sleep(for: .seconds(2)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #expect(finished == 0)
    }

    @Test func resumePolicy() {
        #expect(!ResumePolicy.reprimesDeltas(hiddenFor: 0))
        #expect(!ResumePolicy.reprimesDeltas(hiddenFor: 5))
        #expect(!ResumePolicy.reprimesDeltas(hiddenFor: 30))
        #expect(ResumePolicy.reprimesDeltas(hiddenFor: 30.5))
        #expect(ResumePolicy.reprimesDeltas(hiddenFor: 3600))
    }
}
