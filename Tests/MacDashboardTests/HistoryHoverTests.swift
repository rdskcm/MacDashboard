import Foundation
import Testing
@testable import MacDashboard

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
}
