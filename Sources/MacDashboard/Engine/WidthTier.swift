import CoreGraphics
import Observation

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

/// RESIZE-WIDTH-STATE: the exact window-width breakpoints the section pages read. No hysteresis: the pages never had
/// it (`WidthTier` has it, so `tier.isNarrow` is NOT the same test). Committed at the window root only when a value
/// flips, so a live resize between breakpoints re-evaluates no page.
struct PageBreakpoints: Equatable, Sendable {
    /// Section pages' compact form (two-column tiles): window < 1000.
    let narrow: Bool
    /// Storage SMART card wide form (240 pt drive list, three kv columns): window ≥ `StoragePageModel.wideBreakpoint`.
    let storageWide: Bool

    init(width w: CGFloat) {
        narrow = w < WidthTier.narrowBelow
        storageWide = w >= StoragePageModel.wideBreakpoint
    }
}

/// RESIZE-WIDTH-STATE: the raw window width for the one view that needs it continuously (the Home attention card's
/// hero column). Held by the window root in `@State`: the reference never changes, so the root body does not depend
/// on the width; only a body that reads `value` is re-evaluated when it changes.
@MainActor
@Observable
final class LiveWindowWidth {
    var value: CGFloat
    init(_ value: CGFloat) { self.value = value }
}
