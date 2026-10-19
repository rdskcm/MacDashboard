// Engine/FixtureAppearance.swift
// HARNESS-REDESIGN-RETARGET: under -visualFixture the app's appearance follows the fixture-only key
// `visualAppearance` ("dark" | "light"; anything else = follow the system) in the app's own defaults domain,
// so tools/visual/smoke.sh switches dark/light live without touching the system setting. Created only in fixture mode.
import AppKit

@MainActor
final class FixtureAppearance {
    static let key = "visualAppearance"
    static let shared = FixtureAppearance()
    private var observer: DefaultsKeyObserver?

    private init() {
        apply()
        // KVO reports changes made by other processes (`defaults write`); the callback may come on any thread.
        observer = DefaultsKeyObserver(keys: [Self.key]) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply() } }
        }
    }

    private func apply() {
        switch UserDefaults.standard.string(forKey: Self.key) {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil
        }
    }
}
