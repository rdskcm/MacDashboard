// Views/ProcessCards.swift
// Processes card (LIVE), DS3 §8 Proc block (REDESIGN-CPU): a compact clickable process list, switchable
// between CPU and memory ranking via a sliding segmented control, with a single-expansion accordion
// (only rows with a known PID are expandable). Expanding a row fetches on-demand detail (PID, owner,
// path) via ProcessInspector and offers Quit (SIGTERM) / Force quit… (SIGKILL after an inline confirm;
// another user's process asks for administrator authentication). No energy metric anywhere — CPU/mem only.

import SwiftUI
import AppKit

// `Metric` (cpu | mem) lives in Engine/CPUPageModel.swift.

/// Shared curve for the row gauge width transition AND row-reorder movement —
/// deliberately the SAME `Animation` value for both, so a row and its own
/// gauge move as one object when a live tick both re-sorts and re-values the
/// list (prototype's `cubic-bezier(0.22, 0.61, 0.36, 1)`, shortened to 0.45 s
/// — V2-RELAYOUT-RESIDUAL, CPU cost is ~linear in duration).
private let processRowMotion = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.45)

// MARK: - Shared list card

/// Visual fixture only (tools/visual/content_states.swift): one row shown expanded with a fixed detail.
struct ProcessRowFixture {
    enum Phase { case open, confirm, quitting }
    let pid: Int32
    let detail: ProcDetail
    let phase: Phase
}

/// Single entry point (REDESIGN-CPU, §8 Proc block): one DS3 card, `CPU | Memory` sliding
/// segmented control in the header's trailing slot. Rows are
/// read live off `model.topCPU`/`model.topMem` inside the body every tick —
/// never snapshotted into `@State` — so whichever metric is selected keeps
/// ticking live.
struct ProcessListCard: View {
    let model: DashboardModel

    @State private var procMetric: Metric
    private let memoryPage: Bool
    private let rowFixture: ProcessRowFixture?
    private let onConfirmShown: (Bool) -> Void

    /// `initialMetric` is default-valued only for the visual baseline's offscreen
    /// content render (VISUAL-COVERAGE) and the Memory page: the CPU page and every other
    /// call site use the implicit `.cpu` default. `rowFixture` is the visual fixture's seeded open row.
    /// `memoryPage`: the Memory page's fixed «Processes by memory» list (REDESIGN-MEMORY) — memory ranking only,
    /// no metric control, rows do not open, no foot line.
    /// `onConfirmShown` reports the inline force-quit confirm to the page (it owns Esc while open).
    init(model: DashboardModel, initialMetric: Metric = .cpu, memoryPage: Bool = false, rowFixture: ProcessRowFixture? = nil,
         onConfirmShown: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.memoryPage = memoryPage
        self.rowFixture = rowFixture
        self.onConfirmShown = onConfirmShown
        _procMetric = State(initialValue: memoryPage ? .mem : initialMetric)
        _expandedPID = State(initialValue: rowFixture?.pid)
    }

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

    // `DS3Card`/`metricControl` must sit OUTSIDE the rows.isEmpty branch
    // (V2-FIX-PROCESS-SEGMENT): branching the whole card gave the CPU|Memory
    // segmented control a fresh identity on every state flip, so
    // `DSSlidingSegmented`'s thumb spring never animated — the new instance
    // just mounted pre-selected. Only the row content varies.
    var body: some View {
        DS3Card(
            title: memoryPage ? L.memProcsTitle : L.processesTitle,
            caption: memoryPage ? MemoryPageModel.procsCaption(processCount: model.processCount)
                                : CPUPageModel.procsCaption(metric: procMetric, processCount: model.processCount),
            trailing: { if !memoryPage { metricControl } }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                content
                if !rows.isEmpty && !memoryPage {
                    Text(L.procsFoot)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS3.muted)
                        .padding(.leading, 6)
                }
            }
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
            SectionWait(text: L.commonCollectingData)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    let isOpen = !memoryPage && row.pid != nil && expandedPID == row.pid
                    VStack(alignment: .leading, spacing: 0) {
                        ProcessRowView(
                            row: row, primary: procMetric, maxValue: maxValue,
                            expanded: isOpen, interactive: !memoryPage,
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
                        // expandedPID)`, matching `QuietStripRow`.
                        if !memoryPage {
                            ProcessDetailView(
                                row: row, isOpen: isOpen,
                                fixture: rowFixture?.pid == row.pid ? rowFixture : nil,
                                onConfirmShown: onConfirmShown,
                                onSignalSent: { model.refreshProcessesNow() }
                            )
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
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(DS3.lens)
                            .ds3Elevation(.lens, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .opacity(isOpen ? 1 : 0)
                            .animation(.easeOut(duration: 0.25), value: isOpen)
                    )
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
            // THAT churns the whole list for 0.45 s after every tap on the
            // CPU|Память control. A fresh identity per metric drops the old
            // subtree instead of interpolating into the new one, so the
            // switch is instant while tick-to-tick re-sorts keep the curve.
            // The list length is folded into the same identity via `rows.count`: the list is
            // fixed at `LiveCollector.topProcessCount` rows, but it is shorter while the
            // first samples arrive or processes exit. Keying off the count remounts exactly
            // when the array actually changes length (so rows appearing or leaving never ride
            // the 0.45 s `processRowMotion` reorder curve), while ordinary tick-to-tick
            // re-sorts at a constant length still keep `processRowMotion` exactly as today.
            .id("\(procMetric)-\(rows.count)")
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
        }
    }

    private var metricControl: some View {
        DSSlidingSegmented(options: [Metric.cpu, .mem], selection: $procMetric, size: .section,
                           groupLabel: L.processesMetricA11y) { m in
            m == .cpu ? L.processSegCPU : L.processSegMem
        }
    }
}

// MARK: - Row (compact, gauge behind content)

private struct ProcessRowView: View {
    let row: ProcEntry
    let primary: Metric
    let maxValue: Double
    let expanded: Bool
    /// false on the Memory page: not a button, no chevron, secondary text is the CPU share.
    let interactive: Bool
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
    /// Bar colour per `CPUPageModel.procBar` (D9): CPU mode amber / green / blue by share, memory one blue-grey.
    private var gaugeColor: Color {
        switch CPUPageModel.procBar(row, metric: primary) {
        case .amber: return DS3.amber
        case .green: return DS3.green
        case .accent: return DS3.accent
        case .series: return DS3.s1
        }
    }
    private var isExpandable: Bool { interactive && row.pid != nil }

    private var texts: (value: String, secondary: String) { CPUPageModel.procTexts(row, metric: primary) }
    private var secondary: String { interactive ? texts.secondary : MemoryPageModel.procSecondary(row) }

    @ViewBuilder
    var body: some View {
        if interactive {
            Button(action: onTap) { rowContent }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .pointingHandOnHover(isEnabled: isExpandable, hovering: $hovering)
                .accessibilityLabel("\(row.name), \(texts.value)")
                .accessibilityAddTraits(isExpandable ? [] : .isStaticText)
        } else {
            rowContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.name), \(texts.value)")
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            if interactive { chevron }
            Text(row.name)
                .font(.system(size: 14))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(secondary)
                .font(.system(size: 12.5))
                .foregroundStyle(DS3.muted)
                .lineLimit(1)
                .layoutPriority(1)
            Text(texts.value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                // Flat text row hover class (`hover-surface-classes`): the container carries `row`, so hover is `row`.
                RoundedRectangle(cornerRadius: 16).fill(isExpandable && hovering ? DS3.row : Color.clear)
                if maxValue > 0 {
                    BarFillLayer(spans: [BarSpan(key: "gauge",
                                                 fraction: CGFloat(min(primaryValue / maxValue, 1)),
                                                 alpha: CPUPageModel.procBarOpacity(primary),
                                                 color: gaugeColor)],
                                 layout: .single(minWidth: 0, cornerRadius: 16),
                                 animated: !reduceMotion)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }

    /// Always laid out (space kept for rows without a PID), only drawn when the row can open.
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DS3.muted)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: expanded)
            .frame(width: 12)
            .opacity(isExpandable ? 1 : 0)
    }
}

// MARK: - Expanded detail panel

private struct ProcessDetailView: View {
    let row: ProcEntry
    let isOpen: Bool
    /// Visual fixture only: a fixed detail and phase, no fetch (`ProcessRowFixture`).
    let fixture: ProcessRowFixture?
    /// Reports the inline force-quit confirm to the page, which owns Esc while it is open (D17/D18).
    let onConfirmShown: (Bool) -> Void
    /// A signal was delivered: the card re-samples the process list.
    let onSignalSent: () -> Void

    init(row: ProcEntry, isOpen: Bool, fixture: ProcessRowFixture?,
         onConfirmShown: @escaping (Bool) -> Void, onSignalSent: @escaping () -> Void) {
        self.row = row
        self.isOpen = isOpen
        self.fixture = fixture
        self.onConfirmShown = onConfirmShown
        self.onSignalSent = onSignalSent
        _detail = State(initialValue: fixture?.detail)
        _loading = State(initialValue: fixture == nil)
        _showForceQuitConfirm = State(initialValue: fixture?.phase == .confirm)
        _quitting = State(initialValue: fixture?.phase == .quitting)
        // Seeds `openAmount` from the CURRENT `isOpen` (never true on first
        // mount here — a row is only ever mounted collapsed — but mirrors the
        // seeding idiom of `QuietStripRow` so this stays
        // correct if that assumption ever changes) instead of defaulting to 0
        // and animating in on the next tick.
        _openAmount = State(initialValue: isOpen ? 1 : 0)
    }

    @State private var detail: ProcDetail?
    @State private var loading = true
    @State private var showForceQuitConfirm = false
    @State private var signalError: String? = nil
    /// SIGTERM / SIGKILL was sent (or is being sent): «Quitting…» until the row leaves the list or 5 s pass.
    @State private var quitting = false

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
    /// closed, 1 = fully open — same recipe as `QuietStripRow.openAmount`:
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

    private func kv(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(DS3.muted)
            Text(value)
                .font(.system(size: 12.5, design: mono ? .monospaced : .default))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
        }
    }

    /// Quit (SIGTERM) and Force quit… (opens the inline confirm). Quit swaps its label for «Quitting…»
    /// with an opacity ZStack, so the button keeps its width (`swap-in-place`).
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button { quit(SIGTERM) } label: {
                ZStack {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(L.processQuitting)
                    }
                    .opacity(quitting ? 1 : 0)
                    Text(L.processQuit).opacity(quitting ? 0 : 1)
                }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
            .disabled(quitting)
            .accessibilityLabel(quitting ? L.processQuitting : L.processTerminateA11y(row.name))

            Button(L.processForceQuit) { showForceQuitConfirm = true }
                .buttonStyle(DS3ButtonStyle(kind: .danger, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(quitting)
                .accessibilityLabel(L.processKillA11y(row.name))
            Spacer(minLength: 0)
        }
    }

    /// Inline force-quit confirm (D24: `overlay` fill, no popover shadow — it sits inside the `BleedRect` clips below).
    /// Cancel owns Esc (`.cancelAction`); there is no default action, so Return does nothing.
    private var confirmPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.processForceQuitQuestion(row.name))
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L.commonCancel) { showForceQuitConfirm = false }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(L.commonCancel)
                Button(L.processForceQuitConfirm) {
                    showForceQuitConfirm = false
                    quit(SIGKILL)
                }
                .buttonStyle(DS3ButtonStyle(kind: .dangerSolid, height: 30, hPad: 13, fontSize: 12.5))
                .accessibilityLabel(L.processKillA11y(row.name))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.overlay))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimMid, ring: DS3.lineStrong)
    }

    /// D8/D15/D16: the signal runs off the main actor (a privileged retry blocks on the administrator
    /// dialog). After a send, the list re-samples 1 s later; «Quitting…» ends when the row leaves the list
    /// (the card closes the panel) or after 5 s when the process ignored SIGTERM — no message either way.
    private func quit(_ sig: Int32) {
        quitting = true
        signalError = nil
        let expected = detail?.path
        let p = pid
        Task { @MainActor in
            let outcome = await Task.detached { ProcessInspector.signal(sig, pid: p, expectedPath: expected) }.value
            switch outcome {
            case .sent, .gone:
                try? await Task.sleep(for: .seconds(1))
                onSignalSent()
                try? await Task.sleep(for: .seconds(4))
                quitting = false
            case .cancelled:
                quitting = false
            case .failed:
                quitting = false
                withAnimation(disclosureCurve) { signalError = L.processSignalFailed(row.name) }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L.processLoadingDetails).font(.system(size: 12.5)).foregroundStyle(DS3.muted)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 18) {
                        kv("PID", String(pid), mono: true)
                        kv(L.processOwner, detail?.owner ?? "—")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L.processDetailPath).font(.system(size: 12.5)).foregroundStyle(DS3.muted)
                        // `.frame(maxWidth: .infinity)` gives the text a width CEILING — without
                        // it a long path proposes its full ideal width and pushes the whole
                        // panel/card wider than the window instead of truncating in place.
                        Text(detail?.path ?? "—")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(DS3.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(detail?.path ?? "")
                    }

                    // Force-quit confirmation is INLINE (not a `.confirmationDialog` system
                    // sheet): a single boolean gates whether the action row or the confirm
                    // panel renders (the same "click destructive action → inline line appears
                    // in its place" shape as the System page's startup-item delete confirm).
                    // No action buttons for pid <= 1 (kernel_task, launchd).
                    if CPUPageModel.showsActions(pid: row.pid) {
                        if showForceQuitConfirm {
                            confirmPanel
                        } else {
                            actionRow
                        }
                    }

                    if let signalError {
                        Text(signalError).font(.system(size: 12.5)).foregroundStyle(DS3.hotInk)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 35, bottom: 12, trailing: 14))
        // Width tracked its widest child (long path → wide panel, short path →
        // narrow panel) before this — the background stopped short of the
        // card's right edge on short-path rows. Mirrors `ProcessRowView`'s own
        // `.frame(maxWidth: .infinity, alignment: .leading)`.
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    quitting = false
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
        .onChange(of: showForceQuitConfirm) { _, new in onConfirmShown(new) }
        .onDisappear { if showForceQuitConfirm { onConfirmShown(false) } }
        // Keyed on (pid, isOpen), NOT just pid — the panel is now permanently
        // mounted for every row (see the always-mounted `ProcessDetailView`
        // call site above), so fetching on mount alone would fire path/thread
        // lookups for every visible row instead of staying on-demand. Only a
        // row actually being opened (or the expanded pid changing while open)
        // triggers a fetch; re-opening a row refetches, same as the old
        // expandedPID-keyed behavior.
        .task(id: "\(row.pid ?? -1)-\(isOpen)") {
            guard isOpen, let pid = row.pid, fixture == nil else { return }
            // Animated, not a bare assignment: this swaps the panel's rendered
            // content between the small "loading" spinner and the much taller
            // Grid + action row, which re-measures via `.onGeometryChange`
            // above and resizes this view's `.frame(height:)` — completely
            // independent of `openAmount`'s own open/close progress. `expand`
            // (0.18s) can finish well before this fetch resolves (real
            // syscalls on a busy Mac), so
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
            // Off the main actor: proc_pidpath and the owner sysctl are cheap syscalls, but
            // nothing here may ever block the UI.
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
