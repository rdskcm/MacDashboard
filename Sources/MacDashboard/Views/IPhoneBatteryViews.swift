// Views/IPhoneBatteryViews.swift
// Battery panel and battery history for the iPhone device page (layout only, no animation).

import Charts
import SwiftUI

struct IPhoneBatteryCard: View {
    let record: IPhoneDeviceRecord?
    let snapshot: IPhoneSnapshot?
    @AppStorage("iphoneCapacityUnit") private var unit = "mAh"

    var body: some View {
        CardChrome(title: L.iphoneBatteryTitle, caption: caption, trailing: { unitSwitch }) {
            if let b = snapshot?.battery {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    row(L.iphoneBatHealth, health(b))
                    row(L.iphoneBatCycles, b.cycleCount.map { "\($0)" })
                    row(L.iphoneBatCharge, b.percent.map { "\($0) %" })
                    row(L.iphoneBatState, state(b))
                    row(L.iphoneBatTemperature, b.temperatureC.map { String(format: "%.1f °C", $0) })
                    row(L.iphoneBatVoltage, b.voltageMV.map { String(format: "%.2f %@", Double($0) / 1000, L.iphoneUnitVolt) })
                    row(L.iphoneBatCapacity, capacity(b), help: unit == "Wh" ? L.iphoneWhSourceHelp : nil)
                }
            } else if snapshot != nil {
                text(L.iphoneBatteryNoData)
            } else if let p = lastPoint {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    row(L.iphoneBatHealth, p.healthPercent.map { "\($0) %" })
                    row(L.iphoneBatCycles, p.cycles.map { "\($0)" })
                }
            } else {
                text(L.iphoneBatteryConnectToRead)
            }
        }
    }

    private var lastPoint: BatteryPoint? {
        record?.battery.filter { $0.healthPercent != nil || $0.cycles != nil }.max { $0.day < $1.day }
    }

    private var caption: String? {
        guard snapshot == nil, let p = lastPoint, let d = IPhoneBatteryFormat.date(p.day) else { return nil }
        return L.iphoneBatteryFromHistory(fmtDisplayDay(d))
    }

    private func state(_ b: BatteryDetail) -> String {
        b.isCharging ? L.iphoneChargeCharging : (b.externalConnected ? L.iphoneChargeExternal : L.iphoneChargeBattery)
    }

    /// mAh | Wh switch (its accessibility name is the control's `groupLabel`; an outer
    /// `.accessibilityLabel` would replace the segment names); sits in the header slot, outside any branch on the unit or the snapshot.
    private var unitSwitch: some View {
        DSSlidingSegmented(options: ["mAh", "Wh"], selection: $unit, groupLabel: L.iphoneCapacityUnitA11y) { u in
            u == "Wh" ? L.iphoneUnitWh : L.iphoneUnitMAh
        }
    }

    /// One decimal, half-up, when both capacities are known; the integer value otherwise.
    private func health(_ b: BatteryDetail) -> String? {
        if let max = b.maxCapacityMAh, let design = b.designCapacityMAh,
           let h = IPhoneData.preciseHealth(maxMAh: max, designMAh: design) {
            return oneDecimal(h) + " %"
        }
        return b.healthPercent.map { "\($0) %" }
    }

    private func oneDecimal(_ v: Double) -> String {
        String(format: "%.1f", (v * 10).rounded() / 10).replacingOccurrences(of: ".", with: L.decimalSeparator)
    }

    private func capacity(_ b: BatteryDetail) -> String? {
        guard let max = b.maxCapacityMAh, let design = b.designCapacityMAh else { return nil }
        if unit == "Wh" {
            return "≈ \(oneDecimal(IPhoneData.wattHours(mAh: max))) / \(oneDecimal(IPhoneData.wattHours(mAh: design))) \(L.iphoneUnitWh)"
        }
        return "\(max) / \(design) \(L.iphoneUnitMAh)"
    }

    private func row(_ label: String, _ value: String?, help: String? = nil) -> some View {
        GridRow {
            Text(label).font(.system(size: 12.5)).foregroundStyle(DS.muted)
            Text(value ?? "—").font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                .help(help ?? "")
        }
    }

    private func text(_ s: String) -> some View {
        Text(s).font(.callout).foregroundStyle(DS.muted)
    }
}

enum IPhoneBatteryFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Parses a stored "yyyy-MM-dd" history day.
    static func date(_ day: String) -> Date? { dayFormatter.date(from: day) }
}

struct IPhoneBatteryHistoryCard: View {
    let points: [BatteryPoint]

    private struct ChartPoint: Identifiable {
        var id: String
        var date: Date
        var health: Int
    }

    private var sorted: [BatteryPoint] { points.sorted { $0.day < $1.day } }

    private var chartPoints: [ChartPoint] {
        sorted.compactMap { p in
            guard let h = p.healthPercent, let d = IPhoneBatteryFormat.date(p.day) else { return nil }
            return ChartPoint(id: p.day, date: d, health: h)
        }
    }

    var body: some View {
        if points.isEmpty {
            CardChrome(title: L.iphoneHistoryTitle) {
                Text(L.iphoneHistoryEmpty).font(.callout).foregroundStyle(DS.muted)
            }
        } else {
            ChartOrTableCard(title: L.iphoneHistoryTitle,
                             caption: L.iphoneHistoryCaption(points.count),
                             chart: { chart },
                             table: { table })
        }
    }

    private var chart: some View {
        let pts = chartPoints
        let low = (pts.map(\.health).min() ?? 100) - 2
        return Chart(pts) { p in
            if pts.count > 1 {
                LineMark(x: .value("day", p.date), y: .value("health", p.health))
            }
            PointMark(x: .value("day", p.date), y: .value("health", p.health))
        }
        .chartYScale(domain: low...max(100, pts.map(\.health).max() ?? 100))
        .frame(height: 160)
    }

    private var table: some View {
        SimpleTable(
            headers: [L.iphoneHistoryColDate, L.iphoneHistoryColHealth, L.iphoneHistoryColCycles, L.iphoneHistoryColSource],
            rows: sorted.reversed().map { p in
                [IPhoneBatteryFormat.date(p.day).map(fmtDisplayDay) ?? p.day,
                 p.healthPercent.map { "\($0) %" } ?? "—",
                 p.cycles.map { "\($0)" } ?? "—",
                 p.source == "live" ? L.iphoneHistorySourceLive : L.iphoneHistorySourceImport]
            },
            numericColumns: [1, 2])
    }
}
