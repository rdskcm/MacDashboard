// Engine/VisibilityGate.swift
// SAMPLER-OCCLUSION-GATE: the one owner of "is the user looking at the app" — the app is frontmost AND at least one
// non-panel window is on screen (user decision D1, 2026-10-25). Pure: the window facts are gathered in AppShell.swift
// (AppActivityMonitor, the only reader of NSApp.isActive and NSWindow.occlusionState) and handed in as values, so this
// file stays inside the Engine boundary (EngineBoundaryTests). The fast, slow and Battery loops of AppModel park on
// `waitUntilVisible()`; AppModel.isPaused mirrors `state` for every other reader. Covered by VisibilityGateTests.
import Foundation
import Observation

/// What the gate needs to know about one window. Built from NSWindow in AppShell.swift, by hand in tests.
struct WindowFacts: Equatable, Sendable {
    var isPanel: Bool        // NSPanel (HoverTip's tooltip panels) never keeps the app visible
    var isVisible: Bool      // NSWindow.isVisible: ordered in and not miniaturized
    var isOnScreen: Bool     // NSWindow.occlusionState.contains(.visible)
    var countsAsVisible: Bool { !isPanel && isVisible && isOnScreen }
}

@MainActor @Observable
final class VisibilityGate {
    enum State: Equatable, Sendable { case visible, hidden }

    /// `.visible` while the app is frontmost AND at least one non-panel window is on screen (D1, D7). Default
    /// `.visible`: the fixture and the tests never feed the gate and must behave like a visible app.
    private(set) var state: State = .visible
    /// Set on the visible → hidden transition, cleared on hidden → visible.
    @ObservationIgnored private(set) var hiddenSince: Date? = nil
    /// Length of the most recent hidden period, set on hidden → visible; 0 before the first one.
    @ObservationIgnored private(set) var lastHiddenFor: TimeInterval = 0
    /// -visibilityProbe: print every transition (set by AppModel.start()).
    @ObservationIgnored var logsTransitions = false

    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Pure: the sampling state for the app's activation and its windows (D1, D7).
    nonisolated static func resolve(_ windows: [WindowFacts], appActive: Bool) -> State {
        appActive && windows.contains(where: \.countsAsVisible) ? .visible : .hidden
    }

    /// Resolves and applies. Returns the hidden duration on a hidden → visible transition (nil otherwise), so the
    /// caller can run its resume hooks.
    @discardableResult
    func update(windows: [WindowFacts], appActive: Bool, now: Date = Date()) -> TimeInterval? {
        let next = Self.resolve(windows, appActive: appActive)
        guard next != state else { return nil }
        var hiddenFor: TimeInterval? = nil
        if next == .hidden {
            hiddenSince = now
        } else {
            hiddenFor = hiddenSince.map { now.timeIntervalSince($0) } ?? 0
            lastHiddenFor = hiddenFor ?? 0
            hiddenSince = nil
        }
        state = next
        if logsTransitions {
            print("gate: \(next) appActive=\(appActive) at \(now)" + (hiddenFor.map { String(format: " hiddenFor=%.0fs", $0) } ?? ""))
        }
        if next == .visible { resumeAll() }
        return hiddenFor
    }

    /// Returns 0 at once while visible; otherwise suspends with no wake-ups until the next visible transition or the
    /// caller's cancellation, and returns the total hidden time across every span it waited through (a wake that
    /// finds the gate hidden again re-parks and adds the next span; 0 when cancelled while still hidden). Registration runs on the main actor and the cancel handler hops to it, so a cancellation that
    /// lands before registration is seen by the `Task.isCancelled` check inside the registration closure.
    func waitUntilVisible() async -> TimeInterval {
        guard state == .hidden else { return 0 }
        var total: TimeInterval = 0
        while state == .hidden, !Task.isCancelled {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    if Task.isCancelled { c.resume() } else { waiters[id] = c }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.resume(id) }
            }
            total += lastHiddenFor
        }
        return state == .visible ? total : 0
    }

    private func resume(_ id: UUID) { waiters.removeValue(forKey: id)?.resume() }
    private func resumeAll() { let all = waiters; waiters = [:]; for c in all.values { c.resume() } }
}

/// SAMPLER-OCCLUSION-GATE D6a: what a resumed sampler does with the delta baselines recorded before the gap. Pure; tested.
enum ResumePolicy {
    /// A delta over a gap of up to `CPULoad.maxSampleGap` (30 s) is a legitimately longer sample window and is kept;
    /// over a longer gap the baselines are forgotten and the first sample after resume only primes.
    static func reprimesDeltas(hiddenFor: TimeInterval) -> Bool { hiddenFor > CPULoad.maxSampleGap }
}
