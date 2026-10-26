import CoreGraphics

/// RESIZE-MOTION C2: the compact/full form of a header action row (This Mac: Report + Refresh; iPhone: Restart).
/// Committed at the window root together with `WidthTier`, inside the same transaction, from the window width and
/// the row's fit width — never decided by layout, which runs before the state commits and therefore snapped.
/// User rule 2026-10-26 («граница + запас»): always compact below the tier boundary; above it full only when the
/// full row fits with `margin` to spare. The commit lands one layout pass after the width, so the width may move up
/// to `margin` pt before the form follows and the stale full row still fits; upward crossings wait `hysteresis`.
enum HeaderActionsForm {
    /// Width the window may lose in one layout pass before the stale full row stops fitting (≈ 1400 px/s at 60 Hz).
    static let margin: CGFloat = 24
    static let hysteresis: CGFloat = WidthTier.hysteresis

    /// `fitWidth`: the smallest window width at which the full row fits exactly (`MainDashboardView.fitWindowWidth`).
    /// `previousCompact`: nil for the seed (exact threshold, no hysteresis).
    static func compact(width w: CGFloat, tier: WidthTier, fitWidth: CGFloat, previousCompact: Bool?) -> Bool {
        if tier.isNarrow { return true }
        let threshold = fitWidth + margin + (previousCompact == true ? hysteresis : 0)
        return w < threshold
    }
}
