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
    /// Window width, measured once at the window root (REDESIGN-HOME D18): column counts and text tiers of
    /// the header, Home and the section pages read it. Safe under `no-measured-size-feedback`: the number of
    /// columns cannot change the window's own width.
    @State private var windowWidth: CGFloat = 1150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // One background owner for both modes (REDESIGN-HOME D13): nothing here depends on `router.mode`.
            DS3.ground
            DS3OrbField()
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
            .onChange(of: L10nStore.shared.language) { model.refreshReport(trigger: .automatic) }
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
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { windowWidth = $0 }
        .ignoresSafeArea()
        .sheet(isPresented: $router.isReportShown) { ReportSheet(model: model) { router.isReportShown = false } }
        .ds3PointerTracking(pointer)
    }

    /// This Mac content. Home stays mounted under an open page or report (opacity 0, no hits, hidden from
    /// accessibility) so Back does not replay its entrance (REDESIGN-HOME D7). `body` reads no live model field:
    /// `HomeView` and its slots do the reading (the Now card and the tiles keep the rule of reading live fields in their own structs).
    private var content: some View {
        ZStack {
            HomeView(model: model, router: router, windowWidth: windowWidth)
                .opacity(homeVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: homeVisible)   // opacity only — no size depends on it
                .allowsHitTesting(homeVisible)
                .accessibilityHidden(!homeVisible)
            if router.destination.page == .cpu {
                CPUPage(model: model, router: router) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page == .memory {
                MemoryPage(model: model, router: router, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page == .storage {
                StoragePage(model: model, router: router, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page == .battery {
                BatteryPage(model: model, router: router, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page == .security {
                SecurityPage(model: model, router: router, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page == .backups {
                BackupsPage(model: model, router: router, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page == .system {
                SystemPage(model: model, router: router, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page == .history {
                HistoryPage(model: model, router: router, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            }
        }
    }

    private var homeVisible: Bool { router.destination.page == .home }

    // MARK: Toolbar (single row: title block · mode switch · flexible gap · per-mode actions)

    private var toolbar: some View {
        // Custom layout instead of an HStack + centred overlay: the switch is centred in the window, and the
        // actions are proposed only the width that is really left beside it, so their ViewThatFits picks the
        // full or compact form from that (a fixed window-width threshold would be wrong for one language).
        // The horizontal paddings (leading 20 / trailing 18) sit on the sides, not on the layout, so the
        // layout's centre is the window's centre.
        CentredToolbarLayout(spacing: 12) {
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
                    MacHeaderActions(model: model, router: router)
                } else {
                    IPhoneHeaderActions(model: iphone)
                }
            }
            .padding(.trailing, 18)
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(toolbarChrome)
    }

    /// `DS3GlassBar` (material + `DS3.bar`, following Liquid Glass / Reduce Transparency), a 1 pt inner top rim (`rimMid`, the same
    /// fade-to-clear stroke the card sheen uses), a 1 pt bottom `line` and the `.header` shadow stack.
    private var toolbarChrome: some View {
        DS3GlassBar()
        .overlay(
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: DS3.rimMid, location: 0),
                            .init(color: .clear, location: 0.15),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS3.line).frame(height: 1)
        }
        .ds3Elevation(.header, in: Rectangle())
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

    /// One line, tier picked by the space the leading side is actually offered (`ViewThatFits`): the richest tier that
    /// fits wins. Recorded departure from handoff 00 §3 «tier from the window width» (user 2026-10-25): the mode
    /// switch takes the centre, so the window width does not say how much room is left. `.help` carries the full form.
    private var subtitleView: some View {
        let tiers = subtitleTiers
        return ViewThatFits(in: .horizontal) {
            subtitleText(tiers.full)
            subtitleText(tiers.mid)
            subtitleText(tiers.short).truncationMode(.tail)
        }
        .help(tiers.full)
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
}

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

    /// Picks its form from the width `CentredToolbarLayout` offers: the full row, else the compact row (Report as
    /// icon first, then the short Refresh label); the pill text shortens only when even the compact row does not fit.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: 8) {
            HeaderStatusPill(model: model)
            reportButton(compact: compact)
            refreshButton(compact: compact)
        }
    }

    /// Compact: a 34 pt circle with the icon only; otherwise the labelled secondary button.
    @ViewBuilder private func reportButton(compact: Bool) -> some View {
        if compact {
            Button { router.isReportShown = true } label: {
                Image(systemName: "doc.text").font(.system(size: 13))
            }
            .buttonStyle(DS3CircleButtonStyle(diameter: 34, disabledOpacity: 0.5))
            .reportActionTraits(busy: model.isCollectingReport)
        } else {
            Button { router.isReportShown = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text").font(.system(size: 13))
                    Text(L.commonReport)
                }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1, disabledOpacity: 0.5))
            .reportActionTraits(busy: model.isCollectingReport)
        }
    }

    private func refreshButton(compact: Bool) -> some View {
        Button { model.refreshReport(trigger: .button) } label: {
            // The hidden label keeps the width while the spinner shows (swap-in-place).
            Text(compact ? L.commonRefresh : L.commonRefreshReport)
                .dsSwapInPlace(model.isCollectingReport) { ProgressView().controlSize(.small).tint(.white) }
        }
        .buttonStyle(DS3ButtonStyle(kind: .primary, height: 34, hPad: 16, disabledOpacity: 0.5))
        .disabled(model.isCollectingReport)
        .accessibilityLabel(model.isCollectingReport ? L.commonRefreshing : L.commonRefreshReport)
        .accessibilityIdentifier("main-refresh")
        .layoutPriority(2)
    }
}

/// The header status pill: not a button. Reads the same task list as the Attention card (same arguments as
/// `HomeAttentionSlot`), so the two never disagree. No `.animation(_:value:)` (animation-value-size-coupling);
/// the full text shows unless even the compact row of `MacHeaderActions` does not fit.
@MainActor
private struct HeaderStatusPill: View {
    let model: DashboardModel

    var body: some View {
        let tasks = HomeModel.tasks(model.assessment, report: model.homeReport, disk: model.disk, battery: model.battery)
        let status = HomeModel.status(scan: HomeModel.scan(model.blockState(.scan)), tasks: tasks)
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
private struct CentredToolbarLayout: Layout {
    var spacing: CGFloat = 12

    private func sideProposals(width: CGFloat?, height: CGFloat?, centreWidth: CGFloat)
        -> (leading: ProposedViewSize, trailing: ProposedViewSize) {
        guard let width else {
            return (ProposedViewSize(width: nil, height: height), ProposedViewSize(width: nil, height: height))
        }
        let side = max(0, width / 2 - centreWidth / 2 - spacing)
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
