// Tests/MacDashboardTests/NavigationTests.swift
// REDESIGN-FOUNDATION: router and destination rules. Each test makes its own router.
import Foundation
import Testing
@testable import MacDashboard

@MainActor
struct NavigationTests {
    @Test func destinationNormalization() {
        #expect(Destination(.cpu, focus: .tm).focus == nil, "foreign focus dropped")
        #expect(Destination(.cpu, focus: .procs).focus == .procs, "cpu has procs")
        #expect(Destination(.memory, focus: .procs).focus == .procs, "memory has procs")
        #expect(Destination(.storage, focus: .folders, foldersSegment: .system).foldersSegment == .system, "storage keeps segment")
        #expect(Destination(.cpu, foldersSegment: .home).foldersSegment == nil, "segment dropped off storage")
        #expect(Destination(.history, historyMetric: .battery).historyMetric == .battery, "history keeps metric")
        #expect(Destination(.battery, historyMetric: .battery).historyMetric == nil, "metric dropped off history")
        #expect(Destination.home == Destination(.home), "home constant")
        #expect(Destination(.home, focus: .cpu).focus == nil, "home has no cards")
    }

    @Test func routerDefaults() {
        let r = NavigationRouter()
        #expect(r.mode == .mac, "mode mac")
        #expect(!r.isReportShown, "report hidden")
        #expect(r.destination == .home, "home")
        #expect(r.navigationSerial == 0, "serial 0")
        #expect(!r.canGoBack, "no back on home")
    }

    @Test func navigateShowsThisMacPage() {
        let r = NavigationRouter()
        r.mode = .iphone
        r.isReportShown = true
        r.navigate(to: Destination(.backups, focus: .claude))
        #expect(r.mode == .mac, "mode reset to mac")
        #expect(!r.isReportShown, "report closed")
        #expect(r.destination.page == .backups, "page")
        #expect(r.destination.focus == .claude, "focus")
        #expect(r.navigationSerial == 1, "serial 1")
        #expect(r.canGoBack, "can go back")
        r.navigate(to: Destination(.backups, focus: .claude))
        #expect(r.navigationSerial == 2, "repeat increments serial")
    }

    @Test func back() {
        let r = NavigationRouter()
        #expect(r.back() == false, "back on home is false")
        #expect(r.navigationSerial == 0, "serial unchanged")
        r.navigate(to: Destination(.storage))
        #expect(r.back() == true, "back from storage")
        #expect(r.destination == .home, "home after back")
        #expect(r.navigationSerial == 2, "serial 2")
        #expect(!r.canGoBack, "no back on home")
    }

    @Test func cardMap() {
        for c in CardID.allCases {
            #expect(Page.allCases.contains { $0.cards.contains(c) }, "card \(c) is on a page")
        }
        #expect(Page.home.cards.isEmpty, "home has no cards")
        let procsPages = Page.allCases.filter { $0.cards.contains(.procs) }
        #expect(procsPages == [.cpu, .memory], "procs on cpu and memory")
        for c in CardID.allCases where c != .procs {
            #expect(Page.allCases.filter { $0.cards.contains(c) }.count == 1, "card \(c) on exactly one page")
        }
        #expect(Page.allCases.map(\.cards.count).reduce(0, +) == 24, "24 page-card slots")
        #expect(CardID.allCases.count == 23, "23 card ids")
        #expect(Page.allCases.count == 9, "9 pages")
    }
}
