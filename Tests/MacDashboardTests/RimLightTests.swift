// Tests/MacDashboardTests/RimLightTests.swift
// RIM-GLOW-OPTICS Stage 2: the pointer-light and ambient maths (pure, no process-wide state). Oracles are from the spec §3.2/§3.3.
import CoreGraphics
import Foundation
import IOSurface
import Testing
@testable import MacDashboard

struct RimLightTests {
    static let g = SIMD3<Double>(34, 33, 31) / 255

    private func rgba(_ b: OrbBitmap, width: Int? = nil, height: Int? = nil) -> [UInt8] {
        let w = width ?? b.sidePx, h = height ?? b.sidePx
        IOSurfaceLock(b.surface, .readOnly, nil)
        defer { IOSurfaceUnlock(b.surface, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(b.surface).assumingMemoryBound(to: UInt8.self)
        let stride = IOSurfaceGetBytesPerRow(b.surface)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let s = y * stride + x * 4, o = (y * w + x) * 4
                out[o] = base[s + 2]; out[o + 1] = base[s + 1]; out[o + 2] = base[s]; out[o + 3] = base[s + 3]
            }
        }
        return out
    }

    private func pixel(_ bytes: [UInt8], width: Int, _ x: Int, _ y: Int) -> [Int] {
        let o = (y * width + x) * 4
        return (0..<4).map { Int(bytes[o + $0]) }
    }

    @Test func shapeOracle() {
        let rows: [(Double, Double)] = [(0, 1.0), (0.5, 0.7155), (1, 0.3536), (2, 0.0894), (3, 0.0316), (3.5, 0.0207), (4.25, 0.0060), (5, 0)]
        for h in [40.0, 70, 110] {
            for (x, want) in rows { #expect(abs(RimLight.shape(r: x * h, h: h) - want) <= 0.0005, "h \(h) r/h \(x)") }
            let R = RimLight.range(h: h)
            #expect(RimLight.shape(r: R, h: h) == 0)
            #expect(RimLight.shape(r: 1.5 * R, h: h) == 0)
        }
    }

    @Test func peakCalibration() {
        let g = Self.g
        let pk = RimLight.peak(ground: g)
        #expect(abs(pk.x - 0.3144) <= 0.0005)
        let d1 = RimLight.delta(f: 1, ground: g, peak: pk)
        for k in 0..<3 {
            let want: Double = 0.55 * (255 - g[k] * 255)
            let got: Double = d1[k] * 255
            #expect(abs(got - want) <= 0.01, "channel \(k)")
        }
        let d0 = RimLight.delta(f: 0, ground: g, peak: pk)
        for k in 0..<4 { #expect(abs(d0[k]) <= 1e-12) }
        #expect(abs(RimLight.delta(f: 0.3536, ground: g, peak: pk).x * 255 - 65.9) <= 0.3)
        #expect(abs(RimLight.delta(f: 0.0207, ground: g, peak: pk).x * 255 - 7.3) <= 0.2)
        var prev = SIMD4<Double>(repeating: -1)
        for i in 0...100 {
            let d = RimLight.delta(f: Double(i) / 100, ground: g, peak: pk)
            #expect(d.w == max(d.x, d.y, d.z))
            for k in 0..<4 { #expect(d[k] >= 0 && d[k] >= prev[k]) }
            prev = d
        }
    }

    @Test func tableAndSide() {
        #expect(RimLight.sidePx(h: 70, scale: 2) == 1400)
        #expect(RimLight.sidePx(h: 40, scale: 2) == 800)
        #expect(RimLight.sidePx(h: 110, scale: 2) == 2200)
        #expect(RimLight.sidePx(h: 70, scale: 1) == 700)
        for (h, s) in [(40.0, 1.0), (70, 2), (110, 2)] {
            let t = RimLight.table(h: h, scale: s, ground: Self.g)
            #expect(t.count == Int((5 * h * s).rounded(.up)) + 2)
            #expect(t[t.count - 1] == .zero && t[t.count - 2] == .zero)
        }
    }

    @Test func spriteBitmap() throws {
        let b = try #require(RimLight.render(h: 40, scale: 1, ground: Self.g))
        #expect(b.sidePx == 400)
        #expect(IOSurfaceGetWidth(b.surface) == 400 && IOSurfaceGetHeight(b.surface) == 400)
        #expect(IOSurfaceGetPixelFormat(b.surface) == OrbBitmap.pixelFormatBGRA)
        let bytes = rgba(b)
        var clean = true, premultiplied = true
        for y in 0..<400 {
            for x in 0..<400 {
                let p = pixel(bytes, width: 400, x, y)
                let dx = Double(x) + 0.5 - 200, dy = Double(y) + 0.5 - 200
                if (dx * dx + dy * dy).squareRoot() >= 200, p != [0, 0, 0, 0] { clean = false }
                if p[0] > p[3] || p[1] > p[3] || p[2] > p[3] { premultiplied = false }
            }
        }
        #expect(clean)
        #expect(premultiplied)
        let c = pixel(bytes, width: 400, 200, 200)
        for (got, want) in zip(c, [122, 122, 123, 123]) { #expect(abs(got - want) <= 1, "centre \(c)") }
        let m = pixel(bytes, width: 400, 240, 200)
        #expect(abs(m[0] - 65) <= 2, "mid \(m)")
        let again = try #require(RimLight.render(h: 40, scale: 1, ground: Self.g))
        #expect(rgba(again) == bytes)
    }

    @Test func orbCoreUnchanged() throws {
        let colour = SIMD3<Double>(0.4, 0.5, 0.9), ground = SIMD3<Double>(0.1, 0.1, 0.12)
        let mode = OrbBitmap.Mode.dark(ground: ground)
        let seed = OrbBitmap.seed(orb: 0)
        let a = try #require(OrbBitmap.render(d: 420, scale: 1, colour: colour, alpha: 0.45, mode: mode, seed: seed))
        let lut = OrbBitmap.table(d: 420, scale: 1, colour: colour, alpha: 0.45, mode: mode)
        let b = try #require(OrbBitmap.render(lut: lut, radiusPx: 294, sidePx: 588, seed: seed))
        #expect(rgba(a) == rgba(b))
    }

    @Test func localPoint() {
        let r = CGRect(x: 100, y: 200, width: 400, height: 150)
        #expect(RimLight.localPoint(CGPoint(x: 300, y: 250), in: r) == CGPoint(x: 200, y: 50))
        #expect(RimLight.localPoint(CGPoint(x: 50, y: 100), in: r) == CGPoint(x: -50, y: -100))
    }

    @Test func ambientRamp() {
        let r = RimAmbient.ramp(alpha: 0.55, ground: SIMD3(repeating: 34.0 / 255))
        #expect(r.count == 9)
        for (i, e) in r.enumerated() { #expect(abs(e.location - Double(i) * 0.125) <= 1e-12) }
        #expect(r[0].multiplier == 1 && r[8].multiplier == 0)
        for i in 1..<9 { #expect(r[i].multiplier < r[i - 1].multiplier) }
        #expect(abs(r[4].multiplier - 0.671) <= 0.005)
        let g = SIMD3<Double>(repeating: 34.0 / 255)
        #expect(RimAmbient.delta(t: 1, ground: g, alpha: 0.55) == .zero)
    }

    @Test func ambientBitmap() throws {
        let g = SIMD3<Double>(repeating: 34.0 / 255)
        let b = try #require(RimAmbient.render(depthPx: 40, ground: g, alpha: 0.55))
        #expect(IOSurfaceGetWidth(b.surface) == 1 && IOSurfaceGetHeight(b.surface) == 40)
        let bytes = rgba(b, width: 1, height: 40)
        for y in 0..<40 {
            let p = pixel(bytes, width: 1, 0, y)
            #expect(p[0] <= p[3] && p[1] <= p[3] && p[2] <= p[3])
        }
        let top = pixel(bytes, width: 1, 0, 0)
        for k in 0..<4 { #expect(abs(Double(top[k]) - 0.55 * (255 - 34)) <= 2, "row 0 \(top)") }
        #expect(pixel(bytes, width: 1, 0, 39).allSatisfy { $0 <= 2 })
    }

    @Test func shadedGround() {
        let s = RimLight.shadedGround(SIMD3<Double>(243, 241, 237) / 255, shade: SIMD3<Double>(60, 40, 20) / 255, alpha: 0.12) * 255
        for (got, want) in zip([s.x, s.y, s.z], [221.0, 216.9, 211.0]) { #expect(abs(got - want) <= 0.05) }
    }

    @Test func renderCost() {
        let t0 = Date()
        for h in [40.0, 70, 110] {
            let s = Date()
            #expect(RimLight.render(h: h, scale: 2, ground: Self.g) != nil)
            print("RimLight.render h=\(h) @2x: \(Int(Date().timeIntervalSince(s) * 1000)) ms")
        }
        // The budget is for release builds (`swift test -c release`); a debug build on a CI runner
        // measured 2.8 s, which says nothing about the shipped app.
        #if !DEBUG
        #expect(Date().timeIntervalSince(t0) < 2)
        #endif
    }
}
