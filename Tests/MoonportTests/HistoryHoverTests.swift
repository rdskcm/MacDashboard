import Foundation
import Testing
@testable import Moonport

// HISTORY-HOVER-COST: pure helpers of the Core Animation hover overlay.
struct HistoryHoverTests {
    @Test func nearestIndexEmpty() {
        #expect(HistoryHoverMath.nearestIndex(xs: [], x: 5) == nil)
    }

    @Test func nearestIndexPicksNearestNeighbour() {
        let xs: [CGFloat] = [10, 20, 30]
        #expect(HistoryHoverMath.nearestIndex(xs: xs, x: 14) == 0)
        #expect(HistoryHoverMath.nearestIndex(xs: xs, x: 16) == 1)
        #expect(HistoryHoverMath.nearestIndex(xs: xs, x: 25) == 1)   // tie goes to the lower index
        #expect(HistoryHoverMath.nearestIndex(xs: xs, x: 100) == 2)
        #expect(HistoryHoverMath.nearestIndex(xs: xs, x: -5) == 0)
    }

    @Test func nearestIndexSingleElement() {
        for x: CGFloat in [-50, 7, 900] {
            #expect(HistoryHoverMath.nearestIndex(xs: [7], x: x) == 0)
        }
    }

    @Test func popInStartIsScaledOffsetToAnchor() {
        let s = HistoryHoverMath.popInStart(centre: CGPoint(x: 684, y: 131), anchor: CGPoint(x: 84, y: 31))
        #expect(abs(s.x - -60) < 1e-9)
        #expect(abs(s.y - -10) < 1e-9)
        #expect(HistoryHoverMath.popInStart(centre: CGPoint(x: 84, y: 31), anchor: CGPoint(x: 84, y: 31)) == .zero)
    }

    // CHART-HOVER-STICKY: visibleRect can be larger than bounds (scroll viewport); only the view's own part counts.
    @Test func isOverChartUsesBoundsAndVisibleRect() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 150)
        let wide = CGRect(x: 0, y: -32, width: 600, height: 432)
        #expect(!HistoryHoverMath.isOverChart(CGPoint(x: 100, y: 239), bounds: bounds, visibleRect: wide))
        #expect(HistoryHoverMath.isOverChart(CGPoint(x: 100, y: 75), bounds: bounds, visibleRect: wide))
        let scrolled = CGRect(x: 0, y: 100, width: 300, height: 50)
        #expect(!HistoryHoverMath.isOverChart(CGPoint(x: 100, y: 20), bounds: bounds, visibleRect: scrolled))
        #expect(HistoryHoverMath.isOverChart(CGPoint(x: 100, y: 120), bounds: bounds, visibleRect: scrolled))
    }
}
