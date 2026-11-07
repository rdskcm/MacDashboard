// Engine/SocPageModel.swift
// SOC-DETAILS 1.6: pure view models for what the SoC redesign added to the page: the page-bar readout chip, the
// user/system/idle split, the load average, the CPU cores card, the top-GPU list and the 2-minute chart series.
// Foundation only; the views render what these return. `CPUPageModel.make` keeps the CPU/GPU heroes, the tag,
// the sub line and the failure note.
import Foundation
import CoreGraphics

// MARK: - Page-bar readout chip (design 7.3, 7.12)

struct SocReadout: Equatable {
    struct Temperature: Equatable {
        let value: String          // "58 °C"
        let zone: Int              // 0 normal, 1 warm, 2 hot
        let markerX: Double        // 0...1 on the gauge track
        let word: String?          // "warm" / "hot", nil in the normal zone
    }
    struct Thermal: Equatable {
        let word: String           // "normal"
        let full: String           // "thermal: normal"
        let text: String           // what the segment shows: the word below 1000 pt, else the full text
        let step: Int              // 0...3 on the four-step rail
        let tone: CPUNoteTone
        let help: String           // the app's existing long thermal text
    }
    struct Power: Equatable {
        let prefix: String?        // "Mac"; dropped when the bar is narrow and the state tag is visible
        let value: String          // "6.8 W" or "—"
        let help: String
        let available: Bool
    }

    let temperature: Temperature?
    let thermal: Thermal?
    let power: Power

    /// Gauge track range of design 7.12: x = clamp((t − 30) / 75, 0, 1).
    static func markerX(celsius: Int) -> Double { min(1, max(0, (Double(celsius) - 30) / 75)) }

    /// Shortening order (owner decision 2026-11-05): below 1000 pt the thermal segment shows the word only; below
    /// 1000 pt with the state tag visible the power segment also loses its "Mac" prefix (the sub line then drops
    /// "updates every N s" through `CPUPageModel`). The power segment is never dropped.
    static func make(socTempC: Int?, thermal: ThermalLevel?, powerW: Double?, narrow: Bool, tagVisible: Bool) -> SocReadout {
        var temperature: Temperature? = nil
        if let t = socTempC {
            let level = CPULoad.socLevel(t)
            let zone = level == .hot ? 2 : (level == .warm ? 1 : 0)
            temperature = Temperature(value: "\(t) °C", zone: zone, markerX: markerX(celsius: t),
                                      word: zone == 2 ? L.cpuSocHot : (zone == 1 ? L.cpuSocWarm : nil))
        }
        var thermalSegment: Thermal? = nil
        if let th = thermal {
            let word: String, full: String, help: String, step: Int, tone: CPUNoteTone
            switch th {
            case .nominal:  word = L.cpuThermalWordNominal;  full = L.cpuThermalNominal;  help = L.cpuThermalHelpNominal;  step = 0; tone = .green
            case .fair:     word = L.cpuThermalWordFair;     full = L.cpuThermalFair;     help = L.cpuThermalHelpFair;     step = 1; tone = .neutral
            case .serious:  word = L.cpuThermalWordSerious;  full = L.cpuThermalSerious;  help = L.cpuThermalHelpSerious;  step = 2; tone = .amber
            case .critical: word = L.cpuThermalWordCritical; full = L.cpuThermalCritical; help = L.cpuThermalHelpCritical; step = 3; tone = .hot
            }
            thermalSegment = Thermal(word: word, full: full, text: narrow ? word : full, step: step, tone: tone, help: help)
        }
        let power: Power
        if let w = powerW {
            power = Power(prefix: (narrow && tagVisible) ? nil : L.socPowerPrefix,
                          value: L.socWatts(fmtFixed(w, decimals: SocDisplay.powerDecimals)), help: L.socPowerLabel, available: true)
        } else {
            power = Power(prefix: (narrow && tagVisible) ? nil : L.socPowerPrefix,
                          value: "—", help: L.socPowerUnavailable, available: false)
        }
        return SocReadout(temperature: temperature, thermal: thermalSegment, power: power)
    }
}

// MARK: - User / system / idle (3.3)

struct SocSplit: Equatable {
    let user: String
    let system: String
    let idle: String
    /// 0...1 shares for the stacked bar; 0 when there is no reading.
    let userFraction: Double
    let systemFraction: Double
    let idleFraction: Double

    /// 1 decimal each, "—" when the CPU reading is missing. The sum is not forced to 100.
    static func make(cpu: CPUUsage?) -> SocSplit {
        guard let cpu else { return SocSplit(user: "—", system: "—", idle: "—", userFraction: 0, systemFraction: 0, idleFraction: 0) }
        func text(_ v: Double) -> String { L.homePercent(fmtFixed(v, decimals: SocDisplay.splitDecimals)) }
        // The bar follows the shown value, so `SocSplit ==` changes exactly when a text changes (Stage 5a, D39).
        func fraction(_ v: Double) -> Double { min(1, max(0, SocDisplay.rounded(v, decimals: SocDisplay.splitDecimals) / 100)) }
        return SocSplit(user: text(cpu.user), system: text(cpu.sys), idle: text(cpu.idle),
                        userFraction: fraction(cpu.user), systemFraction: fraction(cpu.sys), idleFraction: fraction(cpu.idle))
    }
}

// MARK: - Load average (3.2)

struct SocLoadAverage: Equatable {
    let one: String
    let five: String
    let fifteen: String
    let available: Bool

    /// 2 decimals each, "—" for all three when the reading is missing.
    static func make(load: [Double]?) -> SocLoadAverage {
        guard let l = load, l.count == 3 else { return SocLoadAverage(one: "—", five: "—", fifteen: "—", available: false) }
        return SocLoadAverage(one: fmtFixed(l[0], decimals: 2), five: fmtFixed(l[1], decimals: 2),
                              fifteen: fmtFixed(l[2], decimals: 2), available: true)
    }
}

// MARK: - CPU cores card (design 7.5)

struct SocCoresCardModel: Equatable {
    struct Cell: Equatable, Identifiable {
        let id: String             // "P1"; "1" in a group of unknown type
        let valueText: String      // "63 %", "—" (a core with no elapsed ticks), "" (not yet, or the call failed)
        let fraction: Double       // 0...1, 0 without a value
    }

    // Pure pieces used by the per-cell views (each view computes only its own text).

    static func caption(loadFailed: Bool) -> String { loadFailed ? L.gpuNotAvailable : L.socLoadPerCore }

    /// "P1" for the first core of the Performance group; "1" in a group of unknown type. `index` is zero-based.
    static func cellID(groupName: String?, index n: Int) -> String {
        let letter = groupName?.first.map { String($0).uppercased() }
        return (letter ?? "") + String(n + 1)
    }

    static func cell(id: String, load: Int?, loadFailed: Bool, hasReading: Bool) -> Cell {
        if let load {
            return Cell(id: id, valueText: L.homePercent("\(load)"), fraction: min(1, max(0, Double(load) / 100)))
        }
        return Cell(id: id, valueText: (loadFailed || !hasReading) ? "" : "—", fraction: 0)
    }

    /// "Performance · 4".
    static func heading(_ group: CoreGroup) -> String { typeName(group.name) + " · \(group.count)" }

    static func frequency(_ f: FrequencyState) -> (text: String, isValue: Bool, help: String?) {
        switch f {
        case .notYet: return ("—", false, nil)
        case .unavailable: return ("—", false, L.gpuNotAvailable)
        case .idle: return (L.socFrequencyIdle, false, L.socFrequencyHelp)
        case .mhz(let mhz):
            return (L.socGHz(fmtFixed(mhz / 1000, decimals: SocDisplay.ghzDecimals)), true, L.socFrequencyHelp)
        }
    }

    /// Hue by the system's name, not by position: Performance 0, Efficiency 1, any other name 2, unknown type 0.
    static func hue(forName name: String?) -> Int {
        switch name {
        case nil: return 0
        case "Performance": return 0
        case "Efficiency": return 1
        default: return 2
        }
    }

    /// The two names the system gives every Apple silicon chip are translated (design 9: "Производительные ·
    /// 4"); any other name is shown as the system gives it (3.1), nil is a group of unknown type.
    static func typeName(_ name: String?) -> String {
        guard let name else { return L.socCoresUnknown }
        switch name {
        case "Performance": return L.socCoreTypePerformance
        case "Efficiency": return L.socCoreTypeEfficiency
        default: return name
        }
    }

    /// Design 7.5: with `fit = max(1, floor((A + 12) / 108))`, `n ≤ fit` → one row of `n`; otherwise balanced rows of
    /// `ceil(n / ceil(n / fit))` columns. `A` is the cells area width in points. No upper limit on `n`.
    static func columns(count n: Int, cellsArea A: CGFloat) -> Int {
        guard n > 0 else { return 1 }
        let fit = max(1, Int(((A + 12) / 108).rounded(.down)))
        if n <= fit { return n }
        let rows = Int((Double(n) / Double(fit)).rounded(.up))
        return Int((Double(n) / Double(rows)).rounded(.up))
    }
}

// MARK: - Top GPU processes (design 7.4)

struct SocGPUListModel: Equatable {
    struct Row: Equatable, Identifiable {
        let id: Int32              // pid
        let name: String
        let valueText: String      // "0.2 %", "0.0 %", "—"
        let muted: Bool            // "0.0 %" and "—"
        let fraction: Double       // share / 100, 0 for "—"
    }

    /// "8 GPU cores · top by GPU", or "top by GPU" when the core count is unknown.
    static func caption(coreCount: Int?) -> String {
        coreCount.map { "\(L.socGPUCores($0)) · \(L.socTopByGPU)" } ?? L.socTopByGPU
    }

    static func row(_ r: GPUProcessRow) -> Row {
        guard let share = r.sharePct else {
            return Row(id: r.id, name: r.name, valueText: "—", muted: true, fraction: 0)
        }
        let text = fmtFixed(share, decimals: SocDisplay.shareDecimals)
        let zero = fmtFixed(0, decimals: SocDisplay.shareDecimals)
        return Row(id: r.id, name: r.name, valueText: L.homePercent(text), muted: text == zero,
                   fraction: min(1, max(0, share / 100)))
    }
}

// MARK: - 2-minute chart series (3.7, D5-D8)

struct SocChartPoint: Equatable {
    let t: Date
    let v: Double
}

/// One unbroken run of samples of one series. A run of one sample is drawn as a dot.
struct SocChartSegment: Equatable, Identifiable {
    let id: String                 // "cpu-0", "gpu-2": unique per run so Charts never joins across a gap
    let points: [SocChartPoint]
    var isDot: Bool { points.count == 1 }
}

enum SocChartState: Equatable { case collecting, partial, full, gpuMissing, unavailable }

struct SocChartSeries: Equatable {
    let windowStart: Date
    let windowEnd: Date
    let cpu: [SocChartSegment]
    let gpu: [SocChartSegment]
    let state: SocChartState
    /// −2 min, −1 min, now.
    let xLabels: [String]
}

enum SocChartModel {
    static let windowSeconds: TimeInterval = 120
    /// D7: a sample later than this many intervals after the previous one starts a new segment.
    static let gapIntervals = 2.5

    /// - Window: `now − 120 s ... now`, both ends inclusive; samples outside it are dropped (D5). Samples sit at their
    ///   real timestamps, whatever the interval was when they were taken.
    /// - A segment breaks when the gap to the previous sample exceeds `2.5 × interval`, or at a nil value (D7); a nil
    ///   breaks only its own series.
    /// - State: fewer than 2 sample instants → `.collecting`; no CPU and no GPU value → `.unavailable`; no GPU value →
    ///   `.gpuMissing`; the oldest sample more than one interval after the window start → `.partial`; else `.full`.
    static func series(cpu: [(Date, Double)], gpu: [(Date, Int?)], now: Date, interval: Int) -> SocChartSeries {
        let start = now.addingTimeInterval(-windowSeconds)
        let maxGap = gapIntervals * Double(max(1, interval))
        func inWindow(_ t: Date) -> Bool { t >= start && t <= now }
        let cpuSamples = cpu.filter { inWindow($0.0) }.sorted { $0.0 < $1.0 }.map { (t: $0.0, v: Optional($0.1)) }
        let gpuSamples = gpu.filter { inWindow($0.0) }.sorted { $0.0 < $1.0 }.map { (t: $0.0, v: $0.1.map(Double.init)) }

        let instants = Set(cpuSamples.map(\.t) + gpuSamples.map(\.t))
        let cpuCount = cpuSamples.count
        let gpuCount = gpuSamples.filter { $0.v != nil }.count
        let state: SocChartState
        if instants.count < 2 { state = .collecting }
        else if cpuCount == 0 && gpuCount == 0 { state = .unavailable }
        else if gpuCount == 0 { state = .gpuMissing }
        else if let oldest = instants.min(), oldest > start.addingTimeInterval(Double(max(1, interval))) { state = .partial }
        else { state = .full }

        return SocChartSeries(windowStart: start, windowEnd: now,
                              cpu: segments(cpuSamples, maxGap: maxGap, prefix: "cpu"),
                              gpu: segments(gpuSamples, maxGap: maxGap, prefix: "gpu"),
                              state: state,
                              xLabels: [L.socChartMinus2, L.socChartMinus1, L.socChartNow])
    }

    /// Pure. `samples` sorted by time.
    static func segments(_ samples: [(t: Date, v: Double?)], maxGap: TimeInterval, prefix: String) -> [SocChartSegment] {
        var out: [SocChartSegment] = []
        var run: [SocChartPoint] = []
        var lastT: Date? = nil
        func close() {
            if !run.isEmpty { out.append(SocChartSegment(id: "\(prefix)-\(out.count)", points: run)) }
            run = []
        }
        for s in samples {
            if let last = lastT, s.t.timeIntervalSince(last) > maxGap { close() }
            lastT = s.t
            guard let v = s.v else { close(); continue }
            run.append(SocChartPoint(t: s.t, v: v))
        }
        close()
        return out
    }
}

// MARK: - Chart hover samples (3.7, D9)

/// One instant of the hover: the sample the pointer snaps to. A series without a value at that instant is nil.
struct SocChartSample: Equatable {
    let t: Date
    let cpu: Double?
    let gpu: Double?
}

/// The three tooltip lines of one sample (D9): time `HH:mm:ss`, then CPU and GPU, "—" for an absent value.
struct SocChartTooltipText: Equatable {
    let time: String
    let cpu: String
    let gpu: String
    let cpuAbsent: Bool
    let gpuAbsent: Bool
}

extension SocChartSeries {
    /// One entry per instant that has a CPU or a GPU value, time ascending (the x positions the hover snaps to). Empty
    /// while the chart shows no marks (`.collecting`, `.unavailable`).
    var hoverSamples: [SocChartSample] {
        guard state != .collecting, state != .unavailable else { return [] }
        var cpuAt: [Date: Double] = [:], gpuAt: [Date: Double] = [:]
        for s in cpu { for p in s.points { cpuAt[p.t] = p.v } }
        for s in gpu { for p in s.points { gpuAt[p.t] = p.v } }
        let instants = Set(cpuAt.keys).union(gpuAt.keys).sorted()
        return instants.map { SocChartSample(t: $0, cpu: cpuAt[$0], gpu: gpuAt[$0]) }
    }
}

extension SocChartModel {
    /// CPU with one decimal ("14.2 %"), GPU as a whole number ("23 %"), through the app's percent format.
    static func tooltipText(_ s: SocChartSample) -> SocChartTooltipText {
        let dash = "—"
        return SocChartTooltipText(
            time: CPUPageModel.hhmmss(s.t),
            cpu: s.cpu.map { L.homePercent(fmtFixed($0, decimals: 1)) } ?? dash,
            gpu: s.gpu.map { L.homePercent(String(Int($0.rounded()))) } ?? dash,
            cpuAbsent: s.cpu == nil, gpuAbsent: s.gpu == nil)
    }

    /// Index of the sample with the highest CPU value (first one on a tie); nil without a CPU value. The fixture pins
    /// the "near the top" hover on it.
    static func topCPUIndex(_ samples: [SocChartSample]) -> Int? {
        var best: Int?
        for (i, s) in samples.enumerated() {
            guard let v = s.cpu else { continue }
            if best == nil || v > (samples[best!].cpu ?? -1) { best = i }
        }
        return best
    }
}

extension AppModel {
    /// The chart's series from the kept histories at the last sample time (`fixtureNow` under the visual fixture).
    /// Read inside the chart card's body only, so it is evaluated once per tick (the card re-runs when `cpuHistory`
    /// or `gpuHistory` change).
    var socChartSeries: SocChartSeries {
        SocChartModel.series(cpu: cpuHistory, gpu: gpuHistory, now: now(or: lastSampleAt),
                             interval: settings.fastIntervalSeconds)
    }
}
