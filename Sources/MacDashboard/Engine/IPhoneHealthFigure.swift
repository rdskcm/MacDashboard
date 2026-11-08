// Engine/IPhoneHealthFigure.swift
// BATTERY-HEALTH-UNIFY fix wave 1: the iPhone health figure shown with the raw switch off (specs/BATTERY-HEALTH-UNIFY-iphone-findings.md, rule P1).
import Foundation

/// The figure the iPhone tile and battery card show with the raw switch off.
struct IPhoneShownHealth: Equatable, Sendable {
    let percent: Int
    let isEstimate: Bool   // true when this phone has no imported Apple figure
    /// "85 %", or "≈ 97 %" for an estimate (the prefix the Wh capacity already uses).
    var text: String { (isEstimate ? "≈ " : "") + "\(percent) %" }
}

extension IPhoneData {
    /// Rule P1: iPhone Settings' Maximum Capacity is a latched value near the ceiling of NominalChargeCapacity / DesignCapacity.
    /// Apple publishes no formula (support.apple.com/101575 only defines the term). Integer arithmetic, so an exact percentage
    /// is not raised by floating-point error. Capped at 100. Without a usable Nominal: the raw `healthPercent`, or nil.
    static func estimatedHealthPercent(_ b: BatteryDetail) -> Int? {
        if let n = b.nominalChargeMAh, n > 0, let design = b.designCapacityMAh, design > 0 {
            return min(100, (n * 100 + design - 1) / design)
        }
        return b.healthPercent.flatMap { $0 > 0 ? min($0, 100) : nil }
    }

    /// The whole percent shown with the raw switch off: the minimum of the latest imported figure, every live point stored
    /// after it, and the live estimate. A newer import resets the floor (`mergeImported`). `points` in any order; `estimate` may be nil.
    static func shownHealthPercent(points: [BatteryPoint], estimate: Int?) -> Int? {
        let anchor = points.filter { $0.source == "import" && $0.healthPercent != nil }.max { $0.day < $1.day }
        let later = points.filter { $0.source == "live" && $0.day > (anchor?.day ?? "") }.compactMap(\.healthPercent)
        return ([anchor?.healthPercent, estimate].compactMap { $0 } + later).min()
    }

    /// The figure a live read stores in history (the shown figure, D8 as amended 2026-11-08).
    static func historyHealthPercent(_ b: BatteryDetail, points: [BatteryPoint]) -> Int? {
        shownHealthPercent(points: points, estimate: estimatedHealthPercent(b))
    }

    /// True when this phone has no imported Apple figure.
    static func healthIsEstimate(_ points: [BatteryPoint]) -> Bool {
        !points.contains { $0.source == "import" && $0.healthPercent != nil }
    }

    /// What the tile and card show with the raw switch off: the last stored figure (`points` is sorted by day: `upsertLive`,
    /// `mergeImported`); with nothing stored yet, the estimate from `live`.
    static func shownHealth(points: [BatteryPoint], live: BatteryDetail?) -> IPhoneShownHealth? {
        guard let percent = points.last(where: { $0.healthPercent != nil })?.healthPercent
                ?? live.flatMap({ estimatedHealthPercent($0) }) else { return nil }
        return IPhoneShownHealth(percent: percent, isEstimate: healthIsEstimate(points))
    }
}
