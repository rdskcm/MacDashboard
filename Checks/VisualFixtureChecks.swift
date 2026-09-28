// Checks/VisualFixtureChecks.swift
// VISUAL-COVERAGE: pure-logic checks for VisualFixture (R2/R11) — the fixed
// dataset used by the real app's `-visualFixture` launch argument and by the
// offscreen content render stage. Real file (not a symlink) — main.swift owns
// the single top-level-statements slot, so this exposes a plain function it
// calls (see README.md).
import Foundation

func runVisualFixtureChecks() {
    let originalLang = L10nStore.shared.language
    defer { L10nStore.shared.language = originalLang }
    L10nStore.shared.language = .en

    let d1 = VisualFixture.make()
    let d2 = VisualFixture.make()

    // --- determinism ---
    check(d1.assessment == d2.assessment, "VisualFixture: two make() calls -> equal assessment")
    check(d1.history.mac_history == d2.history.mac_history, "VisualFixture: two make() calls -> equal history.mac_history")
    check(VisualFixture.referenceDate < Date(), "VisualFixture: referenceDate is in the past")

    // --- R2: attention items / tips ---
    let kinds = Set(d1.assessment.items.map(\.kind))
    check(kinds == [.firewallOff, .diskFullSoon, .timeMachine, .wakeHolders],
          "VisualFixture: attention item kinds == {firewallOff, diskFullSoon, timeMachine, wakeHolders} (got \(kinds))")
    check(d1.assessment.items.count == 4, "VisualFixture: 4 attention items (got \(d1.assessment.items.count))")
    check(d1.assessment.capsules.count == 5, "VisualFixture: 5 tip capsules (got \(d1.assessment.capsules.count))")

    // --- R2: history ---
    check(d1.history.mac_history.count == 500, "VisualFixture: 500 history entries (got \(d1.history.mac_history.count))")

    // --- HistorySeries integration (R11) ---
    let series = HistorySeries.series(d1.history.mac_history, metric: .disk)
    let dayFormatter = DateFormatter()
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.timeZone = .current
    dayFormatter.dateFormat = "yyyy-MM-dd"

    func pointsInRange(_ range: HistoryRange) -> Int {
        guard let bounds = HistorySeries.dateRange(d1.history.mac_history, range) else { return series.count }
        return series.filter { point in
            guard let date = dayFormatter.date(from: point.date) else { return false }
            return bounds.contains(date)
        }.count
    }
    check(pointsInRange(.month) == 30, "VisualFixture: .disk points inside Month range == 30 (got \(pointsInRange(.month)))")
    check(pointsInRange(.quarter) == 90, "VisualFixture: .disk points inside Quarter range == 90 (got \(pointsInRange(.quarter)))")
    check(pointsInRange(.year) == 365, "VisualFixture: .disk points inside Year range == 365 (got \(pointsInRange(.year)))")

    let thinnedAll = HistorySeries.thinned(series, maxCount: HistorySeries.maxChartPoints)
    check(thinnedAll.count == 365, "VisualFixture: thinned(all, maxCount: 365).count == 365 (got \(thinnedAll.count))")
}
