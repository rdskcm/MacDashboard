// Views/MemoryPage.swift
// REDESIGN-MEMORY: the Memory section page (handoff 04-memory) on the shared §8 blocks (SectionPageBlocks.swift):
// page bar (Back, icon, title, sub line, pressure tag), Usage card (hero + four tiles), Memory
// composition card (Chart | Table) and the Processes-by-memory card (ProcessListCard, memory-page variant).
// All texts and states come from the pure `MemoryPageModel`; this file only draws them.

import SwiftUI

@MainActor
struct MemoryPage: View {
    let model: DashboardModel
    let router: NavigationRouter
    let narrow: Bool

    @State private var pulse: CardID? = nil


    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the cards do the
    /// reading, so a 2 s tick never re-evaluates the page itself (same rule as `CPUPage`).
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MemoryUsageCard(model: model, narrow: narrow)
                        .id(CardID.usage)
                        .sectionFocusPulse(pulse == .usage)
                        .ds3Appear(delay: 0.08)
                    MemoryCompositionCard(model: model, narrow: narrow)
                        .id(CardID.comp)
                        .sectionFocusPulse(pulse == .comp)
                        .ds3Appear(delay: 0.14)
                    ProcessListCard(model: model, memoryPage: true)
                        .id(CardID.procs)
                        .sectionFocusPulse(pulse == .procs)
                        .ds3Appear(delay: 0.20)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { MemoryPageBar(model: model, onBack: { _ = router.back() }) }
            .task(id: router.navigationSerial) {
                // Deep link: scroll the focused card under the bar (Usage is already on top) and pulse it.
                let d = router.destination
                guard d.page == .memory, let f = d.focus else { return }
                if f != .usage { proxy.scrollTo(f, anchor: .top) }
                pulse = f
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
    }
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it.
@MainActor
struct MemoryPageBar: View {
    let model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        let m = MemoryPageModel.make(memoryPageInput(model, narrow: false))
        SectionPageBar(symbol: Page.memory.symbol, title: Page.memory.title, sub: m.sub, subIsFailure: m.subIsFailure,
                       onBack: onBack) {
            DS3Tag(tone: tone(m.tag), text: m.tagText).help(m.tagText)
        } trailing: {
            EmptyView()
        }
    }

    private func tone(_ t: MemoryTagKind) -> DS3Tag.Tone {
        switch t {
        case .low: return .green
        case .medium: return .amber
        case .high: return .hot
        case .unknown, .loading: return .neutral
        case .failed: return .hot
        }
    }
}

// MARK: - Usage card

/// Internal: the visual fixture renders it.
@MainActor
struct MemoryUsageCard: View {
    let model: DashboardModel
    let narrow: Bool

    var body: some View {
        let m = MemoryPageModel.make(memoryPageInput(model, narrow: narrow))
        DS3Card(title: L.memUsageTitle, caption: m.usageCaption) {
            if m.showsWait {
                SectionWait(text: L.commonCollectingData)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let note = m.failureNote {
                        SectionNote(tone: DS3.hot, text: note)
                    }
                    HeroSplitLayout {
                        SectionHero(label: L.memUsed, value: m.heroValue, fraction: m.heroFraction, note: m.heroNote,
                                    tone: heroTone(m.heroTone), toneInk: heroInk(m.heroTone),
                                    dimmed: m.heroTone == .neutral)
                        EqualColumnsLayout(columns: narrow ? 2 : 4, spacing: 8) {
                            ForEach(m.tiles.indices, id: \.self) { tile(m.tiles[$0]) }
                        }
                    }
                }
            }
        }
    }

    private func heroTone(_ t: MemoryHeroTone) -> Color {
        switch t {
        case .accent: return DS3.accent
        case .amber: return DS3.amber
        case .hot: return DS3.hot
        case .neutral: return DS3.muted
        }
    }

    private func heroInk(_ t: MemoryHeroTone) -> Color {
        switch t {
        case .accent: return DS3.accentInk
        case .amber: return DS3.amberInk
        case .hot: return DS3.hotInk
        case .neutral: return DS3.inkSoft
        }
    }

    private func tile(_ t: MemoryTileModel) -> some View {
        SectionTile(label: t.label, value: t.value, note: t.note,
                    noteInk: t.amber ? DS3.amberInk : DS3.muted,
                    dot: t.amber ? DS3.amber : nil,
                    valueInk: t.dimmed ? DS3.muted : DS3.ink)
    }
}

// MARK: - Composition card

/// Internal: the visual fixture renders it (`initialView` exists for the snapshot test only).
@MainActor
struct MemoryCompositionCard: View {
    let model: DashboardModel
    let narrow: Bool
    @State private var view: MemoryCompView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Two independent hover sources and a derived `hoveredKey`: each source clears only what it owns, so a
    // bar-exit arriving after a legend-enter cannot wipe the legend's highlight. Legend wins.
    @State private var barHoverKey: String?
    @State private var legendHoverKey: String?

    init(model: DashboardModel, narrow: Bool, initialView: MemoryCompView = .chart) {
        self.model = model
        self.narrow = narrow
        _view = State(initialValue: initialView)
    }

    private static let barLayout = BarFillLayout.segments(gap: 2, minWidth: 3, cornerRadius: 7)

    var body: some View {
        let m = MemoryPageModel.make(memoryPageInput(model, narrow: narrow))
        DS3Card(title: L.memCompTitle, caption: m.compCaption, trailing: { viewControl }) {
            if m.showsWait {
                SectionWait(text: L.commonCollectingData)
            } else if view == .chart {
                stack(m)
            } else {
                list(m)
            }
        }
    }

    /// Outside the wait / chart / table branch (`control-identity-branch`).
    private var viewControl: some View {
        DSSlidingSegmented(options: [MemoryCompView.chart, .table], selection: $view, size: .section,
                           groupLabel: L.memCompViewA11y) { $0 == .chart ? L.commonChart : L.commonTable }
    }

    // MARK: Stack block

    private func stack(_ m: MemoryPageModel) -> some View {
        let hoveredKey = legendHoverKey ?? barHoverKey
        return VStack(alignment: .leading, spacing: 12) {
            bar(m, hoveredKey: hoveredKey)
            legend(m, hoveredKey: hoveredKey)
        }
    }

    @ViewBuilder
    private func bar(_ m: MemoryPageModel, hoveredKey: String?) -> some View {
        if m.phase == .live {
            // Zero-byte segments are omitted from the bar only (D7).
            let barSegs = m.segments.filter { $0.bytes > 0 }
            let spans = barSegs.map { BarSpan(key: $0.key.rawValue, fraction: CGFloat($0.barFraction), color: barColor($0.key),
                                            dim: (hoveredKey == nil || hoveredKey == $0.key.rawValue) ? 1 : 0.45) }
            Color.clear.frame(height: 24)
                .overlay {
                    BarFillLayer(spans: spans, layout: Self.barLayout, animated: !reduceMotion)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .topLeading) {
                    // Hover names: transparent rects on the same geometry the layers draw (D6). Placed with
                    // leading padding, not `.offset`: `.offset` leaves the layout frame at x = 0, so per-rect
                    // `.onHover` tracked the un-offset frames and the topmost overlapping rect won (active
                    // hovered → inactive lit). The highlight comes from ONE continuous-hover handler that
                    // maps the pointer x to a span.
                    GeometryReader { g in
                        let rects = barSpanRects(spans, layout: Self.barLayout, width: g.size.width)
                        ZStack(alignment: .topLeading) {
                            ForEach(rects.indices, id: \.self) { k in
                                Color.clear.contentShape(Rectangle())
                                    .frame(width: rects[k].width, height: 24)
                                    .help(barSegs[k].label)
                                    .padding(.leading, rects[k].x)
                            }
                        }
                        .frame(width: g.size.width, height: 24, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p):
                                barHoverKey = rects.firstIndex { p.x >= $0.x && p.x < $0.x + $0.width }
                                    .map { barSegs[$0].key.rawValue }
                            case .ended:
                                barHoverKey = nil
                            }
                        }
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS3.track).frame(height: 24)
        }
    }

    private func legend(_ m: MemoryPageModel, hoveredKey: String?) -> some View {
        StackLegendLayout(columnSpacing: 22, rowSpacing: 8) {
            ForEach(m.segments, id: \.key) { seg in
                let isActive = hoveredKey == seg.key.rawValue
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(swatch(seg.key)).frame(width: 10, height: 10)
                    Text(seg.label).font(.system(size: 13)).foregroundStyle(isActive ? DS3.ink : DS3.muted).lineLimit(1)
                    Text(seg.value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(DS3.ink).lineLimit(1)
                }
                .contentShape(Rectangle())
                .opacity(hoveredKey == nil || isActive ? 1 : 0.45)
                .help(note(seg.key))
                .onHover { inside in
                    if inside { legendHoverKey = seg.key.rawValue }
                    else if legendHoverKey == seg.key.rawValue { legendHoverKey = nil }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredKey)
        .padding(.top, 4)
    }

    // MARK: List block (D9: same container as ProcessListCard)

    private func list(_ m: MemoryPageModel) -> some View {
        VStack(spacing: 4) {
            ForEach(m.segments, id: \.key) { row($0) }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
    }

    private func row(_ seg: MemorySegmentModel) -> some View {
        HStack(spacing: 10) {
            Circle().fill(swatch(seg.key)).frame(width: 7, height: 7)
            Text(seg.label).font(.system(size: 14)).foregroundStyle(DS3.ink)
                .lineLimit(1).truncationMode(.tail).help(seg.label)
            Spacer(minLength: 8)
            Text(seg.share).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS3.muted)
                .lineLimit(1).layoutPriority(1)
            Text(seg.value).font(.system(size: 13, weight: .semibold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(seg.value == "—" ? DS3.muted : DS3.ink)
                .lineLimit(1).frame(minWidth: 64, alignment: .trailing).layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(alignment: .leading) {
            BarFillLayer(spans: [BarSpan(key: "share", fraction: CGFloat(min(seg.listFraction, 1)), alpha: 0.18,
                                         color: swatch(seg.key))],
                         layout: .single(minWidth: 0, cornerRadius: 16), animated: !reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    // MARK: Colours and notes

    private func barColor(_ k: MemorySegmentKey) -> Color {
        switch k {
        case .active: return DS3.s1
        case .wired: return DS3.s2
        case .other: return DS3.s3
        case .inactive: return DS3.s4
        case .speculative: return DS3.s5
        case .free: return DS3.track
        }
    }

    private func swatch(_ k: MemorySegmentKey) -> Color { k == .free ? DS3.sfree : barColor(k) }

    private func note(_ k: MemorySegmentKey) -> String {
        switch k {
        case .active: return L.memoryNoteActive
        case .wired: return L.memoryNoteWired
        case .other: return L.memoryNoteOther
        case .inactive: return L.memoryNoteInactive
        case .speculative: return L.memoryNoteSpeculative
        case .free: return L.memoryNoteFree
        }
    }
}

/// Wrap layout with separate column (22) and row (8) gaps for the §8 Stack legend; the shared `FlowLayout`
/// has one spacing.
private struct StackLegendLayout: Layout {
    var columnSpacing: CGFloat = 22
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + columnSpacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + columnSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

@MainActor
private func memoryPageInput(_ model: DashboardModel, narrow: Bool) -> MemoryPageModel.Input {
    MemoryPageModel.Input(mem: model.mem, swap: model.swap, pressure: model.memPressure,
                          installedBytes: model.headerSystem?.memBytes, block: model.memoryBlock.phase,
                          intervalSeconds: AppSettings.shared.fastIntervalSeconds, narrow: narrow)
}
