// Tests/MacDashboardTests/SocChartHoverTests.swift
// SOC-DETAILS Stage 3 (3.5): the pure parts of the SoC chart hover: tooltip placement and the merged hover samples
// with their texts. The layers themselves are checked by the snapshot states `content-soc-chart-hover-*`.
import Foundation
import CoreGraphics
import Testing
@testable import MacDashboard

private let plot = CGRect(x: 0, y: 0, width: 1000, height: 160)

@MainActor struct SocChartHoverTests {
    // MARK: box width

    @Test func boxWidthKeepsTheBaseWhenTheRowsFit() {
        #expect(SocChartHoverArt.boxWidth(labelWidths: [60, 40], valueWidths: [40, 40]) == 168)
    }

    @Test func boxWidthGrowsForTheWidestRowWithAnEightPointGap() {
        // Side padding 14 + 14, swatch 8 + gap 7 = 43, gap 8: 43 + 8 + (90 + 50) = 191.
        #expect(SocChartHoverArt.boxWidth(labelWidths: [90, 40], valueWidths: [50, 60]) == 191)
        // Fractional widths round up to a whole point.
        #expect(SocChartHoverArt.boxWidth(labelWidths: [90.2], valueWidths: [50]) == 192)
    }

    // MARK: placement

    @Test func tooltipSitsFourteenAboveTheMarkerCentredOnTheRule() {
        let o = SocChartHoverPlacement.tooltipOrigin(x: 500, markerYs: [120], plot: plot)
        #expect(o == CGPoint(x: 500 - 84, y: 120 - 14 - 80))
    }

    @Test func tooltipFlipsBelowWhenTheMarkerIsInTheTopShare() {
        // 0.38 x 160 = 60.8: 60 is inside the top share, 62 is not.
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 500, markerYs: [60], plot: plot).y == CGFloat(60 + 14))
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 500, markerYs: [0], plot: plot).y == CGFloat(14))
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 500, markerYs: [62], plot: plot).y == CGFloat(62 - 14 - 80))
    }

    @Test func tooltipIsClampedToThePlotAtBothEdges() {
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 10, markerYs: [120], plot: plot).x == CGFloat(0))
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 0, markerYs: [120], plot: plot).x == CGFloat(0))
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 990, markerYs: [120], plot: plot).x == CGFloat(1000 - 168))
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 1000, markerYs: [120], plot: plot).x == CGFloat(1000 - 168))
    }

    @Test func placementFollowsAPlotThatDoesNotStartAtTheOrigin() {
        let p = CGRect(x: 20, y: 5, width: 1000, height: 160)
        // Marker 40 below the plot top (< 60.8): flipped below. Left edge clamps to the plot, not to 0.
        let o = SocChartHoverPlacement.tooltipOrigin(x: 30, markerYs: [45], plot: p)
        #expect(o == CGPoint(x: 20, y: 45 + 14))
        // Marker 100 below the plot top: above.
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 1015, markerYs: [105], plot: p) == CGPoint(x: 1020 - 168, y: 105 - 14 - 80))
    }

    @Test func theTopmostMarkerDecidesAndAGPUOnlySampleUsesTheGPUMarker() {
        // CPU at 130 (low), GPU at 50 (high on screen): the GPU marker is the topmost, so the box flips below it.
        let both = SocChartHoverPlacement.tooltipOrigin(x: 500, markerYs: [130, 50], plot: plot)
        #expect(both.y == CGFloat(50 + 14))
        // Only the GPU marker exists (nil CPU y is simply absent from `markerYs`).
        let gpuOnly = SocChartHoverPlacement.tooltipOrigin(x: 500, markerYs: [150], plot: plot)
        #expect(gpuOnly.y == CGFloat(150 - 14 - 80))
        // Order of the markers does not matter.
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 500, markerYs: [50, 130], plot: plot) == both)
    }

    @Test func aPlotNarrowerThanTheBoxStaysAtTheLeftEdge() {
        let narrow = CGRect(x: 0, y: 0, width: 100, height: 160)
        #expect(SocChartHoverPlacement.tooltipOrigin(x: 90, markerYs: [120], plot: narrow).x == CGFloat(0))
    }

    // MARK: hover samples

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func series(cpu: [(Date, Double)], gpu: [(Date, Int?)]) -> SocChartSeries {
        SocChartModel.series(cpu: cpu, gpu: gpu, now: Self.t0, interval: 2)
    }

    @Test func hoverSamplesMergeBothSeriesByInstant() {
        let t = (0..<5).map { Self.t0.addingTimeInterval(Double($0 - 4) * 2) }
        let cpu = t.map { ($0, 10.0) }
        // GPU has a value at the first three instants and nil at the last two.
        let gpu: [(Date, Int?)] = [(t[0], 1), (t[1], 2), (t[2], 3), (t[3], nil), (t[4], nil)]
        let s = series(cpu: cpu, gpu: gpu).hoverSamples
        #expect(s.map(\.t) == t)
        #expect(s.map(\.gpu) == [1, 2, 3, nil, nil])
        #expect(s.allSatisfy { $0.cpu == 10 })
    }

    @Test func anInstantWithOnlyAGPUValueIsKept() {
        let t = (0..<4).map { Self.t0.addingTimeInterval(Double($0 - 3) * 2) }
        let s = series(cpu: [(t[0], 5), (t[2], 5), (t[3], 5)], gpu: [(t[1], 40), (t[2], 41)]).hoverSamples
        #expect(s.map(\.t) == [t[0], t[1], t[2], t[3]])
        #expect(s[1].cpu == nil && s[1].gpu == 40)
    }

    @Test func noHoverWhileCollectingOrUnavailable() {
        let t = Self.t0
        #expect(series(cpu: [(t, 5)], gpu: [(t, 5)]).hoverSamples.isEmpty)
        #expect(series(cpu: [], gpu: []).hoverSamples.isEmpty)
        let two = [t.addingTimeInterval(-2), t]
        #expect(series(cpu: [], gpu: two.map { ($0, nil) }).hoverSamples.isEmpty)
    }

    @Test func topCPUIndexIsTheFirstHighestCPUValue() {
        let t = Self.t0
        func sample(_ i: Int, _ v: Double?) -> SocChartSample { SocChartSample(t: t.addingTimeInterval(Double(i)), cpu: v, gpu: 1) }
        #expect(SocChartModel.topCPUIndex([sample(0, 10), sample(1, 40), sample(2, 40), sample(3, 20)]) == 1)
        #expect(SocChartModel.topCPUIndex([sample(0, nil), sample(1, 3)]) == 1)
        #expect(SocChartModel.topCPUIndex([sample(0, nil)]) == nil)
        #expect(SocChartModel.topCPUIndex([]) == nil)
    }
}

extension SerialTests {
    @Suite(.uiLanguage(.ru)) @MainActor struct SocChartTooltipTextTests {
        private func english(_ body: () -> Void) {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            body()
        }

        @Test func tooltipLinesUseOneDecimalForCPUAndWholeNumbersForGPU() {
            english {
                let t = Date(timeIntervalSince1970: 1_800_000_000)
                let x = SocChartModel.tooltipText(SocChartSample(t: t, cpu: 14.24, gpu: 22.6))
                #expect(x.cpu == "14.2%" && x.gpu == "23%")
                #expect(!x.cpuAbsent && !x.gpuAbsent)
                #expect(x.time.range(of: #"^\d\d:\d\d:\d\d$"#, options: .regularExpression) != nil)
            }
        }

        @Test func anAbsentSeriesReadsAsADash() {
            english {
                let t = Date(timeIntervalSince1970: 1_800_000_000)
                let x = SocChartModel.tooltipText(SocChartSample(t: t, cpu: 3, gpu: nil))
                #expect(x.gpu == "—" && x.gpuAbsent && !x.cpuAbsent)
                let y = SocChartModel.tooltipText(SocChartSample(t: t, cpu: nil, gpu: 0))
                #expect(y.cpu == "—" && y.cpuAbsent && y.gpu == "0%")
            }
        }

        @Test func russianUsesTheSpacedPercent() {
            let t = Date(timeIntervalSince1970: 1_800_000_000)
            let x = SocChartModel.tooltipText(SocChartSample(t: t, cpu: 14.2, gpu: 23))
            #expect(x.cpu == "14,2 %" && x.gpu == "23 %")   // the struct pins .ru
        }
    }
}
