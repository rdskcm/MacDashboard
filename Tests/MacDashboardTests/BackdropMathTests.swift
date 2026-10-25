// Tests/MacDashboardTests/BackdropMathTests.swift
// REDESIGN-ORBS Stage 1: orb geometry of the window backdrop (pure, no process-wide state).
import CoreGraphics
import Testing
@testable import MacDashboard

struct BackdropMathTests {
    private func near(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat) -> Bool {
        abs(p.x - x) <= 0.01 && abs(p.y - y) <= 0.01
    }

    @Test func gradientEndFactorIsFarthestCornerSeventyPercent() {
        #expect(OrbGeometry.gradientEndFactor > 0.4949 && OrbGeometry.gradientEndFactor < 0.4951)
    }

    @Test func windowCentresAtBenchSize() {
        let size = CGSize(width: 1000, height: 733)
        let c = DS3OrbSpec.window.map { $0.centre(size) }
        #expect(near(c[0], 830, 90))
        #expect(near(c[1], 40, 620))
        #expect(near(c[2], 590, 713))
    }

    @Test func windowCentresAtMinimumSize() {
        let size = CGSize(width: 900, height: 620)
        let c = DS3OrbSpec.window.map { $0.centre(size) }
        #expect(near(c[0], 730, 90))
        #expect(near(c[1], 40, 620))
        #expect(near(c[2], 510, 600))
    }

    @Test func settingsCentresUnchanged() {
        let size = CGSize(width: 680, height: 420)
        let c = DS3OrbSpec.settings.map { $0.centre(size) }
        #expect(near(c[0], 80, 40))
        #expect(near(c[1], 610, 430))
        #expect(near(c[2], 430, -70))
    }

    @Test func diameters() {
        #expect(DS3OrbSpec.window.map(\.d) == [780, 580, 420])
        #expect(DS3OrbSpec.settings.map(\.d) == [520, 460, 380])
    }
}
