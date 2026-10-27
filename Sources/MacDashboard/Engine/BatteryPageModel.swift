// Engine/BatteryPageModel.swift
// REDESIGN-BATTERY: pure state, texts, tones, thresholds and the capacity-history pick of the Battery page (handoff 06-battery).
import Foundation

enum BatteryHealthClass: Equatable, Sendable { case normal, worn, service, unknown }

/// Battery thresholds — the ONLY health → class rule on the Battery page (D6: Assessment keeps its own attention rules).
enum BatteryHealth {
    /// Apple's service threshold: a Mac notebook battery is designed to retain up to 80 % of its original capacity
    /// at the rated cycle count (Apple Support 102888). Below it the page shows the amber note.
    static let wornBelowPercent = 80

    /// `system_profiler` Condition other than "Normal" (trimmed, case-sensitive) and non-empty.
    static func isServiceCondition(_ condition: String?) -> Bool {
        guard let c = condition?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return false }
        return c != "Normal"
    }

    static func classify(healthPercent: Int?, condition: String?) -> BatteryHealthClass {
        if isServiceCondition(condition) { return .service }
        guard let hp = healthPercent else { return .unknown }
        return hp < wornBelowPercent ? .worn : .normal
    }
}

enum BatteryPagePhase: Equatable { case reading, live, failed(BlockFailure, lastGoodAt: Date?) }
enum BatteryTagKind: Equatable { case healthy, worn, service, reading, failed }
/// Tones the view maps to DS3 colours (green / amber / hot; neutral = muted panel / dimmed value).
enum BatteryTone: Equatable { case green, amber, hot, neutral }
enum BatteryNoteButton: Equatable { case tryAgain, batterySettings }

struct BatteryHeroModel: Equatable { var label: String; var value: String; var fraction: Double; var note: String; var tone: BatteryTone; var dimmed: Bool }
/// `valueTone` nil → ink; `.neutral` → muted (the «—» tiles); `.green/.amber/.hot` → the -ink variant. `dot` nil → no dot.
struct BatteryTileModel: Equatable { var label: String; var value: String; var note: String?; var valueTone: BatteryTone?; var dot: BatteryTone? }
struct BatteryNoteModel: Equatable { var tone: BatteryTone; var text: String; var button: BatteryNoteButton }
struct BatteryHistoryRow: Equatable { var id: String /* "yyyy-MM" */; var label: String /* "Oct 2026" */; var value: String /* "76%" */ }

struct BatteryPageModel: Equatable {
    struct Input {
        var detail: BatteryDetail?        // model.batteryDetail — the last good read, kept through failures (D5)
        var condition: String?            // model.report.battery?.condition ?? model.battery?.condition
        var block: BlockPhase             // model.batteryBlock.phase
        var history: [MacHistoryEntry]    // model.history.mac_history (chronological, as stored)
    }
    static let refreshSeconds = 3

    var phase: BatteryPagePhase
    var health: BatteryHealthClass
    var symbol: String
    var sub: String
    var subIsFailure: Bool
    var tag: BatteryTagKind
    var tagText: String
    var nowCaption: String?
    var showsWait: Bool
    var failureNote: String?
    var nowHero: BatteryHeroModel?
    var nowTiles: [BatteryTileModel]
    var nowColumns: Int
    var showsDetailCards: Bool
    var healthHero: BatteryHeroModel
    var healthTiles: [BatteryTileModel]
    var healthNote: BatteryNoteModel?
    var showsCharging: Bool
    var chargingTiles: [BatteryTileModel]
    var lifetimeTiles: [BatteryTileModel]
    var passportTiles: [BatteryTileModel]
    var historyRows: [BatteryHistoryRow]
    var historyCaption: String

    static let dash = "—"

    static func make(_ i: Input) -> BatteryPageModel {
        let d = i.detail
        let hp = d?.healthPercent
        let health = BatteryHealth.classify(healthPercent: hp, condition: i.condition)

        let phase: BatteryPagePhase
        var okAt: Date?
        switch i.block {
        case .failed(let f, let g): phase = .failed(f, lastGoodAt: g)
        case .loading: phase = .reading
        case .ok(let at):
            if d != nil { phase = .live; okAt = at } else { phase = .reading }
        }
        var isFailed = false
        var failure: BlockFailure?
        var lastGood: Date?
        if case .failed(let f, let g) = phase { isFailed = true; failure = f; lastGood = g }
        let isLive = phase == .live

        // Header
        let symbol = Self.symbol(percent: d?.percent, charging: d?.isCharging ?? false)
        var sub = L.batSub(d?.cycleCount)
        if isFailed, let g = lastGood {
            sub = L.batSub(nil) + " · " + L.commonLastData(CPUPageModel.hhmmss(g))
        }
        let tag: BatteryTagKind
        let tagText: String
        switch phase {
        case .reading: (tag, tagText) = (.reading, L.commonCollectingData)
        case .failed: (tag, tagText) = (.failed, L.batTagReadFailed)
        case .live:
            switch health {
            case .service: (tag, tagText) = (.service, L.commonServiceRecommended)
            case .worn: (tag, tagText) = (.worn, L.batTagCapacity(L.homePercent("\(hp ?? 0)")))
            case .normal: (tag, tagText) = (.healthy, L.homeTagHealthy)
            case .unknown: (tag, tagText) = (.reading, L.batTagUnknown)
            }
        }

        // Now card
        var nowCaption: String?
        if let at = okAt { nowCaption = L.batNowCaption(CPUPageModel.hhmmss(at)) }
        else if let g = lastGood { nowCaption = L.commonLastData(CPUPageModel.hhmmss(g)) }
        var failureNote: String?
        if let f = failure {
            var t = f == .timedOut ? L.batFailTimedOut : L.batFailNoReading
            if lastGood != nil && d != nil { t += " " + L.batFailShowingSaved }
            t += " " + L.readRetriesAutomatically
            failureNote = t
        }

        var nowHero: BatteryHeroModel?
        var nowTiles: [BatteryTileModel]
        let labels = (L.batteryLabelPower, L.batteryLabelCurrent, L.batteryLabelVoltage, L.batteryLabelTemperature)
        if isLive, let d {
            nowHero = heroNow(d)
            nowTiles = [
                BatteryTileModel(label: labels.0, value: d.powerW.map { L.batteryWatts(signed(fmtNum(abs($0), decimals: 1), $0)) } ?? dash,
                                 note: nil, valueTone: d.powerW.map(directionTone) ?? .neutral, dot: nil),
                BatteryTileModel(label: labels.1, value: d.amperageMA.map { L.batMA(signed(fmtGrouped(abs($0)), Double($0))) } ?? dash,
                                 note: nil, valueTone: d.amperageMA.map { directionTone(Double($0)) } ?? .neutral, dot: nil),
                BatteryTileModel(label: labels.2, value: d.voltageMV.map { L.batteryVolts(fmtNum(Double($0) / 1000, decimals: 2)) } ?? dash,
                                 note: nil, valueTone: d.voltageMV == nil ? .neutral : nil, dot: nil),
                BatteryTileModel(label: labels.3, value: d.temperatureC.map { L.batteryCelsius(fmtNum($0, decimals: 1)) } ?? dash,
                                 note: nil, valueTone: d.temperatureC == nil ? .neutral : nil, dot: nil),
            ]
        } else {
            nowTiles = [labels.0, labels.1, labels.2, labels.3].map {
                BatteryTileModel(label: $0, value: dash, note: nil, valueTone: .neutral, dot: nil)
            }
        }

        // Capacity and health
        let healthTone: BatteryTone
        switch health {
        case .normal: healthTone = .green
        case .worn: healthTone = .amber
        case .service: healthTone = .hot
        case .unknown: healthTone = .neutral
        }
        let healthHero = BatteryHeroModel(
            label: L.batteryCapHealth, value: hp.map { L.homePercent("\($0)") } ?? dash,
            fraction: hp.map { min(max(Double($0) / 100, 0), 1) } ?? 0, note: L.batHealthNote,
            tone: healthTone, dimmed: healthTone == .neutral)

        func capTile(_ label: String, _ v: Int?) -> BatteryTileModel {
            BatteryTileModel(label: label, value: v.map { L.batMAh(fmtGrouped($0)) } ?? dash, note: nil,
                             valueTone: v == nil ? .neutral : nil, dot: nil)
        }
        let cycles = d?.cycleCount
        let overRated = (cycles != nil && d?.designCycleCount != nil) ? cycles! > d!.designCycleCount! : false
        var cyclesTile = BatteryTileModel(label: L.batteryCapCycles, value: dash, note: nil, valueTone: .neutral, dot: nil)
        if let c = cycles {
            let v = d?.designCycleCount.map { L.batteryCyclesOf(fmtGrouped(c), fmtGrouped($0)) } ?? fmtGrouped(c)
            cyclesTile = BatteryTileModel(label: L.batteryCapCycles, value: v, note: nil, valueTone: overRated ? .hot : nil, dot: nil)
        }
        let condText = conditionText(i.condition)
        let condTrim = i.condition?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isService = BatteryHealth.isServiceCondition(i.condition)
        let condTile = BatteryTileModel(
            label: L.batteryCapCondition, value: condText ?? dash, note: nil,
            valueTone: condText == nil ? .neutral : (isService ? .hot : nil),
            dot: condText == nil ? nil : (condTrim == "Normal" ? .green : (isService ? .hot : nil)))
        let healthTiles = [
            capTile(L.batteryCapMax, d?.maxCapacityMAh),
            capTile(L.batteryCapDesign, d?.designCapacityMAh),
            cyclesTile,
            capTile(L.batteryCapCurrentCharge, d?.currentCapacityMAh),
            condTile,
        ]
        var healthNote: BatteryNoteModel?
        switch health {
        case .worn:
            healthNote = BatteryNoteModel(tone: .amber, text: L.batWornNote, button: .batterySettings)
        case .service:
            let parts = [hp.map { L.batServiceCapacity(L.homePercent("\($0)")) }, overRated ? L.batServiceCycles : nil]
                .compactMap { $0 }
            healthNote = BatteryNoteModel(tone: .hot, text: L.batServiceNote(parts), button: .batterySettings)
        case .normal, .unknown: break
        }

        let (rows, caption) = capacityHistory(i.history)
        return BatteryPageModel(
            phase: phase, health: health, symbol: symbol, sub: sub, subIsFailure: isFailed && lastGood != nil, tag: tag, tagText: tagText,
            nowCaption: nowCaption, showsWait: phase == .reading, failureNote: failureNote, nowHero: nowHero,
            nowTiles: nowTiles, nowColumns: isFailed ? 4 : 2, showsDetailCards: isLive || (isFailed && d != nil),
            healthHero: healthHero, healthTiles: healthTiles, healthNote: healthNote,
            showsCharging: d?.externalConnected ?? false, chargingTiles: d.map(chargingTiles) ?? [],
            lifetimeTiles: d.map(lifetimeTiles) ?? [], passportTiles: d.map(passportTiles) ?? [],
            historyRows: rows, historyCaption: caption)
    }

    // MARK: Now hero

    private static func heroNow(_ d: BatteryDetail) -> BatteryHeroModel {
        var noteParts: [String] = []
        if !d.cellVoltagesMV.isEmpty {
            noteParts.append(L.batteryCellsLine(d.cellVoltagesMV.map { fmtNum(Double($0) / 1000, decimals: 3) }.joined(separator: " · ")))
        }
        if let lpm = d.lowPowerMode {
            noteParts.append(L.batteryDetailLowPower + " " + (lpm ? L.energyValueOn : L.energyValueOff))
        }
        let tone: BatteryTone = d.percent == nil ? .neutral : (d.externalConnected ? .green : .amber)
        return BatteryHeroModel(
            label: statusLine(d), value: d.percent.map { L.homePercent("\($0)") } ?? dash,
            fraction: d.percent.map { min(max(Double($0) / 100, 0), 1) } ?? 0,
            note: noteParts.isEmpty ? dash : noteParts.joined(separator: " · "),
            tone: tone, dimmed: d.percent == nil)
    }

    private static func directionTone(_ v: Double) -> BatteryTone? { v > 0 ? .green : (v < 0 ? .amber : nil) }

    /// Explicit sign: "+" for positive, U+2212 for negative, none for zero.
    static func signed(_ s: String, _ v: Double) -> String {
        v > 0 ? "+" + s : (v < 0 ? "\u{2212}" + s : s)
    }

    // MARK: Charging / lifetime / passport cards

    private static func chargingTiles(_ d: BatteryDetail) -> [BatteryTileModel] {
        guard d.externalConnected else { return [] }
        func tile(_ label: String, _ value: String, note: String? = nil, tone: BatteryTone? = nil, dot: BatteryTone? = nil) -> BatteryTileModel {
            BatteryTileModel(label: label, value: value, note: note, valueTone: tone, dot: dot)
        }
        var out: [BatteryTileModel] = []
        if let a = d.adapter {
            let base = a.name ?? a.adapterDescription ?? L.batteryAdapterUsbC(a.watts ?? 0)
            let note = [a.manufacturer, a.watts.map { L.batteryWatts(fmtGrouped($0)) }].compactMap { $0 }.joined(separator: " · ")
            out.append(tile(L.batteryChargeAdapter, base + (a.isWireless ? L.batteryAdapterWireless : ""), note: note.isEmpty ? nil : note))
            if let sel = a.selectedProfileIndex, let p = a.pdProfiles.first(where: { $0.index == sel }) {
                let v = Double(p.maxVoltageMV) / 1000
                let vStr = fmtNum(v, decimals: v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)
                out.append(tile(L.batteryChargeProtocol, L.batteryUsbPdLine(vStr, fmtNum(Double(p.maxCurrentMA) / 1000, decimals: 2))))
            }
            if !a.pdProfiles.isEmpty {
                let line = a.pdProfiles.map { p -> String in
                    let s = L.batteryVolts(fmtNum(Double(p.maxVoltageMV) / 1000, decimals: 0))
                    return p.index == a.selectedProfileIndex ? "[\(s)]" : s
                }.joined(separator: " · ")
                out.append(tile(L.batteryChargeProfiles, line))
            }
        }
        if let mA = d.charger?.chargingCurrentMA, mA > 0 {
            out.append(tile(L.batteryChargeCurrentLabel, L.batMA(fmtGrouped(mA))))
        }
        if d.isCharging {
            out.append(tile(L.batteryChargeStatus, L.batteryStatusCharging, tone: .green, dot: .green))
        } else if d.fullyCharged {
            out.append(tile(L.batteryChargeStatus, L.batteryStatusFullyCharged))
        } else {
            var s = L.batteryStatusNotCharging
            if let r = d.charger?.notChargingReason, r != 0 { s += L.batteryNotChargingCode(r) }
            out.append(tile(L.batteryChargeStatus, s))
        }
        return out
    }

    private static func lifetimeTiles(_ d: BatteryDetail) -> [BatteryTileModel] {
        guard let l = d.lifetime else { return [] }
        func tile(_ label: String, _ value: String, note: String? = nil) -> BatteryTileModel {
            BatteryTileModel(label: label, value: value, note: note, valueTone: nil, dot: nil)
        }
        var out: [BatteryTileModel] = []
        if let mn = l.minTemperatureC, let av = l.avgTemperatureC, let mx = l.maxTemperatureC {
            out.append(tile(L.batteryLifetimeTempLabel, L.batteryLifetimeTempValue(mn, fmtNum(av, decimals: 1), mx)))
        }
        if let v = l.maxChargeCurrentMA { out.append(tile(L.batteryLifetimeMaxCharge, L.batMA(fmtGrouped(v)))) }
        if let v = l.maxDischargeCurrentMA { out.append(tile(L.batteryLifetimeMaxDischarge, L.batMA(fmtGrouped(v)))) }
        if let mn = l.minPackVoltageMV, let mx = l.maxPackVoltageMV {
            out.append(tile(L.batteryLifetimeVoltage,
                            L.batteryLifetimeVoltageRange(fmtNum(Double(mn) / 1000, decimals: 1), fmtNum(Double(mx) / 1000, decimals: 1))))
        }
        if let h = l.totalOperatingTimeH {
            out.append(tile(L.batteryLifetimeOperatingTime, L.batHours(fmtGrouped(h)), note: L.batEstimate))
        }
        return out
    }

    static let manufacturerNames: [String: String] = [
        "ATL": "Amperex (ATL)", "SMP": "Simplo (SMP)", "LGC": "LG Chem (LGC)", "SDI": "Samsung SDI",
    ]

    private static func passportTiles(_ d: BatteryDetail) -> [BatteryTileModel] {
        func tile(_ label: String, _ value: String, note: String? = nil) -> BatteryTileModel {
            BatteryTileModel(label: label, value: value, note: note, valueTone: nil, dot: nil)
        }
        var out: [BatteryTileModel] = []
        if let code = d.manufacturerCode { out.append(tile(L.batteryDetailManufacturer, manufacturerNames[code] ?? code)) }
        if let s = d.serial { out.append(tile(L.batteryDetailSerial, s)) }
        if let y = d.mfgYear, let w = d.mfgWeek, let code = d.mfgCode {
            if let m = mfgMonth(year: y, week: w) {
                out.append(tile(L.batteryDetailMfgDate, m, note: L.batCode(code)))
            } else {
                out.append(tile(L.batteryDetailMfgDate, code))
            }
        }
        return out
    }

    /// ISO-8601 week → Monday → "Mar 2024" / "март 2024"; nil when the date cannot be built.
    static func mfgMonth(year: Int, week: Int) -> String? {
        var comps = DateComponents()
        comps.weekOfYear = week
        comps.yearForWeekOfYear = year
        comps.weekday = 2 // Monday
        let cal = Calendar(identifier: .iso8601)
        guard let date = cal.date(from: comps) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: L10nStore.shared.language == .en ? "en_US" : "ru_RU")
        df.dateFormat = "LLL yyyy"
        return df.string(from: date)
    }

    // MARK: Helpers

    static func fmtMinutes(_ m: Int) -> String {
        m < 60 ? L.batteryMinutes(m % 60) : L.batteryHoursMinutes(m / 60, m % 60)
    }

    static func statusLine(_ d: BatteryDetail) -> String {
        if !d.externalConnected {
            var s = L.batteryStatusOnBattery
            if let m = d.timeToEmptyMin { s += L.batteryStatusRemaining(fmtMinutes(m)) }
            return s
        }
        if d.isCharging {
            var s = L.batteryStatusCharging
            if let m = d.timeToFullMin { s += L.batteryStatusUntilFull(fmtMinutes(m)) }
            return s
        }
        if d.fullyCharged { return L.batteryStatusACFull }
        return L.batteryStatusACNotCharging
    }

    /// `system_profiler` Condition in the app's language; unknown non-empty strings are shown as macOS reports them.
    static func conditionText(_ raw: String?) -> String? {
        guard let c = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        switch c {
        case "Normal": return L.batConditionNormal
        case "Service Recommended": return L.batConditionService
        case "Replace Soon": return L.batConditionReplaceSoon
        case "Replace Now": return L.batConditionReplaceNow
        case "Check Battery": return L.batConditionCheck
        default: return c
        }
    }

    static func symbol(percent: Int?, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        guard let p = percent else { return "battery.75percent" }
        if p >= 88 { return "battery.100percent" }
        if p >= 63 { return "battery.75percent" }
        if p >= 38 { return "battery.50percent" }
        if p >= 13 { return "battery.25percent" }
        return "battery.0percent"
    }

    // MARK: Capacity history

    static func monthlyCapacity(_ entries: [MacHistoryEntry]) -> [(month: String, mean: Double)] {
        var sums: [String: (sum: Int, n: Int)] = [:]
        for e in entries {
            guard let pct = e.battery_pct else { continue }
            let m = String(e.date.prefix(7))
            let cur = sums[m] ?? (0, 0)
            sums[m] = (cur.sum + pct, cur.n + 1)
        }
        return sums.map { (month: $0.key, mean: Double($0.value.sum) / Double($0.value.n)) }
            .sorted { $0.month > $1.month }
            .prefix(4).map { $0 }
    }

    private static func yearMonth(_ s: String) -> (y: Int, m: Int)? {
        let parts = s.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        return (y, m)
    }

    static func monthLabel(_ yyyyMM: String) -> String {
        guard let (y, m) = yearMonth(yyyyMM) else { return yyyyMM }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return yyyyMM }
        let df = DateFormatter()
        df.locale = Locale(identifier: L10nStore.shared.language == .en ? "en_US" : "ru_RU")
        df.timeZone = .current
        df.dateFormat = "LLL yyyy"
        return df.string(from: date)
    }

    static func capacityHistory(_ entries: [MacHistoryEntry]) -> (rows: [BatteryHistoryRow], caption: String) {
        let monthly = monthlyCapacity(entries)
        let rows = monthly.map {
            BatteryHistoryRow(id: $0.month, label: monthLabel($0.month), value: L.homePercent(fmtNum($0.mean, decimals: 1)))
        }
        guard monthly.count >= 2, let newest = monthly.first, let oldest = monthly.last,
              let n = yearMonth(newest.month), let o = yearMonth(oldest.month) else {
            return (rows, L.batHistoryNotEnough)
        }
        let delta = newest.mean - oldest.mean
        let months = (n.y - o.y) * 12 + (n.m - o.m)
        let pct = L.homePercent(fmtNum(abs(delta), decimals: 1))
        let signedPct = delta < 0 ? "\u{2212}" + pct : (delta > 0 ? "+" + pct : pct)
        return (rows, L.batHistoryDelta(signedPct, months: months))
    }
}
