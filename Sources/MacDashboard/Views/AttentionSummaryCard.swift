// Views/AttentionSummaryCard.swift
// Block V2-SUMMARY: the v2 "attention" card — a single title row (dot + summary
// title + item chips/last-check time) followed by an item grid (3+ items) and a
// recommendation-capsule strip, replacing the legacy Рекомендации card.
// Tone mapping (crit/serious -> DS.hot, warn/info -> DS.amber, good -> DS.green)
// NEVER falls back to the legacy `Severity.color` (Theme.swift) — see the design
// handoff's tone table. The `tone(for:)` mapping itself was hoisted to
// SharedUI.swift in V2-TILES (KPITiles.swift needs the same map), so this file
// is a consumer, not the source, of the table now.

import SwiftUI
import AppKit

@MainActor
struct AttentionSummaryCard: View {
    let model: DashboardModel

    /// Owns confirmations/busy/done state for every clickable item/capsule —
    /// see AdviceActionDispatch.swift. `@State` (not a plain `let`) so the
    /// `@Observable` instance survives body re-evaluations instead of being
    /// rebuilt (and losing its state) on every render.
    @State private var dispatch: AdviceActionDispatch
    /// Item-grid overflow toggle ("Ещё N" / "Свернуть"), only shown past 4 items.
    @State private var attnMore = false
    /// Capsule-row overflow toggle ("+N" / "Свернуть"), only shown past 6 capsules.
    @State private var tipsMore = false

    // Compiled out of the default (public) build — see Package.swift/build_app.sh
    // (AI_ENABLED). Moved verbatim from the legacy Рекомендации card (its only call
    // site — AIAskSheet has no other entry point).
    #if AI_ENABLED
    /// Refreshed in `.onAppear` and again when the AI sheet is dismissed, so a
    /// key just saved/deleted in Settings is reflected without restarting the app.
    @State private var aiKeyExists = false
    @State private var showAISheet = false
    #endif

    init(model: DashboardModel) {
        self.model = model
        _dispatch = State(wrappedValue: AdviceActionDispatch(model: model))
    }

    private var items: [AttentionItem] { model.assessment.items }
    private var capsules: [TipCapsule] { model.assessment.capsules }

    /// V2-FIX-ATTENTION-COMPACT: with no item grid mounted the card holds only the
    /// title row and (optionally) the recommendations row, and the prototype's
    /// spacing reads as emptiness. Three paddings tighten in this state only; the
    /// full state keeps the prototype geometry verbatim.
    private var isSparse: Bool { items.count < 3 }

    /// Title-dot / plate tone from the v2 tone table — `summarySev` is already
    /// the worst item severity (`problems.first?.sev ?? .good`), so this is the
    /// single source of truth for the title dot; per-item tone below re-derives
    /// the same map per item's own `sev`.
    private var titleTone: Color { tone(for: model.assessment.summarySev) }

    var body: some View {
        VStack(alignment: .leading, spacing: isSparse ? 8 : 11) {
            titleRow
            if items.count >= 3 {
                itemGrid
            }
            if !capsules.isEmpty {
                recommendationsSection
            }
            // Both must still surface — trashError is UI-local (this card owns
            // the confirmation), adviceActionError is model-owned (firewall).
            if let trashError = dispatch.trashError {
                Text(trashError).font(.system(size: 11)).foregroundStyle(.red)
            }
            if let adviceActionError = model.adviceActionError {
                Text(adviceActionError).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(.top, 13)
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.bottom, isSparse ? 10 : 12)
        .dsCardSurface()
        .dsBorderHover()
        .adviceActionDialogs(dispatch)
        #if AI_ENABLED
        .onAppear { aiKeyExists = KeychainStore.exists() }
        .sheet(isPresented: $showAISheet, onDismiss: { aiKeyExists = KeychainStore.exists() }) {
            AIAskSheet(model: model)
        }
        #endif
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack(spacing: 11) {
            titleDot
            Text(AttentionModel.summaryTitle(count: items.count, lang: L10nStore.shared.language))
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.15) // -0.01em @ 15 pt
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            trailingArea
            #if AI_ENABLED
            if AppSettings.shared.aiConfig.isComplete && aiKeyExists {
                Button {
                    showAISheet = true
                } label: {
                    Label(L.aiAskButton, systemImage: "sparkles")
                        .font(.system(size: 12.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accentInk)
                .accessibilityLabel(L.aiAskButton)
            }
            #endif
            lastCheckTime
        }
        .frame(minHeight: 30)
    }

    /// 8×8 dot filled with the title tone plus a 4 pt, 16%-opacity ring behind
    /// it (a plain 16×16 stroked circle — the spec's explicitly allowed
    /// alternative to an overlay+scaleEffect, and simpler; no `.shadow`).
    private var titleDot: some View {
        ZStack {
            Circle().stroke(titleTone.opacity(0.16), lineWidth: 4).frame(width: 16, height: 16)
            Circle().fill(titleTone).frame(width: 8, height: 8)
        }
        .padding(.leading, 1)
    }

    /// `items.count <= 2` (including 0): the chips themselves live here,
    /// right-aligned, and the flexible frame still pushes the AI button / last-
    /// check time to the trailing edge even when there are zero chips to show.
    /// `items.count >= 3`: empty flexible space (the item grid renders below
    /// the title row instead).
    @ViewBuilder
    private var trailingArea: some View {
        if items.count <= 2 {
            HStack(spacing: 7) {
                ForEach(items) { item in
                    ItemPlate(item: item, form: .chip, dispatch: dispatch)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var lastCheckTime: some View {
        if let updated = model.reportUpdatedAt {
            // Reuses ReportTab's own formatter verbatim (same-day -> time only,
            // older -> abbreviated date + time) rather than re-deriving HH:mm.
            Text(reportUpdatedTimeString(updated))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Item grid (3+ items)

    @ViewBuilder
    private var itemGrid: some View {
        let displayed = attnMore ? items : Array(items.prefix(4))
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(displayed) { item in
                ItemPlate(item: item, form: .list, dispatch: dispatch)
            }
        }
        .padding(.leading, 19)

        if items.count > 4 {
            MoreLessToggle(
                expanded: attnMore,
                collapsedLabel: L.attnMore(items.count - 4),
                expandedLabel: L.attnCollapse
            ) {
                attnMore.toggle()
            }
            .padding(.leading, 19)
        }
    }

    // MARK: - Recommendation capsules

    @ViewBuilder
    private var recommendationsSection: some View {
        Rectangle().fill(DS.line).frame(height: 1).padding(.top, 1)
        HStack(alignment: .top, spacing: 8) {
            // Literal kicker styling, NOT `.dsKicker()` — that's the section
            // kicker (different size/tracking/color), see spec Step 3.
            Text(L.recommendationsTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.84) // 0.08em @ 10.5 pt
                .foregroundStyle(DS.muted)
                .padding(.top, 9)
                .fixedSize()
            capsuleFlow
        }
        .padding(.leading, 19)
        // isSparse: the outer VStack's own 8pt spacing already sits between the
        // divider and this row, so this padding only needs to add 2pt more to
        // match the card's 10pt bottom padding (8+2=10) — otherwise the two
        // gaps stack to 16pt and the space above the capsule row reads larger
        // than the space below it.
        .padding(.top, isSparse ? 2 : 11)
    }

    @ViewBuilder
    private var capsuleFlow: some View {
        let displayed = tipsMore ? capsules : Array(capsules.prefix(6))
        FlowLayout(spacing: 7) {
            ForEach(displayed) { capsule in
                TipCapsuleView(capsule: capsule, dispatch: dispatch)
            }
            if capsules.count > 6 {
                OverflowCapsuleButton(expanded: tipsMore, overflowCount: capsules.count - 6) {
                    tipsMore.toggle()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Item plate (chip / list forms)

private enum ItemPlateForm { case chip, list }

/// One AttentionItem, rendered either as a compact title-row chip (0–2 items)
/// or a full-width list row inside the grid (3+ items) — same tone/hover/busy/
/// done logic either way, only geometry differs.
private struct ItemPlate: View {
    let item: AttentionItem
    let form: ItemPlateForm
    let dispatch: AdviceActionDispatch

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var itemTone: Color { tone(for: item.sev) }
    private var busy: Bool { dispatch.busy(for: item.action) }
    private var busyDetail: String? { dispatch.busyDetail(for: item.action) }
    private var done: Bool { dispatch.done(item.id) }
    private var interactive: Bool { item.action != nil && !busy && !done }
    /// `item.detail`, swapped for the live brew/firewall progress line while busy.
    private var detailText: String { (busy ? busyDetail : nil) ?? item.detail }

    var body: some View {
        Group {
            switch form {
            case .chip: chipBody
            case .list: listBody
            }
        }
        .contentShape(Rectangle())
        .help(item.fullText)
        .pointingHandOnHover(isEnabled: interactive, hovering: $hovering)
        .animation(reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover, value: hovering)
        .onTapGesture {
            guard interactive, let action = item.action else { return }
            dispatch.handle(action, id: item.id)
        }
        .modifier(InteractiveAccessibility(
            isInteractive: interactive,
            label: "\(item.label) \(item.detail) \(item.verb)"
        ))
    }

    private var chipBody: some View {
        HStack(spacing: 7) {
            Circle().fill(itemTone).frame(width: 5, height: 5)
            // V2-FIX-NARROW-OVERLAP (V2-SWEEP item 7): the whole chip used to be
            // `.fixedSize()` ("never wraps/truncates in the title row"), but that
            // made the title row's total width unshrinkable — with 2 items and
            // realistic label/detail lengths (e.g. "Батарея"/"состояние: Service
            // Recommended" + "Брандмауэр"/"выключен") the row exceeded even the
            // card's full width at the 900pt minimum window. `item.label`
            // (`.layoutPriority(1)`, same idiom as `listBody`'s never-truncate
            // label) keeps its full text; `detailText` shrinks/truncates first.
            Text(item.label)
                .font(.system(size: 12.5))
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .layoutPriority(1)
            Text(detailText)
                .font(.system(size: 12.5))
                .foregroundStyle(DS.inkSoft)
                .lineLimit(1)
                .truncationMode(.tail)
            trailingSlot.padding(.leading, 1).layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(itemTone.opacity(0.13)))
        .overlay(Capsule().strokeBorder(hovering ? DS.accentInk : itemTone.opacity(0.32), lineWidth: 1))
    }

    private var listBody: some View {
        HStack(spacing: 9) {
            Circle().fill(itemTone).frame(width: 6, height: 6)
            Text(item.label)
                .font(.system(size: 13))
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false) // label never wraps/truncates
            Text(detailText)
                .font(.system(size: 12.5))
                .foregroundStyle(DS.inkSoft)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            trailingSlot
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10).fill(itemTone.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hovering ? DS.accentInk : itemTone.opacity(0.32), lineWidth: 1))
    }

    /// Verb (default) / spinner (busy) / checkmark (done) — the one slot that
    /// changes meaning across states, shared between both plate forms. The verb
    /// is always the layout participant (`dsSwapInPlace`): mounting the spinner
    /// or the ✓ in its stead used to shrink the plate by ~48 pt mid-action and
    /// reflow every sibling capsule in the FlowLayout (V2-FIX-OPTICAL).
    private var trailingSlot: some View {
        // `.lineLimit(1)`: chipBody no longer wraps this slot in `.fixedSize()`
        // (V2-FIX-NARROW-OVERLAP) — without it, a squeezed chip would wrap the
        // verb onto a second line instead of letting `detailText` above absorb
        // the shrink.
        Text(item.verb).font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(DS.accentInk)
            .lineLimit(1)
            .dsSwapInPlace(busy || done) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\u{2713}").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.greenInk)
                }
            }
    }
}

// MARK: - Recommendation capsule

private struct TipCapsuleView: View {
    let capsule: TipCapsule
    let dispatch: AdviceActionDispatch

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var busy: Bool { dispatch.busy(for: capsule.action) }
    private var done: Bool { dispatch.done(capsule.id) }
    private var interactive: Bool { capsule.action != nil && !busy && !done }

    var body: some View {
        HStack(spacing: 8) {
            Text(capsule.object).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.ink)
            Text(capsule.value).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(DS.inkSoft)
            trailingSlot
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(DS.row))
        .overlay(Capsule().strokeBorder(hovering ? DS.accentInk : DS.line, lineWidth: 1))
        .contentShape(Rectangle())
        .pointingHandOnHover(isEnabled: interactive, hovering: $hovering)
        .animation(reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover, value: hovering)
        .onTapGesture {
            guard interactive, let action = capsule.action else { return }
            dispatch.handle(action, id: capsule.id)
        }
        .attentionTip(capsule.explanation)
        .modifier(InteractiveAccessibility(
            isInteractive: interactive,
            label: "\(capsule.object) \(capsule.value) \(capsule.verb)"
        ))
    }

    /// Verb (default) / spinner (busy) / checkmark (done) — same idiom as
    /// `ItemPlate.trailingSlot`. `busyDetail` (long brew progress strings)
    /// is intentionally NOT surfaced here: the capsule is `.fixedSize()`
    /// nowrap inside a `FlowLayout`, so only the spinner fits.
    @ViewBuilder
    private var trailingSlot: some View {
        if busy {
            ProgressView().controlSize(.mini)
        } else if done {
            Text("\u{2713}").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.greenInk)
        } else {
            Text(capsule.verb).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.accentInk)
        }
    }
}

/// "+N" outline capsule shown when `capsules.count > 6`; tap expands the row to
/// show every capsule and the label flips to `L.attnCollapse`.
private struct OverflowCapsuleButton: View {
    let expanded: Bool
    let overflowCount: Int
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var label: String { expanded ? L.attnCollapse : "+\(overflowCount)" }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.accentInk)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(hovering ? DS.row : Color.clear))
                .overlay(Capsule().strokeBorder(hovering ? DS.accentInk : DS.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointingHandOnHover(isEnabled: true, hovering: $hovering)
        .animation(reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover, value: hovering)
        .accessibilityLabel(label)
    }
}

// MARK: - "Ещё N" / "Свернуть" toggle (item grid overflow)

private struct MoreLessToggle: View {
    let expanded: Bool
    let collapsedLabel: String
    let expandedLabel: String
    let action: () -> Void

    @State private var hovering = false

    private var label: String { expanded ? expandedLabel : collapsedLabel }

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.accentInk)
        }
        .buttonStyle(.plain)
        .pointingHandOnHover(isEnabled: true, hovering: $hovering)
        .accessibilityLabel(label)
    }
}

// MARK: - Shared hover-cursor helper

/// Balances `NSCursor.pointingHand.push()`/`.pop()` across hover enter/exit —
/// same push/pop-balance idiom used elsewhere in the app (the legacy
/// Рекомендации card's `AdviceRow`, StorageCards' `DirBarRow`), extracted once
/// here since this card needs it in four places (item plates, capsules, the
/// "+N" capsule, the more/less toggle). `pushed` is tracked explicitly rather
/// than inferred from `hovering` so an interactive→non-interactive transition
/// mid-hover (e.g. tapping brew/firewall while the mouse stays put) still
/// balances the push instead of leaking it until the mouse happens to move.
private struct PointingHandOnHover: ViewModifier {
    let isEnabled: Bool
    @Binding var hovering: Bool
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
            .onChange(of: isEnabled) { _, nowEnabled in
                guard !nowEnabled else { return }
                hovering = false
                if pushed { NSCursor.pop(); pushed = false }
            }
    }
}

private extension View {
    func pointingHandOnHover(isEnabled: Bool, hovering: Binding<Bool>) -> some View {
        modifier(PointingHandOnHover(isEnabled: isEnabled, hovering: hovering))
    }
}

/// `.accessibilityLabel` + `.isButton` trait, applied only when the underlying
/// plate is actually interactive (spec: "on interactive plates").
private struct InteractiveAccessibility: ViewModifier {
    let isInteractive: Bool
    let label: String

    func body(content: Content) -> some View {
        if isInteractive {
            content.accessibilityLabel(label).accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
