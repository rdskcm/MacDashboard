// Tests/MacDashboardTests/SocPageModelTests.swift
// SOC-DETAILS 1.6: the pure view models of the SoC page: readout chip, split, load average, cores card, GPU list, chart.
import Foundation
import Testing
@testable import MacDashboard

private func withEnglish(_ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = .en
    body()
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private let perf = CoreGroup(name: "Performance", count: 4, coreIndices: [4, 5, 6, 7])
private let eff = CoreGroup(name: "Efficiency", count: 4, coreIndices: [0, 1, 2, 3])

extension SerialTests {
    struct SocPageModelTests {
        // MARK: columns (design 7.5)

        @Test func columnsFourPerGroupAtEveryWidth() {
            for a in [584, 834, 1484] as [CGFloat] { #expect(SocCoresCardModel.columns(count: 4, cellsArea: a) == 4, "A = \(a)") }
        }

        @Test func columnsSixteenCoresBalanceTheRows() {
            #expect(SocCoresCardModel.columns(count: 16, cellsArea: 584) == 4)    // fit 5 -> 4 rows of 4
            #expect(SocCoresCardModel.columns(count: 16, cellsArea: 834) == 6)    // fit 7 -> 6 + 6 + 4
            #expect(SocCoresCardModel.columns(count: 16, cellsArea: 1484) == 8)   // fit 13 -> 8 + 8
        }

        @Test func columnsEdges() {
            #expect(SocCoresCardModel.columns(count: 1, cellsArea: 10) == 1)
            #expect(SocCoresCardModel.columns(count: 0, cellsArea: 500) == 1)
            #expect(SocCoresCardModel.columns(count: 2, cellsArea: 0) == 1)        // fit = max(1, 0) = 1 -> 2 rows of 1
            #expect(SocCoresCardModel.columns(count: 128, cellsArea: 1484) == 13)  // fit 13 -> 10 rows, no upper limit on n
        }

        // MARK: readout chip

        @Test func readoutWideShowsFullThermalAndPrefix() {
            withEnglish {
                let r = SocReadout.make(socTempC: 58, thermal: .nominal, powerW: 6.8, narrow: false, tagVisible: false)
                #expect(r.temperature?.value == "58 °C" && r.temperature?.zone == 0 && r.temperature?.word == nil && r.temperature?.attention == false)
                #expect(r.thermal?.text == "thermal: normal" && r.thermal?.word == "normal" && r.thermal?.step == 0 && r.thermal?.tone == .green)
                #expect(r.power.prefix == "Mac" && r.power.value == "6.8 W" && r.power.help == "Power, whole Mac" && r.power.available)
            }
        }

        @Test func readoutShorteningOrder() {
            withEnglish {
                // Narrow: the thermal word only, power unchanged.
                let narrow = SocReadout.make(socTempC: 58, thermal: .fair, powerW: 6.8, narrow: true, tagVisible: false)
                #expect(narrow.thermal?.text == "elevated" && narrow.thermal?.full == "thermal: elevated")
                #expect(narrow.power.prefix == "Mac")
                // Narrow with the state tag: also no prefix. The power segment stays.
                let tagged = SocReadout.make(socTempC: 58, thermal: .fair, powerW: 6.8, narrow: true, tagVisible: true)
                #expect(tagged.thermal?.text == "elevated" && tagged.power.prefix == nil && tagged.power.value == "6.8 W")
                // Wide with the tag: nothing shortened.
                let wide = SocReadout.make(socTempC: 58, thermal: .fair, powerW: 6.8, narrow: false, tagVisible: true)
                #expect(wide.thermal?.text == "thermal: elevated" && wide.power.prefix == "Mac")
            }
        }

        @Test func readoutTemperatureZonesAndMarker() {
            withEnglish {
                func temp(_ t: Int) -> SocReadout.Temperature? { SocReadout.make(socTempC: t, thermal: nil, powerW: nil, narrow: false, tagVisible: false).temperature }
                #expect(temp(84)?.zone == 0 && temp(84)?.attention == false)
                #expect(temp(85)?.zone == 1 && temp(85)?.word == "warm" && temp(85)?.attention == true)
                #expect(temp(94)?.zone == 1)
                #expect(temp(95)?.zone == 2 && temp(95)?.word == "hot")
                #expect(SocReadout.markerX(celsius: 30) == 0)
                #expect(SocReadout.markerX(celsius: 105) == 1)
                #expect(SocReadout.markerX(celsius: 20) == 0)        // clamped
                #expect(SocReadout.markerX(celsius: 120) == 1)       // clamped
                #expect(abs(SocReadout.markerX(celsius: 68) - 38.0 / 75) < 1e-9)
            }
        }

        @Test func readoutThermalToneAndStep() {
            withEnglish {
                func th(_ l: ThermalLevel) -> SocReadout.Thermal? { SocReadout.make(socTempC: nil, thermal: l, powerW: nil, narrow: false, tagVisible: false).thermal }
                #expect(th(.nominal)?.step == 0 && th(.nominal)?.tone == .green)
                #expect(th(.fair)?.step == 1 && th(.fair)?.tone == .neutral)
                #expect(th(.serious)?.step == 2 && th(.serious)?.tone == .amber && th(.serious)?.text == "thermal: high")
                #expect(th(.critical)?.step == 3 && th(.critical)?.tone == .hot)
                #expect(th(.nominal)?.help == L.cpuThermalHelpNominal)   // the app's existing long texts are kept
            }
        }

        @Test func readoutUnavailableItems() {
            withEnglish {
                let r = SocReadout.make(socTempC: nil, thermal: nil, powerW: nil, narrow: true, tagVisible: true)
                #expect(r.temperature == nil && r.thermal == nil)
                #expect(r.power.value == "—" && !r.power.available && r.power.help == "Power, whole Mac: Not available on this Mac")
            }
        }

        // MARK: split and load average

        @Test func splitKeepsOneDecimalAndDoesNotForceHundred() {
            withEnglish {
                let s = SocSplit.make(cpu: CPUUsage(user: 16.0, sys: 2.4, idle: 81.5))
                #expect(s.user == "16.0%" && s.system == "2.4%" && s.idle == "81.5%")
                #expect(abs(s.userFraction - 0.16) < 1e-9 && abs(s.idleFraction - 0.815) < 1e-9)
                let none = SocSplit.make(cpu: nil)
                #expect(none.user == "—" && none.system == "—" && none.idle == "—" && none.userFraction == 0 && none.idleFraction == 0)
            }
        }

        @Test func loadAverageTwoDecimalsOrDashes() {
            withEnglish {
                let l = SocLoadAverage.make(load: [1.3, 1.73, 128.0])
                #expect(l.one == "1.30" && l.five == "1.73" && l.fifteen == "128.00" && l.available)
                #expect(SocLoadAverage.make(load: nil).one == "—" && !SocLoadAverage.make(load: nil).available)
                #expect(SocLoadAverage.make(load: [1, 2]).fifteen == "—")
            }
        }

        // MARK: cores card

        private func load(_ g: CoreGroup, _ loads: [Int?], _ f: FrequencyState = .notYet) -> CoreGroupLoad {
            CoreGroupLoad(group: g, loads: loads, frequency: f)
        }

        @Test func coresCardHeadingsCellsAndFrequency() {
            withEnglish {
                let card = SocCoresCardModel.make(cores: [load(perf, [13, 1, 2, 100], .mhz(3953)), load(eff, [14, 14, 9, nil], .idle)], loadFailed: false, hasReading: true)
                #expect(card.caption == "load per core")
                #expect(card.groups.map(\.heading) == ["Performance · 4", "Efficiency · 4"])
                #expect(card.groups.map(\.hue) == [0, 1])
                #expect(card.groups[0].cells.map(\.id) == ["P1", "P2", "P3", "P4"])
                #expect(card.groups[0].cells.map(\.valueText) == ["13%", "1%", "2%", "100%"])
                #expect(card.groups[0].cells[3].fraction == 1)
                #expect(card.groups[1].cells[3].valueText == "—" && card.groups[1].cells[3].fraction == 0)
                #expect(card.groups[0].frequencyText == "3.95 GHz" && card.groups[0].frequencyHelp == "Average speed while the cores were active.")
                #expect(card.groups[1].frequencyText == "idle")
            }
        }

        @Test func coresCardReadingWithAllNilLoadsShowsDash() {
            withEnglish {
                let card = SocCoresCardModel.make(cores: [load(perf, [nil, nil, nil, nil])], loadFailed: false, hasReading: true)
                #expect(card.groups.flatMap(\.cells).allSatisfy { $0.valueText == "—" && $0.fraction == 0 })
            }
        }

        @Test func coresCardNotYetKeepsHeadingsWithEmptyCells() {
            withEnglish {
                let card = SocCoresCardModel.make(cores: [load(perf, [nil, nil, nil, nil]), load(eff, [nil, nil, nil, nil])], loadFailed: false, hasReading: false)
                #expect(card.groups.map(\.heading) == ["Performance · 4", "Efficiency · 4"])
                #expect(card.groups.flatMap(\.cells).allSatisfy { $0.valueText == "" && $0.fraction == 0 })
                #expect(card.groups[0].frequencyText == "—" && card.groups[0].frequencyHelp == nil)
            }
        }

        @Test func coresCardFailedCallKeepsGroupsAndChangesTheCaption() {
            withEnglish {
                let card = SocCoresCardModel.make(cores: [load(perf, [nil, nil, nil, nil], .unavailable)], loadFailed: true, hasReading: true)
                #expect(card.caption == "Not available on this Mac")
                #expect(card.groups.count == 1 && card.groups[0].cells.allSatisfy { $0.valueText == "" })
                #expect(card.groups[0].frequencyText == "—" && card.groups[0].frequencyHelp == "Not available on this Mac")
                #expect(SocCoresCardModel.make(cores: nil, loadFailed: false, hasReading: true).groups.isEmpty)
            }
        }

        @Test func coresCardUnknownTypeIsOneGroupCoresN() {
            withEnglish {
                let g = CoreGroup(name: nil, count: 8, coreIndices: Array(0..<8))
                let card = SocCoresCardModel.make(cores: [load(g, Array(repeating: 5, count: 8), .unavailable)], loadFailed: false, hasReading: true)
                #expect(card.groups.map(\.heading) == ["Cores · 8"] && card.groups[0].hue == 0)
                #expect(card.groups[0].cells.map(\.id) == ["1", "2", "3", "4", "5", "6", "7", "8"])
                #expect(card.groups[0].frequencyText == "—")
            }
        }

        @Test func coresCardThirdTypeAndUnfamiliarName() {
            withEnglish {
                let sup = CoreGroup(name: "Super", count: 2, coreIndices: [8, 9])
                let card = SocCoresCardModel.make(cores: [load(sup, [1, 2]), load(perf, [1, 2, 3, 4]), load(eff, [1, 2, 3, 4])], loadFailed: false, hasReading: true)
                #expect(card.groups.map(\.heading) == ["Super · 2", "Performance · 4", "Efficiency · 4"])
                #expect(card.groups.map(\.hue) == [2, 0, 1])
                #expect(card.groups[0].cells.map(\.id) == ["S1", "S2"])
            }
        }

        // MARK: GPU list

        @Test func gpuListCaption() {
            withEnglish {
                #expect(SocGPUListModel.make(state: .notYet, coreCount: 8).caption == "8 GPU cores · top by GPU")
                #expect(SocGPUListModel.make(state: .notYet, coreCount: nil).caption == "top by GPU")
                #expect(SocGPUListModel.make(state: .notYet, coreCount: 128).caption == "128 GPU cores · top by GPU")
            }
        }

        @Test func gpuListRows() {
            withEnglish {
                let rows = [GPUProcessRow(id: 108, name: "Terminal", sharePct: 12.34, lifetimeNs: 5),
                            GPUProcessRow(id: 101, name: "WindowServer", sharePct: 0, lifetimeNs: 4),
                            GPUProcessRow(id: 5, name: "Odd", sharePct: nil, lifetimeNs: 3)]
                let list = SocGPUListModel.make(state: .rows(rows), coreCount: 8)
                #expect(list.rows.map(\.id) == [108, 101, 5])
                #expect(list.rows.map(\.valueText) == ["12.3%", "0.0%", "—"])
                #expect(list.rows.map(\.muted) == [false, true, true])
                #expect(abs(list.rows[0].fraction - 0.1234) < 1e-9 && list.rows[2].fraction == 0)
                #expect(SocGPUListModel.make(state: .empty, coreCount: 8).rows.isEmpty)
                #expect(SocGPUListModel.make(state: .unavailable, coreCount: 8).rows.isEmpty)
            }
        }

        // MARK: chart

        private func cpuSamples(count: Int, step: Double, endingAt end: Date) -> [(Date, Double)] {
            (0..<count).map { i in (end.addingTimeInterval(-Double(count - 1 - i) * step), Double(i % 50)) }
        }

        @Test func chartWindowAtTwoSecondsHoldsSixtyOneSamples() {
            let s = SocChartModel.series(cpu: cpuSamples(count: 61, step: 2, endingAt: t0), gpu: [], now: t0, interval: 2)
            #expect(s.cpu.count == 1 && s.cpu[0].points.count == 61)
            #expect(s.windowStart == t0.addingTimeInterval(-120) && s.windowEnd == t0)
        }

        @Test func chartWindowSampleCountsByInterval() {
            #expect(SocChartModel.series(cpu: cpuSamples(count: 61, step: 5, endingAt: t0), gpu: [], now: t0, interval: 5).cpu[0].points.count == 25)
            #expect(SocChartModel.series(cpu: cpuSamples(count: 61, step: 10, endingAt: t0), gpu: [], now: t0, interval: 10).cpu[0].points.count == 13)
        }

        @Test func chartSamplesOlderThanTwoMinutesAreDropped() {
            let s = SocChartModel.series(cpu: cpuSamples(count: 70, step: 2, endingAt: t0), gpu: [], now: t0, interval: 2)
            #expect(s.cpu[0].points.count == 61)
            #expect(s.cpu[0].points.first?.t == t0.addingTimeInterval(-120))
        }

        @Test func chartIntervalChangeKeepsRealTimestamps() {
            // 30 samples at 2 s, then the user switches to 10 s and 6 more arrive. Judged with interval 10: no gap.
            var cpu = cpuSamples(count: 30, step: 2, endingAt: t0.addingTimeInterval(-60))
            cpu += (1...6).map { (t0.addingTimeInterval(-60 + Double($0) * 10), 10.0) }
            let s = SocChartModel.series(cpu: cpu, gpu: [], now: t0, interval: 10)
            #expect(s.cpu.count == 1 && s.cpu[0].points.count == 36)
            #expect(s.cpu[0].points.map(\.t) == cpu.map(\.0))
            // The same list judged at 2 s breaks at every 10 s step (10 > 2.5 × 2): the 30 old samples, then 6 lone dots.
            #expect(SocChartModel.series(cpu: cpu, gpu: [], now: t0, interval: 2).cpu.count == 7)
        }

        @Test func chartGapBreaksTheLine() {
            let cpu: [(Date, Double)] = [(-40, 1), (-38, 2), (-36, 3), (-20, 4), (-18, 5)].map { (t0.addingTimeInterval($0.0), $0.1) }
            let s = SocChartModel.series(cpu: cpu, gpu: [], now: t0, interval: 2)   // 16 s > 2.5 × 2
            #expect(s.cpu.map { $0.points.count } == [3, 2])
            #expect(Set(s.cpu.map(\.id)).count == 2)
            // A gap above 2.5 intervals breaks, at or below it joins.
            let atLimit: [(Date, Double)] = [(-10, 1), (-5, 2), (-2.4, 3)].map { (t0.addingTimeInterval($0.0), $0.1) }
            #expect(SocChartModel.series(cpu: atLimit, gpu: [], now: t0, interval: 2).cpu.count == 1)   // 5.0 s = 2.5 × 2
            let above: [(Date, Double)] = [(-10, 1), (-4.9, 2)].map { (t0.addingTimeInterval($0.0), $0.1) }
            #expect(SocChartModel.series(cpu: above, gpu: [], now: t0, interval: 2).cpu.count == 2)     // 5.1 s
            #expect(SocChartModel.series(cpu: above, gpu: [], now: t0, interval: 3).cpu.count == 1)     // 5.1 s <= 7.5 s
        }

        @Test func chartNilGpuBreaksOnlyTheGpuSeries() {
            let cpu = cpuSamples(count: 5, step: 2, endingAt: t0)
            let gpu: [(Date, Int?)] = zip(cpu, [4, nil, 6, 7, 8] as [Int?]).map { ($0.0, $1) }
            let s = SocChartModel.series(cpu: cpu, gpu: gpu, now: t0, interval: 2)
            #expect(s.cpu.count == 1)
            #expect(s.gpu.map { $0.points.count } == [1, 3])
            #expect(s.gpu[0].isDot && !s.gpu[1].isDot)
            #expect(s.gpu[0].points[0].v == 4)
        }

        @Test func chartLoneSampleBetweenGapsIsADot() {
            let cpu: [(Date, Double)] = [(-60, 1), (-58, 2), (-40, 3), (-20, 4), (-18, 5)].map { (t0.addingTimeInterval($0.0), $0.1) }
            let s = SocChartModel.series(cpu: cpu, gpu: [], now: t0, interval: 2)
            #expect(s.cpu.map { $0.points.count } == [2, 1, 2])
            #expect(s.cpu.map(\.isDot) == [false, true, false])
        }

        @Test func chartStates() {
            withEnglish {
                let full = cpuSamples(count: 61, step: 2, endingAt: t0)
                let gpuFull: [(Date, Int?)] = full.map { ($0.0, 5) }
                #expect(SocChartModel.series(cpu: full, gpu: gpuFull, now: t0, interval: 2).state == .full)
                // Just launched: one or zero samples.
                #expect(SocChartModel.series(cpu: [], gpu: [], now: t0, interval: 2).state == .collecting)
                #expect(SocChartModel.series(cpu: [full[60]], gpu: [(full[60].0, 5)], now: t0, interval: 2).state == .collecting)
                // Less than two minutes since launch.
                let few = Array(full.suffix(20))
                #expect(SocChartModel.series(cpu: few, gpu: few.map { ($0.0, 5) }, now: t0, interval: 2).state == .partial)
                // GPU source missing: CPU line only.
                let missing = SocChartModel.series(cpu: full, gpu: full.map { ($0.0, nil) }, now: t0, interval: 2)
                #expect(missing.state == .gpuMissing && missing.gpu.isEmpty && !missing.cpu.isEmpty)
                #expect(SocChartModel.series(cpu: full, gpu: [], now: t0, interval: 2).state == .gpuMissing)
                // Both missing.
                #expect(SocChartModel.series(cpu: [], gpu: full.map { ($0.0, nil) }, now: t0, interval: 2).state == .unavailable)
                #expect(SocChartModel.series(cpu: full, gpu: [], now: t0, interval: 2).xLabels == ["−2 min", "−1 min", "now"])
            }
        }

        @Test func chartGapInsideACoveredWindowStaysFull() {
            let a = cpuSamples(count: 20, step: 2, endingAt: t0.addingTimeInterval(-80))
            let b = cpuSamples(count: 20, step: 2, endingAt: t0)
            let s = SocChartModel.series(cpu: a + b, gpu: (a + b).map { ($0.0, 3) }, now: t0, interval: 2)
            #expect(s.cpu.count == 2 && s.state == .full)   // the oldest sample sits at the left edge; the gap is drawn as a break
        }
    }
}
