// Views/MainDashboardView.swift
// Header (title/sub/chips/refresh) + Обзор|Отчёт tab picker. Обзор = ScrollView
// opening with Рекомендации (the user's stated top-priority card), then the live
// KPI tile row and the card layout: "wide" cards —
// Память, История — sit in their own full-width rows; below that,
// three side-by-side pair rows (each an HStack of two equal-width cards) group
// related cards instead of a row-aligning LazyVGrid or a height-imbalanced
// two-column masonry: Процессы (CPU | память) | Папки (домашняя | служебные),
// and Система (Безопасность/Автозапуск/Энергия/Обслуживание |
// Диски (SMART)/Time Machine).

import SwiftUI
import Charts

@MainActor
struct MainDashboardView: View {
    var model: DashboardModel

    private enum Tab { case overview, report }
    @State private var tab: Tab = .overview

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            switch tab {
            case .overview: overview
            case .report: ReportTab(model: model)
            }
        }
        .onChange(of: L10nStore.shared.language) { model.refreshReport() }
    }

    // MARK: Toolbar (single row: title block · centered tab control · chips/status/refresh)

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 16) {
            titleBlock
                .layoutPriority(1)
            Spacer()
            // Primary navigation must always win its ideal width over title and chips.
            DSSlidingSegmented(options: [Tab.overview, .report], selection: $tab, size: .tabs) { t in
                switch t {
                case .overview: return L.mainTabOverview
                case .report: return L.mainTabReport
                }
            }
            .layoutPriority(2)
            Spacer(minLength: 8)
            // No layoutPriority here (default 0): chips own the progressive-hiding
            // ViewThatFits tiers and must be the first child to lose space.
            HeaderChipsView(model: model)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(toolbarChrome)
    }

    /// Fill `DS.glass2` layered over the same `.regularMaterial` blur backdrop
    /// `dsCardSurface()` uses (DesignSystem.swift), a bottom hairline border, and
    /// a 1 pt inset top highlight using the same fade-to-clear stroke technique
    /// `dsCardSurface()` applies for its own sheen line — mirrored here on a
    /// plain (unrounded) rectangle since the toolbar spans the full width.
    private var toolbarChrome: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle().fill(DS.glass2)
        }
        .overlay(
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: DS.sheenLine, location: 0),
                            .init(color: .clear, location: 0.15),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.line).frame(height: 1)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.appWindowTitle)
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.285) // 19 pt · −0.015em
                .lineSpacing(1.9) // 19 pt · 1.1 line-height
                .lineLimit(1)
                .truncationMode(.tail)
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(DS.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minWidth: 170, alignment: .leading)
    }

    private var subtitle: String {
        guard let sys = model.report.system else { return L.mainCollectingInfo }
        var bits: [String] = []
        if let m = sys.modelName { bits.append(m) }
        if let chip = sys.chip { bits.append(chip) }
        if let mem = sys.memBytes { bits.append(fmtBytes(mem)) }
        if let ver = sys.osVersion {
            let build = sys.osBuild.map { " (\($0))" } ?? ""
            bits.append("macOS \(ver)\(build)")
        }
        return bits.isEmpty ? L.mainCollectingInfo : bits.joined(separator: " · ")
    }

    // MARK: Обзор

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AttentionSummaryCard(model: model)

                Text(L.overviewKickerMetrics).dsKicker()
                kpiRow

                Text(L.overviewKickerMemory).dsKicker()
                MemoryCard(model: model)

                LazyVGrid(columns: Self.twoColumns, spacing: 12) {
                    Text(L.overviewKickerProcesses).dsKicker().frame(maxWidth: .infinity, alignment: .leading)
                    Text(L.overviewKickerFolders).dsKicker().frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: Self.twoColumns, spacing: 12) {
                    ProcessListCard(model: model).frame(maxWidth: .infinity, alignment: .leading)
                    FoldersCard(model: model).frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(L.overviewKickerSystem).dsKickerCentered()
                LazyVGrid(columns: Self.twoColumns, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        SecurityCard(model: model)
                        AutostartCard(model: model)
                        EnergyCard(model: model)
                        MaintenanceCard(model: model)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        SmartDisksCard(model: model)
                        TimeMachineCard(model: model)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(L.overviewKickerHistory).dsKicker()
                HistoryCard(model: model)
            }
            .padding(20)
        }
        .background(DS.ground)
    }

    /// Two truly equal columns. `.frame(maxWidth:.infinity)` inside an HStack only
    /// splits leftovers AFTER each child's minimum is honoured, so a dense card
    /// (ProcessListCard) starves its neighbour; `GridItem(.flexible())` divides the
    /// row width equally regardless of content — same reasoning as `kpiRow`.
    private static let twoColumns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top),
    ]

    // Five equal columns (the CSS `minmax(0,1fr)` fix): `GridItem(.flexible())`
    // divides the row width equally regardless of content, unlike `.adaptive`
    // which sizes columns to their content. `.flexible()` still has a 10pt
    // default minimum, so equal width depends on every tile's content being
    // shrinkable — see KPITileView's nowrap+ellipsis label and ellipsizable
    // "из N" slot. Column count is now dynamic based on tile visibility.
    private var kpiRow: some View {
        let showSwap = SwapTile.isVisible(model)
        let showBattery = BatteryTile.isVisible(model)
        let count = 3 + (showSwap ? 1 : 0) + (showBattery ? 1 : 0)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count), spacing: 12) {
            CPUTile(model: model)
            MemoryTile(model: model)
            if showSwap { SwapTile(model: model) }
            DiskTile(model: model)
            if showBattery { BatteryTile(model: model) }
        }
    }
}

// Extracted from MainDashboardView so that only this small subtree re-executes
// on live ticks / assessment changes — it's the only place in the header that
// reads the model's live fields / assessment, so MainDashboardView.body itself no
// longer depends on them (avoids re-running the whole overview tree on every
// 3s live tick).
@MainActor
struct HeaderChipsView: View {
    let model: DashboardModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if let load = model.load, !load.isEmpty {
                    Chip(text: L.headerLoadChip(load.map { fmtNum($0, decimals: 2) }.joined(separator: " / "), model.ncpu))
                }
                if let uptime = model.report.system?.uptime {
                    Chip(text: L.headerUptimeChip(uptime))
                }
                SeverityChip(isGood: statusIsGood, tone: statusTone, label: statusLabel, hasCrit: statusHasCrit)
                refreshButton
            }
            HStack(spacing: 8) {
                if let uptime = model.report.system?.uptime {
                    Chip(text: L.headerUptimeChip(uptime))
                }
                SeverityChip(isGood: statusIsGood, tone: statusTone, label: statusLabel, hasCrit: statusHasCrit)
                refreshButton
            }
            HStack(spacing: 8) {
                SeverityChip(isGood: statusIsGood, tone: statusTone, label: statusLabel, hasCrit: statusHasCrit)
                refreshButton
            }
        }
    }

    // Status chip is bound to the live assessment — never a static severity/text
    // pair — so it can never disagree with `model.assessment`. Tone comes from
    // the SAME shared `tone(for:)` (SharedUI.swift) applied to the SAME
    // `summarySev` that AttentionSummaryCard's title dot reads, instead of a
    // second parallel "is this bad" computation — the two can no longer
    // disagree because they're reading one computed value through one function.
    private var statusIsGood: Bool { model.assessment.problems.isEmpty }
    private var statusHasCrit: Bool { model.assessment.summarySev == .crit || model.assessment.summarySev == .serious }
    private var statusTone: Color { tone(for: model.assessment.summarySev) }
    private var statusLabel: String { statusIsGood ? L.recommendationsAllGood : L.headerStatusNeedsAttention }

    private var refreshButton: some View {
        RainbowCapsuleButton(title: L.headerRefreshReport, busy: model.isCollectingReport, recipe: .overview, size: .primary) {
            model.refreshReport()
        }
        .accessibilityLabel(L.headerRefreshReport)
    }
}
