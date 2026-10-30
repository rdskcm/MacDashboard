// Views/GlassTint.swift
// CARD-GLASS-BACKDROP: glass card tint opacity from the system Liquid Glass slider (NSGlassTintAmount) and
// Reduce Transparency. `GlassTint` is the single token table (pure, covered by Tests/MacDashboardTests/GlassTintTests.swift);
// `GlassSettings` is the one app-wide reader, created in MacDashboardApp and injected with `.environment(_:)`.
import Foundation
import AppKit
import Observation

enum GlassTint {
    /// NSGlobalDomain float written by System Settings › Appearance › Liquid Glass: 0 = Clear … 1 = Tinted.
    /// Undocumented; absent or unreadable means the default (mockup) look.
    static let systemKey = "NSGlassTintAmount"
    /// Fixture-only keys in the app's own defaults domain, read only under `-visualFixture`
    /// (the visual harness under tools/visual/ writes them).
    static let fixtureTintKey = "visualGlassTintAmount"
    static let fixtureReduceTransparencyKey = "visualReduceTransparency"

    /// Slider value that maps to the mockup opacity (D1). An absent key maps there too.
    static let pivot: Double = 0.5

    struct Stops: Equatable {
        let clear: Double
        let mockup: Double
        let tinted: Double
    }
    /// Tint opacity at slider 0 / pivot / 1. `mockup` is the IPHONE-DESIGN `glassStrong` value.
    static let dark = Stops(clear: 0.50, mockup: 0.70, tinted: 0.90)
    static let light = Stops(clear: 0.50, mockup: 0.66, tinted: 0.90)
    /// CARD-GLASS-LEFTOVERS: the frosted bar (`DS3GlassBar`: main header, section-page bar, iPhone device header).
    /// `mockup` is the IPHONE-DESIGN `DS3.bar` alpha. `tinted` sits near the solid end so the Reduce Transparency flip
    /// macOS performs at the slider's Tinted stop moves the bar by about 4 levels, not 12 (D1).
    static let barDark = Stops(clear: 0.30, mockup: 0.42, tinted: 0.85)
    static let barLight = Stops(clear: 0.30, mockup: 0.42, tinted: 0.85)

    struct Fill: Equatable {
        /// false under Reduce Transparency: no `.regularMaterial`, the tint is opaque.
        let usesMaterial: Bool
        let darkAlpha: Double
        let lightAlpha: Double
        /// Bar tint opacity (`DS3GlassBar`), from `barDark` / `barLight`; 1 under Reduce Transparency.
        let barDarkAlpha: Double
        let barLightAlpha: Double

        /// The default look (absent key, Reduce Transparency off) — what `DS3.glassStrong` draws.
        static let standard = GlassTint.fill(tintAmount: nil, reduceTransparency: false)
        /// Reduce Transparency: no material, every alpha 1. `DSCardSurface` draws this colour under RT (D5).
        static let solid = GlassTint.fill(tintAmount: nil, reduceTransparency: true)
    }

    /// A stored value as a slider position: numbers and numeric strings, clamped to 0…1; anything else (or NaN) is nil.
    static func parse(_ raw: Any?) -> Double? {
        let v: Double?
        if let n = raw as? NSNumber { v = n.doubleValue }
        else if let s = raw as? String { v = Double(s.trimmingCharacters(in: .whitespaces)) }
        else { v = nil }
        guard let v, v.isFinite else { return nil }
        return min(max(v, 0), 1)
    }

    /// Piecewise linear through (0, clear), (pivot, mockup), (1, tinted); nil is the mockup.
    static func alpha(_ s: Stops, tintAmount: Double?) -> Double {
        guard let raw = tintAmount else { return s.mockup }
        let t = min(max(raw, 0), 1)
        if t <= pivot { return s.clear + (s.mockup - s.clear) * (t / pivot) }
        return s.mockup + (s.tinted - s.mockup) * ((t - pivot) / (1 - pivot))
    }

    static func fill(tintAmount: Double?, reduceTransparency: Bool) -> Fill {
        if reduceTransparency { return Fill(usesMaterial: false, darkAlpha: 1, lightAlpha: 1, barDarkAlpha: 1, barLightAlpha: 1) }
        return Fill(usesMaterial: true,
                    darkAlpha: alpha(dark, tintAmount: tintAmount),
                    lightAlpha: alpha(light, tintAmount: tintAmount),
                    barDarkAlpha: alpha(barDark, tintAmount: tintAmount),
                    barLightAlpha: alpha(barLight, tintAmount: tintAmount))
    }
}

/// The one reader of both inputs (D3, D6). Cards read `fill` only; it is assigned only when it changes.
@MainActor @Observable
final class GlassSettings {
    private(set) var fill: GlassTint.Fill
    /// `fill.usesMaterial` as its own observed property: surfaces that only care about Reduce Transparency
    /// (`DSCardSurface`, Settings' `SolidCardSurface`) read this and are not re-run by slider drags (D4).
    private(set) var usesMaterial: Bool

    @ObservationIgnored private let fixture: Bool
    @ObservationIgnored private var keyObserver: DefaultsKeyObserver?
    /// Never removed, by design: `GlassSettings` is created once in `MacDashboardApp.init` and lives as long as the
    /// process, so removal could only happen at exit. Registered only when `fixture == false`, so the test instances
    /// (`GlassSettings(fixture: true)`) register no workspace observer. `DefaultsKeyObserver` removes its KVO in deinit.
    @ObservationIgnored private var workspaceToken: NSObjectProtocol?

    init(fixture: Bool) {
        self.fixture = fixture
        let initial = GlassSettings.read(fixture: fixture)
        self.fill = initial
        self.usesMaterial = initial.usesMaterial
        let keys = fixture
            ? [GlassTint.fixtureTintKey, GlassTint.fixtureReduceTransparencyKey]
            : [GlassTint.systemKey]
        // KVO reports changes made by other processes (NSUserDefaults.h); the callback may come on any thread.
        keyObserver = DefaultsKeyObserver(keys: keys) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        if !fixture {
            workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Re-reads both inputs; assigns only on a real change so an unchanged value never re-renders a card.
    func refresh() {
        let new = GlassSettings.read(fixture: fixture)
        if new != fill { fill = new }
        if new.usesMaterial != usesMaterial { usesMaterial = new.usesMaterial }
    }

    private static func read(fixture: Bool) -> GlassTint.Fill {
        let d = UserDefaults.standard
        if fixture {
            return GlassTint.fill(tintAmount: GlassTint.parse(d.object(forKey: GlassTint.fixtureTintKey)),
                                  reduceTransparency: d.bool(forKey: GlassTint.fixtureReduceTransparencyKey))
        }
        return GlassTint.fill(tintAmount: GlassTint.parse(d.object(forKey: GlassTint.systemKey)),
                              reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }
}

/// KVO on `UserDefaults.standard` for a fixed key list; removed on deinit.
final class DefaultsKeyObserver: NSObject {
    private let keys: [String]
    private let onChange: () -> Void

    init(keys: [String], onChange: @escaping () -> Void) {
        self.keys = keys
        self.onChange = onChange
        super.init()
        for k in keys { UserDefaults.standard.addObserver(self, forKeyPath: k, options: [.new], context: nil) }
    }

    deinit {
        for k in keys { UserDefaults.standard.removeObserver(self, forKeyPath: k) }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        onChange()
    }
}
