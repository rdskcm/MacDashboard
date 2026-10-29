// Views/HomeAttentionCard.swift
// REDESIGN-HOME (stage B): the top of Home — scan-failed banner, the attention card (hero count,
// task rows, "You can" shortcuts), the All-good line and the First-scan card. Values are
// 02-home.md §1 and the prototype `This Mac Home v2.dc.html:60-120`.
//
// Decision 1 = option A (user, 2026-10-18): while a section page is still the interim page, a row's verb
// button runs today's action (`HomeTask.legacyAction`); the row itself always navigates.

import SwiftUI

// MARK: - Small shared pieces

/// Dot with a 4 pt halo at 0.16 (00 §4.1).
private struct HomeToneDot: View {
    let tone: HomeTone
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(tone.base)
            .frame(width: size, height: size)
            .background(Circle().fill(tone.base.opacity(0.16)).frame(width: size + 8, height: size + 8))
            .accessibilityHidden(true)
    }
}

/// "checked at hh:mm" (muted) or, after a failed scan, "last check hh:mm" (hotInk); nothing without a time.
private struct HomeCheckedLine: View {
    let scan: HomeScan

    var body: some View {
        switch scan {
        case .ok(let t), .refreshing(let t):
            Text(L.homeCheckedAt(HomeModel.hhmm(t)))
                .font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS3.muted).lineLimit(1)
        case .failed(_, let t?):
            Text(L.homeLastCheck(HomeModel.hhmm(t)))
                .font(.system(size: 12.5)).monospacedDigit().foregroundStyle(DS3.hotInk).lineLimit(1)
        case .failed(_, nil), .firstScan:
            EmptyView()
        }
    }
}

extension View {
    /// 1 pt ring around a card whose content holds a hot item (attention card, hot tiles).
    func homeHotRing(_ on: Bool, cornerRadius r: CGFloat = 30) -> some View {
        overlay {
            if on {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(DS3.hot.opacity(0.40), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Scan banner

@MainActor
struct HomeScanBannerSlot: View {
    let model: DashboardModel

    var body: some View {
        if case .failed(let failure, let lastGood) = HomeModel.scan(model.blockState(.scan)) {
            HStack(spacing: 12) {
                Text(L.homeScanFailed(timedOut: failure == .timedOut, lastGood: lastGood.map(HomeModel.hhmm)))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS3.hotInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isStaticText)
                Button(L.commonTryAgain) { model.refreshReport(trigger: .button) }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 14))
                    .accessibilityLabel(L.commonTryAgain)
                    .layoutPriority(1)
            }
            .padding(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 7))
            .ds3TintPanel(DS3.hot, from: 0.12, to: 0.12, ring: 0.40, cornerRadius: 999)
        }
    }
}

// MARK: - Attention slot

/// Chooses between the First-scan card, the attention card, the All-good line and nothing.
@MainActor
struct HomeAttentionSlot: View {
    let model: DashboardModel
    let router: NavigationRouter
    let width: LiveWindowWidth
    /// `false` only in the offscreen visual harness (see `homeEntrance`).
    var animatesEntrance = true

    var body: some View {
        let scan = HomeModel.scan(model.blockState(.scan))
        let hasTasks = !model.assessment.items.isEmpty
        slot(scan: scan, hasTasks: hasTasks)
            .homeEntrance(delay: 0.06, enabled: animatesEntrance)
    }

    @ViewBuilder
    private func slot(scan: HomeScan, hasTasks: Bool) -> some View {
        if scan == .firstScan {
            HomeFirstScanCard()
        } else if hasTasks {
            HomeAttentionCard(model: model, router: router, width: width)
        } else if case .failed(_, nil) = scan {
            EmptyView()
        } else {
            HomeAllGoodLine(model: model)
        }
    }
}

// MARK: - Attention card

@MainActor
struct HomeAttentionCard: View {
    let model: DashboardModel
    let router: NavigationRouter
    let width: LiveWindowWidth

    /// The model-owned dispatch for the rows' verb buttons (HIDDEN-CONTENT-WORK: Home is unmounted while a page is
    /// open, so this state must not live in the card). Internal so HomeAdviceDispatchTests can check the sharing.
    var dispatch: AdviceActionDispatch { model.homeAdviceDispatch }
    @State private var showAll: Bool

    init(model: DashboardModel, router: NavigationRouter, width: LiveWindowWidth, initialShowAll: Bool = false) {
        self.model = model
        self.router = router
        self.width = width
        _showAll = State(initialValue: initialShowAll)
    }

    var body: some View {
        let input = HomeInput.attention(model)
        let scan = HomeModel.scan(input.scan)
        let tasks = HomeModel.tasks(model.assessment, report: input.report, disk: model.disk, battery: model.battery)
        let chips = HomeModel.chips(input)
        let anyHot = tasks.contains { $0.tone == .hot }
        HStack(alignment: .top, spacing: 16) {
            hero(tasks: tasks, scan: scan, anyHot: anyHot)
                .modifier(HeroColumnWidth(width: width))
                .frame(maxHeight: .infinity)
            right(tasks: tasks, chips: chips)
                .frame(maxWidth: .infinity)
        }
        // Vertical only: equal column heights. (The horizontal variant is the header-row trap.)
        .fixedSize(horizontal: false, vertical: true)
        .padding(22)
        .ds3GlassCard(cornerRadius: 30)
        .homeHotRing(anyHot)
        .adviceActionDialogs(dispatch)
        .onDisappear { dispatch.dismissConfirmations() }   // a confirmation must not reappear on remount
    }

    // MARK: Hero

    private func hero(tasks: [HomeTask], scan: HomeScan, anyHot: Bool) -> some View {
        let tone: HomeTone = anyHot ? .hot : .amber
        let hot = tasks.filter { $0.tone == .hot }.count
        let warn = tasks.count - hot
        return VStack(alignment: .leading, spacing: 0) {
            Text(L.homeMacStatus)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.ink)
                .lineLimit(1)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.homeTaskCount(tasks.count))
                    .font(.system(size: 40, weight: .heavy))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L.homeNeedAttention(tasks.count))
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(spacing: 6) {
                countRow(tone: .hot, label: L.homeCriticalCount, count: hot)
                countRow(tone: .amber, label: L.homeWarnings, count: warn)
            }
            Spacer(minLength: 12)
            HomeCheckedLine(scan: scan)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ds3TintPanel(tone.base, from: 0.18, to: 0.06, ring: 0.42, cornerRadius: 20, top: DS3.rimMid)
        .accessibilityElement(children: .combine)
    }

    private func countRow(tone: HomeTone, label: String, count: Int) -> some View {
        HStack(spacing: 11) {
            HomeToneDot(tone: tone)
            Text(label).font(.system(size: 13.5)).foregroundStyle(DS3.inkSoft).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").font(.system(size: 17, weight: .bold)).monospacedDigit()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS3.row))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 14, style: .continuous), ring: DS3.line)
    }

    // MARK: Right column

    private func right(tasks: [HomeTask], chips: [HomeChip]) -> some View {
        let shown = (showAll || tasks.count <= 4) ? tasks : Array(tasks.prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 4) {
                ForEach(shown) { task in
                    HomeTaskRow(task: task, model: model, dispatch: dispatch) {
                        router.navigate(to: task.destination)
                    }
                }
                if tasks.count > 4 {
                    HomeShowAllButton(title: showAll ? L.commonShowLess : L.homeShowAll(tasks.count)) { showAll.toggle() }
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 22, style: .continuous), ring: DS3.line)

            if !chips.isEmpty { youCan(chips) }
            if let e = model.adviceActionError {
                Text(e).font(.system(size: 12.5)).foregroundStyle(DS3.hotInk)
            }
            if let e = model.brew.upgradeError {
                Text(e).font(.system(size: 12.5)).foregroundStyle(DS3.hotInk)
            }
        }
    }

    private func youCan(_ chips: [HomeChip]) -> some View {
        FlowLayout(spacing: 8) {
            Text(L.homeYouCan)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DS3.muted)
                .padding(.trailing, 2)
                .frame(height: 28)
            ForEach(chips) { chip in
                Button { router.navigate(to: chip.destination) } label: {
                    HStack(spacing: 6) {
                        Text(chip.object).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS3.ink)
                        if let v = chip.value {
                            Text(v).font(.system(size: 12.5, weight: .medium)).foregroundStyle(DS3.muted).monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Capsule().fill(DS3.chip))
                    .ds3InsetRims(Capsule(), ring: DS3.lineStrong)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel([chip.object, chip.value].compactMap { $0 }.joined(separator: " "))
            }
        }
    }
}

/// RESIZE-WIDTH-STATE: the hero column's width, derived from the window width, never from this card's own size
/// (`no-measured-size-feedback`): 0.8 fr of 0.8 fr + 2 fr over the card's inner width. The one per-drag-frame read
/// of `LiveWindowWidth.value` lives in this modifier's body, so a live resize re-evaluates only this frame,
/// not the card body (tasks, chips, rows, glass).
struct HeroColumnWidth: ViewModifier {
    let width: LiveWindowWidth
    static func heroWidth(window w: CGFloat) -> CGFloat { max(220, (w - 56 - 44 - 16) * 0.8 / 2.8) }
    func body(content: Content) -> some View {
        content.frame(width: Self.heroWidth(window: width.value))
    }
}

// MARK: - Show all

/// Internal: the History table's «Show all (n) / Show less» reuses it (10-history: Home button verbatim).
struct HomeShowAllButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DS3.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(hover ? DS3.lens : Color.clear)
                        .animation(.easeOut(duration: 0.16), value: hover)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }
}

// MARK: - Task row

/// NOT a `Button`: it contains one. The row opens the section; the verb button runs the action.
@MainActor
private struct HomeTaskRow: View {
    let task: HomeTask
    let model: DashboardModel
    let dispatch: AdviceActionDispatch
    let onOpen: () -> Void

    @State private var hover = false

    private var busy: Bool { dispatch.busy(for: task.legacyAction) }

    private var help: String {
        task.wakeHolderKeys.isEmpty ? task.help : "\(task.help) \(L.attnWakeIgnoreHint)"
    }

    private func runVerb() {
        guard !busy else { return }
        if let a = task.legacyAction { dispatch.handle(a, id: task.id) } else { onOpen() }
    }

    var body: some View {
        HStack(spacing: 12) {
            HomeToneDot(tone: task.tone)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                (Text(task.object).font(.system(size: 14.5, weight: .semibold))
                    + Text(" " + task.state).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(task.tone.ink))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("\(task.object) \(task.state)")
                Text(task.section.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
                    .help(task.section.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let verb = task.verb {
                Button(action: runVerb) {
                    Text(verb).dsSwapInPlace(busy) { DS3Spinner(role: .softRing, size: 12) }
                }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(busy)
                .accessibilityLabel("\(verb) — \(task.object)")
                .ds3BusyValue(busy)
                .layoutPriority(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS3.muted)
                .accessibilityHidden(true)
        }
        .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 8))
        .frame(minHeight: 50) // border-box 50 per 02-home.md: padding is inside the min height
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hover ? DS3.lens : Color.clear)
                .animation(.easeOut(duration: 0.16), value: hover)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hover = $0 }
        .onTapGesture(perform: onOpen)
        .help(help)
        .focusable()
        .onKeyPress(.return) { onOpen(); return .handled }
        .onKeyPress(.space) { onOpen(); return .handled }
        .modifier(WakeIgnoreMenu(keys: task.wakeHolderKeys, model: model))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(task.object) \(task.state), \(task.section.title)")
        .accessibilityAction { onOpen() }
        .modifier(VerbAccessibilityAction(verb: task.verb, perform: runVerb))
    }
}

/// The row's verb button is merged into the row's accessibility element, so its action is re-exposed by name.
private struct VerbAccessibilityAction: ViewModifier {
    let verb: String?
    let perform: () -> Void

    func body(content: Content) -> some View {
        if let verb {
            content.accessibilityAction(named: Text(verb), perform)
        } else {
            content
        }
    }
}

/// SLEEP-IGNORE-APP: right-click menu on the Sleep row, one entry per holder the item names — never an
/// "ignore all" entry (user decision 2026-10-05). Rows of every other kind have no keys and get no menu;
/// the branch cannot flip for a mounted row because a `.wakeHolders` item always names ≥ 1.
private struct WakeIgnoreMenu: ViewModifier {
    let keys: [WakeHolderKey]
    let model: DashboardModel

    func body(content: Content) -> some View {
        if keys.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(keys, id: \.self) { key in
                    let title = L.attnWakeIgnore(WakeHolders.label(for: key))
                    Button(title) { model.settings.setWakeHolderIgnored(key, ignored: true) }
                        .accessibilityLabel(title)
                }
            }
        }
    }
}

// MARK: - All good, first scan

@MainActor
struct HomeAllGoodLine: View {
    let model: DashboardModel

    var body: some View {
        HStack(spacing: 12) {
            HomePulseDot(color: DS3.green, size: 9, haloWidth: 3, haloOpacity: 0.22)
            Text(L.commonAllGood)
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.22)
                .foregroundStyle(DS3.greenInk)
                .lineLimit(1)
            Text(L.homeNothingNeedsAttention)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .lineLimit(1)
                .help(L.homeNothingNeedsAttention)
            Spacer(minLength: 8)
            HomeCheckedLine(scan: HomeModel.scan(model.blockState(.scan)))
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .ds3GlassCard(cornerRadius: 30)
        .accessibilityElement(children: .combine)
    }
}

struct HomeFirstScanCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                DS3Spinner(role: .accentRing, size: 14)
                Text(L.homeFirstScanTitle).font(.system(size: 14, weight: .semibold))
                Text(L.homeFirstScanCaption)
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
                    .help(L.homeFirstScanCaption)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .ds3RowPanel(cornerRadius: 20)
            ProgressView().progressViewStyle(.linear)
        }
        .padding(22)
        .ds3GlassCard(cornerRadius: 30)
        .accessibilityElement(children: .combine)
    }
}
