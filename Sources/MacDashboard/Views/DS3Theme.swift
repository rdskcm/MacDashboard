// Views/DS3Theme.swift
// IPHONE-DESIGN: DS v3 tokens (warm glass) used by iPhone mode; APP-REDESIGN will migrate This Mac and Settings. Values from inputs/IPHONE-DESIGN-2026-10-13.

import SwiftUI

/// "rgb(r,g,b) @ a" of the design: 0-255 channels with an opacity.
private func ds3RGB(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255).opacity(a)
}

enum DS3 {
    /// Named coordinate space of the window root; the pointer tracker and every rim use it.
    static let windowSpace = "ds3.window"

    static let ground = Color(light: Color(hex: 0xEEEBE5), dark: Color(hex: 0x100F0D))
    static let ink = Color(light: Color(hex: 0x1C1A17), dark: Color(hex: 0xEEEAE3))
    static let inkSoft = Color(light: Color(hex: 0x46423C), dark: Color(hex: 0xC6C0B6))
    static let muted = Color(light: Color(hex: 0x5F5A52), dark: Color(hex: 0xA39C90))
    static let line = Color(light: ds3RGB(60, 45, 25, 0.09), dark: ds3RGB(255, 240, 220, 0.08))
    static let lineStrong = Color(light: ds3RGB(60, 45, 25, 0.16), dark: ds3RGB(255, 240, 220, 0.15))
    static let row = Color(light: ds3RGB(60, 45, 25, 0.045), dark: ds3RGB(255, 240, 220, 0.045))
    static let track = Color(light: ds3RGB(60, 45, 25, 0.08), dark: ds3RGB(255, 240, 220, 0.09))
    static let chip = Color(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.07))
    static let field = Color(light: ds3RGB(255, 253, 249, 0.7), dark: ds3RGB(255, 248, 235, 0.05))
    static let lens = Color(light: Color.white.opacity(0.42), dark: Color.white.opacity(0.12))
    static let bar = Color(light: Color.white.opacity(GlassTint.barLight.mockup), dark: ds3RGB(30, 30, 34, GlassTint.barDark.mockup))
    static let glassStrong = Color(light: Color.white.opacity(GlassTint.light.mockup), dark: ds3RGB(26, 26, 30, GlassTint.dark.mockup))
    /// CARD-GLASS-BACKDROP: the glass tint at the opacities `GlassSettings` resolved (D8). The default fill returns
    /// `glassStrong` itself; any other fill is memoised on the last one, so a card body that re-runs for another
    /// reason gets the identical Color (a fresh dynamic NSColor compares unequal and would redraw the fill).
    /// One slot is enough: there is one `GlassSettings`, so one live fill at a time, and every card asks for that fill. A second concurrent fill (none exists) would thrash the slot, never return a wrong colour (CARD-GLASS-LEFTOVERS D8).
    @MainActor static func glassTint(_ f: GlassTint.Fill) -> Color {
        if f == .standard { return glassStrong }
        if let last = lastGlassTint, last.fill == f { return last.color }
        let c = Color(light: Color.white.opacity(f.lightAlpha), dark: ds3RGB(26, 26, 30, f.darkAlpha))
        lastGlassTint = (f, c)
        return c
    }
    @MainActor private static var lastGlassTint: (fill: GlassTint.Fill, color: Color)?
    /// CARD-GLASS-LEFTOVERS: the bar tint at the fill's bar opacities; `bar` itself for the default fill, otherwise
    /// memoised like `glassTint`, in its own slot (the two functions return different colours for the same fill).
    @MainActor static func barTint(_ f: GlassTint.Fill) -> Color {
        if f == .standard { return bar }
        if let last = lastBarTint, last.fill == f { return last.color }
        let c = Color(light: Color.white.opacity(f.barLightAlpha), dark: ds3RGB(30, 30, 34, f.barDarkAlpha))
        lastBarTint = (f, c)
        return c
    }
    @MainActor private static var lastBarTint: (fill: GlassTint.Fill, color: Color)?
    static let overlay = Color(light: ds3RGB(250, 248, 244, 0.96), dark: ds3RGB(30, 29, 27, 0.97))

    static let accent = Color(light: Color(hex: 0x2F7FE0), dark: Color(hex: 0x6AA6F2))
    static let accentInk = Color(light: Color(hex: 0x1A63C2), dark: Color(hex: 0x93BFF7))
    static let accentSolid = Color(light: Color(hex: 0x1F6FD6), dark: Color(hex: 0x2F7FE0))
    static let amber = Color(light: Color(hex: 0xC27C00), dark: Color(hex: 0xE9A23B))
    static let amberInk = Color(light: Color(hex: 0x8A5800), dark: Color(hex: 0xF0B45E))
    static let hot = Color(light: Color(hex: 0xD70015), dark: Color(hex: 0xFF453A))
    static let hotInk = Color(light: Color(hex: 0xB0000F), dark: Color(hex: 0xFF6B62))
    static let green = Color(light: Color(hex: 0x0F9A70), dark: Color(hex: 0x2BBD8F))
    static let greenInk = Color(light: Color(hex: 0x0A7454), dark: Color(hex: 0x4FD3A6))
    // REDESIGN-HOME 00-shared §1 series colours
    static let s1 = Color(light: Color(hex: 0x2A78D6), dark: Color(hex: 0x3987E5))      // active / data
    static let s2 = Color(light: Color(hex: 0x1BAF7A), dark: Color(hex: 0x199E70))      // wired
    static let s3 = Color(light: Color(hex: 0xEDA100), dark: Color(hex: 0xC98500))      // compressed / other
    static let s4 = Color(light: Color(hex: 0x008300), dark: Color(hex: 0x1E9A1E))      // inactive
    static let s5 = Color(light: Color(hex: 0x4A3AA7), dark: Color(hex: 0x9085E9))      // speculative
    static let sfree = Color(light: Color(hex: 0x9A958C), dark: Color(hex: 0x6B665E))   // system

    static let rimHi = Color(light: Color.white.opacity(1), dark: Color.white.opacity(0.55))
    static let rimMid = Color(light: Color.white.opacity(0.5), dark: Color.white.opacity(0.2))
    static let rimLo = Color(light: Color.white.opacity(0.14), dark: Color.white.opacity(0.04))
    /// RIM-GLOW-OPTICS: encoded sRGB of a glass card's surface with no orb under it (measured in Stage 1, 2026-10-26).
    static let rimGroundDark = SIMD3<Double>(27, 27, 29) / 255
    static let rimGroundLight = SIMD3<Double>(250, 250, 249) / 255
    /// Light `shade` variant: warm dark ink of the light-mode card shadow (`DS3Shadow.card`), under the additive ring.
    static let rimShade = ds3RGB(60, 40, 20, 0.12)

    static let orbA = Color(light: ds3RGB(62, 123, 239, 0.55), dark: ds3RGB(70, 130, 240, 0.45))
    static let orbB = Color(light: ds3RGB(244, 166, 59, 0.45), dark: ds3RGB(230, 140, 50, 0.30))
    static let orbC = Color(light: ds3RGB(238, 110, 94, 0.42), dark: ds3RGB(220, 95, 90, 0.34))  // v2 (00-shared §1 «orbC (changed)», REDESIGN-ORBS D1)

    /// accentSolid 70 % + white 30 %.
    static let primaryTop = Color(light: Color(hex: 0x629AE2), dark: Color(hex: 0x6DA5E9))
    /// accent 55 % + white 45 %.
    static let barTop = Color(light: Color(hex: 0x8DB9EE), dark: Color(hex: 0xADCEF8))
}

/// Hand-drawn shadow stacks (see `ds3Elevation`). `radius` is the SwiftUI blur radius (CSS blur / 2),
/// `inset` is the negated CSS spread.
enum DS3Shadow {
    case card, pop, lens, primaryGlow, header

    struct Layer {
        let color: Color
        let y: CGFloat
        let radius: CGFloat
        let inset: CGFloat
    }

    var layers: [Layer] {
        switch self {
        case .card:
            return [
                Layer(color: Color(light: ds3RGB(60, 40, 20, 0.08), dark: Color.black.opacity(0.35)), y: 1, radius: 1, inset: 0),
                Layer(color: Color(light: ds3RGB(60, 40, 20, 0.22), dark: Color.black.opacity(0.70)), y: 18, radius: 18, inset: 18),
            ]
        case .pop:
            return [
                Layer(color: Color(light: ds3RGB(60, 40, 20, 0.08), dark: Color.black.opacity(0.40)), y: 2, radius: 2, inset: 0),
                Layer(color: Color(light: ds3RGB(60, 40, 20, 0.35), dark: Color.black.opacity(0.80)), y: 18, radius: 20, inset: 12),
            ]
        case .lens:
            return [
                Layer(color: Color(light: ds3RGB(30, 20, 60, 0.12), dark: Color.black.opacity(0.30)), y: 1, radius: 1, inset: 0),
                Layer(color: Color(light: ds3RGB(30, 20, 60, 0.30), dark: Color.black.opacity(0.60)), y: 6, radius: 7, inset: 6),
            ]
        case .primaryGlow:
            return [
                Layer(color: DS3.accentSolid, y: 4, radius: 5, inset: 6),
            ]
        case .header:
            // 01-window-chrome: y 10, blur 24, spread −18, black .35 (both appearances).
            return [Layer(color: Color.black.opacity(0.35), y: 10, radius: 12, inset: 18)]
        }
    }
}

enum DS3Motion {
    static let press: Animation = .spring(response: 0.45, dampingFraction: 0.55)
    static let pressScale: CGFloat = 0.94

    static let tile: Animation = .spring(response: 0.5, dampingFraction: 0.6)
    static let tileHoverLift: CGFloat = -3
    static let tileHoverScale: CGFloat = 1.01
    static let tilePressScale: CGFloat = 0.97

    static let appear: Animation = .spring(response: 0.6, dampingFraction: 0.7)
    static let appearOffsetY: CGFloat = 14
    static let appearScale: CGFloat = 0.98
    static let tileStagger: Double = 0.07
    /// Battery, history, logs, import, identity.
    static let cardDelays: [Double] = [0.08, 0.14, 0.20, 0.26, 0.32]

    static let page: Animation = .spring(response: 0.5, dampingFraction: 0.75)
    /// RESIZE-MOTION (decision D2): one curve for a width-tier change (tile/cell frames, header capsules, label fades).
    static let tierChange: Animation = .spring(response: 0.45, dampingFraction: 0.85)
    static let pageOffsetX: CGFloat = 28

    /// Rim light spot position smoothing (s).
    static let rimFollow: Double = 0.06
    /// Rim light spot opacity on pointer enter/leave (s).
    static let rimFade: Double = 0.12
    /// Quiet time after the last scroll event before rims re-aim once.
    static let rimScrollSettle: Double = 0.15

    /// Kept under Reduce Motion.
    static let chartTracking: Animation = .easeOut(duration: 0.12)
    static let popIn: Animation = .spring(response: 0.42, dampingFraction: 0.6)
    /// `popIn` for Core Animation (`HistoryHoverView`): the same curve as mass/stiffness/damping. Keep the two equal.
    static let popInSpring = Spring(response: 0.42, dampingRatio: 0.6)

    /// Pulse: 2.8 s cycle = 1.68 s rise (scale 1 -> 2.6, opacity 0.55 -> 0) + 1.12 s hold.
    static let pulseRise: Double = 1.68
    static let pulseHold: Double = 1.12
    static let pulseScale: CGFloat = 2.6
    static let pulseOpacityFrom: Double = 0.55

    /// Ambient motion is frozen in `-visualFixture` runs so captures are deterministic (D24).
    static var isFrozen: Bool { VisualFixture.isRequested }
}
