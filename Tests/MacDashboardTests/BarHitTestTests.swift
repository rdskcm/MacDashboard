// Tests/MacDashboardTests/BarHitTestTests.swift
// Port of Checks/main.swift lines 2066-2082 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct BarHitTestTests {
        @Test func barSegmentHitTest() async {
            // MARK: - barSegmentIndex (re-review 2 [N4]/[N6]: memory-bar hover hit test)
            do {
                // Three 10 pt segments with a 2 pt gap: [0,10] [12,22] [24,34].
                let rects: [(x: CGFloat, width: CGFloat)] = [(0, 10), (12, 10), (24, 10)]
                #expect(barSegmentIndex(at: 0, rects: rects) == 0, "barSegmentIndex: left edge ⇒ first segment")
                #expect(barSegmentIndex(at: 5, rects: rects) == 0, "barSegmentIndex: inside first ⇒ 0")
                #expect(barSegmentIndex(at: 10, rects: rects) == 0, "barSegmentIndex: first segment's right edge ⇒ 0")
                #expect(barSegmentIndex(at: 11, rects: rects) == 0, "barSegmentIndex: inside the gap ⇒ the segment on its LEFT (was nil)")
                #expect(barSegmentIndex(at: 12, rects: rects) == 1, "barSegmentIndex: second segment's left edge ⇒ 1")
                #expect(barSegmentIndex(at: 23, rects: rects) == 1, "barSegmentIndex: second gap ⇒ 1")
                #expect(barSegmentIndex(at: 34, rects: rects) == 2, "barSegmentIndex: right edge of the last segment ⇒ 2")
                #expect(barSegmentIndex(at: 40, rects: rects) == 2, "barSegmentIndex: past the bar ⇒ last segment, never nil")
                #expect(barSegmentIndex(at: -3, rects: rects) == 0, "barSegmentIndex: left of the bar ⇒ first segment, never nil")
                #expect((0...34).allSatisfy { barSegmentIndex(at: CGFloat($0), rects: rects) != nil },
                      "barSegmentIndex: every integer x across the bar resolves to a segment (no boundary drop-outs)")
                #expect(barSegmentIndex(at: 5, rects: []) == nil, "barSegmentIndex: no rects ⇒ nil")
            }
        }
    }
}
