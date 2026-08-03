// Views/MainDashboardView.swift
// Header (title/sub/chips/refresh) + Обзор|Отчёт tab picker. Обзор = ScrollView
// opening with Рекомендации (the user's stated top-priority card), then the live
// KPI tile row and the card layout: "wide" cards —
// Память, История — sit in their own full-width rows; below that,
// three side-by-side pair rows (each an HStack of two equal-width cards) group
// related cards instead of a row-aligning LazyVGrid or a height-imbalanced
// two-column masonry: Процессы (CPU | память), Хранилище (домашняя папка |
// служебные папки), and Система (Безопасность/Автозапуск/Энергия/Обслуживание |
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
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            DSSlidingSegmented(options: [Tab.overview, .report], selection: $tab) { t in
                switch t {
                case .overview: return L.mainTabOverview
                case .report: return L.mainTabReport
                }
            }
            .frame(maxWidth: 260)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            switch tab {
            case .overview: overview
            case .report: ReportTab(model: model)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: L10nStore.shared.language) { model.refreshReport() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.appWindowTitle)
                    .font(.title3.bold())
                    .tracking(-0.285) // 19 pt · −0.015em
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HeaderChipsView(model: model)
        }
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
            VStack(alignment: .leading, spacing: 16) {
                AttentionSummaryCard(model: model)

                Text(L.overviewKickerMetrics).dsKicker()
                kpiRow

                Text(L.overviewKickerMemory).dsKicker()
                MemoryCard(model: model)

                Text(L.overviewKickerProcesses).dsKicker()
                ProcessListCard(model: model).frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 12) {
                    HomeDirsCard(model: model).frame(maxWidth: .infinity, alignment: .leading)
                    ServiceDirsCard(model: model).frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(L.overviewKickerSystem).dsKicker()
                HStack(alignment: .top, spacing: 12) {
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

    // Five equal columns (the CSS `minmax(0,1fr)` fix): `GridItem(.flexible())`
    // divides the row width equally regardless of content, unlike `.adaptive`
    // which sizes columns to their content. `.flexible()` still has a 10pt
    // default minimum, so equal width depends on every tile's content being
    // shrinkable — see KPITileView's nowrap+ellipsis label and ellipsizable
    // "из N" slot.
    private var kpiRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            CPUTile(model: model)
            MemoryTile(model: model)
            SwapTile(model: model)
            DiskTile(model: model)
            BatteryTile(model: model)
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
    }

    // Status chip is bound to the live assessment — never a static severity/text
    // pair — so it can never disagree with `model.assessment`.
    private var statusIsGood: Bool { model.assessment.problems.isEmpty }
    private var statusHasCrit: Bool { model.assessment.problems.contains { $0.sev == .crit } }
    private var statusTone: Color { statusIsGood ? DS.green : (statusHasCrit ? DS.hot : DS.amber) }
    private var statusLabel: String { statusIsGood ? L.recommendationsAllGood : L.headerStatusNeedsAttention }

    private var refreshButton: some View {
        RainbowCapsuleButton(title: L.headerRefreshReport, busy: model.isCollectingReport, recipe: .overview) {
            model.refreshReport()
        }
        .accessibilityLabel(L.headerRefreshReport)
    }
}
