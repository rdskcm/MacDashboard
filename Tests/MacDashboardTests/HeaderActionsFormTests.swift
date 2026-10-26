// Tests/MacDashboardTests/HeaderActionsFormTests.swift
// RESIZE-MOTION stage C2: header form rule (tier + fit width + margin + hysteresis) and the toolbar fit formula.
import CoreGraphics
import Testing
@testable import MacDashboard

struct HeaderActionsFormTests {
    @Test func narrowTierIsAlwaysCompact() {
        #expect(HeaderActionsForm.compact(width: 999, tier: .narrow, fitWidth: 880, previousCompact: false))
        #expect(HeaderActionsForm.compact(width: 999, tier: .narrow, fitWidth: 880, previousCompact: nil))
    }

    @Test func marginAboveTheFitWidth() {
        // fit 994 (EN, Needs attention): compact below 1018, full from 1018 when previously full or at the seed.
        #expect(HeaderActionsForm.compact(width: 1017, tier: .mid, fitWidth: 994, previousCompact: false))
        #expect(!HeaderActionsForm.compact(width: 1018, tier: .mid, fitWidth: 994, previousCompact: false))
        #expect(!HeaderActionsForm.compact(width: 1018, tier: .mid, fitWidth: 994, previousCompact: nil))
    }

    @Test func hysteresisOnlyWhenLeavingCompact() {
        #expect(HeaderActionsForm.compact(width: 1025, tier: .mid, fitWidth: 994, previousCompact: true))
        #expect(!HeaderActionsForm.compact(width: 1026, tier: .mid, fitWidth: 994, previousCompact: true))
    }

    @Test func fitBelowTheTierIsTierDriven() {
        // fit 905 (iPhone EN): above the tier the full row always fits; the tier alone decides.
        #expect(!HeaderActionsForm.compact(width: 1000, tier: .mid, fitWidth: 905, previousCompact: true))
        #expect(HeaderActionsForm.compact(width: 999, tier: .narrow, fitWidth: 905, previousCompact: false))
    }

    @Test func russianBandChangesOncePerCrossing() {
        // fit 1083 (RU, Требует внимания): compact below 1107 (first at 1106), back up → full only from 1115.
        var compact = HeaderActionsForm.compact(width: 1150, tier: .mid, fitWidth: 1083, previousCompact: nil)
        var seen = [compact]
        for w: CGFloat in [1107, 1106, 1110, 1114, 1115, 1106] {
            compact = HeaderActionsForm.compact(width: w, tier: .mid, fitWidth: 1083, previousCompact: compact)
            seen.append(compact)
        }
        #expect(seen == [false, false, true, true, true, false, true])
    }

    @Test func toolbarFitFormulaIsTheLayoutInverse() {
        for (side, centre, spacing): (CGFloat, CGFloat, CGFloat) in [(296, 179, 12), (433, 209, 12), (0, 100, 12)] {
            let container = CentredToolbarLayout.containerWidth(side: side, centreWidth: centre, spacing: spacing)
            #expect(CentredToolbarLayout.sideWidth(container: container, centreWidth: centre, spacing: spacing) == side)
        }
        // Findings C3: full row fits iff W >= 2*row + centre + 60 with the 18 pt trailing pad and 12 pt spacing.
        #expect(CentredToolbarLayout.containerWidth(side: 278 + 101 + 18, centreWidth: 179, spacing: 12) == CGFloat(2 * 379 + 179 + 60))
    }
}
