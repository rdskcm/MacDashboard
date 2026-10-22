// Views/InterimSectionPage.swift
// REDESIGN-HOME (stage B): until each section page is redesigned in its own stage, a section opens
// on this interim page — a DS3 page bar (Back chip, icon, name, sub line, tag) over the section's
// EXISTING cards, unchanged. Each later page stage replaces exactly one case of `cards`.
// Only History still renders here; every other section has its own page.
// `Destination.focus`, `foldersSegment` and `historyMetric` are ignored here.

import SwiftUI

@MainActor
struct InterimSectionPage: View {
    let model: DashboardModel
    let page: Page
    let windowWidth: CGFloat
    let onConfirmShown: (Bool) -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { cards }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) { InterimPageBar(model: model, page: page, onBack: onBack) }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
        .onDisappear { onConfirmShown(false) }
    }

    /// KPI tiles keep `.frame(maxWidth: .infinity)` in an `HStack`, never a lazy container (`live-list-identity`).
    @ViewBuilder private var cards: some View {
        switch page {
        case .home:
            EmptyView()
        case .cpu:
            // .cpu renders CPUPage (MainDashboardView), never this page.
            EmptyView()
        case .memory:
            // .memory renders MemoryPage (MainDashboardView), never this page.
            EmptyView()
        case .storage:
            // .storage renders StoragePage (MainDashboardView), never this page.
            EmptyView()
        case .battery:
            // .battery renders BatteryPage (MainDashboardView), never this page.
            EmptyView()
        case .security:
            // .security renders SecurityPage (MainDashboardView), never this page.
            EmptyView()
        case .backups:
            // .backups renders BackupsPage (MainDashboardView), never this page.
            EmptyView()
        case .system:
            // .system renders SystemPage (MainDashboardView), never this page.
            EmptyView()
        case .history:
            HistoryRestartNotice(model: model)
            HistoryCard(model: model)
        }
    }
}

// MARK: - Page bar

/// The interim page's bar: `SectionPageBar` fed from the Home tile of the page (sub line and tag).
@MainActor
private struct InterimPageBar: View {
    let model: DashboardModel
    let page: Page
    let onBack: () -> Void

    var body: some View {
        let tile = HomeInput.tiles(model).first { $0.page == page }
        SectionPageBar(symbol: page.symbol, title: page.title, sub: tile?.sub,
                       subIsFailure: tile?.subIsFailure ?? false, onBack: onBack) {
            if let tile {
                Group {
                    if tile.skeleton {
                        HomeShimmerCapsule()
                    } else {
                        DS3Tag(tone: tile.tagTone.ds3Tag, text: tile.tagText).help(tile.tagText)
                    }
                }
            }
        } trailing: {
            EmptyView()
        }
    }
}
