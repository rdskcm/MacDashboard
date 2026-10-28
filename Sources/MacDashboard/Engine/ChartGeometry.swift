// Engine/ChartGeometry.swift
// ARCH-ENGINE-GUARD (C9): chart helpers shared by the Mac History page and the iPhone battery charts. CoreGraphics
// only; covered by Tests/MacDashboardTests/IPhoneTests.swift (tooltip clamping).
import CoreGraphics

enum ChartGeometry {
    /// Top-left of the hover tooltip in plot coordinates: centred on the point, clamped to the plot
    /// by pixel width; 12 pt above the point, or below it when the point is in the top 38 %.
    static func tooltipOrigin(point: CGPoint, plot: CGSize,
                              size: CGSize = CGSize(width: 168, height: 74),
                              gap: CGFloat = 12, topZone: CGFloat = 0.38) -> CGPoint {
        let x = min(max(0, point.x - size.width / 2), max(0, plot.width - size.width))
        let below = plot.height > 0 && point.y / plot.height <= topZone
        return CGPoint(x: x, y: below ? point.y + gap : point.y - gap - size.height)
    }
}
