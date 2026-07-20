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
