import Foundation
import CoreGraphics
import Dispatch
import IOSurface

/// REDESIGN-ORBS: pure geometry of the window backdrop. Mockup boxes are CSS `top/right/bottom/left` offsets of a
/// d × d square; a centre is `(left + d/2, top + d/2)` in flipped (top-left origin) coordinates.
enum OrbGeometry {
    /// CSS `right: r` → left edge, for a box of side d in a width w.
    static func leftFromRight(_ r: CGFloat, d: CGFloat, width w: CGFloat) -> CGFloat { w - r - d }
    /// CSS `bottom: b` → top edge, for a box of side d in a height h.
    static func topFromBottom(_ b: CGFloat, d: CGFloat, height h: CGFloat) -> CGFloat { h - b - d }
    static func centre(left: CGFloat, top: CGFloat, d: CGFloat) -> CGPoint { CGPoint(x: left + d / 2, y: top + d / 2) }
}

/// REDESIGN-ORBS Stage 2 (D11): the optically honest orb profile H1 (spec §3.3) and the bitmap it renders.
/// Pure: Foundation + CoreGraphics + IOSurface + Dispatch only; every constant and formula here is pinned by `BackdropMathTests`.
enum OrbProfile {
    static let sigmaFactor = 1.0 / 6        // σ = d/6 (H1)
    static let r0Factor = 1.0 / 6           // r0 = d/6 (H1)
    static let radiusFactor = 0.7           // Rl = 0.7·d: f is 0 at and beyond it
    static let sideFactor: CGFloat = 1.4    // layer side = 2·Rl
    static let windowStart = 0.7            // W(u) = 1 − smoothstep(0.7, 1, u)

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// P(r)/P(0)·W(u) with r and d in the same unit; 0 for r ≥ 0.7·d. P(0) = 0.65 + 0.35 = 1.
    static func shape(r: Double, d: Double) -> Double {
        let u = r / (radiusFactor * d)
        guard u < 1 else { return 0 }
        let sigma = sigmaFactor * d, r0 = r0Factor * d
        let p = 0.65 * exp(-r * r / (2 * sigma * sigma)) + 0.35 * pow(1 + (r / r0) * (r / r0), -1.5)
        return p * (1 - smoothstep(windowStart, 1, u))
    }

    /// sRGB transfer (IEC 61966-2-1), components on 0…1.
    static func decode(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func encode(_ l: Double) -> Double { l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055 }

    /// Dark: the stored premultiplied delta (r, g, b, a) over `ground` for shape value `f` — spec §3.3 «Dark».
    static func darkDelta(f: Double, ground: SIMD3<Double>, colour: SIMD3<Double>, alpha: Double) -> SIMD4<Double> {
        var d = SIMD3<Double>(repeating: 0)
        for k in 0..<3 {
            let gl = decode(ground[k])
            let l0 = decode(ground[k] + colour[k] * alpha) - gl
            d[k] = encode(gl + l0 * f) - ground[k]
        }
        return SIMD4(d.x, d.y, d.z, d.max())
    }

    /// Light: the premultiplied tint for shape value `f` — spec §3.3 «Light».
    static func lightTint(f: Double, colour: SIMD3<Double>, alpha: Double) -> SIMD4<Double> {
        let a = alpha * f
        return SIMD4(colour.x * a, colour.y * a, colour.z * a, a)
    }
}

/// One orb's premultiplied 8-bit bitmap, `sidePx × sidePx`, ±1 LSB triangular dither (spec §3.3). The pixels live in a
/// single IOSurface (BGRA, tagged sRGB) that goes straight into `layer.contents`: no `[UInt8]`, `Data` or `CGImage`
/// copy, and no colour-converted copy made by Core Animation (step M, memory findings F1).
struct OrbBitmap {
    enum Mode { case dark(ground: SIMD3<Double>), light }
    let sidePx: Int
    let surface: IOSurfaceRef

    static let pixelFormatBGRA: UInt32 = 0x4247_5241     // 'BGRA'

    static func sidePx(d: CGFloat, scale: CGFloat) -> Int { Int((OrbProfile.sideFactor * d * scale).rounded()) }

    /// Seed of orb `index` (0 = A, 1 = B, 2 = C). Rows re-seed from it, so the parallel bands below are
    /// scheduling-independent and two renders of the same inputs are byte-identical.
    static func seed(orb index: Int) -> UInt64 { 0x5EED_0C0D_E0BB_5000 &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15 }

    /// SplitMix64, inline so the sequence never depends on the platform's generator.
    struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The 1-D table (D12): stored components at integer device-pixel radius `i` (r = i/scale pt),
    /// `⌈0.7·d·scale⌉ + 2` entries, exactly zero at and beyond Rl.
    static func table(d: CGFloat, scale: CGFloat, colour: SIMD3<Double>, alpha: Double, mode: Mode) -> [SIMD4<Double>] {
        let n = Int((OrbProfile.radiusFactor * Double(d) * Double(scale)).rounded(.up)) + 2
        return (0..<n).map { i in
            let f = OrbProfile.shape(r: Double(i) / Double(scale), d: Double(d))
            switch mode {
            case .dark(let ground): return OrbProfile.darkDelta(f: f, ground: ground, colour: colour, alpha: alpha)
            case .light: return OrbProfile.lightTint(f: f, colour: colour, alpha: alpha)
            }
        }
    }

    /// Fills the surface from the table by pixel radius, rows in bands across the cores. Pure CPU, called once per
    /// appearance × scale by `DS3OrbView.renderImagesIfNeeded`; never on the frame path (`gpu-per-frame`).
    /// The surface row is padded (`IOSurfaceGetBytesPerRow` ≥ 4·side), so every offset uses the stride. Every pixel
    /// is written, pixels at and beyond Rl as four zero bytes (a fresh surface is not documented to be zeroed). Nil only if the surface cannot be created.
    static func render(d: CGFloat, scale: CGFloat, colour: SIMD3<Double>, alpha: Double, mode: Mode, seed: UInt64) -> OrbBitmap? {
        let side = sidePx(d: d, scale: scale)
        let lut = table(d: d, scale: scale, colour: colour, alpha: alpha, mode: mode)
        let centre = Double(side) / 2
        let rlPx = OrbProfile.radiusFactor * Double(d) * Double(scale)   // u ≥ 1 is skipped, as in honest.swift
        let props: [CFString: Any] = [kIOSurfaceWidth: side, kIOSurfaceHeight: side, kIOSurfaceBytesPerElement: 4,
                                      kIOSurfacePixelFormat: pixelFormatBGRA]
        guard let surface = IOSurfaceCreate(props as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB), let tag = space.copyPropertyList() else { return nil }
        IOSurfaceLock(surface, [], nil)
        let out = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
        let stride = IOSurfaceGetBytesPerRow(surface)
        let bandRows = 64
        let bands = (side + bandRows - 1) / bandRows
        DispatchQueue.concurrentPerform(iterations: bands) { band in
            let y0 = band * bandRows, y1 = min(side, y0 + bandRows)
            for y in y0..<y1 {
                var g = Generator(state: seed ^ (UInt64(y) &* 0xD1B5_4A32_D192_ED03))
                let dy = Double(y) + 0.5 - centre
                for x in 0..<side {
                    let dx = Double(x) + 0.5 - centre
                    let r = (dx * dx + dy * dy).squareRoot()
                    let o = y * stride + x * 4
                    guard r < rlPx else {                               // at/beyond Rl the pixel is exactly 0
                        out[o] = 0; out[o + 1] = 0; out[o + 2] = 0; out[o + 3] = 0
                        continue
                    }
                    let i = Int(r)                                      // i + 1 < lut.count follows from r < rlPx
                    let v = lut[i] + (lut[i + 1] - lut[i]) * (r - Double(i))
                    let bits = g.next()                                 // four 16-bit lanes → four ±1 LSB triangulars
                    var a: UInt8 = 0
                    for k in (0..<4).reversed() {                       // alpha first, colour clamped to it
                        let lane = bits >> (UInt64(k) * 16)
                        let tri = Double(lane & 0xFF) / 255 + Double((lane >> 8) & 0xFF) / 255 - 1
                        let q = UInt8(min(255, max(0, (v[k] * 255 + tri).rounded())))
                        if k == 3 { a = q; out[o + 3] = q } else { out[o + 2 - k] = min(q, a) }   // BGRA byte order
                    }
                }
            }
        }
        IOSurfaceUnlock(surface, [], nil)
        IOSurfaceSetValue(surface, kIOSurfaceColorSpace, tag)    // sRGB, the tag the Stage 1 `ImageRenderer` output carried
        return OrbBitmap(sidePx: side, surface: surface)
    }
}
