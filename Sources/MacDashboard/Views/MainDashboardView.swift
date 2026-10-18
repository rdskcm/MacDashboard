// Views/MainDashboardView.swift
// Header (title/sub/chips/refresh) + Overview|Report tab control. Under the header the This Mac
// content is the Home page (HomeView.swift) with section pages shown in place over it
// (InterimSectionPage.swift, REDESIGN-HOME); the Report tab replaces both.

import SwiftUI
import Charts

/// Vertical band the window's traffic-light buttons occupy, measured from the window's
/// top edge. `.windowStyle(.hiddenTitleBar)` (MacDashboardApp.swift:26) keeps AppKit's
/// standard titlebar and lets it draw those buttons over our content — they are not
/// SwiftUI views, so nothing in `toolbar`'s layout knows they are there. `toolbar`'s
/// `.padding(.leading, 78)` is the app's acknowledgement of them on the horizontal axis
/// for every child EXCEPT `titleBlock` (see `headerTitlePullLeft` below); this constant is
/// the vertical counterpart, and it is why the title block is padded down instead of being
/// left to centre itself against the window edge. Calibrated once from a screenshot — the
/// acceptance test is equal INK gaps above and below the title block (see the block's
/// verification), not this literal.
private let headerTrafficLightBand: CGFloat = 21

/// Once the title sits below the traffic lights rather than beside them (see
/// `headerTrafficLightBand` above), it no longer needs the full `.padding(.leading, 78)`
/// gutter that the tab control and the rest of the row still need — user decision
/// 2026-08-26 (V2-UI-POLISH). Applied as an `.offset`, not a smaller padding, so ONLY the
/// title's paint position moves; the tab control's x stays anchored to the row's shared
/// leading padding exactly as before, undisturbed by the title's own position.
private let headerTitlePullLeft: CGFloat = 58

@MainActor
struct MainDashboardView: View {
    var model: DashboardModel
    var iphone: IPhoneModel = .shared

    /// Option type of the Overview | Report tab control; the state lives in `router.isReportShown`.
    private enum Tab { case overview, report }
    /// REDESIGN-FOUNDATION: mode, report tab and (later) pages go through the router.
    @State private var router = NavigationRouter()
    @State private var pointer = DS3PointerTracker()
    /// Window width, measured once at the window root (REDESIGN-HOME D18): column counts and text tiers of
    /// Home and the section pages read it. Safe under `no-measured-size-feedback`: the number of columns
    /// cannot change the window's own width.
    @State private var windowWidth: CGFloat = 1150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if router.mode == .iphone {
                DS3.ground
                DS3OrbField()
            } else {
                DS.ground
                OrbLayer()
            }
            VStack(spacing: 0) {
                toolbar

                // Only the content branches; both segmented controls live in `toolbar`
                // outside this branch (control-identity-branch).
                if router.mode == .mac {
                    content
                } else {
                    IPhoneModeView(model: iphone)
                }
            }
            .onChange(of: L10nStore.shared.language) { model.refreshReport(trigger: .automatic) }
            .background {
                if router.canGoBack && router.mode == .mac { BackShortcuts { _ = router.back() } }
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
            } else if router.destination.page != .home {
                InterimSectionPage(model: model, page: router.destination.page, windowWidth: windowWidth) { _ = router.back() }
                    .id(router.destination.page)
            }
        }
    }

    private var homeVisible: Bool { !router.isReportShown && router.destination.page == .home }

    /// The tab control's selection, stored in the router.
    private var tabSelection: Binding<Tab> {
        Binding(get: { router.isReportShown ? .report : .overview },
                set: { router.isReportShown = ($0 == .report) })
    }

    // MARK: Toolbar (single row: title block · leading-anchored tab control · flexible gap · chips/status/refresh)

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 16) {
            titleBlock
                // Pushes the title/subtitle clear of the traffic lights, so the toolbar's
                // own `.padding(.top, 14)` below reads as the gap between the buttons and
                // the title — matching the 14 pt between the subtitle and the header's
                // bottom hairline. Padding, not `.offset`: the header has to actually grow,
                // or the subtitle would ride into that hairline. `titleBlock` is the
                // tallest child, so the tab control and the chips stay exactly centred in
                // the taller header rather than being dragged down with the title.
                .padding(.top, headerTrafficLightBand)
                .offset(x: -headerTitlePullLeft)
                .layoutPriority(1)
            // Anchored immediately after the title at a fixed gap (spacing: 16 above) —
            // this control's x position must never depend on window width. All slack
            // and all shrink pressure live to its right, past the flexible Spacer below.
            DSSlidingSegmented(options: [AppMode.mac, .iphone], selection: $router.mode, size: .tabs, identifier: { m in
                m == .mac ? "main-mode-mac" : "main-mode-iphone"
            }) { m in
                m == .mac ? L.mainModeMac : L.mainModeIPhone
            }
            .layoutPriority(2)
            DSSlidingSegmented(options: [Tab.overview, .report], selection: tabSelection, size: .tabs, identifier: { t in
                switch t {
                case .overview: return "main-tab-overview"
                case .report: return "main-tab-report"
                }
            }) { t in
                switch t {
                case .overview: return L.mainTabOverview
                case .report: return L.mainTabReport
                }
            }
            .layoutPriority(2)
            // Stays mounted in iPhone mode (D14): hidden, not removable, so the header
            // geometry is identical across modes.
            .opacity(router.mode == .mac ? 1 : 0)
            .allowsHitTesting(router.mode == .mac)
            .accessibilityHidden(router.mode != .mac)
            Spacer(minLength: 12)
            // No layoutPriority here (default 0): chips own the progressive-hiding
            // ViewThatFits tiers and must be the first child to lose space.
            if router.mode == .mac {
                HeaderChipsView(model: model)
            } else {
                // Above the title (1): the title block claims its whole ideal width (the full
                // subtitle tier) before any lower-priority sibling is sized, which left the buttons
                // only what remained (compact icon below ~1230 pt, «Иск…» clipped at 900). Here the
                // subtitle tiers yield first; `titleBlock`'s name is pinned in iPhone mode, so it never does.
                IPhoneHeaderActions(model: iphone)
                    .layoutPriority(1.5)
            }
        }
        .padding(.leading, 78)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .background(toolbarChrome)
    }

    /// Fill `DS.glass2` layered over the same `.regularMaterial` blur backdrop
    /// `dsCardSurface()` uses (DesignSystem.swift), a bottom hairline border, and
    /// a 1 pt inset top highlight using the same fade-to-clear stroke technique
    /// `dsCardSurface()` applies for its own sheen line — mirrored here on a
    /// plain (unrounded) rectangle since the toolbar spans the full width.
    private var toolbarChrome: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle().fill(DS.glass2)
            // Slightly darkens the header only (user request 2026-08-10) — a local
            // tint on top of the shared `DS.glass2` fill rather than changing that
            // token, since it's also shared with Settings' toolbar and the language
            // dropdown's hover fill.
            Rectangle().fill(Color(light: Color.black.opacity(0.035), dark: Color.black.opacity(0.12)))
        }
        .overlay(
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: DS.sheenLine, location: 0),
                            .init(color: .clear, location: 0.15),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.line).frame(height: 1)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppInfo.name)
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.285) // 19 pt · −0.015em
                .lineSpacing(1.9) // 19 pt · 1.1 line-height
                .lineLimit(1)
                .truncationMode(.tail)
                // iPhone mode ranks the actions above the title (see `toolbar`), so the name is
                // pinned to its width there and only the subtitle tiers give way. In This Mac mode
                // the title keeps its original truncating behaviour (`false` is a no-op).
                .fixedSize(horizontal: router.mode == .iphone, vertical: false)
            subtitleView
        }
    }

    /// Tiered subtitle: model · chip · RAM · macOS ver (build) → …ver → …RAM → …chip → model.
    /// Mirrors `HeaderChipsView`'s `ViewThatFits` idiom — the row DROPS a trailing
    /// segment when it doesn't fit rather than ellipsizing mid-string, so `.fixedSize`
    /// on every tier forces `ViewThatFits` to measure intrinsic width and pick a tier,
    /// not truncate one. `L.mainCollectingInfo` is a single segment, so it's one tier.
    private var subtitleView: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(subtitleTiers.indices, id: \.self) { i in
                Text(subtitleTiers[i])
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .truncationMode(i == subtitleTiers.count - 1 ? .tail : .head)
            }
        }
    }

    private var subtitleTiers: [String] {
        guard let sys = model.headerSystem else { return [L.mainCollectingInfo] }
        let modelName = sys.modelName
        let chip = sys.chip
        let ram = sys.memBytes.map { tight(fmtBytesParts($0)) }
        let osFull: String? = sys.osVersion.map { ver in
            let build = sys.osBuild.map { " (\($0))" } ?? ""
            return "macOS \(ver)\(build)"
        }
        let osShort: String? = sys.osVersion.map { "macOS \($0)" }

        func join(_ parts: [String?]) -> String? {
            let present = parts.compactMap { $0 }
            return present.isEmpty ? nil : present.joined(separator: " · ")
        }

        let candidates: [String?] = [
            join([modelName, chip, ram, osFull]),
            join([modelName, chip, ram, osShort]),
            join([modelName, chip, ram]),
            join([modelName, chip]),
            join([modelName]),
        ]

        // Optional fields collapse out of the join, so adjacent tiers can come out
        // identical (e.g. no osBuild ⇒ tier 1 == tier 2; no chip ⇒ tier 3 == tier 4).
        // Dedup consecutive duplicates so ViewThatFits never wastes a measurement slot.
        var tiers: [String] = []
        for t in candidates.compactMap({ $0 }) where tiers.last != t {
            tiers.append(t)
        }
        return tiers.isEmpty ? [L.mainCollectingInfo] : tiers
    }
}

/// Esc and ⌘[ = Back (handoff 00 §5), installed only while a section page is shown
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

// Extracted from MainDashboardView so that only this small subtree re-executes
// on live ticks / assessment changes — it's the only place in the header that
// reads the model's live fields / assessment, so MainDashboardView.body itself no
// longer depends on them (avoids re-running the whole overview tree on every
// 3s live tick).
@MainActor
struct HeaderChipsView: View {
    let model: DashboardModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if let load = model.load, !load.isEmpty {
                    Chip(text: L.headerLoadChip(load.map { fmtNum($0, decimals: 2) }.joined(separator: " / "), model.ncpu))
                }
                if let uptime = model.headerSystem?.uptime {
                    Chip(text: L.headerUptimeChip(uptime))
                }
                SeverityChip(isGood: statusIsGood, tone: statusTone, label: statusLabel, hasCrit: statusHasCrit)
                refreshButton
            }
            HStack(spacing: 8) {
                if let uptime = model.headerSystem?.uptime {
                    Chip(text: L.headerUptimeChip(uptime))
                }
                SeverityChip(isGood: statusIsGood, tone: statusTone, label: statusLabel, hasCrit: statusHasCrit)
                refreshButton
            }
            HStack(spacing: 8) {
                SeverityChip(isGood: statusIsGood, tone: statusTone, label: statusLabel, hasCrit: statusHasCrit)
                refreshButton
            }
        }
    }

    // Status chip is bound to the live assessment — never a static severity/text
    // pair — so it can never disagree with `model.assessment`. Tone comes from
    // the SAME shared `tone(for:)` (SharedUI.swift) applied to the SAME
    // `summarySev` that the Home attention card's hero reads, instead of a
    // second parallel "is this bad" computation — the two can no longer
    // disagree because they're reading one computed value through one function.
    private var statusIsGood: Bool { model.assessment.problems.isEmpty }
    private var statusHasCrit: Bool { model.assessment.summarySev == .crit || model.assessment.summarySev == .serious }
    private var statusTone: Color { tone(for: model.assessment.summarySev) }
    private var statusLabel: String { statusIsGood ? L.recommendationsAllGood : L.headerStatusNeedsAttention }

    private var refreshButton: some View {
        RainbowCapsuleButton(title: L.headerRefreshReport, busy: model.isCollectingReport, recipe: .overview, size: .primary) {
            model.refreshReport(trigger: .button)
        }
        .accessibilityLabel(L.headerRefreshReport)
    }
}
