// Views/InterimSectionPage.swift
// REDESIGN-HOME (stage B): until each section page is redesigned in its own stage, a section opens
// on this interim page — a DS3 page bar (Back chip, icon, name, sub line, tag) over the section's
// EXISTING cards, unchanged. Each later page stage replaces exactly one case of `cards`.
// `Destination.focus`, `foldersSegment` and `historyMetric` are ignored here.

import SwiftUI

@MainActor
struct InterimSectionPage: View {
    let model: DashboardModel
    let page: Page
    let windowWidth: CGFloat
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
    }

    /// KPI tiles keep `.frame(maxWidth: .infinity)` in an `HStack`, never a lazy container (`live-list-identity`).
    @ViewBuilder private var cards: some View {
        switch page {
        case .home:
            EmptyView()
        case .cpu:
            HStack(alignment: .top, spacing: 12) { CPUTile(model: model).frame(maxWidth: .infinity) }
            ProcessListCard(model: model, initialMetric: .cpu)
        case .memory:
            InterimMemoryTiles(model: model)
            MemoryCard(model: model)
            ProcessListCard(model: model, initialMetric: .mem)
        case .storage:
            HStack(alignment: .top, spacing: 12) { DiskTile(model: model).frame(maxWidth: .infinity) }
            LegacySpaceTips(model: model)
            FoldersCard(model: model, initialTab: .home)
            SmartDisksCard(model: model)
        case .battery:
            HStack(alignment: .top, spacing: 12) { BatteryTile(model: model).frame(maxWidth: .infinity) }
        case .security:
            InterimSecurityCards(model: model)
        case .backups:
            TimeMachineCard(model: model)
            ClaudeBackupCard(model: model)
        case .system:
            AutostartCard(model: model)
            EnergyCard(model: model)
            MaintenanceCard(model: model)
        case .history:
            HistoryRestartNotice(model: model)
            HistoryCard(model: model)
        }
    }
}

/// Memory and (when there is swap) Swap tiles. Own struct: `SwapTile.isVisible` reads the live `model.swap`,
/// which must not make the whole page an observer of the 2 s tick (see `KPIRowView`).
@MainActor
private struct InterimMemoryTiles: View {
    let model: DashboardModel

    var body: some View {
        let showSwap = SwapTile.isVisible(model)
        HStack(alignment: .top, spacing: 12) {
            MemoryTile(model: model).frame(maxWidth: .infinity)
            if showSwap { SwapTile(model: model).frame(maxWidth: .infinity) }
        }
    }
}

/// Security and Updates/Crashes cards, collapsing into `QuietStrip` rows once quiet — the code that lived in
/// `MainDashboardView.systemBand` / `quietSections`, moved here unchanged.
@MainActor
private struct InterimSecurityCards: View {
    let model: DashboardModel

    var body: some View {
        let q = QuietState.quiet(report: model.report)
        let sections = quietSections(q)
        if q.security != .quiet { SecurityCard(model: model, state: q) }
        if q.updates != .quiet { UpdatesCrashesCard(model: model, state: q) }
        if !sections.isEmpty { QuietStrip(sections: sections) }
    }

    private func quietSections(_ q: QuietState) -> [QuietSection] {
        var sections: [QuietSection] = []
        if q.security == .quiet {
            sections.append(QuietSection(id: "sec", title: L.securityTitle, status: L.quietStatusAllEnabled,
                                          rows: securityRows(model.report.security ?? SecurityState())))
        }
        if q.updates == .quiet {
            sections.append(QuietSection(id: "maint", title: L.quietUpdatesTitle, status: L.quietStatusAllClear,
                                          rows: updatesRows(updates: model.report.updates ?? [], crashes: model.report.crashes ?? []),
                                          checkedAt: model.report.updatesCheckedAt))
        }
        return sections
    }
}

// MARK: - Page bar

/// Pinned frosted bar (00 §4.2 / §8), the shape of `IPhoneDeviceView.header`.
@MainActor
private struct InterimPageBar: View {
    let model: DashboardModel
    let page: Page
    let onBack: () -> Void

    var body: some View {
        let tile = HomeInput.tiles(model).first { $0.page == page }
        HStack(spacing: 14) {
            back
            HomeIconTile(symbol: page.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.4)
                    .lineLimit(1)
                if let tile {
                    Text(tile.sub)
                        .font(.system(size: 13))
                        .foregroundStyle(tile.subIsFailure ? DS3.hotInk : DS3.muted)
                        .lineLimit(1)
                        .help(tile.sub)
                }
            }
            if let tile {
                Group {
                    if tile.skeleton {
                        HomeShimmerCapsule()
                    } else {
                        DS3Tag(tone: tile.tagTone.ds3Tag, text: tile.tagText).help(tile.tagText)
                    }
                }
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(DS3.bar)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
    }

    private var back: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                Text(L.commonThisMac)
            }
            .padding(.leading, -4)
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 13, topRim: 1))
        .accessibilityLabel(L.homeBackA11y)
        .accessibilityIdentifier("page-back")
        .layoutPriority(1)
    }
}

// MARK: - Legacy space tips (decision 1 = option A)

/// Today's Downloads / Trash / Caches shortcuts, shown on the interim Storage page while the Home rows
/// no longer carry them: `Assessment.capsules` whose action is `.revealPath` or `.emptyTrash`. The Storage
/// page stage replaces this with the redesigned cards.
@MainActor
struct LegacySpaceTips: View {
    let model: DashboardModel

    @State private var dispatch: AdviceActionDispatch

    init(model: DashboardModel) {
        self.model = model
        _dispatch = State(wrappedValue: AdviceActionDispatch(model: model))
    }

    private var capsules: [TipCapsule] {
        model.assessment.capsules.filter {
            switch $0.action {
            case .revealPath?, .emptyTrash?: return true
            default: return false
            }
        }
    }

    var body: some View {
        let caps = capsules
        if !caps.isEmpty || dispatch.trashError != nil {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(caps) { c in tip(c) }
                }
                if let e = dispatch.trashError {
                    Text(e).font(.system(size: 12.5)).foregroundStyle(DS3.hotInk)
                    if let pane = dispatch.trashErrorPane {
                        RainbowCapsuleButton(title: L.adviceTrashOpenAutomation, size: .card) {
                            AdviceActionRunner.openPane(pane)
                        }
                        .accessibilityLabel(L.adviceTrashOpenAutomation)
                    }
                }
            }
            .adviceActionDialogs(dispatch)
        }
    }

    private func tip(_ c: TipCapsule) -> some View {
        let busy = dispatch.busy(for: c.action)
        let done = dispatch.done(c.id)
        return Button {
            if let a = c.action { dispatch.handle(a, id: c.id) }
        } label: {
            Text("\(c.object) \(c.value)" + (done ? " \u{2713}" : ""))
                .dsSwapInPlace(busy) { ProgressView().controlSize(.small) }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
        .disabled(busy || done)
        .help(c.explanation)
        .accessibilityLabel("\(c.verb) \(c.object)")
    }
}
