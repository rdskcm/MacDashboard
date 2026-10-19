// Views/MainDashboardView.swift
// One window chrome for both modes (REDESIGN-HOME, 01-window-chrome.md): the header (title block, mode switch,
// per-mode actions) and the single background (`DS3.ground` + `DS3OrbField`). Under the header the This Mac
// content is the Home page (HomeView.swift) with section pages shown in place over it
// (InterimSectionPage.swift); the Report view replaces both while `router.isReportShown`.

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
            .background {
                if router.canGoBack && router.mode == .mac && !router.isInlineConfirmOpen { BackShortcuts { _ = router.back() } }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { windowWidth = $0 }
        .ignoresSafeArea()
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
            if router.isReportShown {
                ReportTab(model: model)
            } else if router.destination.page == .cpu {
                CPUPage(model: model, router: router) { _ = router.back() }
                    .id(router.destination.page)
            } else if router.destination.page != .home {
                InterimSectionPage(model: model, page: router.destination.page, windowWidth: windowWidth, onConfirmShown: { router.isInlineConfirmOpen = $0 }) { _ = router.back() }
                    .id(router.destination.page)
            }
        }
    }

    private var homeVisible: Bool { !router.isReportShown && router.destination.page == .home }

    // MARK: Toolbar (single row: title block · mode switch · flexible gap · per-mode actions)

    /// Title block width by window width (01-window-chrome, width rules).
    private var titleWidth: CGFloat { windowWidth >= 1200 ? 460 : windowWidth >= 1000 ? 400 : 280 }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            // Pushes the title/subtitle clear of the traffic lights, so the toolbar's own `.padding(.top, 14)`
            // reads as the gap between the buttons and the title. Padding, not `.offset`: the header has to
            // actually grow, or the subtitle would ride into the bottom hairline. `titleBlock` is the tallest
            // child, so the mode switch and the actions stay centred in the taller header.
            titleBlock
                .frame(width: titleWidth, alignment: .leading)
                .padding(.top, headerTrafficLightBand)
            // Outside the mode branch (control-identity-branch); its x depends only on the title block width.
            DSSlidingSegmented(options: [AppMode.mac, .iphone], selection: $router.mode, size: .header, identifier: { m in
                m == .mac ? "main-mode-mac" : "main-mode-iphone"
            }, onReselect: { m in
                // «This Mac» clicked again on a section page or over the report: back to Home.
                if m == .mac && router.canGoBack { router.navigate(to: .home) }
            }) { m in
                m == .mac ? L.mainModeMac : L.mainModeIPhone
            }
            .layoutPriority(2)
            Spacer(minLength: 12)
            if router.mode == .mac {
                MacHeaderActions(model: model, router: router, narrow: windowWidth < 1000)
                    .layoutPriority(1.5)
            } else {
                IPhoneHeaderActions(model: iphone)
                    .layoutPriority(1.5)
            }
        }
        .padding(.top, 14)
        .padding(.trailing, 18)
        .padding(.bottom, 14)
        .padding(.leading, 20)
        .background(toolbarChrome)
    }

    /// `DS3.bar` over the `.regularMaterial` blur backdrop, a 1 pt inner top rim (`rimMid`, the same
    /// fade-to-clear stroke the card sheen uses), a 1 pt bottom `line` and the `.header` shadow stack.
    private var toolbarChrome: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle().fill(DS3.bar)
        }
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

    /// One line, tier picked from the window width (not by `ViewThatFits`, 00 §3); `.help` carries the full form.
    private var subtitleView: some View {
        let tiers = subtitleTiers
        return Text(tiers.text)
            .font(.system(size: 12))
            .foregroundStyle(DS3.muted)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .help(tiers.full)
    }

    /// ≥ 1200 → model · chip · RAM · macOS ver (build) · uptime; 1000-1199 drops the build; < 1000 keeps model ·
    /// chip · uptime. Missing parts drop out; uptime is never dropped. No system yet → `mainCollectingInfo`.
    private var subtitleTiers: (text: String, full: String) {
        guard let sys = model.headerSystem else { return (L.mainCollectingInfo, L.mainCollectingInfo) }
        let ram = sys.memBytes.map { tight(fmtBytesParts($0)) }
        let osFull: String? = sys.osVersion.map { ver in
            let build = sys.osBuild.map { " (\($0))" } ?? ""
            return "macOS \(ver)\(build)"
        }
        let osShort: String? = sys.osVersion.map { "macOS \($0)" }
        let uptime = sys.uptime.map { L.headerUptimeChip($0) }

        func join(_ parts: [String?]) -> String? {
            let present = parts.compactMap { $0 }
            return present.isEmpty ? nil : present.joined(separator: " · ")
        }

        let full = join([sys.modelName, sys.chip, ram, osFull, uptime]) ?? L.mainCollectingInfo
        let text: String
        if windowWidth >= 1200 {
            text = full
        } else if windowWidth >= 1000 {
            text = join([sys.modelName, sys.chip, ram, osShort, uptime]) ?? L.mainCollectingInfo
        } else {
            text = join([sys.modelName, sys.chip, uptime]) ?? L.mainCollectingInfo
        }
        return (text, full)
    }
}

/// Esc and ⌘[ = Back (handoff 00 §5), installed only while a section page or the report is shown
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
    let narrow: Bool

    var body: some View {
        HStack(spacing: 8) {
            HeaderStatusPill(model: model)
            reportButton
            refreshButton
        }
    }

    /// Narrow (< 1000 pt): a 34 pt circle with the icon only; otherwise the labelled secondary button.
    @ViewBuilder private var reportButton: some View {
        if narrow {
            Button { router.isReportShown.toggle() } label: {
                Image(systemName: "doc.text").font(.system(size: 13))
            }
            .buttonStyle(DS3CircleButtonStyle(diameter: 34, disabledOpacity: 0.5))
            .reportActionTraits(busy: model.isCollectingReport, shown: router.isReportShown)
        } else {
            Button { router.isReportShown.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text").font(.system(size: 13))
                    Text(L.commonReport)
                }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1, disabledOpacity: 0.5))
            .reportActionTraits(busy: model.isCollectingReport, shown: router.isReportShown)
        }
    }

    private var refreshButton: some View {
        Button { model.refreshReport(trigger: .button) } label: {
            // The hidden label keeps the width while the spinner shows (swap-in-place).
            Text(narrow ? L.commonRefresh : L.commonRefreshReport)
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
/// the full text shows at every width.
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
    /// What both Report button forms share: tooltip, busy-disabled, label, the shown state (selected trait while
    /// the report is open — the button is a toggle) and identifier.
    func reportActionTraits(busy: Bool, shown: Bool) -> some View {
        self.help(L.commonReport)
            .disabled(busy)
            .accessibilityLabel(L.commonReport)
            .accessibilityAddTraits(shown ? .isSelected : [])
            .accessibilityIdentifier("main-report")
            .layoutPriority(1)
    }
}
