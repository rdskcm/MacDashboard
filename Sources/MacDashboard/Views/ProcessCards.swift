// Views/ProcessCards.swift
// Процессы по CPU / по памяти cards (LIVE): compact clickable process lists with
// a single-expansion accordion per card. Expanding a row (only rows with a known
// PID are expandable) fetches on-demand detail (path, thread count) via
// ProcessInspector and offers Reveal-in-Finder / Quit (SIGTERM) / Force Quit
// (SIGKILL). No energy metric anywhere — CPU/mem only.

import SwiftUI
import AppKit

/// Which ProcEntry field drives a ProcessListCard's row gauge/bold value — the
/// CPU card reads `.cpu`, the Mem card reads `.mem` (the other field becomes the
/// row's dimmer secondary annotation).
enum Metric { case cpu, mem }

// MARK: - Thin card wrappers (keep call sites in MainDashboardView unchanged)

struct ProcessesCPUCard: View {
    let model: DashboardModel
    var body: some View {
        ProcessListCard(title: L.processCpuTitle, rows: model.topCPU, primary: .cpu)
    }
}

struct ProcessesMemCard: View {
    let model: DashboardModel
    var body: some View {
        ProcessListCard(title: L.processMemTitle, rows: model.topMem, primary: .mem)
    }
}

// MARK: - Shared list card

struct ProcessListCard: View {
    let title: String            // L.processCpuTitle / L.processMemTitle
    let rows: [ProcEntry]
    let primary: Metric          // .cpu or .mem — which value drives the gauge & right-aligned bold value

    // Single-expansion accordion per card: expanding one row collapses any other.
    @State private var expandedPID: Int32? = nil

    /// Row gauges are proportional to the FIRST row's value (rows already arrive
    /// sorted descending by `primary` from LiveCollector.sampleProcesses).
    private var maxValue: Double {
        guard let first = rows.first else { return 0 }
        switch primary {
        case .cpu: return first.cpu ?? 0
        case .mem: return Double(first.memBytes ?? 0)
        }
    }

    var body: some View {
        if rows.isEmpty {
            CardChrome(title: title) { SectionStateView(done: false) }
        } else {
            CardChrome(title: title, caption: L.processListCaption) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 0) {
                            ProcessRowView(
                                row: row, primary: primary, maxValue: maxValue,
                                expanded: row.pid != nil && expandedPID == row.pid,
                                onTap: {
                                    guard let pid = row.pid else { return }
                                    expandedPID = (expandedPID == pid) ? nil : pid
                                }
                            )
                            if let pid = row.pid, expandedPID == pid {
                                ProcessDetailView(row: row)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: expandedPID)
            }
        }
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
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.035))
            GeometryReader { geo in
                if maxValue > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gaugeColor.opacity(0.18))
                        .frame(width: max(0, geo.size.width * CGFloat(min(primaryValue / maxValue, 1))))
                }
            }
            HStack(spacing: 6) {
                if isExpandable {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                Text(row.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(primaryText)
                    .font(.callout.monospacedDigit().weight(.semibold))
                Text(secondaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 24)
        .background(isExpandable && hovering ? Color.primary.opacity(0.06) : Color.clear)
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
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("PID").font(.caption2).foregroundStyle(.secondary)
                        Text(String(pid)).font(.caption2)
                    }
                    GridRow {
                        Text(L.processDetailThreads).font(.caption2).foregroundStyle(.secondary)
                        Text(detail?.threads.map(String.init) ?? "—").font(.caption2)
                    }
                    GridRow {
                        Text("CPU").font(.caption2).foregroundStyle(.secondary)
                        Text(row.cpu.map { fmtNum($0, decimals: 1) + "%" } ?? "—").font(.caption2)
                    }
                    GridRow {
                        Text(L.processDetailMemory).font(.caption2).foregroundStyle(.secondary)
                        Text(fmtBytes(row.memBytes)).font(.caption2)
                    }
                    GridRow {
                        Text(L.processDetailPath).font(.caption2).foregroundStyle(.secondary)
                        Text(detail?.path ?? "—")
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(detail?.path ?? "")
                    }
                }

                HStack(spacing: 8) {
                    Button(L.reportShowInFinder) {
                        guard let path = detail?.path else { return }
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: ProcessInspector.revealTarget(for: path))])
                    }
                    .disabled(detail?.path == nil)

                    Button(L.processQuit) {
                        signalError = ProcessInspector.sendSignal(SIGTERM, to: pid)
                            ? nil : L.processSignalError
                    }

                    Button(L.processForceQuit, role: .destructive) {
                        showForceQuitConfirm = true
                    }
                    .foregroundStyle(.red)
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
        .padding(8)
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
