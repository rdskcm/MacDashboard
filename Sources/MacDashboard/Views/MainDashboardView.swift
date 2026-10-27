// Views/MainDashboardView.swift
// One window chrome for both modes (REDESIGN-HOME, 01-window-chrome.md): the header (title block, mode switch,
// per-mode actions) and the single background (`DS3.ground` + `DS3OrbField`). Under the header the This Mac
// content is the Home page (HomeView.swift) with section pages shown in place over it (the real CPU, Memory,
// Storage, Battery, Security, Backups, System and History pages); the Report
// sheet is presented over both while `router.isReportShown`.

import SwiftUI
import Charts

/// Vertical band the window's traffic-light buttons occupy, measured from the window's
/// top edge. `.windowStyle(.hiddenTitleBar)` (MacDashboardApp.swift) keeps AppKit's
/// standard titlebar and lets it draw those buttons over our content — they are not
/// SwiftUI views, so nothing in `toolbar`'s layout knows they are there. The header's
/// `.padding(.leading, 20)` leaves the buttons their own column above the title block;
/// this constant is the vertical counterpart: the title block is padded down by it
/// (01-window-chrome: «pushed down 21 pt under the traffic lights») instead of being left to
/// centre itself against the window edge. Calibrated once from a screenshot — the
/// acceptance test is equal INK gaps above and below the title block, not this literal.
private let headerTrafficLightBand: CGFloat = 21

@MainActor
struct MainDashboardView: View {
    var model: DashboardModel
    var iphone: IPhoneModel = .shared

    /// REDESIGN-FOUNDATION: mode, report tab and (later) pages go through the router.
    @State private var router = NavigationRouter()
    @State private var pointer = DS3PointerTracker()
    /// Window width, measured once at the window root (REDESIGN-HOME D18). RESIZE-WIDTH-STATE: the body never reads
    /// the raw width (it changes every drag frame). It goes to `liveWidth` (read only by the Home attention slot) and to
    /// `breakpoints` (written only when a page breakpoint flips). Safe under `no-measured-size-feedback`: column counts
    /// and the hero column cannot change the window's own width.
    @State private var liveWidth = LiveWindowWidth(1150)
    @State private var breakpoints = PageBreakpoints(width: 1150)
    /// RESIZE-MOTION: the width tier (`WidthTier`), committed once per boundary crossing from the same measurement.
    /// Everything tier-shaped (Home tiles, Now cells) reads this, never the raw width; seeded by the first callback.
    @State private var tier = WidthTier.initial(width: 1150)
    @State private var tierSeeded = false
    /// RESIZE-MOTION C2: the committed form of each header action row (`HeaderActionsForm`), decided here with the
    /// tier from the window width so the change is inside the animation transaction — never by layout.
    @State private var macActionsCompact = false
    @State private var iphoneActionsCompact = false
    /// RESIZE-MOTION C2: the subtitle form the content-fit probe chose last (`subtitleView`); drives opacity only.
    @State private var subtitleLevel = SubtitleLevel.full
    @State private var subtitleLevelSeeded = false
    /// Toolbar geometry shared by the layout and the header-form fit formula (RESIZE-MOTION C2): keep them equal.
    private static let toolbarSpacing: CGFloat = 12
    private static let actionsTrailingPad: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar

                // Only the content branches; the mode switch lives in `toolbar` outside this branch
                // (control-identity-branch).
                if router.mode == .mac {
                    content
                } else {
                    IPhoneModeView(model: iphone)
                }
            }
            .onChange(of: L10nStore.shared.language) {
                model.refreshReport(trigger: .automatic)
                commitWidthState(liveWidth.value, seeding: false, animated: false)
            }
            // REDESIGN-NOTIFY: a notification click navigates through the view-owned router (R5, D15).
            .onChange(of: model.externalDestinationSerial) { if let d = model.consumeExternalDestination() { router.navigate(to: d) } }
            .onAppear { if let d = model.consumeExternalDestination() { router.navigate(to: d) } }
            .background {
                if router.mode == .mac {
                    if router.canGoBack && !router.isInlineConfirmOpen { BackShortcuts { _ = router.back() } }
                } else if iphone.selectedDeviceKey != nil {
                    BackShortcuts { iphone.selectedDeviceKey = nil }
                }
            }
        }
        // One background owner for both modes (REDESIGN-HOME D13): nothing here depends on `router.mode`.
        .ds3Backdrop(orbs: DS3OrbSpec.window)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { w in
            liveWidth.value = w
            let nextBreakpoints = PageBreakpoints(width: w)
            if nextBreakpoints != breakpoints { breakpoints = nextBreakpoints }
            let seeding = !tierSeeded
            tierSeeded = true
            commitWidthState(w, seeding: seeding, animated: !seeding)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $router.isReportShown) { ReportSheet(model: model) { router.isReportShown = false } }
        .ds3PointerTracking(pointer)
    }

    /// This Mac content. Home stays mounted under an open page or report (opacity 0, no hits, hidden from
    /// accessibility) so Back does not replay its entrance (REDESIGN-HOME D7). `body` reads no live model field:
    /// `HomeView` and its slots do the reading (the Now card and the tiles keep the rule of reading live fields in their own structs).
    private var content: some View {
        ZStack {
            HomeView(model: model, router: router, width: liveWidth, tier: tier)
                .opacity(homeVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: homeVisible)   // opacity only — no size depends on it
                .allowsHitTesting(homeVisible)
                .accessibilityHidden(!homeVisible)
            if router.destination.page == .cpu {
                CPUPage(model: model, router: router)
                    .id(router.destination.page)
            } else if router.destination.page == .memory {
                MemoryPage(model: model, router: router, narrow: breakpoints.narrow)
                    .id(router.destination.page)
            } else if router.destination.page == .storage {
                StoragePage(model: model, router: router, breakpoints: breakpoints)
                    .id(router.destination.page)
            } else if router.destination.page == .battery {
                BatteryPage(model: model, router: router, narrow: breakpoints.narrow)
                    .id(router.destination.page)
            } else if router.destination.page == .security {
                SecurityPage(model: model, router: router, narrow: breakpoints.narrow)
                    .id(router.destination.page)
            } else if router.destination.page == .backups {
                BackupsPage(model: model, router: router, narrow: breakpoints.narrow)
                    .id(router.destination.page)
            } else if router.destination.page == .system {
                SystemPage(model: model, router: router)
                    .id(router.destination.page)
            } else if router.destination.page == .history {
                HistoryPage(model: model, router: router, narrow: breakpoints.narrow)
                    .id(router.destination.page)
            }
        }
    }

    private var homeVisible: Bool { router.destination.page == .home }

    // MARK: Toolbar (single row: title block · mode switch · flexible gap · per-mode actions)

    private var toolbar: some View {
        // Custom layout instead of an HStack + centred overlay: the switch is centred in the window, and the
        // actions are proposed only the width that is really left beside it. The actions' form is committed at the
        // root from the same width (RESIZE-MOTION C2); the layout still proposes the real room, which the actions'
        // last-resort ViewThatFits uses.
        // The horizontal paddings (leading 20 / trailing 18) sit on the sides, not on the layout, so the
        // layout's centre is the window's centre.
        CentredToolbarLayout(spacing: Self.toolbarSpacing) {
            // Pushes the title/subtitle clear of the traffic lights, so the toolbar's own `.padding(.top, 14)`
            // reads as the gap between the buttons and the title. Padding, not `.offset`: the header has to
            // actually grow, or the subtitle would ride into the bottom hairline. `titleBlock` is the tallest
            // child, so the mode switch and the actions stay centred in the taller header.
            titleBlock
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.top, headerTrafficLightBand)
                .padding(.leading, 20)
            // Centred in the window, outside the mode branch (control-identity-branch): the same x in both modes
            // at every width.
            DSSlidingSegmented(options: [AppMode.mac, .iphone], selection: $router.mode, size: .header, identifier: { m in
                m == .mac ? "main-mode-mac" : "main-mode-iphone"
            }, onReselect: { m in
                // The selected segment clicked again: This Mac → Home, Devices → the device list.
                if m == .mac && router.canGoBack { router.navigate(to: .home) }
                if m == .iphone && iphone.selectedDeviceKey != nil { iphone.selectedDeviceKey = nil }
            }) { m in
                m == .mac ? L.mainModeMac : L.mainModeDevices
            }
            Group {
                if router.mode == .mac {
                    MacHeaderActions(model: model, router: router, compact: macActionsCompact)
                } else {
                    IPhoneHeaderActions(model: iphone, compact: iphoneActionsCompact)
                }
            }
            .padding(.trailing, Self.actionsTrailingPad)
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(toolbarChrome)
    }

    /// `DS3GlassBar` (material + `DS3.bar`, following Liquid Glass / Reduce Transparency), a 1 pt inner top rim (`rimMid`, the same
    /// fade-to-clear stroke the card sheen uses), a 1 pt bottom `line` and the `.header` shadow stack.
    private var toolbarChrome: some View {
        DS3GlassBar()
        .overlay(alignment: .top) {
            DS3StretchSprite(shape: Rectangle(), content: .topRim(stops: [.init(color: DS3.rimMid, location: 0), .init(color: .clear, location: 0.15)], lineWidth: 1))
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS3.line).frame(height: 1)
        }
        .ds3ElevationSprite(.header, cornerRadius: 0)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppInfo.name)
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.285) // 19 pt · −0.015em
                .lineSpacing(1.9) // 19 pt · 1.1 line-height
                .lineLimit(1)
                .truncationMode(.tail)
            subtitleView
        }
    }

    /// One line, form picked by the space the leading side is actually offered (`ViewThatFits`): the richest form
    /// that fits wins. Recorded departure from handoff 00 §3 «tier from the window width» (user 2026-10-25): the mode
    /// switch takes the centre, so the window width does not say how much room is left. RESIZE-MOTION C2: the
    /// `ViewThatFits` stays the laid-out element but is invisible; the child it picks commits `subtitleLevel` through
    /// `withAnimation`, and the visible texts are overlay layers that only cross-fade — the layout decision drives
    /// opacity, never layout (no-measured-size-feedback). `.help` carries the full form.
    private var subtitleView: some View {
        let tiers = subtitleTiers
        return ViewThatFits(in: .horizontal) {
            subtitleText(tiers.full).onAppear { commitSubtitleLevel(.full) }
            subtitleText(tiers.mid).onAppear { commitSubtitleLevel(.mid) }
            subtitleText(tiers.short).truncationMode(.tail).onAppear { commitSubtitleLevel(.short) }
        }
        .opacity(0)
        .overlay(alignment: .leading) {
            // Proposed the chosen child's width: an outgoing wider text truncates with `…` while it fades (one layout
            // per level change, none per frame); the common prefix of two forms renders on the same pixels.
            ZStack(alignment: .leading) {
                subtitleText(tiers.full).opacity(subtitleLevel == .full ? 1 : 0)
                subtitleText(tiers.mid).opacity(subtitleLevel == .mid ? 1 : 0)
                subtitleText(tiers.short).truncationMode(.tail).opacity(subtitleLevel == .short ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tiers.full)
        .help(tiers.full)
    }

    /// The content-fit probe's choice, committed as the visible form. The first write (launch) and Reduce Motion /
    /// the fixture are instant; every later change cross-fades with the tier spring.
    private func commitSubtitleLevel(_ level: SubtitleLevel) {
        let animated = subtitleLevelSeeded && !reduceMotion && !DS3Motion.isFrozen
        subtitleLevelSeeded = true
        guard level != subtitleLevel else { return }
        withAnimation(animated ? DS3Motion.tierChange : nil) { subtitleLevel = level }
    }

    private func subtitleText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12))
            .foregroundStyle(DS3.muted)
            .monospacedDigit()
            .lineLimit(1)
    }

    /// full: model · chip · RAM · macOS ver (build) · uptime; mid drops the build; short keeps model · chip · uptime.
    /// Missing parts drop out; uptime is never dropped. No system yet → `mainCollectingInfo` in all three.
    private var subtitleTiers: (full: String, mid: String, short: String) {
        let none = L.mainCollectingInfo
        guard let sys = model.headerSystem else { return (none, none, none) }
        let ram = sys.memBytes.map { tight(fmtBytesParts($0)) }
        let osFull: String? = sys.osVersion.map { ver in
            let build = sys.osBuild.map { " (\($0))" } ?? ""
            return "macOS \(ver)\(build)"
        }
        let osShort: String? = sys.osVersion.map { "macOS \($0)" }
        let uptime = sys.uptime.map { L.headerUptimeChip($0) }

        func join(_ parts: [String?]) -> String {
            let present = parts.compactMap { $0 }
            return present.isEmpty ? none : present.joined(separator: " · ")
        }

        return (join([sys.modelName, sys.chip, ram, osFull, uptime]),
                join([sys.modelName, sys.chip, ram, osShort, uptime]),
                join([sys.modelName, sys.chip, uptime]))
    }

    /// Everything the window width decides — the tier and the two header forms — committed in ONE transaction
    /// (RESIZE-MOTION §3.1, C2). `seeding`: exact thresholds, no previous state (launch). `animated` is false for the
    /// seed and for a language switch (the strings swap instantly anyway); Reduce Motion and the fixture never animate.
    private func commitWidthState(_ w: CGFloat, seeding: Bool, animated: Bool) {
        let nextTier = seeding ? WidthTier.initial(width: w) : WidthTier.next(width: w, previous: tier)
        let macNext = HeaderActionsForm.compact(
            width: w, tier: nextTier, fitWidth: Self.fitWindowWidth(rowWidth: MacHeaderActions.fullRowIdealWidth()),
            previousCompact: seeding ? nil : macActionsCompact)
        let iphoneNext = HeaderActionsForm.compact(
            width: w, tier: nextTier, fitWidth: Self.fitWindowWidth(rowWidth: IPhoneHeaderActions.fullRowIdealWidth()),
            previousCompact: seeding ? nil : iphoneActionsCompact)
        guard nextTier != tier || macNext != macActionsCompact || iphoneNext != iphoneActionsCompact else { return }
        withAnimation((animated && !reduceMotion && !DS3Motion.isFrozen) ? DS3Motion.tierChange : nil) {
            tier = nextTier
            macActionsCompact = macNext
            iphoneActionsCompact = iphoneNext
        }
    }

    /// Smallest window width at which a header row of `rowWidth` pt shows its full form: the inverse of what
    /// `CentredToolbarLayout` proposes the trailing side, minus the actions' trailing padding (RESIZE-MOTION C2).
    @MainActor
    static func fitWindowWidth(rowWidth: CGFloat) -> CGFloat {
        CentredToolbarLayout.containerWidth(side: rowWidth + actionsTrailingPad, centreWidth: modeSwitchIdealWidth(),
                                            spacing: toolbarSpacing)
    }

    /// Ideal width of the header mode switch (the layout's centre), hosted once per language like the button labels.
    @MainActor
    private static func modeSwitchIdealWidth() -> CGFloat {
        ds3IdealWidth(key: "mode-switch|\(L.mainModeMac)|\(L.mainModeDevices)|header") {
            DSSlidingSegmented(options: [AppMode.mac, .iphone], selection: .constant(.mac), size: .header) { m in
                m == .mac ? L.mainModeMac : L.mainModeDevices
            }
        }
    }
}

/// The subtitle form the content-fit probe chose (RESIZE-MOTION C2).
private enum SubtitleLevel { case full, mid, short }

/// Esc and ⌘[ = Back (handoff 00 §5), installed only while a section page, the report or an iPhone device page is shown
/// (REDESIGN-FOUNDATION D8). Zero-size and hidden from accessibility: the visible Back chip
/// (REDESIGN-HOME) carries the label.
private struct BackShortcuts: View {
    let action: () -> Void
    var body: some View {
        ZStack {
            Button("", action: action).keyboardShortcut(.escape, modifiers: [])
            Button("", action: action).keyboardShortcut("[", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - This Mac header actions

// Extracted from MainDashboardView so that only this small subtree re-executes on live ticks / assessment
// changes — it is the only place in the header that reads the model's assessment and report state, so
// MainDashboardView.body itself does not depend on them.

/// Status pill · Report · Refresh report (01-window-chrome, «This Mac actions»).
@MainActor
struct MacHeaderActions: View {
    let model: DashboardModel
    let router: NavigationRouter
    /// The committed form (RESIZE-MOTION C2, `HeaderActionsForm`): compact below the tier boundary and whenever the
    /// full row would not fit with the margin to spare, decided at the window root inside the tier transaction so
    /// Report and Refresh animate between their two forms (one identity each).
    let compact: Bool

    var body: some View {
        let tasks = HomeModel.tasks(model.assessment, report: model.homeReport, disk: model.disk, battery: model.battery)
        let status = HomeModel.status(scan: HomeModel.scan(model.blockState(.scan)), tasks: tasks)
        let busy = model.isCollectingReport
        // Last resort only: the committed form leaves `HeaderActionsForm.margin` to spare, so this fallback fires
        // only when one layout pass loses more than that (programmatic resize, fullscreen exit, a flick) and then
        // snaps to compact rather than overlapping the mode switch. A status change never changes the form.
        ViewThatFits(in: .horizontal) {
            row(status: status, busy: busy, compact: compact)
            row(status: status, busy: busy, compact: true)
        }
    }

    private func row(status: HomeStatus, busy: Bool, compact: Bool) -> MacActionsRow {
        MacActionsRow(status: status, busy: busy, compact: compact,
                      onReport: { router.isReportShown = true },
                      onRefresh: { model.refreshReport(trigger: .button) })
    }

    /// Ideal width of the full row with the WIDEST of the four status texts, so the committed form never depends on
    /// the live status. Hosted once per language and status by `ds3IdealWidth` (RESIZE-MOTION C2).
    @MainActor
    static func fullRowIdealWidth() -> CGFloat {
        let statuses: [HomeStatus] = [.checking, .good, .attention, .critical]
        return statuses.map { status in
            ds3IdealWidth(key: "mac-actions-full|\(L10nStore.shared.language.rawValue)|\(status)") {
                MacActionsRow(status: status, busy: false, compact: false, onReport: {}, onRefresh: {})
            }
        }.max() ?? 0
    }
}

/// One row at one form, built from values only (no model) so the width probe can host it with any status.
private struct MacActionsRow: View {
    let status: HomeStatus
    let busy: Bool
    let compact: Bool
    let onReport: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HeaderStatusPill(status: status)
            reportButton
            refreshButton
        }
    }

    /// One button in both forms (RESIZE-MOTION §3.3): the label slot and the padding animate with the tier, the text
    /// keeps a constant frame and only fades, so the capsule shrinks into the mockup's 34 pt circle (D4).
    private var reportButton: some View {
        let font = Font.system(size: 13, weight: .semibold)
        let labelW = ds3IdealWidth(key: "report|\(L.commonReport)|13s") { Text(L.commonReport).font(font).lineLimit(1) }
        let iconW = ds3IdealWidth(key: "report|doc.text|13") { Image(systemName: "doc.text").font(.system(size: 13)) }
        return Button { onReport() } label: {
            HStack(spacing: compact ? 0 : 7) {
                Image(systemName: "doc.text").font(.system(size: 13))
                Color.clear
                    .frame(width: compact ? 0 : labelW)
                    .overlay(alignment: .leading) { Text(L.commonReport).frame(width: labelW, alignment: .leading) }
                    .clipped()
                    .opacity(compact ? 0 : 1)
            }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: compact ? (34 - iconW) / 2 : 15, topRim: 1,
                                    disabledOpacity: 0.5))
        .reportActionTraits(busy: busy)
    }

    private var refreshButton: some View {
        let font = Font.system(size: 13, weight: .semibold)
        let longW = ds3IdealWidth(key: "refresh|\(L.commonRefreshReport)|13s") { Text(L.commonRefreshReport).font(font).lineLimit(1) }
        let shortW = ds3IdealWidth(key: "refresh|\(L.commonRefresh)|13s") { Text(L.commonRefresh).font(font).lineLimit(1) }
        return Button { onRefresh() } label: {
            // The slot keeps the width while the spinner shows (swap-in-place); the two texts cross-fade in it.
            Color.clear
                .frame(width: compact ? shortW : longW)
                .overlay { Text(L.commonRefreshReport).frame(width: longW).opacity(compact ? 0 : 1) }
                .overlay { Text(L.commonRefresh).frame(width: shortW).opacity(compact ? 1 : 0) }
                .clipped()
                .dsSwapInPlace(busy) { ProgressView().controlSize(.small).tint(.white) }
        }
        .buttonStyle(DS3ButtonStyle(kind: .primary, height: 34, hPad: 16, disabledOpacity: 0.5))
        .disabled(busy)
        .accessibilityLabel(busy ? L.commonRefreshing : L.commonRefreshReport)
        .accessibilityIdentifier("main-refresh")
        .layoutPriority(2)
    }
}

/// The header status pill: not a button. The status is computed by `MacHeaderActions` (the same task list as the
/// Attention card, so the two never disagree) so the width probe can host the pill with any status. No
/// `.animation(_:value:)` (animation-value-size-coupling); the full text shows unless even the compact row of
/// `MacHeaderActions` does not fit.
private struct HeaderStatusPill: View {
    let status: HomeStatus

    var body: some View {
        let (colour, ink, text) = look(status)
        HStack(spacing: 8) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .ds3TintPanel(colour, from: 0.14, to: 0.14, ring: 0.45, cornerRadius: 999)
        .accessibilityElement(children: .combine)
    }

    private func look(_ status: HomeStatus) -> (Color, Color, String) {
        switch status {
        case .checking: return (DS3.muted, DS3.inkSoft, L.commonChecking)
        case .good: return (DS3.green, DS3.greenInk, L.commonAllGood)
        case .attention: return (DS3.amber, DS3.amberInk, L.commonNeedsAttention)
        case .critical: return (DS3.hot, DS3.hotInk, L.commonCritical)
        }
    }
}

private extension View {
    /// What both Report button forms share: tooltip, busy-disabled, label and identifier (the button opens a
    /// modal sheet, so it has no selected state).
    func reportActionTraits(busy: Bool) -> some View {
        self.help(L.commonReport)
            .disabled(busy)
            .accessibilityLabel(L.commonReport)
            .accessibilityIdentifier("main-report")
            .layoutPriority(1)
    }
}

/// Three subviews in order: leading, centre, trailing. The centre sits at the container's horizontal midpoint at its
/// ideal size; the sides are proposed only the width left on their side of it (minus `spacing`), so a side that
/// adapts to its proposal (`ViewThatFits`) picks its form from the real room. A side that reports more than it was
/// proposed keeps its size and stays flush at its own edge; the centre does not move.
struct CentredToolbarLayout: Layout {
    var spacing: CGFloat = 12

    /// Room one side is proposed in a container of `container` pt: the layout's rule, also used by
    /// `MainDashboardView.fitWindowWidth` through its inverse `containerWidth` (RESIZE-MOTION C2).
    static func sideWidth(container: CGFloat, centreWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        max(0, container / 2 - centreWidth / 2 - spacing)
    }

    /// Inverse of `sideWidth`: the smallest container width that proposes `side` pt to each side.
    static func containerWidth(side: CGFloat, centreWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        2 * (side + spacing) + centreWidth
    }

    private func sideProposals(width: CGFloat?, height: CGFloat?, centreWidth: CGFloat)
        -> (leading: ProposedViewSize, trailing: ProposedViewSize) {
        guard let width else {
            return (ProposedViewSize(width: nil, height: height), ProposedViewSize(width: nil, height: height))
        }
        let side = Self.sideWidth(container: width, centreWidth: centreWidth, spacing: spacing)
        return (ProposedViewSize(width: side, height: height), ProposedViewSize(width: side, height: height))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let centre = subviews[1].sizeThatFits(.unspecified)
        let sides = sideProposals(width: proposal.width, height: proposal.height, centreWidth: centre.width)
        let leading = subviews[0].sizeThatFits(sides.leading)
        let trailing = subviews[2].sizeThatFits(sides.trailing)
        let width = proposal.width ?? (leading.width + spacing + centre.width + spacing + trailing.width)
        return CGSize(width: width, height: max(leading.height, centre.height, trailing.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let centre = subviews[1].sizeThatFits(.unspecified)
        let sides = sideProposals(width: bounds.width, height: proposal.height, centreWidth: centre.width)
        let midY = bounds.midY
        subviews[0].place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading, proposal: sides.leading)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: midY), anchor: .center, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: midY), anchor: .trailing, proposal: sides.trailing)
    }
}
