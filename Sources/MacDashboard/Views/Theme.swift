// Views/Theme.swift
// Color helpers, severity/series palette, and deterministic Russian number/byte formatting.

import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    /// 0xRRGGBB literal, e.g. Color(hex: 0x0ca30c).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Appearance-aware color: picks `light` or `dark` based on the effective
    /// NSAppearance at draw time (system semantic colors don't cover our custom
    /// severity/series palette, so we roll our own dynamic provider).
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        }))
    }
}

// MARK: - Severity palette (from legacy mac_dashboard.py CSS, lines 612-700)

extension Severity {
    /// Single hex per severity — same value works in light and dark per legacy CSS
    /// (only the series/free palette actually swaps per-theme).
    var color: Color {
        switch self {
        case .good: return Color(hex: 0x0ca30c)
        case .info: return Color(hex: 0x898781)
        case .warn: return Color(hex: 0xfab219)
        case .serious: return Color(hex: 0xec835a)
        case .crit: return Color(hex: 0xd03b3b)
        }
    }

    var icon: String {
        switch self {
        case .good: return "\u{2713}"      // ✓
        case .info: return "\u{2022}"      // •
        case .warn: return "!"
        case .serious: return "!"
        case .crit: return "\u{2715}"      // ✕
        }
    }
}

/// Chart series palette (legacy --s1…--s5, --free), light/dark aware.
enum SeriesPalette {
    static let s1 = Color(light: Color(hex: 0x2a78d6), dark: Color(hex: 0x3987e5))
    static let s2 = Color(light: Color(hex: 0x1baf7a), dark: Color(hex: 0x199e70))
    static let s3 = Color(light: Color(hex: 0xeda100), dark: Color(hex: 0xc98500))
    static let s4 = Color(light: Color(hex: 0x008300), dark: Color(hex: 0x008300))
    static let s5 = Color(light: Color(hex: 0x4a3aa7), dark: Color(hex: 0x9085e9))
    static let free = Color(light: Color(hex: 0xdcdbd4), dark: Color(hex: 0x383835))
}

// Russian number/byte formatting (fmtNum, fmtBytes) lives in Engine/Formatting.swift
// now — Foundation-only so MacDashboardChecks can symlink and unit-test it.

// MARK: - Design System (v2.0) token namespace
//
// Block V2-FOUND. Shared vocabulary for the v2.0 UI rebuild — the app ships the
// "calm" variant at "regular" density only (glass/density are prototype-only
// exploration knobs, never surfaced as a setting). Values are inlined from the
// design handoff Spec §1; notation there is light/dark unless a value is itself
// an opacity on black/white, in which case light/dark is still first/second.
//
// Light theme is NOT a tint of dark: `accentInk`/`greenInk`/`amberInk` exist
// because the plain fill colors fail 4.5:1 contrast on the light ground — use
// the `-ink` role for TEXT in light appearance, never collapse it into the
// fill role. Fills/dots/borders/strokes keep the base (non-ink) values.
enum DS {
    // Grounds & ink
    static let ground = Color(light: Color(hex: 0xEAEEF3), dark: Color(hex: 0x0B0E13))
    static let ground2 = Color(light: Color(hex: 0xF6F8FA), dark: Color(hex: 0x10151C))
    static let ink = Color(light: Color(hex: 0x161A1F), dark: Color(hex: 0xE7EAF0))
    static let inkSoft = Color(light: Color(hex: 0x3B434D), dark: Color(hex: 0xBAC2CD))
    static let muted = Color(light: Color(hex: 0x5E6774), dark: Color(hex: 0x7E8896))

    // Hairlines & fills (black/white alpha — light uses black, dark uses white)
    static let line = Color(light: Color.black.opacity(0.09), dark: Color.white.opacity(0.09))
    static let lineStrong = Color(light: Color.black.opacity(0.16), dark: Color.white.opacity(0.16))
    static let track = Color(light: Color.black.opacity(0.09), dark: Color.white.opacity(0.10))
    static let row = Color(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.035))

    // Roles with light-mode "-ink" text variants (accent/green/amber only)
    static let accent = Color(light: Color(hex: 0x2F7FE0), dark: Color(hex: 0x5B9BF0))
    static let accentInk = Color(light: Color(hex: 0x1A63C2), dark: Color(hex: 0x5B9BF0))
    static let green = Color(light: Color(hex: 0x0F9A70), dark: Color(hex: 0x2BBD8F))
    static let greenInk = Color(light: Color(hex: 0x0A7454), dark: Color(hex: 0x2BBD8F))
    static let amber = Color(light: Color(hex: 0xC98500), dark: Color(hex: 0xEDA100))
    static let amberInk = Color(light: Color(hex: 0x8C5C00), dark: Color(hex: 0xEDA100))

    // No -ink variant (not used as light-mode text per spec)
    static let hot = Color(light: Color(hex: 0xD70015), dark: Color(hex: 0xFF453A))
    static let violet = Color(light: Color(hex: 0x4A3AA7), dark: Color(hex: 0x9085E9))

    /// Capsule/trigger glass fill — the only "glass" token that ships (cards use
    /// native materials, see `dsCardSurface()` in DesignSystem.swift).
    static let glass3 = Color(light: Color.white.opacity(0.92), dark: Color.white.opacity(0.11))
    /// Card fill (spec token, not currently wired into `dsCardSurface()` — see
    /// that modifier's doc comment for why it still uses `.regularMaterial`).
    static let glass = Color(light: Color.white.opacity(0.62), dark: Color.white.opacity(0.045))
    /// Toolbar/sidebar fill.
    static let glass2 = Color(light: Color.white.opacity(0.80), dark: Color.white.opacity(0.075))
    /// 1 pt inset top highlight on cards/buttons.
    static let sheenLine = Color(light: Color.white.opacity(0.85), dark: Color.white.opacity(0.10))
}
