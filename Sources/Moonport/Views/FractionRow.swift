// Views/FractionRow.swift
// Columns by fraction with a fixed gap. iPhone history table: 1.2 : 1 : 1 : 1.4, 12 pt; Mac History table: equal fractions, 16 pt (ARCH-ENGINE-GUARD C9: was IPhoneFractionRow).
import SwiftUI

/// IPHONE-DESIGN: history table columns 1.2 : 1 : 1 : 1.4 with 12 pt gaps.
/// REDESIGN-HISTORY: the History table uses it with equal fractions and 16 pt spacing.
struct FractionRow: Layout {
    var fractions: [CGFloat] = [1.2, 1, 1, 1.4]
    var spacing: CGFloat = 12
    private func widths(_ w: CGFloat) -> [CGFloat] {
        let avail = max(0, w - spacing * CGFloat(fractions.count - 1))
        let total = fractions.reduce(0, +)
        return fractions.map { avail * $0 / total }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        let ws = widths(w)
        let h = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (s, w) in zip(subviews, widths(bounds.width)) {
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}
