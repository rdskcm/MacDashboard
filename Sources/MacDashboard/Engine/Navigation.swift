// Engine/Navigation.swift
// REDESIGN-FOUNDATION: the main window's navigation state (handoff 00 §5): pages, the cards a
// deep link can focus, the page state a link hands over, and Back. Pure; covered by tests.
import Foundation
import Observation

/// Content mode of the main window (header «This Mac | iPhone»).
enum AppMode: Hashable, Sendable {
    case mac, iphone
}

/// This Mac pages. Settings is its own window, never a page.
enum Page: String, CaseIterable, Hashable, Sendable {
    case home, cpu, memory, storage, battery, security, backups, system, history

    /// Cards a deep link can focus on this page, in on-page order (handoff swiftui/03–10).
    var cards: [CardID] {
        switch self {
        case .home: return []
        case .cpu: return [.cpu, .procs]
        case .memory: return [.usage, .comp, .procs]
        case .storage: return [.disk, .folders, .smart]
        case .battery: return [.batnow, .bathero, .batchg, .batlife, .batid, .bathist]
        case .security: return [.protect, .updates, .crashes]
        case .backups: return [.tm, .claude]
        case .system: return [.sleep, .auto, .brew, .energy]
        case .history: return [.hist]
        }
    }
}

/// Handoff `focus` card ids. `procs` is on both the CPU and the Memory page.
enum CardID: String, CaseIterable, Hashable, Sendable {
    case cpu, procs, usage, comp, disk, folders, smart, protect, updates, crashes, tm, claude
    case sleep, auto, brew, energy, batnow, bathero, batchg, batlife, batid, bathist, hist
}

/// Storage › Folders segmented control (05-storage «Home | System»).
enum FoldersSegment: String, CaseIterable, Hashable, Sendable {
    case home, system
}

// History chart metric (10-history «Disk | Battery | Cycles | Swap»): `HistoryMetric` in Engine/HistorySeries.swift.

/// Where a navigation goes. A focus card or page state that does not belong to `page` is dropped.
struct Destination: Equatable, Sendable {
    let page: Page
    let focus: CardID?
    let foldersSegment: FoldersSegment?
    let historyMetric: HistoryMetric?

    init(_ page: Page, focus: CardID? = nil,
         foldersSegment: FoldersSegment? = nil, historyMetric: HistoryMetric? = nil) {
        self.page = page
        self.focus = focus.flatMap { page.cards.contains($0) ? $0 : nil }
        self.foldersSegment = page == .storage ? foldersSegment : nil
        self.historyMetric = page == .history ? historyMetric : nil
    }

    static let home = Destination(.home)
}

@MainActor
@Observable
final class NavigationRouter {
    var mode: AppMode = .mac
    /// REDESIGN-REPORT: the Report sheet is presented while this is true (`MainDashboardView` `.sheet(isPresented:)`).
    var isReportShown = false
    private(set) var destination: Destination = .home
    /// +1 on every navigation, a repeat of the current destination included, so a page can
    /// re-run scroll + focus pulse for a second tap on the same deep link.
    private(set) var navigationSerial = 0
    /// REDESIGN-CPU D17: true while an inline destructive confirm owns Esc; MainDashboardView then removes the Esc/⌘[ Back shortcuts.
    var isInlineConfirmOpen = false

    var canGoBack: Bool { destination.page != .home || isReportShown }

    /// Shows `destination` in This Mac mode, in place of an open report.
    func navigate(to destination: Destination) {
        mode = .mac
        isReportShown = false
        isInlineConfirmOpen = false
        self.destination = destination
        navigationSerial += 1
    }

    /// Back chip, Esc, ⌘[: the sheet closes (the page underneath stays); a section page returns to Home;
    /// on Home it does nothing.
    @discardableResult
    func back() -> Bool {
        guard canGoBack else { return false }
        if isReportShown {
            isReportShown = false
            return true
        }
        navigate(to: .home)
        return true
    }
}
