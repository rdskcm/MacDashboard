// Views/AutostartCard.swift
// Автозагрузка card: Login Items, user/system agents & daemons, background tasks,
// plus an orphan-cleanup flow (Block N-orphan): a "check for outdated" button that
// reveals every launchd .plist whose backing executable is gone, each deletable
// (Trash for user-level, privileged `rm` for system-level).

import SwiftUI

// MARK: - Автозагрузка

@MainActor
struct AutostartCard: View {
    let model: DashboardModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Login Items expanded by default: it's the one section users most often
    // need to check/act on at a glance (the others are mostly Apple's own
    // agents/daemons, rarely actionable). The rest start collapsed.
    @State private var loginItemsExpanded = true
    @State private var userAgentsExpanded = false
    @State private var systemAgentsExpanded = false
    @State private var systemDaemonsExpanded = false
    @State private var backgroundExpanded = false

    /// Reveals the orphan cleanup list below the header; toggled by tapping
    /// `L.autostartCheckOutdated` in the card header.
    @State private var showOrphans = false
    /// Hover state for the header "check for outdated" capsule.
    @State private var checkButtonHovering = false
    /// Path of the orphan whose inline delete confirmation line is expanded;
    /// nil = none pending. Gates the inline confirm/cancel row in place of a
    /// system `.confirmationDialog` sheet.
    @State private var pendingDeletePath: String? = nil

    var body: some View {
        if let auto = model.report.autostart {
            let orphans = (auto.userAgents + auto.systemAgents + auto.systemDaemons).filter(\.isOrphan)

            CardChrome(title: L.autostartTitle, trailing: { orphanHeader(orphans: orphans) }) {
                VStack(alignment: .leading, spacing: 12) {
                    orphanListSection(orphans: orphans)

                    autoSection("Login Items", count: auto.loginItems?.count, isExpanded: $loginItemsExpanded) {
                        if let items = auto.loginItems {
                            PillFlow(items: items)
                        } else {
                            Text(L.autostartNoPermission).font(.system(size: 11.5)).foregroundStyle(DS.muted)
                        }
                    }
                    autoSection(L.autostartUserAgents, count: auto.userAgents.count, isExpanded: $userAgentsExpanded) { PlistPillFlow(items: auto.userAgents) }
                    autoSection(L.autostartSystemAgents, count: auto.systemAgents.count, isExpanded: $systemAgentsExpanded) { PlistPillFlow(items: auto.systemAgents) }
                    autoSection(L.autostartSystemDaemons, count: auto.systemDaemons.count, isExpanded: $systemDaemonsExpanded) { PlistPillFlow(items: auto.systemDaemons) }
                    if !auto.background.isEmpty {
                        autoSection(L.autostartBackgroundTasks, count: auto.background.count, isExpanded: $backgroundExpanded) {
                            FlowLayout(spacing: 6) {
                                ForEach(Array(auto.background.enumerated()), id: \.offset) { _, bg in
                                    Pill(text: bg.label)
                                        .hoverTip("PID \(bg.pid)")
                                }
                            }
                        }
                    }
                }
                .animation(
                    reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
                    value: showOrphans
                )
            }
        } else {
            CardChrome(title: L.autostartTitle) {
                SectionStateView(done: model.report.progress["autostart"] ?? false)
            }
        }
    }

    /// Slow pulsing glow for the "check for outdated" button when it has orphans to
    /// show — mirrors `PulsingBoltModifier` in `BatteryDetailPopover.swift` (same
    /// reduce-motion fallback + 2s easeInOut timing), adapted to a border/glow instead
    /// of icon opacity/scale.
    ///
    /// Block PERF: the pulse is FINITE (5 legs = 2.5 breaths, ~10 s), not
    /// `repeatForever` — a continuous animation kept `NSHostingView` re-laying out
    /// every frame and alone cost ~16pp of idle CPU (measured 2026-07-18). After the
    /// last leg the glow settles at the bright state, which still flags the orphans
    /// statically. The breathe is also gated on `DashboardModel.isPaused` (the same
    /// occlusion/miniaturization/activity signal that pauses the live collectors):
    /// cancelled while paused, restarted on resume — re-drawing attention each time
    /// the user comes back to the app.
    private struct BreathingWarnBackground: ViewModifier {
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        /// `DashboardModel.isPaused`: true when no effectively visible window exists
        /// or the app is inactive. Passed in by value from the card body so the
        /// modifier stays a plain value type.
        let paused: Bool
        @State private var isAnimating = false

        func body(content: Content) -> some View {
            if reduceMotion {
                content.background(
                    Capsule()
                        .strokeBorder(DS.amber, lineWidth: 1.5)
                        .shadow(color: DS.amber.opacity(0.5), radius: 6)
                )
            } else {
                content
                    .background(
                        Capsule()
                            .strokeBorder(DS.amber.opacity(isAnimating ? 1.0 : 0.5), lineWidth: 1.5)
                            .shadow(color: DS.amber.opacity(isAnimating ? 0.6 : 0.25), radius: 6)
                    )
                    .onAppear(perform: startBreathing)
                    .onDisappear { isAnimating = false }
                    .onChange(of: paused) { _, isNowPaused in
                        if isNowPaused { stopBreathing() } else { startBreathing() }
                    }
            }
        }

        /// Odd repeat count on purpose: with `autoreverses`, an odd number of legs
        /// ends the presentation at the bright state — which is also the model value
        /// (`isAnimating == true`) — so the animation finishes without a visible snap.
        private func startBreathing() {
            guard !paused, !isAnimating else { return }
            withAnimation(DSMotion.breathing) {
                isAnimating = true
            }
        }

        /// Cancelling an in-flight repeating animation in SwiftUI = writing a NEW
        /// value with a short non-repeating animation (re-setting the same value is
        /// a no-op and would leave the repeat running).
        private func stopBreathing() {
            withAnimation(.easeInOut(duration: 0.2)) { isAnimating = false }
        }
    }

    /// Card-header content: the "no outdated plists" reveal text (once checked and
    /// clean) plus the "check for outdated" capsule itself. Lives in `CardChrome`'s
    /// `trailing:` closure, after the `Spacer(minLength: 8)` it already renders.
    @ViewBuilder
    private func orphanHeader(orphans: [LaunchdPlistInfo]) -> some View {
        HStack(spacing: 8) {
            if showOrphans && orphans.isEmpty {
                Text(L.autostartOrphanEmptyText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.greenInk)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            checkButton(orphans: orphans)
        }
        .animation(
            reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
            value: showOrphans
        )
    }

    @ViewBuilder
    private func checkButton(orphans: [LaunchdPlistInfo]) -> some View {
        Button {
            showOrphans.toggle()
        } label: {
            if orphans.isEmpty {
                Text(L.autostartCheckOutdated)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(checkButtonHovering ? DS.ink : DS.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DS.glass3))
                    .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
            } else {
                Text(L.autostartCheckOutdatedCount(orphans.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.amberInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DS.glass3))
                    .overlay(Capsule().strokeBorder(DS.amber.opacity(0.62), lineWidth: 1))
                    .modifier(BreathingWarnBackground(paused: model.isPaused))
            }
        }
        .buttonStyle(.plain)
        .onHover { checkButtonHovering = $0 }
        .animation(
            reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
            value: checkButtonHovering
        )
        .accessibilityLabel(orphans.isEmpty ? L.autostartCheckOutdated : L.autostartCheckOutdatedCount(orphans.count))
    }

    /// The orphan list itself (once revealed) plus any delete error — lives in the
    /// card's main content column, above the launchd sections.
    @ViewBuilder
    private func orphanListSection(orphans: [LaunchdPlistInfo]) -> some View {
        if showOrphans {
            VStack(alignment: .leading, spacing: 6) {
                if !orphans.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(orphans, id: \.path) { info in
                            orphanRow(info)
                        }
                    }
                }
                if let plistDeleteError = model.plistDeleteError {
                    Text(L.autostartDeleteError(plistDeleteError))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.hot)
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private func orphanRow(_ info: LaunchdPlistInfo) -> some View {
        let busy = model.deletingPlistPaths.contains(info.path)
        let isPending = pendingDeletePath == info.path
        let fileName = URL(fileURLWithPath: info.path).lastPathComponent

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.amber)
                    Text(fileName)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .hoverTip(orphanTooltip(info))
                Spacer(minLength: 8)
                if busy {
                    DSSpinner()
                } else if !isPending {
                    OrphanAskButton(title: L.autostartDeleteButton) {
                        pendingDeletePath = info.path
                    }
                    .accessibilityLabel("\(L.autostartDeleteButton) \(fileName)")
                }
            }

            if isPending {
                HStack(spacing: 8) {
                    Text(isSystemLevel(info.path) ? L.autostartDeleteConfirmMessageSystem : L.autostartDeleteConfirmMessageUser)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 8)
                    OrphanCancelButton(title: L.adviceCancel) {
                        pendingDeletePath = nil
                    }
                    .accessibilityLabel(L.adviceCancel)
                    OrphanConfirmDeleteButton(title: L.autostartDeleteButton) {
                        model.deleteOrphanPlist(path: info.path, isSystemLevel: isSystemLevel(info.path))
                        pendingDeletePath = nil
                    }
                    .accessibilityLabel("\(L.autostartDeleteButton) \(fileName)")
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.row))
        .animation(
            reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
            value: isPending
        )
    }

    private func orphanTooltip(_ info: LaunchdPlistInfo) -> String {
        var parts: [String] = []
        if let description = info.description { parts.append(description) }
        if let executablePath = info.executablePath { parts.append(executablePath) }
        parts.append(L.autostartOrphanTooltip)
        return parts.joined(separator: "\n")
    }

    /// Paths under `~/Library/LaunchAgents` never start with `/Library/`, so this is
    /// unambiguous: system-level plists live at `/Library/LaunchAgents` or
    /// `/Library/LaunchDaemons`.
    private func isSystemLevel(_ path: String) -> Bool { path.hasPrefix("/Library/") }

    /// `count` is nil when the item list itself is unavailable (e.g. Login
    /// Items without permission) — shown without a "(N)" suffix in that case,
    /// and never tinted for containing orphans (only the pills inside are).
    @ViewBuilder
    private func autoSection<Content: View>(
        _ title: String, count: Int?, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        AutoSectionRow(title: title, count: count, isExpanded: isExpanded, content: content)
    }
}

/// A single collapsible launchd/Login-Items section header + its expanded pill
/// flow. Broken out as its own `View` (rather than a plain function returning
/// `some View`) so its hover `@State` is a real per-instance property — a helper
/// *function* on `AutostartCard` can't own `@State` of its own.
private struct AutoSectionRow<Content: View>: View {
    let title: String
    let count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// A concrete zero count (e.g. an empty agents/daemons list) never
    /// expands and reads muted; `nil` (permission unknown, e.g. Login Items)
    /// stays at the normal ink and remains tappable.
    private var isEmptySection: Bool { count == 0 }

    private var label: String {
        if let count { return "\(title) (\(count))" }
        return title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                DSDisclosureBars(expanded: isExpanded)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isEmptySection ? DS.muted : DS.inkSoft)
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? DS.row : Color.clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                guard !isEmptySection else { return }
                isExpanded.toggle()
            }

            if isExpanded {
                content()
                    .padding(.leading, 18)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
            value: isExpanded
        )
    }
}

// MARK: - Orphan-row action buttons

/// Per-orphan "Удалить" trigger — swaps itself out for the inline confirm/cancel
/// line in place. Mirrors `ProcessCards.swift`'s `ProcessOutlineNeutralButton`
/// shape at this card's own smaller padding (h10/v5), but tints `DS.hot` on
/// hover (unlike that button's neutral "Отмена") since this IS the entry point
/// into a destructive flow, not a cancel.
private struct OrphanAskButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? DS.hot : DS.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().strokeBorder(hovering ? DS.hot.opacity(0.45) : DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(
            reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
            value: hovering
        )
    }
}

/// Inline confirm-line "Отмена" — mirrors `ProcessCards.swift`'s
/// `ProcessOutlineNeutralButton`, at this card's own padding (h11/v5).
private struct OrphanCancelButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? DS.ink : DS.inkSoft)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(hovering ? DS.row : Color.clear))
                .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(
            reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
            value: hovering
        )
    }
}

/// Inline confirm-line destructive "Удалить" — mirrors `ProcessCards.swift`'s
/// `ProcessFilledHotButton`, at this card's own padding (h11/v5).
private struct OrphanConfirmDeleteButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(DS.hot))
        }
        .buttonStyle(.plain)
    }
}

/// Pill flow over `[LaunchdPlistInfo]` (Login Items stays on the plain-`[String]`
/// `PillFlow` — it has no plist behind it). Orphaned entries get a warning tint plus
/// a small triangle badge; every pill carries a composed hover tooltip (description +
/// executable path + orphan/OK status).
private struct PlistPillFlow: View {
    let items: [LaunchdPlistInfo]

    var body: some View {
        if items.isEmpty {
            Text(L.sharedEmpty).font(.system(size: 11.5)).foregroundStyle(DS.muted)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.path) { info in
                    PlistPill(info: info)
                }
            }
        }
    }
}

private struct PlistPill: View {
    let info: LaunchdPlistInfo

    var body: some View {
        HStack(spacing: 4) {
            if info.isOrphan {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
            }
            Text(URL(fileURLWithPath: info.path).lastPathComponent)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(info.isOrphan ? DS.amberInk : DS.inkSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().strokeBorder(info.isOrphan ? DS.amber.opacity(0.42) : DS.lineStrong, lineWidth: 1))
        .hoverTip(tooltip)
    }

    private var tooltip: String {
        var parts: [String] = []
        if let description = info.description { parts.append(description) }
        if let executablePath = info.executablePath { parts.append(executablePath) }
        parts.append(info.isOrphan ? L.autostartOrphanTooltip : L.autostartOkTooltip)
        return parts.joined(separator: "\n")
    }
}
