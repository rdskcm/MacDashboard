import CoreGraphics

/// RESIZE-MOTION: the window width tier of the handoff (00-shared §3), committed once per crossing.
enum WidthTier: Equatable, Sendable {
    case narrow, mid, wide
    /// Handoff boundaries: narrow below 1000, wide from 1200.
    static let narrowBelow: CGFloat = 1000
    static let wideFrom: CGFloat = 1200
    /// Upward crossings wait this far past the boundary (decision D1); downward crossings are exact.
    static let hysteresis: CGFloat = 8

    /// First tier after launch (no previous): exact boundaries.
    static func initial(width w: CGFloat) -> WidthTier {
        w < narrowBelow ? .narrow : (w < wideFrom ? .mid : .wide)
    }

    /// Next tier for a width, given the tier the window is in.
    static func next(width w: CGFloat, previous: WidthTier) -> WidthTier {
        switch previous {
        case .narrow: return w >= narrowBelow + hysteresis ? initial(width: w) : .narrow
        case .mid:    return w < narrowBelow ? .narrow : (w >= wideFrom + hysteresis ? .wide : .mid)
        case .wide:   return w < wideFrom ? initial(width: w) : .wide
        }
    }

    var isNarrow: Bool { self == .narrow }
    var isMid: Bool { self == .mid }
    /// 01-window-chrome width table: title block 280 / 400 / 460.
    var titleBlockWidth: CGFloat { switch self { case .narrow: 280; case .mid: 400; case .wide: 460 } }
}
