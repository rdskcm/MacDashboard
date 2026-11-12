// Views/Theme.swift
// Color helpers and the DS token namespace.

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

// Number/byte formatting (fmtNum, fmtBytes) lives in Engine/Formatting.swift
// now — Foundation-only so Tests/MoonportTests can unit-test it.

// MARK: - Design System (v2.0) token namespace
//
// Only the tokens the hover tip (`HoverTip.swift`) still reads. The app's current
// palette is `DS3` (`DS3Theme.swift`). Values are light/dark.
enum DS {
    static let ground2 = Color(light: Color(hex: 0xF6F8FA), dark: Color(hex: 0x10151C))
    static let inkSoft = Color(light: Color(hex: 0x3B434D), dark: Color(hex: 0xBAC2CD))
    static let lineStrong = Color(light: Color.black.opacity(0.16), dark: Color.white.opacity(0.16))
}
