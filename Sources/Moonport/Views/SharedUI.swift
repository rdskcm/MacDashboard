// Views/SharedUI.swift
// Shared primitives: the flow layout, the brew progress line and the pointing-hand hover cursor.

import SwiftUI
import AppKit

/// Minimal flow/wrap layout (macOS 13+ Layout protocol) — legacy CSS used
/// `.pills{display:flex;flex-wrap:wrap}`; SwiftUI has no built-in equivalent.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = Self.measure(subview, maxWidth: maxWidth)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + rowHeight)
    }

    /// Ideal size, re-measured at the row width when the ideal is wider than
    /// the row — so an over-wide subview truncates instead of overflowing.
    /// Subviews that fit are measured exactly as before (`.unspecified`).
    private static func measure(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, ideal.width > maxWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = Self.measure(subview, maxWidth: bounds.width)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Human-readable one-liner for the live `brew upgrade` progress state.
/// Views-layer helper (app-only) — reads `L` at call time so it follows
/// instant language switching.
@MainActor func brewProgressText(_ p: BrewProgress) -> String {
    switch p.phase {
    case .downloading:
        return L.maintenanceBrewProgressDownloading(p.downloadsDone)
    case .upgrading:
        guard let name = p.formula else { return L.maintenanceBrewUpgrading }
        if p.total == 0 {
            return L.maintenanceBrewProgressUpgradingBare(name)
        }
        let k = min(p.completed, p.total)
        let n = p.total
        let pct = min(100, Int((Double(p.completed) / Double(p.total) * 100).rounded()))
        return L.maintenanceBrewProgressUpgrading(name, k, n, pct)
    }
}

// MARK: - Shared pointing-hand hover cursor

/// Pointing-hand cursor for a hover affordance, via `.pointerStyle(.link)`: the system owns the cursor, so there is
/// nothing to balance and it survives a view being rebuilt or removed under a stationary pointer.
///
/// `hovering` is optional: sites that keep their own hover visual pass a binding,
/// sites that only need the cursor pass nothing. While `isEnabled` is false the
/// binding is left alone entirely, so a non-interactive element shows no hover
/// visual either — that gating is load-bearing for the former attention card's plates.
/// `isEnabled` going false mid-hover sets the binding to false.
struct PointingHandOnHover: ViewModifier {
    var isEnabled: Bool = true
    var hovering: Binding<Bool>? = nil

    func body(content: Content) -> some View {
        content
            .pointerStyle(isEnabled ? .link : nil)
            .onHover { isHovering in
                guard isEnabled else { return }
                hovering?.wrappedValue = isHovering
            }
            .onChange(of: isEnabled) { _, nowEnabled in
                guard !nowEnabled else { return }
                hovering?.wrappedValue = false
            }
    }
}

extension View {
    /// Pointing-hand cursor on hover (`.pointerStyle(.link)`), enabled by `isEnabled`.
    func pointingHandOnHover(isEnabled: Bool = true, hovering: Binding<Bool>? = nil) -> some View {
        modifier(PointingHandOnHover(isEnabled: isEnabled, hovering: hovering))
    }
}
