// Tests/MacDashboardTests/IPhoneHealthFigureTests.swift
// BATTERY-HEALTH-UNIFY fix wave 1: the iPhone default figure (rule P1, findings C4-C6).
import Testing
@testable import MacDashboard

private func p(_ day: String, _ h: Int?, _ src: String, cycles: Int? = 1, design: Int? = nil) -> BatteryPoint {
    BatteryPoint(day: day, cycles: cycles, healthPercent: h, maxCapacityMAh: nil, designCapacityMAh: design, source: src)
}

private func detail(nominal: Int?, max: Int? = nil, design: Int?, health: Int? = nil) -> BatteryDetail {
    var d = VisualFixture.batteryDetail
    d.maxCapacityMAh = max; d.designCapacityMAh = design; d.healthPercent = health; d.nominalChargeMAh = nominal
    return d
}

struct IPhoneHealthFigureTests {
    @Test func estimate() {
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: 3732, design: 4395)) == 85)
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: 4865, design: 5030)) == 97)
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: 4400, design: 5000)) == 88, "an exact percentage is not raised")
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: 5600, design: 5030)) == 100, "capped")
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: 0, design: 5030, health: 90)) == 90, "a zero Nominal is not a reading")
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: nil, design: 5030, health: 98)) == 98)
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: nil, design: nil, health: nil)) == nil)
        #expect(IPhoneData.estimatedHealthPercent(detail(nominal: 4000, design: 0, health: nil)) == nil)
    }

    @Test func floorFromImportAndLaterLive() {
        // 15 Pro Max on 2026-11-08: imported 85, old live points 86/88/86, estimate 87.
        let pts = [p("2026-10-10", 85, "import"), p("2026-10-12", 86, "live"), p("2026-11-04", 88, "live"), p("2026-11-08", 86, "live")]
        #expect(IPhoneData.shownHealthPercent(points: pts, estimate: 87) == 85)
        // 17 Pro Max: imported 97, live 98, estimate 97.
        let m17 = [p("2026-11-03", 97, "import"), p("2026-11-04", 98, "live"), p("2026-11-08", 98, "live")]
        #expect(IPhoneData.shownHealthPercent(points: m17, estimate: 97) == 97)
    }

    @Test func followsEstimateDownAndNeverRises() {
        let pts = [p("2026-10-10", 85, "import")]
        #expect(IPhoneData.shownHealthPercent(points: pts, estimate: 84) == 84)
        let after = pts + [p("2026-10-20", 84, "live")]
        #expect(IPhoneData.shownHealthPercent(points: after, estimate: 86) == 84, "a Nominal rebound does not raise it")
    }

    @Test func newImportWinsAndCanRaise() {
        let before = [p("2026-11-01", 85, "import"), p("2026-11-04", 84, "live"), p("2026-11-06", 84, "live")]
        let merged = IPhoneData.mergeImported(before, [p("2026-11-05", 86, "import")])
        #expect(merged.first { $0.day == "2026-11-06" }?.healthPercent == 86, "a live point after the newest import is raised to it")
        #expect(merged.first { $0.day == "2026-11-04" }?.healthPercent == 84, "a point before the newest import is kept")
        #expect(IPhoneData.shownHealthPercent(points: merged, estimate: 90) == 86)
        let older = IPhoneData.mergeImported(merged, [p("2026-10-01", 90, "import")])
        #expect(older.first { $0.day == "2026-11-06" }?.healthPercent == 86, "an older archive does not touch later points")
    }

    @Test func noImportIsAnEstimateAndOnlyFalls() {
        let pts = [p("2026-11-01", 98, "live"), p("2026-11-02", 97, "live")]
        #expect(IPhoneData.shownHealthPercent(points: pts, estimate: 98) == 97)
        #expect(IPhoneData.shownHealthPercent(points: [], estimate: 97) == 97)
        #expect(IPhoneData.shownHealthPercent(points: [], estimate: nil) == nil)
        #expect(IPhoneData.healthIsEstimate(pts))
        #expect(!IPhoneData.healthIsEstimate([p("2026-11-01", 85, "import")]))
    }

    @Test func shownHealthAndText() {
        let imported = [p("2026-10-10", 85, "import"), p("2026-11-08", 85, "live")]
        #expect(IPhoneData.shownHealth(points: imported, live: nil) == IPhoneShownHealth(percent: 85, isEstimate: false))
        #expect(IPhoneData.shownHealth(points: imported, live: nil)?.text == "85 %")
        let bare = detail(nominal: 4865, design: 5030)
        #expect(IPhoneData.shownHealth(points: [], live: bare) == IPhoneShownHealth(percent: 97, isEstimate: true))
        #expect(IPhoneData.shownHealth(points: [], live: bare)?.text == "≈ 97 %")
        #expect(IPhoneData.shownHealth(points: [], live: nil) == nil)
    }

    @Test func mergeOnSameDayAndUpsert() {
        let live = [p("2026-11-08", 97, "live", cycles: 9, design: 5030)]
        let merged = IPhoneData.mergeImported(live, [p("2026-11-08", 97, "import", cycles: 8)])
        #expect(merged[0].source == "import" && merged[0].designCapacityMAh == 5030 && merged[0].cycles == 8)
        let up = IPhoneData.upsertLive(merged, p("2026-11-08", 96, "live", cycles: 10, design: 5030))
        #expect(up.count == 1 && up[0].source == "import" && up[0].healthPercent == 96 && up[0].cycles == 10)
    }

    @Test func historyPointIsTheShownFigure() {
        let pts = [p("2026-10-10", 85, "import")]
        #expect(IPhoneData.historyHealthPercent(detail(nominal: 3781, max: 3890, design: 4395, health: 89), points: pts) == 85)
    }
}
