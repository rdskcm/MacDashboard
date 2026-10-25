import Foundation
import CoreGraphics

/// REDESIGN-ORBS: pure geometry of the window backdrop. Mockup boxes are CSS `top/right/bottom/left` offsets of a
/// d × d square; a centre is `(left + d/2, top + d/2)` in flipped (top-left origin) coordinates.
enum OrbGeometry {
    /// CSS `right: r` → left edge, for a box of side d in a width w.
    static func leftFromRight(_ r: CGFloat, d: CGFloat, width w: CGFloat) -> CGFloat { w - r - d }
    /// CSS `bottom: b` → top edge, for a box of side d in a height h.
    static func topFromBottom(_ b: CGFloat, d: CGFloat, height h: CGFloat) -> CGFloat { h - b - d }
    static func centre(left: CGFloat, top: CGFloat, d: CGFloat) -> CGPoint { CGPoint(x: left + d / 2, y: top + d / 2) }
    /// CSS `radial-gradient(circle, c 0%, transparent 70%)`: the default ray is farthest-corner = d/2·√2.
    static let gradientEndFactor: CGFloat = 0.7 * 2.0.squareRoot() / 2   // 0.49497…
}
