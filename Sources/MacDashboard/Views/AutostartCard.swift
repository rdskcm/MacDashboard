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
    /// Gates the bulk "Удалить все (N)" confirm line, mirroring
    /// `pendingDeletePath` for the per-row flow.
    @State private var pendingBulkDelete = false

    /// Local mirror of the model's live orphan list, kept one step "behind" on
    /// removal so a just-deleted row can play its collapse animation (see
    /// `OrphanRow`) before actually leaving the list — synced from the real
    /// list via `syncDisplayOrphans`, called on every change.
    @State private var displayOrphans: [LaunchdPlistInfo] = []
    /// Paths currently playing their collapse-out animation (present in
    /// `displayOrphans` but already gone from the model's real orphan list).
    @State private var collapsingPaths: Set<String> = []

    /// Reconciles `displayOrphans`/`collapsingPaths` with the model's current
    /// orphan list: paths that disappeared from `orphans` are kept in
    /// `displayOrphans` and marked `collapsing` for one animation cycle (see
    /// `OrphanRow`'s `openAmount` writeup) instead of vanishing immediately;
    /// newly-appeared paths are appended right away. Mirrors the
    /// `EnergyCard`/`QuietStrip` collapse recipe applied per-row instead of
    /// per-section.
    private func syncDisplayOrphans(_ orphans: [LaunchdPlistInfo]) {
        let newPaths = Set(orphans.map(\.path))
        let removed = displayOrphans.filter { !newPaths.contains($0.path) && !collapsingPaths.contains($0.path) }
        // Just flips `collapsing` on — `OrphanRow` reacts via its own
        // `.onChange(of: collapsing)` and commits `displayOrphans.removeAll`
        // from a `withAnimation(..., completion:)` callback tied to its own
        // collapse actually finishing (see `OrphanRow.onCollapsed`), instead
        // of a `DispatchQueue.main.asyncAfter` racing a hardcoded duration
        // against the real animation.
        for row in removed {
            collapsingPaths.insert(row.path)
        }
        let displayedPaths = Set(displayOrphans.map(\.path))
        displayOrphans.append(contentsOf: orphans.filter { !displayedPaths.contains($0.path) })
    }

    var body: some View {
        if let auto = model.report.autostart {
            let orphans = (auto.userAgents + auto.systemAgents + auto.systemDaemons).filter(\.isOrphan)

            CardChrome(title: L.autostartTitle, trailing: { orphanHeader(orphans: orphans) }) {
                VStack(alignment: .leading, spacing: 12) {
                    orphanListSection(orphans: orphans)

                    // Scoped to just the launchd sections below, NOT
                    // `orphanListSection` above: `OrphanRow`/`BulkDeleteRow`
                    // each drive their own removal off a single `openAmount`
                    // mutated by one explicit `withAnimation` (see their doc
                    // comments) — an ambient `.animation(value:)` reaching
                    // into that subtree reintroduces exactly the "several
                    // things independently reacting to the same value"
                    // failure mode `EnergyCard.swift:89-98` documents. This
                    // still needs to stay keyed on `showOrphans` for the
                    // launchd sections themselves, which visibly shift
                    // up/down as the orphan list above them reveals/hides.
                    VStack(alignment: .leading, spacing: 12) {
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
                    .transition(.dsDisclosure(reduceMotion: reduceMotion))
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
            // spacing: 0 on both nested stacks (was 6/5): `OrphanRow` and
            // `BulkDeleteRow` each collapse to height 0 on their own via
            // `openAmount` (see their doc comments); a fixed VStack `spacing`
            // here would still be paid while a row's animated height is
            // already 0, only snapping shut when the array element is
            // finally dropped — the source of the reported "delay, then too
            // abrupt". Each row instead carries its own trailing gap as
            // `.padding(.bottom, …)` INSIDE its `openAmount`-scaled content,
            // so the gap shrinks together with the row instead of surviving
            // it.
            VStack(alignment: .leading, spacing: 0) {
                if !displayOrphans.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(displayOrphans, id: \.path) { info in
                            OrphanRow(
                                info: info,
                                isSystemLevel: isSystemLevel(info.path),
                                busy: model.deletingPlistPaths.contains(info.path),
                                isPending: pendingDeletePath == info.path,
                                collapsing: collapsingPaths.contains(info.path),
                                tooltip: orphanTooltip(info),
                                onAsk: {
                                    pendingDeletePath = info.path
                                    pendingBulkDelete = false
                                },
                                onCancel: { pendingDeletePath = nil },
                                onConfirm: {
                                    // Starts the collapse the instant the user confirms,
                                    // instead of waiting for the real Trash/`rm` operation
                                    // (a background disk op with real, user-visible latency)
                                    // to land in the model — that wait was read as "delay,
                                    // then abrupt" since nothing moved until the file op
                                    // finished. `syncDisplayOrphans` still marks this path
                                    // collapsing on its own if this optimistic insert is
                                    // ever missed, so a rare delete failure just leaves a
                                    // gone row that quietly reappears on the next report
                                    // refresh (surfaced via `plistDeleteError` either way).
                                    collapsingPaths.insert(info.path)
                                    model.deleteOrphanPlist(path: info.path, isSystemLevel: isSystemLevel(info.path))
                                    pendingDeletePath = nil
                                },
                                onCollapsed: {
                                    // Commits the removal on the animation
                                    // finishing, not on a wall clock — see
                                    // `OrphanRow`'s own `withAnimation(...,
                                    // completion:)` call for where this fires.
                                    collapsingPaths.remove(info.path)
                                    displayOrphans.removeAll { $0.path == info.path }
                                }
                            )
                        }
                    }
                }
                // Always mounted (not gated behind `displayOrphans.count >=
                // 2`): see `BulkDeleteRow`'s own doc comment for why it needs
                // the same `openAmount` collapse treatment as a row instead
                // of an `if`-gated appear/disappear.
                BulkDeleteRow(
                    orphans: displayOrphans,
                    busy: !displayOrphans.isEmpty && displayOrphans.allSatisfy { model.deletingPlistPaths.contains($0.path) },
                    pendingBulkDelete: $pendingBulkDelete,
                    onAsk: {
                        pendingDeletePath = nil
                        pendingBulkDelete = true
                    },
                    onConfirm: {
                        // Same optimistic-collapse reasoning as the single-row
                        // `onConfirm` above, applied to the whole batch.
                        for orphan in displayOrphans { collapsingPaths.insert(orphan.path) }
                        model.deleteOrphanPlists(paths: displayOrphans.map(\.path))
                        pendingBulkDelete = false
                    },
                    onCancel: { pendingBulkDelete = false }
                )
                if let plistDeleteError = model.plistDeleteError {
                    Text(L.autostartDeleteError(plistDeleteError))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.hot)
                        .padding(.top, 6)
                }
            }
            .onChange(of: orphans, initial: true) { _, newOrphans in
                syncDisplayOrphans(newOrphans)
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

    init(title: String, count: Int?, isExpanded: Binding<Bool>, content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self._isExpanded = isExpanded
        self.content = content
        // Seeds `openAmount` from the CURRENT binding value (e.g. Login Items
        // starts already-expanded, see `loginItemsExpanded` above) so the
        // first frame renders fully open/closed instead of animating in from
        // 0 on mount — see `openAmount`'s own doc comment for why this can't
        // just default to 0 and rely on `.onChange(of:initial:)` to correct
        // it post-mount (that would play one unwanted animated frame).
        self._openAmount = State(initialValue: isExpanded.wrappedValue ? 1 : 0)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    /// Single source of truth for the disclosure's progress, 0 = fully
    /// closed, 1 = fully open. Height/opacity/offset below are all PURE
    /// functions of this one value (see its assignment in `.onChange` below)
    /// instead of each being independently derived from `isExpanded` under a
    /// shared `.animation(value:)` — three modifiers each reacting to the same
    /// boolean can each set up their own implicit Core Animation transition,
    /// which measured out to a small but consistent ~15 ms longer pre-motion
    /// delay on collapse than on expand (live-testing wave 2: "same animation,
    /// reversed" complaint after the guillotine fix). Driving everything off
    /// one `Double`, mutated inside a single explicit `withAnimation` call,
    /// makes open and close provably the same interpolation played forward
    /// vs. backward — there is only one Animatable value, so there is nothing
    /// left that could start on a different frame between the two directions.
    @State private var openAmount: Double
    /// Natural (fully-expanded) height of `content()`, captured once via
    /// `.onGeometryChange` (below) instead of gating `content()`'s presence
    /// behind `if isExpanded`. The old `if isExpanded { content() }` +
    /// `.transition(.dsDisclosure)` shape let SwiftUI drive the removal via
    /// its own implicit remove-transition machinery, which is NOT the same
    /// per-frame interpolation as the container's `.clipped()` height
    /// shrink — on expand both grow from nothing in lockstep and it reads
    /// fine, but on collapse the already-fully-visible content raced the
    /// shrinking `.clipped()` frame and got hard-clipped ("guillotined")
    /// well before the fade/rise had sold the disappearance. Keeping
    /// `content()` permanently mounted and driving its *visible* height via
    /// `.frame(height:)` off this measured value — fed by the SAME
    /// `.animation(value: isExpanded)` below — makes open and close two
    /// directions of one continuous numeric interpolation, so they're
    /// genuinely symmetric. `.onGeometryChange` reports the child's actual
    /// rendered size, but the modifier chain still means `.frame(height:)`
    /// *wraps* the measured child, so the frame's proposed height flows
    /// DOWN into `content()` before geometry is read back up — this only
    /// stays a faithful "natural height" reading because `content()` itself
    /// has no height-flexible children (no bare `Spacer`, no layout that
    /// consumes `proposal.height`) that would collapse under a tight
    /// proposal; that's a documented constraint on what may go inside this
    /// disclosure, not an accident. It also isn't itself a GeometryReader
    /// sitting inside the animated/clipped subtree (the bug this project hit
    /// twice before, V2-CARD-MEM).
    ///
    /// Starts `nil` rather than `0`: sections that begin already-expanded
    /// (e.g. Login Items, see `loginItemsExpanded` above) must not be
    /// frame-clamped to zero for the one frame before the first
    /// `.onGeometryChange` callback fires. `nil` here means "no measurement
    /// yet" and is read by `.frame(height:)` below as "impose no height
    /// constraint," which lays the content out at its natural size — correct
    /// for the already-expanded case and harmless for the collapsed case
    /// (nothing is visible either way before first layout).
    @State private var measuredHeight: CGFloat?

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
            // Vertical padding is deliberately symmetric (5/5) instead of the
            // prototype's 3/7 (Overview Screen.dc.html:481) — user decision
            // 2026-08-09: the asymmetric box read as visibly bottom-heavy on
            // hover. Box height (25.5 pt) is unchanged.
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? DS.row : Color.clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                guard !isEmptySection else { return }
                isExpanded.toggle()
            }

            content()
                .padding(.leading, 18)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                    measuredHeight = newHeight
                }
                .frame(height: measuredHeight.map { $0 * openAmount }, alignment: .top)
                .clipped()
                .opacity(openAmount)
                .offset(y: reduceMotion ? 0 : DSMotion.discloseRiseY * (1 - openAmount))
        }
        // Backstop for the same offset-sliver case `EnergyCard` documents:
        // the inner `.clipped()` above already clamps the frame itself, but
        // that clamped box is offset by up to `DSMotion.discloseRiseY` while
        // collapsing/collapsed, which can poke a sliver above the header;
        // this outer clip re-clips to the current animated frame every frame.
        .clipped()
        // The single point where `isExpanded` (owned by the parent, e.g. by
        // `AutostartCard`) is translated into this row's own `openAmount`
        // progress — an explicit `withAnimation` here, rather than an
        // `.animation(value:)` on the modifiers above, so the whole
        // height/opacity/offset trio starts from the exact same transaction
        // in both directions (see `openAmount`'s doc comment).
        .onChange(of: isExpanded) { _, newValue in
            let target: Double = newValue ? 1 : 0
            let curve: Animation = reduceMotion
                ? .easeInOut(duration: DSMotion.reduceMotionFallback)
                : DSMotion.expand
            withAnimation(curve) { openAmount = target }
        }
    }
}

/// A single orphan-plist row, with its own collapse-to-height-0 mechanism —
/// same recipe as `AutoSectionRow.openAmount`/`measuredHeight` above and
/// `EnergyCard.openAmount`/`QuietStrip.openAmount` (Security/Updates/Crashes):
/// letting `ForEach`'s implicit remove-transition machinery drive a row's
/// disappearance races its fade against the container's own layout pass and
/// hard-clips it before the fade sells the exit ("guillotined"). Driving
/// height/opacity/offset off one `openAmount: Double`, mutated by a single
/// explicit `withAnimation` when `collapsing` flips true, fixes that — the
/// row stays mounted (fed by `AutostartCard.displayOrphans`, which lags the
/// model's real orphan list by one animation cycle on removal) until its own
/// collapse finishes, instead of vanishing the instant the model drops it.
private struct OrphanRow: View {
    let info: LaunchdPlistInfo
    let isSystemLevel: Bool
    let busy: Bool
    let isPending: Bool
    let collapsing: Bool
    let tooltip: String
    let onAsk: () -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void
    /// Fires once this row's own collapse animation has actually finished —
    /// the single commit point for `AutostartCard.displayOrphans.removeAll`
    /// (see its call site), replacing a `DispatchQueue.main.asyncAfter`
    /// racing a hardcoded duration against the real animation.
    let onCollapsed: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openAmount: Double = 1
    @State private var measuredHeight: CGFloat?

    var body: some View {
        rowContent
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                measuredHeight = newHeight
            }
            .frame(height: measuredHeight.map { $0 * openAmount } ?? (openAmount == 0 ? 0 : nil), alignment: .top)
            .clipShape(BleedRect(top: 20, leading: 20, trailing: 20))
            .opacity(openAmount)
            .offset(y: reduceMotion ? 0 : DSMotion.discloseRiseY * (1 - openAmount))
            // Outer backstop clip — same rationale as `EnergyCard`'s (see
            // its comment above `.clipShape(BleedRect(leading:trailing:))`,
            // EnergyCard.swift:146-159): the inner clip above is itself
            // offset upward by up to `DSMotion.discloseRiseY` while
            // collapsing/collapsed, so an already-clipped-to-zero-height row
            // can still poke a sliver above its neighbor without this outer
            // re-clip.
            .clipShape(BleedRect(leading: 20, trailing: 20))
            .onChange(of: collapsing, initial: true) { _, isCollapsing in
                guard isCollapsing else { return }
                let curve: Animation = reduceMotion
                    ? .easeInOut(duration: DSMotion.reduceMotionFallback)
                    : DSMotion.expand
                withAnimation(curve) {
                    openAmount = 0
                } completion: {
                    onCollapsed()
                }
            }
    }

    private var rowContent: some View {
        let fileName = URL(fileURLWithPath: info.path).lastPathComponent

        return VStack(alignment: .leading, spacing: 5) {
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
                .hoverTip(tooltip)
                Spacer(minLength: 8)
                if busy {
                    DSSpinner()
                } else if !isPending {
                    OrphanAskButton(title: L.autostartDeleteButton, action: onAsk)
                        .accessibilityLabel("\(L.autostartDeleteButton) \(fileName)")
                }
            }

            if isPending {
                HStack(spacing: 8) {
                    Text(isSystemLevel ? L.autostartDeleteConfirmMessageSystem : L.autostartDeleteConfirmMessageUser)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 8)
                    OrphanCancelButton(title: L.adviceCancel, action: onCancel)
                        .accessibilityLabel(L.adviceCancel)
                    OrphanConfirmDeleteButton(title: L.autostartDeleteButton, action: onConfirm)
                        .accessibilityLabel("\(L.autostartDeleteButton) \(fileName)")
                }
                .transition(.dsDisclosure(reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.row))
        // Inter-row gap, carried here (inside `rowContent`, i.e. inside the
        // `openAmount`-scaled block in `body` above) instead of as the
        // parent `VStack`'s own `spacing` — see that VStack's doc comment in
        // `orphanListSection`. Applied to every row including the last, so
        // this is a ~1pt approximation of the former 6pt gap before
        // `BulkDeleteRow`/the error text, not a pixel-exact carry-over.
        .padding(.bottom, 5)
        .animation(
            reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
            value: isPending
        )
    }
}

/// Bulk "Удалить все (N)" row, shown under the orphan list once there are
/// ≥ 2 orphans. Same ask → confirm → busy shape as `OrphanRow`'s own inline
/// confirm line, but acts on the whole batch via `model.deleteOrphanPlists(paths:)`
/// (one Touch ID/admin prompt for the whole batch).
///
/// Same `openAmount` collapse recipe as `OrphanRow` above — permanently
/// mounted, height/opacity/offset driven off one `Double` mutated by a
/// single explicit `withAnimation` — instead of the former `if
/// displayOrphans.count >= 2 { }.transition(...)` conditional mount/unmount:
/// that shape popped in/out unanimated the moment `displayOrphans.count`
/// crossed the threshold (which, after `OrphanRow.onCollapsed` started
/// committing that count change exactly when a row's own collapse finishes,
/// would otherwise be the one remaining "structural change landing
/// mid-collapse" left in this card). Picked over "hold mounted until the
/// collapse completes" because that alternative still needs an animated
/// mount/unmount transition of its own once `orphanListSection`'s ambient
/// `.animation(value: displayOrphans.count)` is gone (see that VStack's doc
/// comment) — this recipe already *is* that animated transition, reusing
/// the exact same one `OrphanRow` and `AutoSectionRow` use.
private struct BulkDeleteRow: View {
    let orphans: [LaunchdPlistInfo]
    let busy: Bool
    @Binding var pendingBulkDelete: Bool
    let onAsk: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(
        orphans: [LaunchdPlistInfo],
        busy: Bool,
        pendingBulkDelete: Binding<Bool>,
        onAsk: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.orphans = orphans
        self.busy = busy
        self._pendingBulkDelete = pendingBulkDelete
        self.onAsk = onAsk
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // Seeds `openAmount` from the CURRENT count so a launch with ≥ 2
        // orphans already showing doesn't animate in from 0 — same
        // rationale as `AutoSectionRow`'s init.
        _openAmount = State(initialValue: orphans.count >= 2 ? 1 : 0)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openAmount: Double
    @State private var measuredHeight: CGFloat?

    private var visible: Bool { orphans.count >= 2 }

    var body: some View {
        rowContent
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
                measuredHeight = newHeight
            }
            .frame(height: measuredHeight.map { $0 * openAmount } ?? (openAmount == 0 ? 0 : nil), alignment: .top)
            .clipShape(BleedRect(top: 20, leading: 20, trailing: 20))
            .opacity(openAmount)
            .offset(y: reduceMotion ? 0 : DSMotion.discloseRiseY * (1 - openAmount))
            .clipShape(BleedRect(leading: 20, trailing: 20))
            .onChange(of: visible, initial: true) { _, isVisible in
                let curve: Animation = reduceMotion
                    ? .easeInOut(duration: DSMotion.reduceMotionFallback)
                    : DSMotion.expand
                withAnimation(curve) { openAmount = isVisible ? 1 : 0 }
            }
    }

    private var rowContent: some View {
        let hasSystemLevel = orphans.contains { $0.path.hasPrefix("/Library/") }

        return HStack(spacing: 8) {
            if busy {
                DSSpinner()
                Text(L.autostartDeletingAll)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
            } else if pendingBulkDelete {
                Text(hasSystemLevel
                    ? L.autostartDeleteAllConfirmMessageSystem(orphans.count)
                    : L.autostartDeleteAllConfirmMessageUser(orphans.count))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
                OrphanConfirmDeleteButton(title: L.autostartDeleteAllButton(orphans.count), action: onConfirm)
                    .accessibilityLabel(L.autostartDeleteAllButton(orphans.count))
                OrphanCancelButton(title: L.adviceCancel, action: onCancel)
                    .accessibilityLabel(L.adviceCancel)
            } else {
                BulkDeleteAskButton(title: L.autostartDeleteAllButton(orphans.count), action: onAsk)
                    .accessibilityLabel(L.autostartDeleteAllButton(orphans.count))
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        // Trailing gap before the error text below, carried here instead of
        // in the parent `VStack`'s own `spacing` — see `OrphanRow.rowContent`'s
        // matching `.padding(.bottom, 5)` and `orphanListSection`'s doc
        // comment. Collapses to 0 together with this row since it lives
        // inside the `openAmount`-scaled block above.
        .padding(.bottom, 6)
        .animation(
            reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
            value: pendingBulkDelete
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

/// Bulk-row "Удалить все (N)" trigger — same hover-tint-to-hot shape as
/// `OrphanAskButton`, but at the spec's own padding for this row (v6/h12
/// rather than the per-row ask button's v5/h10).
private struct BulkDeleteAskButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? DS.hot : DS.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
