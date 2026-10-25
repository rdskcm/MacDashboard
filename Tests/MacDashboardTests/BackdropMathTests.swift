// Tests/MacDashboardTests/BackdropMathTests.swift
// REDESIGN-ORBS: orb geometry (Stage 1) and the H1 orb profile and bitmap (Stage 2) of the window backdrop
// (pure, no process-wide state). Every oracle is computed from the spec's §3.3, none from a first run.
import CoreGraphics
import Foundation
import IOSurface
import Testing
@testable import MacDashboard

struct BackdropMathTests {
    private func near(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat) -> Bool {
        abs(p.x - x) <= 0.01 && abs(p.y - y) <= 0.01
    }

    @Test func windowCentresAtBenchSize() {
        let size = CGSize(width: 1000, height: 733)
        let c = DS3OrbSpec.window.map { $0.centre(size) }
        #expect(near(c[0], 830, 90))
        #expect(near(c[1], 40, 620))
        #expect(near(c[2], 590, 713))
    }

    @Test func windowCentresAtMinimumSize() {
        let size = CGSize(width: 900, height: 620)
        let c = DS3OrbSpec.window.map { $0.centre(size) }
        #expect(near(c[0], 730, 90))
        #expect(near(c[1], 40, 620))
        #expect(near(c[2], 510, 600))
    }

    @Test func settingsCentresUnchanged() {
        let size = CGSize(width: 680, height: 420)
        let c = DS3OrbSpec.settings.map { $0.centre(size) }
        #expect(near(c[0], 80, 40))
        #expect(near(c[1], 610, 430))
        #expect(near(c[2], 430, -70))
    }

    @Test func diameters() {
        #expect(DS3OrbSpec.window.map(\.d) == [780, 580, 420])
        #expect(DS3OrbSpec.settings.map(\.d) == [520, 460, 380])
    }

    // MARK: Stage 2 — H1 profile

    private static let darkGround = SIMD3<Double>(16, 15, 13) / 255
    private static let darkColour = SIMD3<Double>(70, 130, 240) / 255
    private static let lightColour = SIMD3<Double>(62, 123, 239) / 255

    @Test func shapeOracle() {
        let rows: [(Double, Double)] = [(0, 1.0), (0.25, 0.4894), (0.5, 0.0995), (0.7, 0.0203), (0.85, 0.0040), (1.0, 0.0)]
        for d in [1.0, 780.0] {
            for (u, f) in rows {
                let got = OrbProfile.shape(r: u * 0.7 * d, d: d)
                #expect(abs(got - f) <= 0.0005, "d \(d) u \(u): \(got) vs \(f)")
            }
            #expect(OrbProfile.shape(r: 0.7 * d, d: d) == 0)
            #expect(OrbProfile.shape(r: 0.7 * d * 1.5, d: d) == 0)
        }
    }

    @Test func transfer() {
        for x in [0.0, 0.5, 1.0] {
            #expect(abs(OrbProfile.encode(OrbProfile.decode(x)) - x) <= 1e-9)
        }
        // The IEC thresholds (0.04045 decoded, 0.0031308 encoded) are not exact inverses of each other, so the
        // round trip at the decode threshold itself is off by ~3e-8 (below 1e-5 of one 8-bit step).
        #expect(abs(OrbProfile.encode(OrbProfile.decode(0.04045)) - 0.04045) <= 1e-7)
        #expect(abs(OrbProfile.decode(16.0 / 255) - 0.00518) <= 0.00002)
    }

    @Test func darkDeltaOracle() {
        let full = OrbProfile.darkDelta(f: 1, ground: Self.darkGround, colour: Self.darkColour, alpha: 0.45) * 255
        for (got, want) in zip([full.x, full.y, full.z, full.w], [31.5, 58.5, 108.0, 108.0]) {
            #expect(abs(got - want) <= 0.01)
        }
        let mid = OrbProfile.darkDelta(f: 0.099478, ground: Self.darkGround, colour: Self.darkColour, alpha: 0.45) * 255
        #expect(abs(mid.x - 5.10) <= 0.05)
        #expect(abs(mid.z - 28.5) <= 0.1)
        #expect(mid.w == mid.z)
        // f = 0 round-trips through decode/encode, so the delta is zero up to floating-point residue (~7e-18).
        let zero = OrbProfile.darkDelta(f: 0, ground: Self.darkGround, colour: Self.darkColour, alpha: 0.45)
        #expect(max(abs(zero.x), abs(zero.y), abs(zero.z), abs(zero.w)) <= 1e-12)
        for f in [0.01, 0.3, 0.7] {
            let v = OrbProfile.darkDelta(f: f, ground: Self.darkGround, colour: Self.darkColour, alpha: 0.45)
            #expect(v.x >= 0 && v.y >= 0 && v.z >= 0 && v.w >= 0)
            #expect(v.w == max(v.x, v.y, v.z))
        }
    }

    @Test func lightTintOracle() {
        let mid = OrbProfile.lightTint(f: 0.099478, colour: Self.lightColour, alpha: 0.55) * 255
        #expect(abs(mid.w - 13.95) <= 0.02)
        #expect(abs(mid.x - 3.39) <= 0.02)
        #expect(abs(OrbProfile.lightTint(f: 1, colour: Self.lightColour, alpha: 0.55).w * 255 - 140.25) <= 0.01)
    }

    @Test func profileConstants() {
        #expect(OrbProfile.sideFactor == 1.4)
        #expect(OrbProfile.radiusFactor == 0.7)
        #expect(OrbProfile.sigmaFactor == 1.0 / 6 && OrbProfile.r0Factor == 1.0 / 6)
        #expect(OrbBitmap.sidePx(d: 780, scale: 2) == 2184)
        #expect(OrbBitmap.sidePx(d: 580, scale: 2) == 1624)
        #expect(OrbBitmap.sidePx(d: 420, scale: 2) == 1176)
        #expect(OrbBitmap.sidePx(d: 520, scale: 2) == 1456)
        #expect(OrbBitmap.sidePx(d: 420, scale: 1) == 588)
    }

    /// Tight RGBA rows read back from the IOSurface (BGRA, padded stride) — the order and layout the Stage 2 tests used.
    private func rgba(_ b: OrbBitmap) -> [UInt8] {
        IOSurfaceLock(b.surface, .readOnly, nil)
        defer { IOSurfaceUnlock(b.surface, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(b.surface).assumingMemoryBound(to: UInt8.self)
        let stride = IOSurfaceGetBytesPerRow(b.surface)
        var out = [UInt8](repeating: 0, count: b.sidePx * b.sidePx * 4)
        for y in 0..<b.sidePx {
            for x in 0..<b.sidePx {
                let s = y * stride + x * 4, o = (y * b.sidePx + x) * 4
                out[o] = base[s + 2]; out[o + 1] = base[s + 1]; out[o + 2] = base[s]; out[o + 3] = base[s + 3]
            }
        }
        return out
    }

    private func pixel(_ bytes: [UInt8], side: Int, _ x: Int, _ y: Int) -> [Int] {
        let o = (y * side + x) * 4
        return (0..<4).map { Int(bytes[o + $0]) }
    }

    private func render(d: CGFloat, scale: CGFloat, colour: SIMD3<Double>, alpha: Double, mode: OrbBitmap.Mode, orb: Int) throws -> OrbBitmap {
        try #require(OrbBitmap.render(d: d, scale: scale, colour: colour, alpha: alpha, mode: mode, seed: OrbBitmap.seed(orb: orb)))
    }

    @Test func darkBitmap() throws {
        let mode = OrbBitmap.Mode.dark(ground: Self.darkGround)
        let b = try render(d: 420, scale: 1, colour: Self.darkColour, alpha: 0.45, mode: mode, orb: 0)
        #expect(b.sidePx == 588)
        #expect(IOSurfaceGetWidth(b.surface) == 588 && IOSurfaceGetHeight(b.surface) == 588)
        #expect(IOSurfaceGetPixelFormat(b.surface) == OrbBitmap.pixelFormatBGRA)
        #expect(IOSurfaceGetBytesPerRow(b.surface) >= 588 * 4)
        let bytes = rgba(b)
        func pixel(_ x: Int, _ y: Int) -> [Int] { self.pixel(bytes, side: 588, x, y) }
        let c = pixel(294, 294)
        for (got, want) in zip(c, [32, 59, 108, 108]) { #expect(abs(got - want) <= 1, "centre \(c)") }
        let m = pixel(441, 294)
        #expect((4...6).contains(m[0]), "mid \(m)")
        #expect((27...30).contains(m[2]), "mid \(m)")
        #expect(pixel(0, 0) == [0, 0, 0, 0])
        #expect(pixel(587, 294)[3] <= 1)
        var outsideClean = true, premultiplied = true
        for y in 0..<588 {
            for x in 0..<588 {
                let p = pixel(x, y)
                let dx = Double(x) + 0.5 - 294, dy = Double(y) + 0.5 - 294
                if (dx * dx + dy * dy).squareRoot() >= 294, p != [0, 0, 0, 0] { outsideClean = false }
                if p[0] > p[3] || p[1] > p[3] || p[2] > p[3] { premultiplied = false }
            }
        }
        #expect(outsideClean)
        #expect(premultiplied)
        let again = try render(d: 420, scale: 1, colour: Self.darkColour, alpha: 0.45, mode: mode, orb: 0)
        #expect(rgba(again) == bytes)
    }

    @Test func lightBitmap() throws {
        let b = try render(d: 420, scale: 1, colour: Self.lightColour, alpha: 0.55, mode: .light, orb: 0)
        let bytes = rgba(b)
        func pixel(_ x: Int, _ y: Int) -> [Int] { self.pixel(bytes, side: 588, x, y) }
        let c = pixel(294, 294)
        #expect(abs(c[3] - 140) <= 1, "centre \(c)")
        #expect(abs(c[0] - 34) <= 1, "centre \(c)")
        #expect(pixel(0, 0) == [0, 0, 0, 0])
        #expect(pixel(587, 0) == [0, 0, 0, 0])
        #expect(pixel(0, 587) == [0, 0, 0, 0])
        #expect(pixel(587, 587) == [0, 0, 0, 0])
        var premultiplied = true
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i] > bytes[i + 3] || bytes[i + 1] > bytes[i + 3] || bytes[i + 2] > bytes[i + 3] {
            premultiplied = false
        }
        #expect(premultiplied)
    }

    /// The D12 bound: the real number is read from the release run (`swift test -c release …`); this only catches a pathological loop.
    @Test func renderCost() throws {
        let clock = ContinuousClock()
        let mode = OrbBitmap.Mode.dark(ground: Self.darkGround)
        var times: [Duration] = []
        for (i, d) in [CGFloat(780), 580, 420].enumerated() {
            var made: OrbBitmap?
            times.append(clock.measure {
                made = OrbBitmap.render(d: d, scale: 2, colour: Self.darkColour, alpha: 0.45, mode: mode, seed: OrbBitmap.seed(orb: i))
            })
            #expect(made != nil)
        }
        func ms(_ t: Duration) -> Int { Int(t.components.seconds * 1000 + t.components.attoseconds / 1_000_000_000_000_000) }
        let total = times.reduce(Duration.zero, +)
        print("orb render 2x: A \(ms(times[0])) B \(ms(times[1])) C \(ms(times[2])) total \(ms(total)) ms")
        #expect(total < .seconds(5))
    }

    // MARK: - Stage 3: drift (spec §3.4, §4.3)

    private static let driftOrbs: [OrbDrift.Params] = [OrbDrift.a, OrbDrift.b, OrbDrift.c]

    @Test func driftWeights() {
        let oracle: [(Double, Double, Double)] = [(46, 63, 0.7178), (31, 43, 0.7204), (21, 29, 0.7195),
                                                   (52, 71, 0.7172), (37, 53, 0.7268), (25, 34, 0.7164)]
        for (t1, t2, c1) in oracle {
            let w = OrbDrift.weights(t1: t1, t2: t2)
            #expect(abs(w.c1 - c1) <= 0.0005, "T \(t1)/\(t2): \(w.c1)")
            #expect(w.c1 + w.c2 == 1)
        }
    }

    @Test func driftTermLayout() {
        let paths = ["transform.translation.x", "transform.translation.x", "transform.translation.y", "transform.translation.y",
                     "transform.scale.x", "transform.scale.y",
                     "transform.scale.x", "transform.scale.x", "transform.scale.x", "transform.scale.x",
                     "transform.scale.y", "transform.scale.y", "transform.scale.y", "transform.scale.y"]
        let translation: [[Double]] = [[58.5, 31.5, 45.5, 24.5], [71.5, 38.5, 52, 28], [84.5, 45.5, 58.5, 31.5]]
        for (p, want) in zip(Self.driftOrbs, translation) {
            let terms = OrbDrift.terms(p)
            #expect(terms.count == 14)
            #expect(terms.map(\.keyPath) == paths)
            for (t, w) in zip(terms.prefix(4), want) { #expect(abs(t.amplitude - w) <= 1e-9) }
            for t in terms where t.keyPath.hasPrefix("transform.scale") { #expect(abs(t.amplitude) <= 0.12) }
        }
    }

    @Test func driftSamplesCloseTheLoop() {
        for p in Self.driftOrbs {
            for term in OrbDrift.terms(p) {
                let s = OrbDrift.samples(term)
                #expect(s.count == OrbDrift.keyframes)
                #expect(abs(s[0] - s[s.count - 1]) <= 1e-9, "\(term)")
                #expect(s.allSatisfy { abs($0) <= abs(term.amplitude) + 1e-12 })
            }
        }
    }

    @Test func driftTranslationMatchesMockup() {
        let w = 2 * Double.pi, p = OrbDrift.a
        let terms = OrbDrift.terms(p)
        for t in [0, 7.3, 100.0] {
            let x = terms[0].value(at: t) + terms[1].value(at: t)
            let y = terms[2].value(at: t) + terms[3].value(at: t)
            let wantX = 90 * (0.65 * sin(w * t / 46) + 0.35 * sin(w * t / 63))
            let wantY = 70 * (0.65 * sin(w * t / 52 + 1.3) + 0.35 * sin(w * t / 71 + 1.7 * 1.3))
            #expect(abs(x - wantX) <= 1e-9, "x at \(t)")
            #expect(abs(y - wantY) <= 1e-9, "y at \(t)")
        }
    }

    @Test func driftShipsEnabled() {
        #expect(OrbDrift.isEnabled)
    }
}
