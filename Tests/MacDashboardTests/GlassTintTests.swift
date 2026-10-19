// Tests/MacDashboardTests/GlassTintTests.swift
// CARD-GLASS-BACKDROP: token table for the glass card tint (Engine/GlassTint.swift). Same shape as RimAngleTests.swift.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct GlassTintTests {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

        @Test func defaultIsMockup() {
            let f = GlassTint.fill(tintAmount: nil, reduceTransparency: false)
            #expect(f.usesMaterial, "GlassTint: default uses material")
            #expect(near(f.darkAlpha, 0.70), "GlassTint: default dark is 0.70")
            #expect(near(f.lightAlpha, 0.66), "GlassTint: default light is 0.66")
            let mid = GlassTint.fill(tintAmount: 0.5, reduceTransparency: false)
            #expect(near(mid.darkAlpha, 0.70) && near(mid.lightAlpha, 0.66), "GlassTint: 0.5 is the mockup")
            #expect(GlassTint.Fill.standard == f, "GlassTint: standard equals the nil default")
        }

        @Test func ends() {
            let c = GlassTint.fill(tintAmount: 0, reduceTransparency: false)
            #expect(near(c.darkAlpha, 0.50) && near(c.lightAlpha, 0.50), "GlassTint: Clear is 0.50 / 0.50")
            let t = GlassTint.fill(tintAmount: 1, reduceTransparency: false)
            #expect(near(t.darkAlpha, 0.90) && near(t.lightAlpha, 0.90), "GlassTint: Tinted is 0.90 / 0.90")
        }

        @Test func midpoints() {
            let a = GlassTint.fill(tintAmount: 0.25, reduceTransparency: false)
            #expect(near(a.darkAlpha, 0.60) && near(a.lightAlpha, 0.58), "GlassTint: 0.25 is 0.60 / 0.58")
            let b = GlassTint.fill(tintAmount: 0.75, reduceTransparency: false)
            #expect(near(b.darkAlpha, 0.80) && near(b.lightAlpha, 0.78), "GlassTint: 0.75 is 0.80 / 0.78")
        }

        @Test func monotonic() {
            var ok = true
            var prev = GlassTint.fill(tintAmount: 0, reduceTransparency: false)
            for t in stride(from: 0.0, through: 1.0, by: 0.05) {
                let f = GlassTint.fill(tintAmount: t, reduceTransparency: false)
                if f.darkAlpha < prev.darkAlpha - 1e-9 || f.lightAlpha < prev.lightAlpha - 1e-9 { ok = false }
                if f.darkAlpha < 0.50 - 1e-9 || f.darkAlpha > 0.90 + 1e-9 { ok = false }
                if f.lightAlpha < 0.50 - 1e-9 || f.lightAlpha > 0.90 + 1e-9 { ok = false }
                prev = f
            }
            #expect(ok, "GlassTint: alphas are non-decreasing and within 0.50…0.90")
        }

        @Test func reduceTransparencyWins() {
            for t: Double? in [nil, 0, 0.5, 1] {
                let f = GlassTint.fill(tintAmount: t, reduceTransparency: true)
                #expect(!f.usesMaterial && near(f.darkAlpha, 1) && near(f.lightAlpha, 1),
                        "GlassTint: Reduce Transparency wins at \(String(describing: t))")
            }
        }

        @Test func parse() {
            #expect(GlassTint.parse(NSNumber(value: 0.3)) == 0.3, "GlassTint.parse: number 0.3")
            #expect(GlassTint.parse("0.4") == 0.4, "GlassTint.parse: numeric string 0.4")
            #expect(GlassTint.parse(NSNumber(value: -1)) == 0, "GlassTint.parse: -1 clamps to 0")
            #expect(GlassTint.parse(NSNumber(value: 2)) == 1, "GlassTint.parse: 2 clamps to 1")
            #expect(GlassTint.parse(NSNumber(value: Double.nan)) == nil, "GlassTint.parse: NaN is nil")
            #expect(GlassTint.parse("abc") == nil, "GlassTint.parse: non-numeric string is nil")
            #expect(GlassTint.parse(nil) == nil, "GlassTint.parse: nil is nil")
            #expect(GlassTint.parse(Date()) == nil, "GlassTint.parse: other types are nil")
        }

        @MainActor @Test func fixtureProvider() {
            let d = UserDefaults.standard
            defer {
                d.removeObject(forKey: GlassTint.fixtureTintKey)
                d.removeObject(forKey: GlassTint.fixtureReduceTransparencyKey)
            }
            d.set(0.0, forKey: GlassTint.fixtureTintKey)
            d.set(false, forKey: GlassTint.fixtureReduceTransparencyKey)
            let g = GlassSettings(fixture: true)
            #expect(g.fill == GlassTint.fill(tintAmount: 0, reduceTransparency: false),
                    "GlassSettings: fixture keys set the fill at init")
            d.set(true, forKey: GlassTint.fixtureReduceTransparencyKey)
            g.refresh()
            #expect(!g.fill.usesMaterial, "GlassSettings: fixture RT key reaches the fill on refresh")
        }
    }
}
