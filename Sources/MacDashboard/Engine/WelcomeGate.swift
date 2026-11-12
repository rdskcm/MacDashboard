// Engine/WelcomeGate.swift
// MOONPORT-RENAME: the one app-level "the Welcome panel is up" state. While it holds, nothing at launch may raise a
// macOS permission prompt over the panel (Automation, Files & Folders, Local Network). Work that can prompt is handed to
// `whenOpen`; it runs at once when the gate is open and in the order it arrived when `release()` opens it. No timer, no
// polling. The archive move's own Documents access is not gated (it is part of what the panel reports).
import Foundation

@MainActor
final class WelcomeGate {
    private(set) var isHolding = false
    private var waiting: [@MainActor () -> Void] = []

    /// The panel is going to be shown this launch. Called once, before any launch work starts.
    func hold() { isHolding = true }

    /// Runs `work` now when the gate is open, else after `release()`.
    func whenOpen(_ work: @escaping @MainActor () -> Void) {
        if isHolding { waiting.append(work) } else { work() }
    }

    /// The panel was closed (Later, Done, Esc). Opens the gate and runs what waited; a second call does nothing.
    func release() {
        guard isHolding else { return }
        isHolding = false
        let queued = waiting
        waiting = []
        for work in queued { work() }
    }
}
