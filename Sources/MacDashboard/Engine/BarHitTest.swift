// Engine/BarHitTest.swift
// Pure hit-test math for segmented bars (`BarFillLayout.segments`): which segment index a
// local x-coordinate belongs to, given the SAME rects `barSpanRects` hands the CALayers.
// Lives in Engine/, not next to its only caller in Views/, because Views/ is deliberately
// not symlinked into the Checks target (Checks/README.md) and this is the function the
// memory card's hover behaviour actually depends on.
import Foundation
import CoreGraphics

/// Index of the segment `x` belongs to, or nil when there are no rects.
///
/// `rects` are the ascending, non-overlapping (x, width) pairs `barSpanRects` produces for
/// `.segments`, separated by the layout's gap. A gap x is attributed to the segment on its
/// LEFT, and an x outside the bar to the nearest end segment: returning nil there dropped
/// `hoveredKey` at every boundary crossing, which flashed the whole bar back to undimmed and
/// reset the legend emphasis on each pass (re-review 2 [N4]). Every x now maps to exactly one
/// segment, so a sweep across the bar changes the hovered key monotonically and never clears it.
func barSegmentIndex(at x: CGFloat, rects: [(x: CGFloat, width: CGFloat)]) -> Int? {
    guard !rects.isEmpty else { return nil }
    var previous: Int?
    for (i, r) in rects.enumerated() {
        if x <= r.x + r.width {
            // Inside this rect, or in the gap before it (⇒ the previous rect owns the gap).
            return x >= r.x ? i : (previous ?? i)
        }
        previous = i
    }
    return rects.count - 1  // past the right edge of the last segment
}
