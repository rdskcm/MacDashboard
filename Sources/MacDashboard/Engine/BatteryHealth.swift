// Engine/BatteryHealth.swift
// BATTERY-HEALTH-UNIFY: the ONE battery-health rule. Home (Assess.assess), the Battery page (BatteryPageModel) and the
// iPhone (IPhoneData.healthTone) judge health here; nothing else compares a battery percentage with 80 %.
import Foundation

enum BatteryHealthClass: Equatable, Sendable { case normal, worn, service, unknown }

enum BatteryHealth {
    /// Apple: a Mac laptop battery is designed to retain up to 80 % of its original capacity at its maximum cycle count
    /// (support.apple.com/102888), and AppleCare replaces one that holds less than 80 % (support.apple.com/100170), with
    /// no cycle-count condition; iPhone: 80 % at the rated cycle count (support.apple.com/101575, /106348).
    /// Below it the battery is worn (amber) whatever its cycle count.
    static let wornBelowPercent = 80

    /// `system_profiler` Condition other than "Normal" (trimmed, case-sensitive) and non-empty: macOS's own service
    /// flag (support.apple.com/108376 — Apple publishes no percentage for it).
    static func isServiceCondition(_ condition: String?) -> Bool {
        guard let c = condition?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return false }
        return c != "Normal"
    }

    /// Service > worn > normal; no percentage and no service Condition → unknown. Pass the number the surface SHOWS.
    static func classify(healthPercent: Int?, condition: String?) -> BatteryHealthClass {
        classify(precisePercent: healthPercent.map(Double.init), condition: condition)
    }

    /// Same rule for a fractional percentage (the iPhone shows one decimal). Pass it rounded to the shown precision,
    /// so "80.0 %" on screen is never amber. A non-finite value is unknown.
    static func classify(precisePercent: Double?, condition: String?) -> BatteryHealthClass {
        if isServiceCondition(condition) { return .service }
        guard let p = precisePercent, p.isFinite else { return .unknown }
        return p < Double(wornBelowPercent) ? .worn : .normal
    }

    /// The Mac percentage every surface shows and judges (D2): Apple's «Maximum Capacity» (`system_profiler`), or —
    /// with Settings › Monitoring › «Raw battery health» on — the ioreg AppleRawMaxCapacity / DesignCapacity ratio,
    /// falling back to Apple's figure until an ioreg read exists.
    static func macShownPercent(apple: Int?, raw: Int?, prefersRaw: Bool) -> Int? {
        prefersRaw ? (raw ?? apple) : apple
    }
}
