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

    // System band column-height balance: `bal > 0` means the left column is
    // taller (pad the right column inside SmartDisksCard), `bal < 0` means the
    // right column is taller (pad the left column just above the quiet strip).
    @State private var bal: CGFloat = 0
    @State private var leftMeasured: CGFloat = 0
    @State private var rightMeasured: CGFloat = 0

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

    // MARK: Toolbar (single row: title block · leading-anchored tab control · flexible gap · chips/status/refresh)

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 16) {
            titleBlock
                .layoutPriority(1)
            // Anchored immediately after the title at a fixed gap (spacing: 16 above) —
            // this control's x position must never depend on window width. All slack
            // and all shrink pressure live to its right, past the flexible Spacer below.
            DSSlidingSegmented(options: [Tab.overview, .report], selection: $tab, size: .tabs) { t in
                switch t {
                case .overview: return L.mainTabOverview
                case .report: return L.mainTabReport
                }
            }
            .layoutPriority(2)
            Spacer(minLength: 12)
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
            subtitleView
        }
    }

    /// Tiered subtitle: model · chip · RAM · macOS ver (build) → …ver → …RAM → …chip → model.
    /// Mirrors `HeaderChipsView`'s `ViewThatFits` idiom — the row DROPS a trailing
    /// segment when it doesn't fit rather than ellipsizing mid-string, so `.fixedSize`
    /// on every tier forces `ViewThatFits` to measure intrinsic width and pick a tier,
    /// not truncate one. `L.mainCollectingInfo` is a single segment, so it's one tier.
    private var subtitleView: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(subtitleTiers.indices, id: \.self) { i in
                Text(subtitleTiers[i])
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .truncationMode(i == subtitleTiers.count - 1 ? .tail : .head)
            }
        }
    }

    private var subtitleTiers: [String] {
        guard let sys = model.report.system else { return [L.mainCollectingInfo] }
        let modelName = sys.modelName
        let chip = sys.chip
        let ram = sys.memBytes.map { tight(fmtBytesParts($0)) }
        let osFull: String? = sys.osVersion.map { ver in
            let build = sys.osBuild.map { " (\($0))" } ?? ""
            return "macOS \(ver)\(build)"
        }
        let osShort: String? = sys.osVersion.map { "macOS \($0)" }

        func join(_ parts: [String?]) -> String? {
            let present = parts.compactMap { $0 }
            return present.isEmpty ? nil : present.joined(separator: " · ")
        }

        let candidates: [String?] = [
            join([modelName, chip, ram, osFull]),
            join([modelName, chip, ram, osShort]),
            join([modelName, chip, ram]),
            join([modelName, chip]),
            join([modelName]),
        ]

        // Optional fields collapse out of the join, so adjacent tiers can come out
        // identical (e.g. no osBuild ⇒ tier 1 == tier 2; no chip ⇒ tier 3 == tier 4).
        // Dedup consecutive duplicates so ViewThatFits never wastes a measurement slot.
        var tiers: [String] = []
        for t in candidates.compactMap({ $0 }) where tiers.last != t {
            tiers.append(t)
        }
        return tiers.isEmpty ? [L.mainCollectingInfo] : tiers
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
                systemBand

                Text(L.overviewKickerHistory).dsKicker()
                HistoryCard(model: model)
            }
            .padding(20)
        }
        .background(DS.ground)
    }

    // MARK: System band (Security/Autostart/Energy/Maintenance | SMART/Time Machine)

    /// Security and Updates/Crashes move out of their fixed left-column slots
    /// once quiet (nothing to report) and collapse into `QuietStrip` rows
    /// instead — a loud card only occupies column space while it has something
    /// to say. The two columns can therefore end up different heights, which
    /// `bal` corrects by padding whichever column is shorter.
    private var systemBand: some View {
        let q = QuietState.quiet(report: model.report)
        let sections = quietSections(q)
        let stripPresent = !sections.isEmpty

        return LazyVGrid(columns: Self.twoColumns, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                AutostartCard(model: model)
                EnergyCard(model: model)
                MaintenanceCard(model: model)
                if q.security != .quiet { SecurityCard(model: model, state: q) }
                if q.updates != .quiet { UpdatesCrashesCard(model: model, state: q) }
                if bal < 0 { Color.clear.frame(height: -bal) }
                QuietStrip(sections: sections)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                leftMeasured = newHeight
                recomputeBalance(stripPresent: stripPresent)
            }

            VStack(alignment: .leading, spacing: 12) {
                SmartDisksCard(model: model, balanceSpacer: max(0, bal))
                TimeMachineCard(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                rightMeasured = newHeight
                recomputeBalance(stripPresent: stripPresent)
            }
        }
        .onChange(of: stripPresent) { recomputeBalance(stripPresent: stripPresent) }
    }

    private func quietSections(_ q: QuietState) -> [QuietSection] {
        var sections: [QuietSection] = []
        if q.security == .quiet {
            sections.append(QuietSection(id: "sec", title: L.securityTitle, status: L.quietStatusAllEnabled,
                                          rows: securityRows(model.report.security ?? SecurityState())))
        }
        if q.updates == .quiet {
            sections.append(QuietSection(id: "maint", title: L.quietUpdatesTitle, status: L.quietStatusAllClear,
                                          rows: updatesRows(updates: model.report.updates ?? [], crashes: model.report.crashes ?? [])))
        }
        return sections
    }

    /// Subtracts our own spacer injection from each side's measured height
    /// before comparing, so the two-way feedback loop (bal → spacer → height →
    /// bal) converges in a single pass instead of needing repeated iterations.
    private func recomputeBalance(stripPresent: Bool) {
        guard stripPresent else { if bal != 0 { bal = 0 }; return }
        let naturalLeft = leftMeasured - max(0, -bal)
        let naturalRight = rightMeasured - max(0, bal)
        let raw = naturalLeft - naturalRight
        let next: CGFloat = abs(raw) > 44 ? 0 : (raw * 2).rounded() / 2
        if abs(next - bal) >= 0.5 { bal = next }
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
