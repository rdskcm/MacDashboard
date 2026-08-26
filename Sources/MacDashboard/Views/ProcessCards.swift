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
/// list (prototype's `cubic-bezier(0.22, 0.61, 0.36, 1)`, shortened to 0.45 s
/// — V2-RELAYOUT-RESIDUAL, CPU cost is ~linear in duration).
private let processRowMotion = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.45)

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
    // V2-FIX-ROWID Step 2: while a detail panel is open, freeze row ORDER (values
    // keep updating in place) so a live-tick re-sort can't land under the user
    // mid-drilldown. Captured/released in `onTap` below, not `.onChange`, so the
    // snapshot is exactly the one the user just clicked.
    @State private var frozenOrder: [Int32] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [ProcEntry] {
        let base = procMetric == .cpu ? model.topCPU : model.topMem
        return frozenOrder.isEmpty ? base : base.stableOrdered(matching: frozenOrder)
    }

    /// V2-FIX-PROCESS-ROWS wave 2: the ONLY thing `:144`'s reorder animation
    /// needs to react to is the row SEQUENCE changing — `rows` itself changes
    /// on every live tick (CPU%/mem values drift a little each sample even
    /// when nobody's rank changes), so keying `.animation(value:)` off the
    /// full array made that ambient reorder-curve transaction open on
    /// virtually every tick, not just on an actual re-sort. Keying off just
    /// the row IDENTITY sequence instead makes the animated transaction open
    /// only on a true re-sort (rarer), leaving per-tick value-only updates
    /// alone — a real, verified improvement (fewer ambient-transaction opens
    /// overall) and worth keeping regardless of the note below.
    ///
    /// NEEDS-HUMAN — does NOT fully fix the reported catastrophic
    /// double-exposure glitch. Live rapid-screenshot repro (`swift run` app,
    /// non-fullscreen window, ~180 screenshots/burst at ~60ms intervals while
    /// clicking a row repeatedly across several live-tick boundaries) still
    /// catches the same one-frame double-exposure (stale + fresh row content
    /// composited together, occasionally bleeding past the card into the
    /// SYSTEM section below) after this change, on genuine re-sort ticks —
    /// just less often than before, since fewer ticks now qualify as a
    /// "true" re-sort. A follow-up ABLATION (temporarily setting
    /// `.animation(nil, value: rowOrder)` — reorder fully UNANIMATED)
    /// disproved the original leading hypothesis: the glitch still
    /// reproduced with no reorder animation running at all, so this is not
    /// "two competing `Animation` curves fighting over a CATransaction" as
    /// theorized. The defect appears to be in `ForEach(rows)`'s reorder-diff
    /// itself (or how SwiftUI/AppKit commits the resulting frame) racing
    /// SOME per-row content update — possibly the always-mounted
    /// `ProcessDetailView`'s own `.onGeometryChange` writes now firing for
    /// all ~10 rows instead of one, but not confirmed. Needs a fresh
    /// `hunter`-style investigation (not a repeat of this reasoning) before
    /// another fix attempt; do not re-scope `.animation(value:)` again
    /// without new evidence.
    private var rowOrder: [String] { rows.map(\.id) }

    /// Row gauges are proportional to the LARGEST value currently in `rows` for
    /// `procMetric`, which is the first row's value only when the list is not
    /// frozen (V2-FIX-ROWID Step 2). While a detail panel is open, `rows` holds
    /// its ORDER but values keep updating, so a row above the frozen leader can
    /// legitimately exceed it — trusting `rows.first` in that state would scale
    /// every gauge against the wrong reference and produce fill fractions > 1.
    private var maxValue: Double {
        switch procMetric {
        case .cpu: return rows.map { $0.cpu ?? 0 }.max() ?? 0
        case .mem: return rows.map { Double($0.memBytes ?? 0) }.max() ?? 0
        }
    }

    // `CardChrome`/`metricControl` must sit OUTSIDE the rows.isEmpty branch
    // (V2-FIX-PROCESS-SEGMENT): branching the whole card gave the CPU|Память
    // segmented control a fresh identity on every state flip, so
    // `DSSlidingSegmented`'s thumb spring never animated — the new instance
    // just mounted pre-selected. Only the row content varies.
    var body: some View {
        CardChrome(
            title: L.processesTitle,
            caption: rows.isEmpty ? nil : L.processListCaption,
            trailing: { metricControl }
        ) {
            content
        }
        .onChange(of: procMetric) { expandedPID = nil; frozenOrder = [] }
        // V2-FIX-ROWID Step 2 follow-up: release the freeze if the expanded process
        // itself disappears from the snapshot (dies, or falls out of the top-N —
        // including via a process-limit shrink). Without this, `isOpen` goes false
        // for every row (no panel visible) while `frozenOrder` stays non-empty, so
        // the list stays frozen indefinitely with nothing open to justify it — a
        // stuck state invisible to the user and unrecoverable without an unrelated
        // tap. `rowOrder` (row IDENTITY sequence) changes the moment the expanded
        // pid's row drops out, so it is the right hook; checked here, not during
        // body evaluation, so it's a state write in response to a change, not a
        // side effect of rendering.
        .onChange(of: rowOrder) {
            guard let pid = expandedPID, !rows.contains(where: { $0.pid == pid }) else { return }
            expandedPID = nil
            frozenOrder = []
        }
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            SectionStateView(done: false)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    let isOpen = row.pid != nil && expandedPID == row.pid
                    VStack(alignment: .leading, spacing: 0) {
                        ProcessRowView(
                            row: row, primary: procMetric, maxValue: maxValue,
                            expanded: isOpen,
                            onTap: {
                                guard let pid = row.pid else { return }
                                if expandedPID == pid {
                                    expandedPID = nil
                                    frozenOrder = []
                                } else {
                                    expandedPID = pid
                                    // Re-capturing from an already-frozen `rows` when
                                    // switching directly between two open rows is
                                    // correct — the order keeps holding still.
                                    frozenOrder = rows.compactMap(\.pid)
                                }
                            }
                        )
                        // Always mounted (never `if`-gated) — see
                        // `ProcessDetailView.openAmount`'s doc comment for why:
                        // its own `openAmount`/`.onGeometryChange`/single
                        // `withAnimation` disclosure replaces the old
                        // `.transition` + this container's `.animation(value:
                        // expandedPID)`, matching `QuietStripRow`/
                        // `AutoSectionRow`/`OrphanRow`.
                        ProcessDetailView(row: row, isOpen: isOpen)
                            // V2-FIX-PROCESS-ROWS wave 2 (`rowOrder` doc comment
                            // above has the full writeup, INCLUDING the NEEDS-HUMAN
                            // note — this does not fully resolve the defect either):
                            // even keyed on row IDENTITY, `rowOrder`'s ambient
                            // reorder transaction still reaches every row's
                            // permanently-mounted panel, including the 9 COLLAPSED,
                            // fully invisible (`opacity(0)`, height 0) ones. A
                            // collapsed panel has nothing worth animating, so it has
                            // no business sharing a CATransaction with 9 siblings'
                            // worth of `.onGeometryChange` writes during a reorder —
                            // only the row actually mid-disclosure (which drives
                            // itself off its own explicit
                            // `withAnimation(disclosureCurve)` regardless of ambient
                            // context) needs to. Stripping the ambient animation
                            // here for every OTHER row is a no-op for anything
                            // visible and removes 9/10 panels from the shared
                            // transaction — a defensible improvement kept for that
                            // reason, but live re-repro after this change still
                            // caught the same class of glitch, so it is NOT the
                            // fix; see `rowOrder`'s NEEDS-HUMAN note.
                            .transaction { t in
                                if !isOpen { t.animation = nil }
                            }
                    }
                }
            }
            // Row reordering (a live tick re-sorting `rows`) moves with the
            // SAME curve/duration as the gauge width transition below, so a
            // row and its own gauge travel together instead of the row
            // snapping to its new slot while the gauge is still animating —
            // that mismatch is what let the gauge fill visibly detach from
            // its row. `nil` under Reduce Motion: reordering is instant.
            // Keyed on `rowOrder` (row IDENTITY sequence), NOT `rows` itself
            // — see `rowOrder`'s doc comment above for why keying on the
            // full array (which changes on every value-only tick too) kept
            // this ambient transaction open almost continuously and fought
            // each row's own permanently-mounted `ProcessDetailView`
            // disclosure animation (V2-FIX-PROCESS-ROWS wave 2).
            .animation(reduceMotion ? nil : processRowMotion, value: rowOrder)
            // …but a metric switch replaces `rows` wholesale, and animating
            // THAT churns the whole list for 0.8 s after every tap on the
            // CPU|Память control. A fresh identity per metric drops the old
            // subtree instead of interpolating into the new one, so the
            // switch is instant while tick-to-tick re-sorts keep the curve.
            // The process-limit setting (V2-SETTINGS-PROCLIMIT) is folded into
            // the same identity via `rows.count`, NOT `AppSettings.shared.processListLimit`
            // directly — the setting changes the moment the segmented control moves, well
            // before a resample (periodic tick or the Apply button) actually shortens
            // `rows`; keying off the setting flipped identity too early (while `rows` was
            // still the old length), so the ACTUAL shrink still landed inside the old
            // identity and rode the 0.8 s `processRowMotion` reorder curve — visible as a
            // sluggish "settle" after Apply instead of an instant cut. Keying off the
            // count itself remounts exactly when the array actually changes length (e.g.
            // 15 → 5 would otherwise animate ten rows out), while ordinary tick-to-tick
            // re-sorts at a constant length still keep `processRowMotion` exactly as today.
            .id("\(procMetric)-\(rows.count)")
        }
    }

    private var metricControl: some View {
        DSSlidingSegmented(options: [Metric.cpu, .mem], selection: $procMetric) { m in
            m == .cpu ? L.processSegCPU : L.processSegMem
        }
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
    // The gauge plate + bar live in a `.background` (see `body`), never as a
    // sibling inside the row's own layout — a `.background` sizes to its parent
    // and can't feed anything back into it, which is what breaks the one-way
    // measurement ratchet (row width -> bar width -> ZStack width -> row width,
    // never shrinking) that used to inflate the whole card on live-drag window
    // resize (V2-FIX-RATCHET). The fill's width must also never come from a
    // `GeometryReader` inside this subtree: on a fresh mount / `ForEach` reorder
    // its first pass is 0-width and the 0 -> real settle shows as a thin
    // mis-placed sliver (V2-FIX-BARFLY).
    // V2-RELAYOUT-COREANIM: the fill is now a `BarFillLayer` (CALayer driven by
    // CoreAnimation, BarFillLayer.swift) with no SwiftUI animation on it at all —
    // ~10 of these rows animating through SwiftUI cost up to ~47% of one core.
    // Do not reintroduce `.frame(width:)`, a GeometryReader, or an
    // `.animation(_:value:)` on the gauge.

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
    /// V2-FIX-UNITS follow-up: mem-primary mode splits value/unit so the
    /// literal-space gap (a full glyph advance in this monospaced face) can be
    /// tightened to `.padding(.leading, 1.5)` — see `fmtBytesParts`. (1.5pt,
    /// not the 27pt-tile's 3pt: at this 13pt size 3pt reads proportionally
    /// wide.)
    private var primaryMemParts: (value: String, unit: String?)? {
        primary == .mem ? fmtBytesParts(row.memBytes) : nil
    }
    private var secondaryText: String {
        switch primary {
        case .cpu: return "· " + tight(fmtBytesParts(row.memBytes))
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
            if let parts = primaryMemParts {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(parts.value)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(DS.inkSoft)
                    if let unit = parts.unit {
                        Text(unit)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .padding(.leading, 1.5)
                            .foregroundStyle(DS.inkSoft)
                    }
                }
            } else {
                Text(primaryText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(DS.inkSoft)
            }
            Text(secondaryText)
                .font(.system(size: 11))
                .foregroundStyle(DS.muted)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 27)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9).fill(DS.row)
                if maxValue > 0 {
                    BarFillLayer(spans: [BarSpan(key: "gauge",
                                                 fraction: CGFloat(min(primaryValue / maxValue, 1)),
                                                 alpha: gaugeOpacity,
                                                 color: gaugeColor)],
                                 layout: .single(minWidth: 0, cornerRadius: 9),
                                 animated: !reduceMotion)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // Hover highlight only for expandable rows — DS.track token (prototype's
        // `style-hover="background:var(--track)"`), 0.14 s ease transition
        // (already Reduce-Motion-safe: color-only).
        .background(isExpandable && hovering ? DS.track : Color.clear)
        .animation(.easeInOut(duration: 0.14), value: hovering)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .pointingHandOnHover(isEnabled: isExpandable, hovering: $hovering)
        .onTapGesture { onTap() }
    }
}

// MARK: - Expanded detail panel

private struct ProcessDetailView: View {
    let row: ProcEntry
    let isOpen: Bool

    init(row: ProcEntry, isOpen: Bool) {
        self.row = row
        self.isOpen = isOpen
        // Seeds `openAmount` from the CURRENT `isOpen` (never true on first
        // mount here — a row is only ever mounted collapsed — but mirrors the
        // seeding idiom of `QuietStripRow`/`AutoSectionRow` so this stays
        // correct if that assumption ever changes) instead of defaulting to 0
        // and animating in on the next tick.
        _openAmount = State(initialValue: isOpen ? 1 : 0)
    }

    @State private var detail: ProcDetail?
    @State private var loading = true
    @State private var showForceQuitConfirm = false
    @State private var signalError: String? = nil

    /// True once the CURRENT open/close disclosure transaction (driven by
    /// `.onChange(of: isOpen)` below) has actually finished animating — set
    /// false the instant the transaction starts, true only from that
    /// `withAnimation`'s own `completion:` callback. Deliberately NOT derived
    /// from `openAmount == 1`: `openAmount` is a plain `@State` value and
    /// reads back as its target immediately when the withAnimation block
    /// runs, well before the animation has visually finished — so gating on
    /// it would let the fetch-completion write below land mid-disclosure-
    /// transaction, which is the root cause this state fixes (see
    /// V2-FIX-PROCESS-GHOST). Starts `true`: a row is only ever mounted
    /// collapsed and at rest.
    @State private var disclosureSettled = true
    /// Fetch result buffered here (instead of committed straight to
    /// `detail`/`loading`) when it resolves while `disclosureSettled` is
    /// still false — see `.task(id:)` below.
    @State private var pendingDetail: ProcDetail?
    @State private var hasPendingFetch = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Single source of truth for the disclosure's progress, 0 = fully
    /// closed, 1 = fully open — same recipe as `QuietStripRow.openAmount` /
    /// `AutoSectionRow.openAmount` / `AutostartCard.OrphanRow.openAmount`:
    /// permanently mounted, height/opacity/offset are pure functions of this
    /// one value, committed by a single explicit `withAnimation` in
    /// `.onChange(of: isOpen)` below — replaces the old `if expandedPID ==
    /// pid { … }.transition(...)` + the row list's competing
    /// `.animation(value: expandedPID)` (V2-FIX-PROCESS-ROWS).
    @State private var openAmount: Double
    /// Natural (fully-expanded) height of the panel, captured via
    /// `.onGeometryChange` — see `QuietStripRow.measuredHeight` for the full
    /// root-cause writeup.
    @State private var measuredHeight: CGFloat?

    private var pid: Int32 { row.pid ?? 0 }

    /// Shared with `.onChange(of: isOpen)` below AND the `.task` fetch's own
    /// state writes — the fetch's loading→loaded content swap (spinner →
    /// Grid + action row) is a SEPARATE, unrelated resize from the
    /// open/close disclosure itself, but it still changes this view's
    /// natural height (re-measured by the same `.onGeometryChange` below),
    /// so it needs the identical curve or the two resizes visibly disagree.
    private var disclosureCurve: Animation {
        reduceMotion
            ? .easeInOut(duration: DSMotion.reduceMotionFallback)
            : DSMotion.expand
    }

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
                        Text(tight(fmtBytesParts(row.memBytes))).font(.system(size: 11.5))
                    }
                    GridRow {
                        Text(L.processDetailPath).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        // `.frame(maxWidth: .infinity)` gives the grid cell a width
                        // CEILING — without it this text proposes its own full ideal
                        // width (a long path) and pushes the whole panel/card wider
                        // than the window instead of truncating in place.
                        Text(detail?.path ?? "—")
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        // Matches the confirm branch's trailing `Spacer(minLength: 8)`
                        // above so the action row's width doesn't shift when
                        // `showForceQuitConfirm` toggles.
                        Spacer(minLength: 8)
                    }
                    .padding(.top, 2)
                }

                if let signalError {
                    Text(signalError).font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 19, bottom: 8, trailing: 10))
        // Width tracked its widest child (long path → wide panel, short path →
        // narrow panel) before this — the background stopped short of the
        // card's right edge on short-path rows. Mirrors `ProcessRowView`'s own
        // `.frame(maxWidth: .infinity, alignment: .leading)`.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
            measuredHeight = newHeight
        }
        .frame(height: measuredHeight.map { $0 * openAmount } ?? (openAmount == 0 ? 0 : nil), alignment: .top)
        .clipShape(BleedRect(top: 8, leading: 8, trailing: 8))
        .opacity(openAmount)
        .offset(y: reduceMotion ? 0 : DSMotion.discloseRiseY * (1 - openAmount))
        // Outer backstop clip — same rationale as `QuietStripRow`'s (see its
        // comment above its own second `.clipShape(BleedRect(leading:trailing:))`):
        // the inner clip above is itself offset upward by up to
        // `DSMotion.discloseRiseY` while collapsing/collapsed, so an
        // already-clipped-to-zero-height panel can still poke a sliver above
        // its row without this outer re-clip.
        .clipShape(BleedRect(leading: 8, trailing: 8))
        .onChange(of: isOpen) { _, new in
            disclosureSettled = false
            withAnimation(disclosureCurve) {
                openAmount = new ? 1 : 0
            } completion: {
                disclosureSettled = true
                // The panel is permanently mounted (see `.task(id:)` below), so its
                // @State outlives a collapse — without this, reopening a row showed the
                // force-quit confirmation still armed and the previous attempt's error
                // still up (V2-POLISH B2). Reset in the CLOSE transaction's completion,
                // not at its start: at that point `openAmount` is already 0, so swapping
                // the confirm row back to the action row is invisible and cannot disturb
                // the collapse's own height interpolation.
                if !new {
                    showForceQuitConfirm = false
                    signalError = nil
                }
                // The fetch completion below buffers instead of writing
                // straight to `detail`/`loading` while this transaction is
                // open — flush it now that the disclosure has actually
                // settled. Re-checks `isOpen` (not just `hasPendingFetch`):
                // if the row was closed again before this open transaction's
                // completion fired, the buffered result belongs to a panel
                // that's no longer open and must be dropped, not applied.
                guard new, hasPendingFetch else { return }
                hasPendingFetch = false
                let result = pendingDetail
                pendingDetail = nil
                withAnimation(disclosureCurve) {
                    detail = result
                    loading = false
                }
            }
        }
        // Keyed on (pid, isOpen), NOT just pid — the panel is now permanently
        // mounted for every row (see the always-mounted `ProcessDetailView`
        // call site above), so fetching on mount alone would fire path/thread
        // lookups for every visible row instead of staying on-demand. Only a
        // row actually being opened (or the expanded pid changing while open)
        // triggers a fetch; re-opening a row refetches, same as the old
        // expandedPID-keyed behavior.
        .task(id: "\(row.pid ?? -1)-\(isOpen)") {
            guard isOpen, let pid = row.pid else { return }
            // Animated, not a bare assignment: this swaps the panel's rendered
            // content between the small "loading" spinner and the much taller
            // Grid + action row, which re-measures via `.onGeometryChange`
            // above and resizes this view's `.frame(height:)` — completely
            // independent of `openAmount`'s own open/close progress. `expand`
            // (0.18s) reliably finishes well before this fetch resolves (real
            // syscalls, plus a `ps -M` fallback that can run up to 3s), so
            // WITHOUT this `withAnimation` the loading→loaded swap lands as a
            // plain, unanimated state write after the disclosure has already
            // settled at `openAmount == 1` (opacity already 1, no offset) —
            // the taller content pops in whole and instantly and the sudden
            // height jump shoves the row below it, reading as the panel
            // jittering/overlapping neighbours before "settling" downward.
            withAnimation(disclosureCurve) {
                loading = true
                detail = nil
            }
            // Discards any buffer left over from a previous open/fetch cycle
            // on this same row (e.g. closed again before its own transaction
            // settled, see `.onChange(of: isOpen)` above) — this cycle's own
            // result, once it arrives, is what gets buffered/committed below.
            hasPendingFetch = false
            pendingDetail = nil
            // Off the main actor: proc_pidpath/proc_pidinfo are cheap syscalls but
            // the `ps -M` fallback shells out (up to 3s) — never block the UI on it.
            let fetched = await Task.detached { ProcessInspector.detail(pid: pid) }.value
            // `.task(id:)` cancels the previous task the instant `isOpen`
            // flips (id includes it) — but `Task.detached` above is
            // unstructured and keeps running regardless, so without this
            // check a row closed mid-fetch would still land its result here
            // once the detached work finishes.
            guard !Task.isCancelled else { return }
            // THE FIX (V2-FIX-PROCESS-GHOST): this fetch-completion write is
            // the second writer into the shared height/opacity/offset
            // pipeline above (see :539-545) — `disclosureSettled` (set only
            // by the disclosure's own `withAnimation` completion, above) is
            // the gate that stops it from landing while the first writer's
            // (the disclosure) transaction is still open. When the fetch
            // resolves before the disclosure has settled (the common case:
            // `expand` is 0.18s, the fetch typically takes longer, but a
            // cached/very-fast fetch can still beat it), buffer the result
            // instead of committing it — the disclosure's completion
            // callback above applies it once `openAmount` has actually
            // finished animating to 1. If the disclosure is already settled
            // by the time the fetch resolves (the fetch was slow, or Reduce
            // Motion made the disclosure's own short animation finish
            // first), commit immediately — there is no open transaction left
            // to collide with.
            if disclosureSettled {
                withAnimation(disclosureCurve) {
                    detail = fetched
                    loading = false
                }
            } else {
                pendingDetail = fetched
                hasPendingFetch = true
            }
        }
    }
}

// MARK: - Expanded-row action buttons

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
        .pointingHandOnHover(isEnabled: !disabled, hovering: $hovering)
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
        .pointingHandOnHover(hovering: $hovering)
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
        .pointingHandOnHover(hovering: $hovering)
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
        .pointingHandOnHover(hovering: $hovering)
    }
}
