// Views/SettingsSidebarIcons.swift
// Block V2-SETTINGS. The two custom sidebar glyphs for the Settings window,
// replacing SF Symbols per Spec §7.1 (SW:20-28): an 8-tooth gear (Общие) and a
// single-stroke pulse/EKG line (Мониторинг), both drawn on a 14 pt design grid
// and scaled to whatever square frame the caller gives them.

import SwiftUI

/// 8-tooth gear, drawn procedurally from the spec's parametric radii (outer
/// 5.55, root 3.9, hub 1.85) rather than replicating the prototype's raw SVG
/// path (SW:21) byte-for-byte — that path is built from elliptical `A` arcs,
/// which `Path` has no direct equivalent for, and the parametric description
/// is what Spec §7.1's prose gives as the authoritative shape anyway. Each
/// tooth is a trapezoid (narrower tip than root, the standard gear silhouette)
/// whose tip and root edges are circular arcs; with the row's round line-join/
/// cap stroke style the corners read as gently rounded, the same impression as
/// the prototype's arc-smoothed flanks.
struct SettingsGearIconShape: Shape {
    private let teeth = 8
    private let outerRadius: CGFloat = 5.55
    private let rootRadius: CGFloat = 3.9
    private let hubRadius: CGFloat = 1.85
    /// Half-angle (degrees) of a tooth's outer (tip) edge and root (base) edge —
    /// the root is wider than the tip, which is what gives the tooth its taper.
    private let toothHalfAngleOuter: Double = 10
    private let toothHalfAngleRoot: Double = 16

    func path(in rect: CGRect) -> Path {
        // The icon is always laid out square (14×14 design grid); scale off
        // width alone rather than averaging width/height.
        let scale = rect.width / 14
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = outerRadius * scale
        let root = rootRadius * scale
        let hub = hubRadius * scale
        let anglePerTooth = 360.0 / Double(teeth)

        func point(radius: CGFloat, angleDeg: Double) -> CGPoint {
            let rad = angleDeg * .pi / 180
            return CGPoint(x: center.x + radius * CGFloat(cos(rad)), y: center.y + radius * CGFloat(sin(rad)))
        }

        var path = Path()
        for i in 0..<teeth {
            let centerAngle = -90 + Double(i) * anglePerTooth
            let outerStart = centerAngle - toothHalfAngleOuter
            let outerEnd = centerAngle + toothHalfAngleOuter
            let rootStart = centerAngle - toothHalfAngleRoot
            let rootEnd = centerAngle + toothHalfAngleRoot
            let nextRootStart = -90 + Double(i + 1) * anglePerTooth - toothHalfAngleRoot

            if i == 0 {
                path.move(to: point(radius: root, angleDeg: rootStart))
            } else {
                path.addLine(to: point(radius: root, angleDeg: rootStart))
            }
            path.addLine(to: point(radius: outer, angleDeg: outerStart))
            path.addArc(center: center, radius: outer, startAngle: .degrees(outerStart), endAngle: .degrees(outerEnd), clockwise: false)
            path.addLine(to: point(radius: root, angleDeg: rootEnd))
            path.addArc(center: center, radius: root, startAngle: .degrees(rootEnd), endAngle: .degrees(nextRootStart), clockwise: false)
        }
        path.closeSubpath()

        // Hub circle: a separate closed subpath (mirrors the prototype's own
        // separate <circle> element rather than an even-odd cut hole — this
        // shape is only ever stroked, never filled, so a second subpath reads
        // as two concentric strokes exactly like the source SVG's two elements).
        path.addEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))

        return path
    }
}

/// Single-stroke pulse/EKG line (SW:26-28): `M1.3 7.4h2.4l1.4-3.9 2.1 7.5 1.5-3.6h4`
/// on the 14 pt grid, replicated point-for-point — this SVG path is plain line
/// segments (no arcs), so it translates exactly.
struct SettingsPulseIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 14
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: p(1.3, 7.4))
        path.addLine(to: p(3.7, 7.4))
        path.addLine(to: p(5.1, 3.5))
        path.addLine(to: p(7.2, 11.0))
        path.addLine(to: p(8.7, 7.4))
        path.addLine(to: p(12.7, 7.4))
        return path
    }
}

/// Which glyph a sidebar row draws, plus (SW:20/26) its own stroke width — the
/// gear strokes at 1.25 pt, the pulse line at 1.4 pt. `.symbol` is the legacy
/// SF-Symbol path kept only for the `AI_ENABLED`-only AI row (out of scope for
/// this block): it keeps compiling and keeps its `sparkles` glyph without being
/// forced into either custom shape above.
enum SettingsSidebarIconKind {
    case gear
    case pulse
    case symbol(name: String, tint: Color)
}
