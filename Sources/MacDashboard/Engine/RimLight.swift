import Foundation
import CoreGraphics
import IOSurface

/// RIM-GLOW-OPTICS: the pointer light on card edges — a point light at height h over the glass (spec §3.2). Pure; pinned by RimLightTests.
enum RimLight {
    enum LightMode { case none, white, shade }
    /// Stage 3a/3b: read from the hidden defaults; Stage 4 freezes both to the user's picks.
    static let heights: [String: Double] = ["1": 40, "2": 70, "3": 110]
    static let defaultProfileKey = "2"
    static let rangeFactor = 5.0                      // R = 5h
    static let windowStart = 0.7
    static let peakAlpha = 0.55                       // today's rimHi dark peak, the calibration point (D2)
    static let seed: UInt64 = 0x5EED_0C0D_E0BB_5A17

    static func range(h: Double) -> Double { rangeFactor * h }

    /// f(r) = (1 + (r/h)²)^(-3/2) · W(r/R); 0 for r ≥ R.
    static func shape(r: Double, h: Double) -> Double {
        let u = r / range(h: h)
        guard u < 1 else { return 0 }
        return pow(1 + (r / h) * (r / h), -1.5) * (1 - OrbProfile.smoothstep(windowStart, 1, u))
    }

    /// L0_k: white at `alpha` over the reference ground, in linear light.
    static func peak(ground g: SIMD3<Double>, alpha: Double = peakAlpha) -> SIMD3<Double> {
        var l = SIMD3<Double>(repeating: 0)
        for k in 0..<3 { l[k] = OrbProfile.decode(g[k] + alpha * (1 - g[k])) - OrbProfile.decode(g[k]) }
        return l
    }

    /// Stored premultiplied delta (Δr, Δg, Δb, max) over `ground` for shape value `f`.
    static func delta(f: Double, ground: SIMD3<Double>, peak: SIMD3<Double>) -> SIMD4<Double> {
        var d = SIMD3<Double>(repeating: 0)
        for k in 0..<3 { d[k] = OrbProfile.encode(OrbProfile.decode(ground[k]) + peak[k] * f) - ground[k] }
        return SIMD4(d.x, d.y, d.z, d.max())
    }

    /// `⌈R·s⌉ + 2` entries by integer device-pixel radius, exactly zero at and beyond R.
    static func table(h: Double, scale: Double, ground: SIMD3<Double>) -> [SIMD4<Double>] {
        let n = Int((range(h: h) * scale).rounded(.up)) + 2
        let l0 = peak(ground: ground)
        return (0..<n).map { i in
            let f = shape(r: Double(i) / scale, h: h)
            return f == 0 ? SIMD4(repeating: 0) : delta(f: f, ground: ground, peak: l0)
        }
    }

    static func sidePx(h: Double, scale: Double) -> Int { Int((2 * range(h: h) * scale).rounded()) }

    static func render(h: Double, scale: Double, ground: SIMD3<Double>) -> OrbBitmap? {
        OrbBitmap.render(lut: table(h: h, scale: scale, ground: ground), radiusPx: range(h: h) * scale,
                         sidePx: sidePx(h: h, scale: scale), seed: seed)
    }

    /// Window space → card-local; both flipped (top-left origin). Negatives are allowed.
    static func localPoint(_ p: CGPoint, in rect: CGRect) -> CGPoint { CGPoint(x: p.x - rect.minX, y: p.y - rect.minY) }

    /// g·(1−α) + shade·α
    static func shadedGround(_ g: SIMD3<Double>, shade: SIMD3<Double>, alpha: Double) -> SIMD3<Double> {
        g * (1 - alpha) + shade * alpha
    }
}

/// Ambient light from above (spec §3.3), shared by the CA ring and the SwiftUI strokes.
enum RimAmbient {
    static let stops = 9
    static func profile(_ t: Double) -> Double { max(0, 1 - t) }

    static func delta(t: Double, ground: SIMD3<Double>, alpha: Double) -> SIMD4<Double> {
        RimLight.delta(f: profile(t), ground: ground, peak: RimLight.peak(ground: ground, alpha: alpha))
    }

    /// One entry per device-pixel row; row 0 is t = 0 (full), the last row t = 1 (zero).
    static func table(depthPx: Int, ground: SIMD3<Double>, alpha: Double) -> [SIMD4<Double>] {
        (0..<depthPx).map { i in
            delta(t: depthPx > 1 ? Double(i) / Double(depthPx - 1) : 0, ground: ground, alpha: alpha)
        }
    }

    /// Multiplier on the top colour's opacity at t = 0, 0.125 … 1: Δ(t) / Δ(0) on the brightest channel.
    static func ramp(alpha: Double, ground: SIMD3<Double>) -> [(location: Double, multiplier: Double)] {
        let top = delta(t: 0, ground: ground, alpha: alpha).w
        return (0..<stops).map { i in
            let t = Double(i) / Double(stops - 1)
            return (t, top > 0 ? delta(t: t, ground: ground, alpha: alpha).w / top : 0)
        }
    }

    /// 1 × depthPx premultiplied BGRA IOSurface tagged sRGB, ±1 LSB triangular dither (same as `OrbBitmap.render`).
    static func render(depthPx: Int, ground: SIMD3<Double>, alpha: Double) -> OrbBitmap? {
        guard depthPx > 0 else { return nil }
        let lut = table(depthPx: depthPx, ground: ground, alpha: alpha)
        let props: [CFString: Any] = [kIOSurfaceWidth: 1, kIOSurfaceHeight: depthPx, kIOSurfaceBytesPerElement: 4,
                                      kIOSurfacePixelFormat: OrbBitmap.pixelFormatBGRA]
        guard let surface = IOSurfaceCreate(props as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB), let tag = space.copyPropertyList() else { return nil }
        IOSurfaceLock(surface, [], nil)
        let out = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
        let stride = IOSurfaceGetBytesPerRow(surface)
        for y in 0..<depthPx {
            var g = OrbBitmap.Generator(state: RimLight.seed ^ (UInt64(y) &* 0xD1B5_4A32_D192_ED03))
            let v = lut[y]
            let bits = g.next()
            let o = y * stride
            var a: UInt8 = 0
            for k in (0..<4).reversed() {
                let lane = bits >> (UInt64(k) * 16)
                let tri = Double(lane & 0xFF) / 255 + Double((lane >> 8) & 0xFF) / 255 - 1
                let q = UInt8(min(255, max(0, (v[k] * 255 + tri).rounded())))
                if k == 3 { a = q; out[o + 3] = q } else { out[o + 2 - k] = min(q, a) }
            }
        }
        IOSurfaceUnlock(surface, [], nil)
        IOSurfaceSetValue(surface, kIOSurfaceColorSpace, tag)
        return OrbBitmap(sidePx: depthPx, surface: surface)
    }
}
