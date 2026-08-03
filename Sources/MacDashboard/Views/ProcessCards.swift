// Views/ProcessCards.swift
// Процессы card (LIVE): a single compact clickable process list, switchable
// between CPU and memory ranking via a sliding segmented control, with a
// single-expansion accordion (only rows with a known PID are expandable).
// Expanding a row fetches on-demand detail (path, thread count) via
// ProcessInspector and offers Reveal-in-Finder / Quit (SIGTERM) / Force Quit
// (SIGKILL). No energy metric anywhere — CPU/mem only.

import SwiftUI
import AppKit

/// Which ProcEntry field drives a ProcessListCard's row gauge/bold value —
/// `.cpu` reads CPU%, `.mem` reads memory bytes (the other field becomes the
/// row's dimmer secondary annotation). `Hashable` so `DSSlidingSegmented<T>`
/// (Views/DesignSystem.swift) can track the current selection.
enum Metric: Hashable { case cpu, mem }

/// Shared curve for the row gauge width transition AND row-reorder movement —
/// deliberately the SAME `Animation` value for both, so a row and its own
/// gauge move as one object when a live tick both re-sorts and re-values the
/// list (prototype's `cubic-bezier(0.22, 0.61, 0.36, 1)`, 0.8 s).
private let processRowMotion = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.8)

// MARK: - Shared list card

/// Single entry point (v2 restyle, Spec §6): one card, `CPU | Память` sliding
/// segmented control in the header's trailing slot (mirrors how
/// `ChartOrTableCard` places its trailing content in `CardChrome`). Rows are
/// read live off `model.topCPU`/`model.topMem` inside the body every tick —
/// never snapshotted into `@State` — so whichever metric is selected keeps
/// ticking live.
struct ProcessListCard: View {
    let model: DashboardModel

    @State private var procMetric: Metric = .cpu
    // Single-expansion accordion: expanding one row collapses any other.
    // Switching metric also collapses it — the accordion never carries a PID
    // from the other list.
    @State private var expandedPID: Int32? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [ProcEntry] {
        procMetric == .cpu ? model.topCPU : model.topMem
    }

    /// Row gauges are proportional to the FIRST row's value (rows already arrive
    /// sorted descending by `procMetric` from LiveCollector.sampleProcesses).
    private var maxValue: Double {
        guard let first = rows.first else { return 0 }
        switch procMetric {
        case .cpu: return first.cpu ?? 0
        case .mem: return Double(first.memBytes ?? 0)
        }
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                CardChrome(title: L.processesTitle, trailing: { metricControl }) {
                    SectionStateView(done: false)
                }
            } else {
                CardChrome(title: L.processesTitle, caption: L.processListCaption, trailing: { metricControl }) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 0) {
                                ProcessRowView(
                                    row: row, primary: procMetric, maxValue: maxValue,
                                    expanded: row.pid != nil && expandedPID == row.pid,
                                    onTap: {
                                        guard let pid = row.pid else { return }
                                        expandedPID = (expandedPID == pid) ? nil : pid
                                    }
                                )
                                if let pid = row.pid, expandedPID == pid {
                                    ProcessDetailView(row: row)
                                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    }
                    .animation(
                        reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
                        value: expandedPID
                    )
                    // Row reordering (a live tick re-sorting `rows`) moves with the
                    // SAME curve/duration as the gauge width transition below, so a
                    // row and its own gauge travel together instead of the row
                    // snapping to its new slot while the gauge is still animating —
                    // that mismatch is what let the gauge fill visibly detach from
                    // its row. `nil` under Reduce Motion: reordering is instant.
                    .animation(reduceMotion ? nil : processRowMotion, value: rows)
                }
            }
        }
        .onChange(of: procMetric) { expandedPID = nil }
    }

    private var metricControl: some View {
        DSSlidingSegmented(options: [Metric.cpu, .mem], selection: $procMetric) { m in
            m == .cpu ? L.processSegCPU : L.processSegMem
        }
        .frame(width: 168, height: 26)
        .accessibilityLabel(L.processesMetricA11y)
    }
}

// MARK: - Row (compact, gauge behind content)

private struct ProcessRowView: View {
    let row: ProcEntry
    let primary: Metric
    let maxValue: Double
    let expanded: Bool
    let onTap: () -> Void

    @State private var hovering = false
    // Row width, captured once via `onGeometryChange` (below) instead of read
    // live from a `GeometryReader` sitting inside the animated gauge subtree.
    // A `GeometryReader` inside a view that's simultaneously (a) reordering
    // within its `ForEach` and (b) mid-way through the `.animation(value:)`
    // width transition reports its size as part of that SAME transaction —
    // for one committed frame it can hand the animated `RoundedRectangle` a
    // stale/transitional size (and, since GeometryReader top-leading-aligns
    // its content by default, a collapsed height reads as a thin mis-placed
    // sliver instead of a properly clipped bar). Caching the width in
    // `@State` and feeding the animated rectangle from that plain `CGFloat`
    // removes GeometryReader from the animated subtree entirely, so its
    // geometry read can no longer race the reorder.
    @State private var rowWidth: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryValue: Double {
        switch primary {
        case .cpu: return row.cpu ?? 0
        case .mem: return Double(row.memBytes ?? 0)
        }
    }
    private var primaryText: String {
        switch primary {
        case .cpu: return row.cpu.map { fmtNum($0, decimals: 1) + "%" } ?? "—"
        case .mem: return fmtBytes(row.memBytes)
        }
    }
    private var secondaryText: String {
        switch primary {
        case .cpu: return "· " + fmtBytes(row.memBytes)
        case .mem: return "· CPU " + (row.cpu.map { fmtNum($0, decimals: 1) + "%" } ?? "—")
        }
    }
    private var gaugeColor: Color {
        primary == .cpu ? SeriesPalette.s1 : SeriesPalette.s2
    }
    private var isExpandable: Bool { row.pid != nil }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9).fill(DS.row)
            if maxValue > 0 {
                RoundedRectangle(cornerRadius: 9)
                    .fill(gaugeColor.opacity(0.22))
                    .frame(width: max(0, rowWidth * CGFloat(min(primaryValue / maxValue, 1))))
                    .animation(reduceMotion ? nil : processRowMotion, value: primaryValue)
            }
            HStack(spacing: 6) {
                if isExpandable {
                    DSDisclosureBars(expanded: expanded)
                }
                Text(row.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(DS.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(primaryText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(DS.inkSoft)
                Text(secondaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.muted)
            }
            .padding(.horizontal, 9)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { newWidth in
            rowWidth = newWidth
        }
        .frame(height: 27)
        // Hover highlight only for expandable rows — DS.track token (prototype's
        // `style-hover="background:var(--track)"`), 0.14 s ease transition
        // (already Reduce-Motion-safe: color-only).
        .background(isExpandable && hovering ? DS.track : Color.clear)
        .animation(.easeInOut(duration: 0.14), value: hovering)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onHover { isHovering in
            guard isExpandable else { return }
            if isHovering {
                hovering = true
                NSCursor.pointingHand.push()
            } else {
                hovering = false
                NSCursor.pop()
            }
        }
        .onTapGesture { onTap() }
    }
}

// MARK: - Expanded detail panel

private struct ProcessDetailView: View {
    let row: ProcEntry

    @State private var detail: ProcDetail?
    @State private var loading = true
    @State private var showForceQuitConfirm = false
    @State private var signalError: String? = nil

    private var pid: Int32 { row.pid ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L.processLoadingDetails).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                    GridRow {
                        Text("PID").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(String(pid)).font(.system(size: 11.5))
                    }
                    GridRow {
                        Text(L.processDetailThreads).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(detail?.threads.map(String.init) ?? "—").font(.system(size: 11.5))
                    }
                    GridRow {
                        Text("CPU").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(row.cpu.map { fmtNum($0, decimals: 1) + "%" } ?? "—").font(.system(size: 11.5))
                    }
                    GridRow {
                        Text(L.processDetailMemory).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(fmtBytes(row.memBytes)).font(.system(size: 11.5))
                    }
                    GridRow {
                        Text(L.processDetailPath).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(detail?.path ?? "—")
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(detail?.path ?? "")
                    }
                }

                HStack(spacing: 8) {
                    Button(L.reportShowInFinder) {
                        guard let path = detail?.path else { return }
                        // Shared rule (AdviceActionRunner.reveal): plain folders open, files
                        // and bundles are selected in their enclosing folder — `revealTarget`
                        // returns the .app bundle for app-hosted executables, so the package
                        // branch there is what keeps this from launching the app.
                        AdviceActionRunner.reveal(ProcessInspector.revealTarget(for: path))
                    }
                    .disabled(detail?.path == nil)
                    .accessibilityLabel(L.processRevealA11y(row.name))

                    Button(L.processQuit) {
                        signalError = ProcessInspector.sendSignal(SIGTERM, to: pid)
                            ? nil : L.processSignalError
                    }
                    .accessibilityLabel(L.processTerminateA11y(row.name))

                    Button(L.processForceQuit, role: .destructive) {
                        showForceQuitConfirm = true
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel(L.processKillA11y(row.name))
                }
                .controlSize(.small)
                .confirmationDialog(
                    L.processForceQuitTitle(row.name),
                    isPresented: $showForceQuitConfirm
                ) {
                    Button(L.processForceQuitConfirm, role: .destructive) {
                        signalError = ProcessInspector.sendSignal(SIGKILL, to: pid)
                            ? nil : L.processSignalError
                    }
                }

                if let signalError {
                    Text(signalError).font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 19, bottom: 8, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        // Keyed on pid (stable across live ticks), NOT the whole `row` — path/threads
        // are only refetched when the expanded process changes, while `row.cpu`/
        // `row.memBytes` above still read live off the (re-passed-in, unchanged-id)
        // `row` value on every tick.
        .task(id: row.pid) {
            loading = true
            detail = nil
            guard let pid = row.pid else { loading = false; return }
            // Off the main actor: proc_pidpath/proc_pidinfo are cheap syscalls but
            // the `ps -M` fallback shells out (up to 3s) — never block the UI on it.
            let fetched = await Task.detached { ProcessInspector.detail(pid: pid) }.value
            detail = fetched
            loading = false
        }
    }
}
