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

/// 5-stop CPU heat ramp for the CPU-sorted list's row gauge (Spec: value-based
/// ramp, NOT the flat single-color fill the mem-sorted list uses). Evaluated at
/// each row's OWN cpu%/100 — independent of `maxValue`, which only drives the
/// gauge's WIDTH — so a busy row reads hot even when a busier row above it caps
/// the bar's fill fraction. No ramp/interpolation helper exists elsewhere in the
/// app to reuse: `Theme.swift`'s `SeriesPalette`/`tone(for:)` only pick one
/// discrete color per severity bucket, they don't lerp between stops — this is
/// a new, narrowly-scoped helper.
private let cpuGaugeRampStops: [(at: Double, r: Double, g: Double, b: Double)] = [
    (0.00, 74, 154, 232),
    (0.45, 46, 196, 160),
    (0.70, 224, 167, 46),
    (0.88, 226, 112, 58),
    (1.00, 220, 75, 62),
]

/// Linear-interpolates `cpuGaugeRampStops` at `fraction` (clamped 0...1) between
/// the two nearest stops.
private func cpuGaugeColor(_ fraction: Double) -> Color {
    let f = min(max(fraction, 0), 1)
    var lower = cpuGaugeRampStops[0]
    var upper = cpuGaugeRampStops[cpuGaugeRampStops.count - 1]
    for i in 0..<(cpuGaugeRampStops.count - 1) {
        if f >= cpuGaugeRampStops[i].at && f <= cpuGaugeRampStops[i + 1].at {
            lower = cpuGaugeRampStops[i]
            upper = cpuGaugeRampStops[i + 1]
            break
        }
    }
    let span = upper.at - lower.at
    let t = span > 0 ? (f - lower.at) / span : 0
    return Color(
        red: (lower.r + (upper.r - lower.r) * t) / 255,
        green: (lower.g + (upper.g - lower.g) * t) / 255,
        blue: (lower.b + (upper.b - lower.b) * t) / 255
    )
}

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
                    // …but a metric switch replaces `rows` wholesale, and animating
                    // THAT churns the whole list for 0.8 s after every tap on the
                    // CPU|Память control. A fresh identity per metric drops the old
                    // subtree instead of interpolating into the new one, so the
                    // switch is instant while tick-to-tick re-sorts keep the curve.
                    .id(procMetric)
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
    /// CPU list: per-row value-based ramp (see `cpuGaugeColor` above). Mem list:
    /// still the flat `SeriesPalette.s2` — only the CPU list's gauge is a ramp.
    private var gaugeColor: Color {
        switch primary {
        case .cpu: return cpuGaugeColor((row.cpu ?? 0) / 100)
        case .mem: return SeriesPalette.s2
        }
    }
    /// CPU list stays at 0.22; mem list is a notch lighter at 0.18 — the two
    /// lists are NOT the same opacity despite sharing this gauge shape.
    private var gaugeOpacity: Double {
        primary == .cpu ? 0.22 : 0.18
    }
    private var isExpandable: Bool { row.pid != nil }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9).fill(DS.row)
            if maxValue > 0 {
                RoundedRectangle(cornerRadius: 9)
                    .fill(gaugeColor.opacity(gaugeOpacity))
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

                // Force-quit confirmation is INLINE (not a `.confirmationDialog` system
                // sheet) — swaps the whole action row in place for the confirm/cancel
                // pair, the same "click destructive action → inline line appears in
                // its place" shape as `AutostartCard`'s orphan-plist delete flow (a
                // single optional/boolean piece of state gates which row renders;
                // `AutostartCard.pendingDeletePath`/`showOrphans` is the state-
                // management idiom mirrored here as `showForceQuitConfirm`, though
                // that flow itself still opens a system `.confirmationDialog` — this
                // is the first genuinely inline instance of the pattern in the app).
                if showForceQuitConfirm {
                    HStack(spacing: 7) {
                        Text(L.processForceQuitInlineQuestion)
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.inkSoft)
                        Spacer(minLength: 8)
                        ProcessOutlineNeutralButton(title: L.adviceCancel) {
                            showForceQuitConfirm = false
                        }
                        ProcessFilledHotButton(title: L.processForceQuitConfirm) {
                            signalError = ProcessInspector.sendSignal(SIGKILL, to: pid)
                                ? nil : L.processSignalError
                            showForceQuitConfirm = false
                        }
                        .accessibilityLabel(L.processKillA11y(row.name))
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 7) {
                        ProcessCapsuleButton(title: L.reportShowInFinder, disabled: detail?.path == nil) {
                            guard let path = detail?.path else { return }
                            // Shared rule (AdviceActionRunner.reveal): plain folders open, files
                            // and bundles are selected in their enclosing folder — `revealTarget`
                            // returns the .app bundle for app-hosted executables, so the package
                            // branch there is what keeps this from launching the app.
                            AdviceActionRunner.reveal(ProcessInspector.revealTarget(for: path))
                        }
                        .accessibilityLabel(L.processRevealA11y(row.name))

                        ProcessCapsuleButton(title: L.processQuit) {
                            signalError = ProcessInspector.sendSignal(SIGTERM, to: pid)
                                ? nil : L.processSignalError
                        }
                        .accessibilityLabel(L.processTerminateA11y(row.name))

                        ProcessOutlineHotButton(title: L.processForceQuit) {
                            showForceQuitConfirm = true
                        }
                        .accessibilityLabel(L.processKillA11y(row.name))
                    }
                    .padding(.top, 2)
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

// MARK: - Expanded-row action buttons

/// Balances `NSCursor.pointingHand.push()`/`.pop()` across hover enter/exit —
/// mirrors `AttentionSummaryCard.swift`'s `PointingHandOnHover` (same
/// explicit-`pushed`-tracking idiom, kept as a separate `private` copy here
/// since that one is file-private to its own file). The four buttons below
/// sit in `ProcessDetailView`'s action row, which gets swapped out from under
/// the cursor when "Снять принудительно" flips `showForceQuitConfirm` (and
/// back again on "Отмена"/"Снять"): SwiftUI does not reliably fire
/// `onHover`'s exit callback for a view that's removed from the hierarchy
/// mid-hover, only for an actual mouse-leave while the view is still
/// present, so a plain `push()`/`pop()` pair would leak the push. Tracking
/// `pushed` explicitly (not inferred from `hovering`) and popping it on
/// `.onDisappear` too, not just on hover-exit, keeps that removal balanced.
private struct ProcessButtonPointingHandHover: ViewModifier {
    @Binding var hovering: Bool
    var isEnabled: Bool = true
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                guard isEnabled else { return }
                hovering = isHovering
                if isHovering {
                    if !pushed { NSCursor.pointingHand.push(); pushed = true }
                } else if pushed {
                    NSCursor.pop(); pushed = false
                }
            }
            .onDisappear {
                if pushed { NSCursor.pop(); pushed = false }
            }
    }
}

private extension View {
    func processButtonPointingHandHover(_ hovering: Binding<Bool>, isEnabled: Bool = true) -> some View {
        modifier(ProcessButtonPointingHandHover(hovering: hovering, isEnabled: isEnabled))
    }
}

/// Small capsule chrome for the expanded row's non-destructive actions ("Показать
/// в Finder", "Завершить"). Mirrors the app's existing small-capsule idiom for
/// card-header-adjacent actions — `ChartOrTableCard`'s chart/table toggle
/// (Views/SharedUI.swift, DS.glass3 fill + DS.lineStrong border) — minus that
/// control's shimmering rainbow hover ring, at this spec's own size/padding/
/// hover-tint numbers.
private struct ProcessCapsuleButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? DS.ink : DS.inkSoft)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(Capsule().fill(DS.glass3))
                .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .processButtonPointingHandHover($hovering, isEnabled: !disabled)
        .animation(reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover, value: hovering)
    }
}

/// Outlined (not filled) destructive trigger — "Снять принудительно" before the
/// inline confirmation replaces it. Transparent fill at rest, `DS.hot` tint on
/// hover, `DS.hot` text/border throughout (never system `.red`).
private struct ProcessOutlineHotButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.hot)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(Capsule().fill(DS.hot.opacity(hovering ? 0.14 : 0)))
                .overlay(Capsule().strokeBorder(DS.hot.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .processButtonPointingHandHover($hovering)
        .animation(reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover, value: hovering)
    }
}

/// Outlined neutral "Отмена" for the inline force-quit confirmation — transparent
/// fill at rest, a faint neutral hover fill, no destructive tint (mirrors the
/// outline-capsule idiom `AttentionSummaryCard.swift`'s `OverflowCapsuleButton`
/// uses for its own non-destructive "+N"/"Свернуть" toggle: clear fill, `DS.row`
/// on hover, hairline border).
private struct ProcessOutlineNeutralButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? DS.ink : DS.inkSoft)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(Capsule().fill(hovering ? DS.row : Color.clear))
                .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .processButtonPointingHandHover($hovering)
        .animation(reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover, value: hovering)
    }
}

/// Filled destructive confirm — "Снять" in the inline force-quit confirmation.
/// White text on solid `DS.hot` fill.
private struct ProcessFilledHotButton: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(Capsule().fill(DS.hot))
        }
        .buttonStyle(.plain)
        .processButtonPointingHandHover($hovering)
    }
}
