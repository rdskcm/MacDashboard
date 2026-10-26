// Tests/MacDashboardTests/WidthTierTests.swift
// RESIZE-MOTION stage A: width tier thresholds, upward hysteresis, one change per crossing.
import CoreGraphics
import Testing
@testable import MacDashboard

struct WidthTierTests {
    @Test func initialBoundaries() {
        let widths: [CGFloat] = [899, 900, 999, 1000, 1199, 1200, 1280]
        let expected: [WidthTier] = [.narrow, .narrow, .narrow, .mid, .mid, .wide, .wide]
        #expect(widths.map { WidthTier.initial(width: $0) } == expected)
    }

    @Test func nextFromNarrow() {
        #expect(WidthTier.next(width: 1000, previous: .narrow) == .narrow)
        #expect(WidthTier.next(width: 1007, previous: .narrow) == .narrow)
        #expect(WidthTier.next(width: 1008, previous: .narrow) == .mid)
        #expect(WidthTier.next(width: 1250, previous: .narrow) == .wide)
    }

    @Test func nextFromMid() {
        #expect(WidthTier.next(width: 999, previous: .mid) == .narrow)
        #expect(WidthTier.next(width: 1000, previous: .mid) == .mid)
        #expect(WidthTier.next(width: 1207, previous: .mid) == .mid)
        #expect(WidthTier.next(width: 1208, previous: .mid) == .wide)
    }

    @Test func nextFromWide() {
        #expect(WidthTier.next(width: 1200, previous: .wide) == .wide)
        #expect(WidthTier.next(width: 1199, previous: .wide) == .mid)
        #expect(WidthTier.next(width: 990, previous: .wide) == .narrow)
    }

    @Test func backAndForthChangesOncePerCrossing() {
        var tier = WidthTier.initial(width: 1150)
        var seen: [WidthTier] = [tier]
        for w: CGFloat in [999, 1003, 1007, 1008, 1001, 999] {
            tier = WidthTier.next(width: w, previous: tier)
            seen.append(tier)
        }
        #expect(seen == [.mid, .narrow, .narrow, .narrow, .mid, .mid, .narrow])
    }

    @Test func titleBlockWidths() {
        #expect(WidthTier.narrow.titleBlockWidth == 280)
        #expect(WidthTier.mid.titleBlockWidth == 400)
        #expect(WidthTier.wide.titleBlockWidth == 460)
    }
}
