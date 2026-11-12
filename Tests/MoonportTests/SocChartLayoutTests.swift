// Tests/MoonportTests/SocChartLayoutTests.swift
// CPU-CHART-LEAK: the plot rectangle and the hover view's size must hold across a resize sequence, widen then narrow.

import Testing
import SwiftUI
import AppKit
@testable import Moonport

extension SerialTests {
    @MainActor struct SocChartLayoutTests {
        private func hoverView(in v: NSView) -> SocChartHoverView? {
            if let h = v as? SocChartHoverView { return h }
            for s in v.subviews { if let h = hoverView(in: s) { return h } }
            return nil
        }

        @Test func plotAndHoverViewHoldAcrossAResizeSequence() throws {
            _ = NSApplication.shared
            let hoverHeight: CGFloat = 178  // plot 160 + 18 below it, today's value, written out so the test compiles on the old code
            let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let times = stride(from: 118.0, through: 0, by: -2).map { now.addingTimeInterval(-$0) }
            let series = SocChartModel.series(cpu: times.map { ($0, 40.0) }, gpu: times.map { ($0, Optional(20)) },
                                              now: now, interval: 2)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1094, height: SocLoadChart.bodyHeight),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: SocLoadChart(series: series))
            hosting.sizingOptions = []
            window.contentView = hosting
            defer { window.contentView = nil; window.close() }

            for width in [1094.0, 844, 1744, 844, 1094] as [CGFloat] {
                window.setContentSize(NSSize(width: width, height: SocLoadChart.bodyHeight))
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
                hosting.layoutSubtreeIfNeeded()

                let h = try #require(hoverView(in: hosting), "hover view mounted at width \(width)")
                let plot = try #require(h.plotRect, "plot rect known at width \(width)")
                #expect(abs(plot.minX) < 0.5, "plot starts at the leading edge, width \(width)")
                #expect(abs(plot.maxX - (width - SocLoadChart.gutter)) < 0.5, "plot ends at the gutter, width \(width)")
                #expect(abs(plot.minY) < 0.5, "plot starts at the top, width \(width)")
                #expect(abs(plot.height - SocLoadChart.plotHeight) < 0.5, "plot height, width \(width)")
                #expect(abs(h.frame.height - hoverHeight) < 0.5, "hover view height, width \(width)")
                // visibleRect is not limited to the view's own bounds (186 pt here, the whole clip view in the real card), so intersect it.
                #expect(abs(h.visibleRect.intersection(h.bounds).height - hoverHeight) < 0.5, "hover reach is not clipped, width \(width)")
            }
        }
    }
}
