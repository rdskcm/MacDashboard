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

    // Login Items expanded by default: it's the one section users most often
    // need to check/act on at a glance (the others are mostly Apple's own
    // agents/daemons, rarely actionable). The rest start collapsed.
    @State private var loginItemsExpanded = true
    @State private var userAgentsExpanded = false
    @State private var systemAgentsExpanded = false
    @State private var systemDaemonsExpanded = false
    @State private var backgroundExpanded = false

    /// Reveals the orphan cleanup list below the button; toggled by tapping
    /// `L.autostartCheckOutdated`.
    @State private var showOrphans = false
    /// Path of the orphan awaiting the delete confirmation dialog; nil = none pending.
    @State private var pendingDeletePath: String? = nil

    var body: some View {
        CardChrome(title: L.autostartTitle) {
            if let auto = model.report.autostart {
                VStack(alignment: .leading, spacing: 12) {
                    orphanCleanupSection(auto)

                    autoSection("Login Items", count: auto.loginItems?.count, isExpanded: $loginItemsExpanded) {
                        if let items = auto.loginItems {
                            PillFlow(items: items)
                        } else {
                            Text(L.autostartNoPermission).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    autoSection(L.autostartUserAgents, count: auto.userAgents.count, isExpanded: $userAgentsExpanded, hasOrphans: auto.userAgents.contains(where: \.isOrphan)) { PlistPillFlow(items: auto.userAgents) }
                    autoSection(L.autostartSystemAgents, count: auto.systemAgents.count, isExpanded: $systemAgentsExpanded, hasOrphans: auto.systemAgents.contains(where: \.isOrphan)) { PlistPillFlow(items: auto.systemAgents) }
                    autoSection(L.autostartSystemDaemons, count: auto.systemDaemons.count, isExpanded: $systemDaemonsExpanded, hasOrphans: auto.systemDaemons.contains(where: \.isOrphan)) { PlistPillFlow(items: auto.systemDaemons) }
                    if !auto.background.isEmpty {
                        autoSection(L.autostartBackgroundTasks, count: auto.background.count, isExpanded: $backgroundExpanded) {
                            FlowLayout(spacing: 6) {
                                ForEach(Array(auto.background.enumerated()), id: \.offset) { _, bg in
                                    Pill(text: bg.label)
                                        .help("PID \(bg.pid)")
                                }
                            }
                        }
                    }
                }
            } else {
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
                        .strokeBorder(Severity.warn.color, lineWidth: 1.5)
                        .shadow(color: Severity.warn.color.opacity(0.5), radius: 6)
                )
            } else {
                content
                    .background(
                        Capsule()
                            .strokeBorder(Severity.warn.color.opacity(isAnimating ? 1.0 : 0.5), lineWidth: 1.5)
                            .shadow(color: Severity.warn.color.opacity(isAnimating ? 0.6 : 0.25), radius: 6)
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
            withAnimation(.easeInOut(duration: 2.0).repeatCount(5, autoreverses: true)) {
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

    /// "Check for outdated" button + (once tapped) the list of orphaned plists across
    /// all three launchd sections, each with a delete affordance.
    @ViewBuilder
    private func orphanCleanupSection(_ auto: AutostartInfo) -> some View {
        let orphans = (auto.userAgents + auto.systemAgents + auto.systemDaemons).filter(\.isOrphan)

        VStack(alignment: .leading, spacing: 6) {
            Button {
                showOrphans.toggle()
            } label: {
                if orphans.isEmpty {
                    Text(L.autostartCheckOutdated)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                } else {
                    Text(L.autostartCheckOutdatedCount(orphans.count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Severity.warn.color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .modifier(BreathingWarnBackground(paused: model.isPaused))
                }
            }
            .buttonStyle(.plain)

            if showOrphans {
                if orphans.isEmpty {
                    Text(L.autostartNoOrphans).font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(orphans, id: \.path) { info in
                            orphanRow(info)
                        }
                    }
                }
                if let plistDeleteError = model.plistDeleteError {
                    Text(L.autostartDeleteError(plistDeleteError)).font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(L.autostartDeleteConfirmTitle, isPresented: pendingDeleteBinding) {
            if let path = pendingDeletePath {
                Button(L.autostartDeleteButton, role: .destructive) {
                    model.deleteOrphanPlist(path: path, isSystemLevel: isSystemLevel(path))
                }
                Button(L.adviceCancel, role: .cancel) {}
            }
        } message: {
            if let path = pendingDeletePath {
                Text(isSystemLevel(path) ? L.autostartDeleteConfirmMessageSystem : L.autostartDeleteConfirmMessageUser)
            }
        }
    }

    @ViewBuilder
    private func orphanRow(_ info: LaunchdPlistInfo) -> some View {
        let busy = model.deletingPlistPaths.contains(info.path)
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Severity.warn.color)
                Text(URL(fileURLWithPath: info.path).lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .hoverTip(orphanTooltip(info))
            Spacer(minLength: 8)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    pendingDeletePath = info.path
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func orphanTooltip(_ info: LaunchdPlistInfo) -> String {
        var parts: [String] = []
        if let description = info.description { parts.append(description) }
        if let executablePath = info.executablePath { parts.append(executablePath) }
        parts.append(L.autostartOrphanTooltip)
        return parts.joined(separator: "\n")
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(get: { pendingDeletePath != nil }, set: { if !$0 { pendingDeletePath = nil } })
    }

    /// Paths under `~/Library/LaunchAgents` never start with `/Library/`, so this is
    /// unambiguous: system-level plists live at `/Library/LaunchAgents` or
    /// `/Library/LaunchDaemons`.
    private func isSystemLevel(_ path: String) -> Bool { path.hasPrefix("/Library/") }

    /// `count` is nil when the item list itself is unavailable (e.g. Login
    /// Items without permission) — shown without a "(N)" suffix in that case.
    @ViewBuilder
    private func autoSection<Content: View>(
        _ title: String, count: Int?, isExpanded: Binding<Bool>, hasOrphans: Bool = false, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let label = count.map { "\(title) (\($0))" } ?? title
        DisclosureGroup(isExpanded: isExpanded) {
            content().padding(.top, 6)
        } label: {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(hasOrphans ? Severity.warn.color : .secondary)
        }
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
            Text(L.sharedEmpty).font(.caption).foregroundStyle(.secondary)
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
        .font(.caption)
        .foregroundStyle(info.isOrphan ? Severity.warn.color : .primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().strokeBorder(info.isOrphan ? Severity.warn.color.opacity(0.6) : Color.primary.opacity(0.18)))
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
