// HiddenContentTests.swift
// HIDDEN-CONTENT-WORK (R1, R2, R8): only the shown page is mounted and registered with the pointer tracker.
// Runs frozen (fixture mode), so every transition is `.identity` and no removing view is left in the tree.
// Repeating animations are out of reach here (frozen runs create no pulse ring or shimmer); V6 / APP-WASTE-AUDIT cover them.

import SwiftUI
import AppKit
import Testing
@testable import MacDashboard

/// Covers the `ZStack`/frame wrapper of `MacContentView` (first run: every delta was 0, so 8 is headroom, not a fitted value); the controls below need ≥ 50.
private let slack = 8

@MainActor private let width = LiveWindowWidth(1150)
@MainActor private let tier = WidthTier.initial(width: 1150)
private let breakpoints = PageBreakpoints(width: 1150)

@MainActor
private final class Host {
    let tracker = DS3PointerTracker()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1150, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    init<V: View>(_ view: V) {
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.frame(width: 1150, height: 700).ds3PointerTracking(tracker))
        hosting.frame = NSRect(x: 0, y: 0, width: 1150, height: 700)
        window.contentView = hosting
        settle()
    }
    func settle(_ s: TimeInterval = 0.6) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: s))
        window.contentView?.layoutSubtreeIfNeeded()
    }
    var rims: Int { tracker.registeredCount }
    /// Presence metric (R1): every NSView under the hosting view, recursively.
    var views: Int {
        func count(_ v: NSView) -> Int { 1 + v.subviews.reduce(0) { $0 + count($1) } }
        return window.contentView.map(count) ?? 0
    }
    func close() { window.contentView = nil; window.close(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
}

/// Each page alone; no `default:`, so a new `Page` case fails to compile until this test is extended.
@MainActor @ViewBuilder
private func pageAlone(_ p: Page, _ m: AppModel, _ r: NavigationRouter) -> some View {
    switch p {
    case .home: HomeView(model: m, router: r, width: width, tier: tier)
    case .cpu: CPUPage(model: m, router: r)
    case .memory: MemoryPage(model: m, router: r, narrow: breakpoints.narrow)
    case .storage: StoragePage(model: m, router: r, breakpoints: breakpoints)
    case .battery: BatteryPage(model: m, router: r, narrow: breakpoints.narrow)
    case .security: SecurityPage(model: m, router: r, narrow: breakpoints.narrow)
    case .backups: BackupsPage(model: m, router: r, narrow: breakpoints.narrow)
    case .system: SystemPage(model: m, router: r)
    case .history: HistoryPage(model: m, router: r, narrow: breakpoints.narrow)
    }
}

@MainActor
private func router(_ p: Page) -> NavigationRouter {
    let r = NavigationRouter()
    if p != .home { r.navigate(to: Destination(p)) }
    return r
}

extension SerialTests {
    @Suite struct HiddenContentTests {
        @MainActor @Test func onlyTheShownPageIsMountedAndTracked() throws {
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            let savedLanguage = L10nStore.shared.language
            L10nStore.shared.language = .en
            defer { L10nStore.shared.language = savedLanguage }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-hidden-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let m = AppModel(dataDirectory: dir)
            m.applyVisualFixture()

            // 1. Expected counts: each page hosted alone.
            var expectedRims: [Page: Int] = [:]
            var expectedViews: [Page: Int] = [:]
            for p in Page.allCases {
                let h = Host(pageAlone(p, m, router(p)))
                expectedRims[p] = h.rims
                expectedViews[p] = h.views
                h.close()
            }

            // 2. Controls: a Home left mounted must change both metrics.
            #expect(expectedRims[.home]! > 0, "Home registers rims, so a Home left mounted changes the rim count")
            #expect(expectedViews[.home]! >= 50, "Home is about 100 NSViews (findings C5), so a Home left mounted changes the view count")

            func check(_ h: Host, _ p: Page, _ label: String) {
                #expect(h.rims == expectedRims[p], "\(label): only the page's rims")
                #expect(h.views <= expectedViews[p]! + slack, "\(label): nothing else mounted")
            }

            // 3. One MacContentView at Home.
            let r = NavigationRouter()
            let h = Host(MacContentView(model: m, router: r, width: width, tier: tier, breakpoints: breakpoints))
            check(h, .home, "home")

            // 4. Every page, with the report over it, then Back.
            for p in Page.allCases where p != .home {
                r.navigate(to: Destination(p))
                h.settle()
                check(h, p, "\(p)")
                r.isReportShown = true
                h.settle(0.3)
                check(h, p, "\(p) + report")
                r.isReportShown = false
                r.back()
                h.settle()
                check(h, .home, "Back from \(p)")
            }

            // 5. Report over Home: Home stays mounted (N1 = A).
            r.isReportShown = true
            h.settle(0.3)
            check(h, .home, "home + report")
            h.close()
        }
    }
}
