// Views/SystemPage.swift
// REDESIGN-SYSTEM: the System section page (handoff 09-system) on the shared §8 blocks. Every text, tone, row and
// state comes from the pure SystemPageModel; this file only draws them and forwards actions to DashboardModel.
// No pulse on any button (user decision 2026-10-22): the attention cues are the tag, the dots and the primary button.

import SwiftUI

@MainActor
struct SystemPage: View {
    let model: DashboardModel
    let router: NavigationRouter

    @State private var pulse: CardID? = nil
    /// Each card reports its own inline confirm; the router flag (Back shortcuts off) is their OR.
    @State private var startupConfirmOpen = false
    @State private var energyConfirmOpen = false

    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the cards do the reading.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SystemSleepCard(model: model)
                        .id(CardID.sleep)
                        .sectionFocusPulse(pulse == .sleep)
                        .ds3Appear(delay: 0.08)
                    SystemStartupCard(model: model, router: router, onConfirmShown: { startupConfirmOpen = $0; router.isInlineConfirmOpen = startupConfirmOpen || energyConfirmOpen })
                        .id(CardID.auto)
                        .sectionFocusPulse(pulse == .auto)
                        .ds3Appear(delay: 0.14)
                    SystemBrewCard(model: model)
                        .id(CardID.brew)
                        .sectionFocusPulse(pulse == .brew)
                        .ds3Appear(delay: 0.20)
                    SystemEnergyCard(model: model, router: router, onConfirmShown: { energyConfirmOpen = $0; router.isInlineConfirmOpen = startupConfirmOpen || energyConfirmOpen })
                        .id(CardID.energy)
                        .sectionFocusPulse(pulse == .energy)
                        .ds3Appear(delay: 0.26)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { SystemPageBar(model: model, onBack: { _ = router.back() }) }
            .task(id: router.navigationSerial) {
                // Deep link: scroll the focused card under the bar (Sleep is already on top) and pulse it.
                let d = router.destination
                guard d.page == .system, let f = d.focus else { return }
                if f != .sleep { proxy.scrollTo(f, anchor: .top) }
                pulse = f
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
        .onDisappear { router.isInlineConfirmOpen = false }
    }
}

// MARK: - Input and mapping helpers

/// `ignored` overrides the stored ignore list (visual fixture only); `pending` is the Energy card's edit state.
@MainActor
private func systemInput(_ model: DashboardModel, pending: [EnergyChange] = [], ignored: [IgnoredWakeHolder]? = nil,
                         now: Date) -> SystemPageModel.Input {
    .init(wakeSampled: model.wakeSampled, wakeHolders: model.wakeHolders, systemWakeHolders: model.systemWakeHolders,
          ignored: ignored ?? AppSettings.shared.ignoredWakeHolderEntries,
          autostart: model.report.autostart, startupChecking: model.startupChecking,
          startupCheckedAt: model.startupCheckedAt, startupRemoved: model.startupRemovedCount,
          deletingPaths: model.deletingPlistPaths, plistFailure: model.plistDeleteFailure,
          brewStatus: model.report.brewStatus, brewOutdated: model.report.brewOutdated,
          brewDetail: model.report.brewOutdatedDetail, brewInstalled: model.report.brewInstalledCount,
          brewCheckedAt: model.brewCheckedAt, brewUpgrading: model.brewUpgrading, brewProgress: model.brewProgress,
          brewError: model.brewUpgradeError, brewNotice: model.brewUpgradeNotice, brewRefreshing: model.brewRefreshing,
          energy: model.report.energy, energyPending: pending, energyApply: model.energyApply, now: now)
}

private func tagTone(_ t: SystemTone) -> DS3Tag.Tone {
    switch t {
    case .green: return .green
    case .amber: return .amber
    case .hot: return .hot
    case .neutral: return .neutral
    case .accent: return .accent
    }
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it. No Refresh button on this page.
@MainActor
struct SystemPageBar: View {
    let model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        let m = SystemPageModel.make(systemInput(model, now: model.fixtureNow ?? Date()))
        // The mockup bar has the title block flexible and the tag at the far right: it goes in the trailing slot.
        SectionPageBar(symbol: Page.system.symbol, title: Page.system.title, sub: m.sub, onBack: onBack) {
            EmptyView()
        } trailing: {
            DS3Tag(tone: tagTone(m.tag), text: m.tagText).help(m.tagText)
        }
    }
}

// MARK: - Sleep card

/// Internal: the visual fixture renders it (`initialHidden` / `initialHiddenOpen` exist for the snapshots only).
@MainActor
struct SystemSleepCard: View {
    let model: DashboardModel
    let initialHidden: [IgnoredWakeHolder]?
    @State private var hiddenOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: DashboardModel, initialHidden: [IgnoredWakeHolder]? = nil, initialHiddenOpen: Bool = false) {
        self.model = model
        self.initialHidden = initialHidden
        _hiddenOpen = State(initialValue: initialHiddenOpen)
    }

    var body: some View {
        let m = SystemPageModel.make(systemInput(model, ignored: initialHidden, now: model.fixtureNow ?? Date()))
        let rowCurve = sectionRowAnimation(reduceMotion: reduceMotion)
        let rowTransition = sectionRowTransition(reduceMotion: reduceMotion)
        DS3Card(title: L.sysSleepTitle, caption: m.sleepCaption) {
            Button { AdviceActionRunner.openApp(AdviceApps.activityMonitor) } label: {
                Text(L.sysActivityMonitor)
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 13))
            .accessibilityLabel(L.sysActivityMonitor)
            .accessibilityIdentifier("system-activity-monitor")
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                switch m.sleepState {
                case .wait:
                    SectionWait(text: L.commonCollectingData)
                case .none:
                    SectionNote(tone: DS3.green, text: L.sysSleepNone)
                case .blockers:
                    SectionList(ring: true) {
                        ForEach(m.sleepRows) { row in
                            SleepRowView(row: row) {
                                withAnimation(rowCurve) { model.setWakeHolderIgnored(row.key, ignored: true) }
                            }
                            .transition(rowTransition)
                        }
                    }
                }
                if m.hiddenCount > 0 {
                    SectionList(ring: true) {
                        SectionCollapsibleGroup(title: L.sysHidden, count: m.hiddenCount, isOpen: $hiddenOpen,
                                                enabled: true, bodyInset: 20, bodyTrailing: 0, bodyBottom: 4) {
                            VStack(spacing: 4) {
                                ForEach(m.hiddenRows) { r in
                                    SectionRowsRow(name: r.name, sub: r.sub) {
                                        Button {
                                            withAnimation(rowCurve) { model.setWakeHolderIgnored(r.key, ignored: false) }
                                        } label: {
                                            Text(L.sysWarnAgain)
                                        }
                                        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 28, hPad: 12, fontSize: 12.5))
                                        .help(r.a11y)
                                        .accessibilityLabel(r.a11y)
                                        .accessibilityIdentifier("system-warn-again-\(r.id)")
                                    }
                                    .transition(rowTransition)
                                }
                            }
                        }
                    }
                    .transition(rowTransition)
                }
            }
        }
    }
}

/// One blocker: dot (amber when the app would warn, muted for system services), name, age, «Don’t warn».
private struct SleepRowView: View {
    let row: SleepRow
    let onDontWarn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(row.warnable ? DS3.amber : DS3.muted).frame(width: 7, height: 7)
            Text(row.name)
                .font(.system(size: 14))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .layoutPriority(1)
                .help(row.name)
            Spacer(minLength: 8)
            // Mockup: the age is the 12.5 muted secondary text; the 64 pt value column after it stays empty.
            Text(row.age)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(DS3.muted)
                .lineLimit(1)
            Color.clear.frame(width: 64, height: 1)
            if row.warnable {
                Button(action: onDontWarn) { Text(L.sysDontWarn) }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 28, hPad: 12, fontSize: 12.5))
                    .accessibilityLabel(L.sysDontWarnA11y(row.name))
                    .accessibilityIdentifier("system-dont-warn-\(row.id)")
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Startup items card

/// Internal: the visual fixture renders it (`initialOpen` / `initialConfirm` exist for the snapshots only).
@MainActor
struct SystemStartupCard: View {
    let model: DashboardModel
    let router: NavigationRouter
    /// Reports the confirm's visibility to the page (which ORs both cards); nil = set the router flag directly.
    let onConfirmShown: ((Bool) -> Void)?
    @State private var open: Set<StartupGroupID>
    @State private var pendingDelete: PendingDelete?
    /// Local copy of the stale rows, written inside `withAnimation`: the rows leave when `report.autostart` drops
    /// them, which happens in the model, so the view mirrors the list to play the row transition.
    @State private var rows: [StaleRow]
    @State private var bulkInFlight = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum PendingDelete: Equatable { case one(StaleRow), all }

    init(model: DashboardModel, router: NavigationRouter, initialOpen: Set<StartupGroupID>? = nil,
         initialConfirm: Bool = false, onConfirmShown: ((Bool) -> Void)? = nil) {
        self.model = model
        self.router = router
        self.onConfirmShown = onConfirmShown
        _open = State(initialValue: initialOpen ?? [.login])
        _pendingDelete = State(initialValue: initialConfirm ? .all : nil)
        _rows = State(initialValue: SystemPageModel.make(systemInput(model, now: model.fixtureNow ?? Date())).staleRows)
    }

    /// The ageing caption («checked just now» → «checked 10:31») re-renders once a minute.
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            card(now: model.fixtureNow ?? ctx.date)
        }
    }

    private var rowCurve: Animation { sectionRowAnimation(reduceMotion: reduceMotion) }
    private var confirmCurve: Animation { reduceMotion ? .easeOut(duration: 0.12) : DS3Motion.popIn }

    @ViewBuilder
    private func card(now: Date) -> some View {
        let m = SystemPageModel.make(systemInput(model, now: now))
        DS3Card(title: L.sysStartupTitle, caption: m.startupWait ? nil : m.startupCaption) {
            Button { model.checkStaleStartupItemsNow() } label: {
                Text(L.sysCheckStale).dsSwapInPlace(m.startupChecking) {
                    HStack(spacing: 8) {
                        DS3Spinner(role: .track, size: 13)
                        Text(L.sysChecking)
                    }
                }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14,
                                        disabledOpacity: m.startupChecking ? 1 : 0.45))
            .disabled(m.startupChecking || m.startupBusy)
            .accessibilityLabel(L.sysCheckStale)
            .ds3BusyValue(m.startupChecking)
            .accessibilityIdentifier("system-check-stale")
        } content: {
            if m.startupWait {
                SectionWait(text: L.commonCollectingData)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    SectionList(ring: true) {
                        ForEach(m.groups) { g in
                            SectionCollapsibleGroup(title: g.title, count: g.count,
                                                    warn: g.staleCount > 0 ? L.sysGroupStale(g.staleCount) : nil,
                                                    isOpen: binding(g.id), enabled: g.count != 0, bodyInset: 30) {
                                groupBody(g)
                            }
                        }
                    }
                    if let note = m.startupNote { noteView(note) }
                    if let p = pendingDelete { confirm(p, m) }
                    if !rows.isEmpty || bulkBusy(m) { rowsBlock(m) }
                }
            }
        }
        .onChange(of: m.staleRows) { _, new in
            withAnimation(rowCurve) { rows = new }
            // A pending single delete whose row vanished (or a pending bulk one with nothing left) is void.
            switch pendingDelete {
            case .one(let r)? where !new.contains(where: { $0.id == r.id }): pendingDelete = nil
            case .all? where new.isEmpty: pendingDelete = nil
            default: break
            }
        }
        .onChange(of: m.startupChecked) { _, checked in
            if checked { openStaleGroups(m) }
        }
        .onChange(of: m.startupChecking) { old, new in
            if old && !new { openStaleGroups(m) }
        }
        .onChange(of: m.startupBusy) { _, busy in
            if !busy { bulkInFlight = false }
        }
        .onChange(of: pendingDelete != nil) { _, shown in reportConfirm(shown) }
        .onAppear {
            if m.startupChecked { openStaleGroups(m) }
            if pendingDelete != nil { reportConfirm(true) }
        }
        .onDisappear { reportConfirm(false) }
    }

    private func reportConfirm(_ shown: Bool) {
        if let onConfirmShown { onConfirmShown(shown) } else { router.isInlineConfirmOpen = shown }
    }

    private func bulkBusy(_ m: SystemPageModel) -> Bool { bulkInFlight && m.startupBusy }

    private func openStaleGroups(_ m: SystemPageModel) {
        for g in m.groups where g.staleCount > 0 { open.insert(g.id) }
    }

    private func binding(_ id: StartupGroupID) -> Binding<Bool> {
        Binding(get: { open.contains(id) },
                set: { if $0 { open.insert(id) } else { open.remove(id) } })
    }

    @ViewBuilder
    private func groupBody(_ g: StartupGroup) -> some View {
        if g.noPermission {
            Text(L.autostartNoPermission)
                .font(.system(size: 12.5))
                .foregroundStyle(DS3.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(g.pills, id: \.id) { p in
                    // The mockup names the pills without the «.plist» extension (the stale rows below keep the file name).
                    SectionPill(text: p.text.hasSuffix(".plist") ? String(p.text.dropLast(6)) : p.text,
                                stale: p.stale, help: p.help)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func noteView(_ n: StartupNote) -> some View {
        switch n {
        case .noStale: SectionNote(tone: DS3.green, text: L.sysNoStale)
        case .failed(let d): SectionNote(tone: DS3.hot, text: L.sysDeleteFailed(d))
        case .cancelled: SectionNote(tone: DS3.hot, text: L.sysDeleteCancelled)
        case .timedOut: SectionNote(tone: DS3.hot, text: L.sysDeleteTimedOut)
        }
    }

    // MARK: confirm

    private func confirm(_ p: PendingDelete, _ m: SystemPageModel) -> some View {
        let targets: [StaleRow]
        switch p {
        case .one(let r): targets = [r]
        case .all: targets = m.staleRows
        }
        let user = targets.filter { !$0.isSystemLevel }.count
        let system = targets.count - user
        return SectionConfirmPanel(
            title: SystemPageModel.startupConfirmTitle(targets.count),
            paragraphs: SystemPageModel.confirmParagraphs(userCount: user, systemCount: system),
            cancelTitle: L.sysEnergyCancel,
            confirmTitle: L.sysDelete,
            confirmKind: .dangerSolid,
            busy: false,
            onCancel: { withAnimation(confirmCurve) { pendingDelete = nil } },
            onConfirm: { perform(p, m) }
        )
        .transition(.opacity)
    }

    private func perform(_ p: PendingDelete, _ m: SystemPageModel) {
        switch p {
        case .one(let r):
            if let live = m.staleRows.first(where: { $0.id == r.id }) {
                bulkInFlight = false
                model.deleteOrphanPlist(path: live.id, isSystemLevel: live.isSystemLevel)
            }
        case .all:
            let paths = m.staleRows.map(\.id)
            if !paths.isEmpty {
                bulkInFlight = true
                model.deleteOrphanPlists(paths: paths)
            }
        }
        withAnimation(confirmCurve) { pendingDelete = nil }
    }

    // MARK: stale rows

    /// One List container (as in the mockup): the stale rows, then «Delete all (n)» right-aligned inside the same
    /// container; the whole container dims while a delete runs.
    private func rowsBlock(_ m: SystemPageModel) -> some View {
        let busy = m.startupBusy
        let bulk = bulkBusy(m)
        return SectionRows {
            ForEach(rows) { row in
                SectionRowsRow(icon: "exclamationmark.triangle", tint: DS3.amber, name: row.fileName,
                               nameMono: true, sub: row.folder) {
                    Button {
                        withAnimation(confirmCurve) { pendingDelete = .one(row) }
                    } label: {
                        Text(L.sysDelete).dsSwapInPlace(row.deleting) { DS3Spinner(role: .track, size: 13) }
                    }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 28, hPad: 12, fontSize: 12.5,
                                                disabledOpacity: busy ? 1 : 0.45, dangerOnHover: true))
                    .disabled(busy || m.startupChecking)
                    .accessibilityLabel(row.a11yDelete)
                    .ds3BusyValue(row.deleting)
                    .accessibilityIdentifier("system-delete-\(row.fileName)")
                }
                .transition(sectionRowTransition(reduceMotion: reduceMotion))
            }
            if m.showDeleteAll || bulk {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(confirmCurve) { pendingDelete = .all }
                    } label: {
                        Text(L.sysDeleteAll(m.staleRows.count)).dsSwapInPlace(bulk) {
                            HStack(spacing: 8) {
                                DS3Spinner(role: .track, size: 13)
                                Text(L.sysDeleting)
                            }
                        }
                    }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5,
                                                disabledOpacity: busy ? 1 : 0.45, dangerOnHover: true))
                    .disabled(busy || m.startupChecking)
                    .accessibilityLabel(L.sysDeleteAll(m.staleRows.count))
                    .ds3BusyValue(bulk)
                    .accessibilityIdentifier("system-delete-all")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .opacity(busy ? 0.55 : 1)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.14), value: busy)
    }
}

// MARK: - Homebrew card

/// Internal: the visual fixture renders it.
@MainActor
struct SystemBrewCard: View {
    let model: DashboardModel
    @State private var showConfirm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = SystemPageModel.make(systemInput(model, now: model.fixtureNow ?? Date()))
        let updating = m.brewState == .updating
        DS3Card(title: L.sysBrewTitle, caption: m.brewCaption.isEmpty ? nil : m.brewCaption) {
            if showsUpdateButton(m) {
                // One Button for «Update packages…» and «Updating…» so it keeps its identity and width: the
                // idle label stays underneath at opacity 0 (`swap-in-place`).
                Button { showConfirm = true } label: {
                    Text(L.sysBrewUpdate).dsSwapInPlace(updating) {
                        HStack(spacing: 8) {
                            DS3Spinner(role: .track, size: 13)
                            Text(m.brewUpdatingLabel)
                        }
                    }
                }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, disabledOpacity: 1))
                .disabled(updating)
                .accessibilityLabel(updating ? m.brewUpdatingLabel : L.sysBrewUpdate)
                .ds3BusyValue(updating)
                .accessibilityIdentifier("system-brew-update")
            }
        } content: {
            content(m)
        }
        .brewUpgradeConfirm(isPresented: $showConfirm, model: model)
    }

    /// Outdated or updating; a stopped upgrade with packages left offers the same button (no other way back).
    private func showsUpdateButton(_ m: SystemPageModel) -> Bool {
        switch m.brewState {
        case .outdated, .updating: return true
        case .stopped: return !m.brewRows.isEmpty
        default: return false
        }
    }

    @ViewBuilder
    private func content(_ m: SystemPageModel) -> some View {
        switch m.brewState {
        case .wait:
            SectionWait(text: L.commonCollectingData)
        case .none:
            SectionNote(tone: DS3.muted, text: L.sysBrewNotInstalled,
                        button: (L.sysBrewHowToInstall, L.sysBrewHowToInstall, false, {
                            if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
                        }),
                        buttonIdentifier: "system-brew-how-to-install")
        case .outdated:
            list(m)
        case .updating:
            VStack(alignment: .leading, spacing: 16) {
                updatingPanel(m)
                list(m).opacity(0.55)
            }
        case .ok:
            SectionNote(tone: DS3.green, text: m.brewNoteText)
        case .checkFailed:
            SectionNote(tone: DS3.amber, text: L.sysBrewCheckFailed,
                        button: (L.commonTryAgain, L.commonTryAgain, m.brewRefreshing, { model.refreshBrewNow() }),
                        buttonIdentifier: "system-brew-recheck")
        case .upgradeFailed(let msg):
            VStack(alignment: .leading, spacing: 16) {
                SectionNote(tone: DS3.hot, text: msg,
                            button: (L.commonTryAgain, L.commonTryAgain, false, { showConfirm = true }),
                            buttonIdentifier: "system-brew-try-again")
                if !m.brewRows.isEmpty { list(m) }
            }
        case .stopped(let notice):
            VStack(alignment: .leading, spacing: 16) {
                SectionNote(tone: DS3.muted, text: notice)
                if !m.brewRows.isEmpty { list(m) }
            }
        }
    }

    private func list(_ m: SystemPageModel) -> some View {
        SectionList(ring: true) {
            ForEach(m.brewRows) { r in
                SectionListRow(dot: DS3.amber, name: r.name, sub: r.sub, value: "", subTrailing: true)
            }
        }
    }

    /// Spinner, status line, `brew upgrade` in small mono, Stop, and the indeterminate bar (a system control, so
    /// Reduce Motion keeps it).
    private func updatingPanel(_ m: SystemPageModel) -> some View {
        let status: String = model.brewStopRequested
            ? (model.brewUpgradeStoppable ? L.maintenanceBrewStopping : L.maintenanceBrewRechecking)
            : m.brewProgressText
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DS3Spinner(role: .tinted, size: 14)
                Text(status)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS3.accentInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text("brew upgrade")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
                // Not in the mockup: the app can stop a running upgrade, so Stop stays (kept from the earlier build).
                Button { model.stopBrewUpgrade() } label: { Text(L.maintenanceBrewStopButton) }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                    .disabled(!model.brewUpgradeStoppable || model.brewStopRequested)
                    .accessibilityLabel(L.maintenanceBrewStopA11y)
                    .accessibilityIdentifier("system-brew-stop")
            }
            ProgressView()
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ds3TintPanel(DS3.accent, from: 0.16, to: 0.06, ring: 0.42, cornerRadius: 20)
    }
}

// MARK: - Energy settings card

/// Internal: the visual fixture renders it (`initial*` parameters exist for the snapshots only).
@MainActor
struct SystemEnergyCard: View {
    let model: DashboardModel
    let router: NavigationRouter
    /// Reports the confirm's visibility to the page (which ORs both cards); nil = set the router flag directly.
    let onConfirmShown: ((Bool) -> Void)?
    @State private var pending: [EnergyChange]
    @State private var infoKey: String?
    @State private var showConfirm: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: DashboardModel, router: NavigationRouter, initialPending: [EnergyChange] = [],
         initialInfoKey: String? = nil, initialConfirm: Bool = false,
         onConfirmShown: ((Bool) -> Void)? = nil) {
        self.model = model
        self.router = router
        self.onConfirmShown = onConfirmShown
        _pending = State(initialValue: initialPending)
        _infoKey = State(initialValue: initialInfoKey)
        _showConfirm = State(initialValue: initialConfirm)
    }

    private var applying: Bool { model.energyApply == .applying }
    private var curve: Animation { sectionRowAnimation(reduceMotion: reduceMotion) }
    private var confirmCurve: Animation { reduceMotion ? .easeOut(duration: 0.12) : DS3Motion.popIn }

    var body: some View {
        let m = SystemPageModel.make(systemInput(model, pending: pending, now: model.fixtureNow ?? Date()))
        DS3Card(title: L.sysEnergyTitle, caption: m.energyCaption) {
            content(m)
        }
        .onChange(of: model.energyApply) { _, new in
            switch new {
            case .applied:
                pending = []
                showConfirm = false
            case .failed(.error):
                pending = []
                showConfirm = false
            default:
                break
            }
        }
        .onChange(of: showConfirm) { _, shown in reportConfirm(shown) }
        .onAppear { if showConfirm { reportConfirm(true) } }
        .onDisappear { reportConfirm(false) }
    }

    private func reportConfirm(_ shown: Bool) {
        if let onConfirmShown { onConfirmShown(shown) } else { router.isInlineConfirmOpen = shown }
    }

    @ViewBuilder
    private func content(_ m: SystemPageModel) -> some View {
        if m.energyWait {
            SectionWait(text: L.commonCollectingData)
        } else if m.energyEmpty {
            SectionNote(tone: DS3.muted, text: L.sysEnergyEmpty,
                        button: (L.commonTryAgain, L.commonTryAgain, model.energyRefreshing, { model.refreshEnergyNow() }),
                        buttonIdentifier: "system-energy-retry")
        } else {
            // One mockup block: bar, banner, confirm and table are 8 pt apart.
            VStack(alignment: .leading, spacing: 8) {
                if let banner = m.energyBanner { bannerView(banner) }
                if m.showActionBar { actionBar(m) }
                if showConfirm { confirmPanel(m) }
                table(m)
                    .opacity(applying ? 0.55 : 1)
                    .disabled(applying)
            }
        }
    }

    // MARK: banner and action bar

    private func bannerView(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS3.hotInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { model.dismissEnergyApplyResult() } label: { Text(L.sysOK) }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                .accessibilityLabel(L.sysOK)
                .accessibilityIdentifier("system-energy-ok")
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 8))
        .background(Capsule().fill(DS3.hot.opacity(0.12)))
        .ds3InsetRims(Capsule(), ring: DS3.hot.opacity(0.40))
    }

    private func actionBar(_ m: SystemPageModel) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(confirmCurve) { showConfirm = true }
            } label: {
                Text(L.sysEnergyApply(m.dirtyCount)).dsSwapInPlace(applying) { DS3Spinner(role: .onSolid, size: 12) }
            }
            .buttonStyle(DS3ButtonStyle(kind: .primary, height: 30, hPad: 13, fontSize: 12.5, disabledOpacity: 0.5))
            .disabled(m.dirtyCount == 0 || applying)
            .accessibilityLabel(L.sysEnergyApply(m.dirtyCount))
            .ds3BusyValue(applying)
            .accessibilityIdentifier("system-energy-apply")

            Button {
                withAnimation(curve) { pending = []; showConfirm = false }
            } label: {
                Text(L.sysEnergyCancel)
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5, disabledOpacity: 0.5))
            .disabled(m.dirtyCount == 0 || applying)
            .accessibilityLabel(L.sysEnergyCancel)
            .accessibilityIdentifier("system-energy-cancel")

            Button {
                guard let energy = model.report.energy else { return }
                let new = SystemPageModel.resetChanges(energy: energy, pending: pending)
                guard new != pending else { return }
                withAnimation(curve) { pending = new }
                if model.energyApply == .applied { model.dismissEnergyApplyResult() }
            } label: {
                Text(L.sysEnergyReset)
            }
            .buttonStyle(DS3ButtonStyle(kind: .outline, height: 30, hPad: 13, fontSize: 12.5))
            .disabled(applying)
            .help(L.sysEnergyResetHelp)
            .accessibilityLabel(L.sysEnergyReset)
            .accessibilityIdentifier("system-energy-reset")

            Spacer(minLength: 8)
            if m.showApplied {
                Text(L.sysEnergyApplied)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS3.greenInk)
            }
        }
    }

    private func confirmPanel(_ m: SystemPageModel) -> some View {
        SectionConfirmPanel(
            title: m.confirmTitle,
            paragraphs: m.confirmLines,   // one line per paragraph, as in the mockup
            note: L.sysEnergyConfirmAdmin,
            cancelTitle: L.sysEnergyCancel,
            confirmTitle: L.sysEnergyConfirmApply,
            confirmKind: .primary,
            busy: applying,
            onCancel: { withAnimation(confirmCurve) { showConfirm = false } },
            onConfirm: {
                model.applyEnergyChanges(pending)
                withAnimation(confirmCurve) { showConfirm = false }
            }
        )
        .transition(.opacity)
    }

    // MARK: table

    /// Mockup table: columns `[flex] 96 96 30`, no gaps; every cell has a 1 pt hairline on top and 6 pt vertical
    /// padding around a 24 pt minimum (36 pt rows); the header cells carry 8 pt.
    private func table(_ m: SystemPageModel) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text(L.sysEnergyColSetting).frame(maxWidth: .infinity, alignment: .leading)
                Text(L.sysEnergyColBattery).frame(width: 96, alignment: .trailing)
                Text(L.sysEnergyColAC).frame(width: 96, alignment: .trailing)
                Color.clear.frame(width: 30, height: 1)
            }
            .font(.system(size: 12))
            .foregroundStyle(DS3.muted)
            .padding(.vertical, 8)
            ForEach(m.energyRows) { row in
                GridRow {
                    Text(row.spec.label)
                        .font(.system(size: 13.5))
                        .foregroundStyle(row.spec.kind == .readOnly ? DS3.muted : DS3.ink)
                        .lineLimit(1)
                        .help(row.spec.label)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(DS3.line).frame(height: 1) }
                    valueCell(row, .battery, column: L.sysEnergyColBattery)
                    valueCell(row, .ac, column: L.sysEnergyColAC)
                    infoButton(row)
                }
                if infoKey == row.id {
                    GridRow {
                        Text(row.spec.info)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DS3.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS3.row))
                            .padding(.bottom, 8)
                            .gridCellColumns(4)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 22, style: .continuous), ring: DS3.line)
    }

    /// 22 pt circle with an italic serif «i» (the mockup draws a glyph, not an SF Symbol); open = lens fill.
    private func infoButton(_ row: EnergyRow) -> some View {
        let open = infoKey == row.id
        return Button {
            withAnimation(curve) { infoKey = open ? nil : row.id }
        } label: {
            Text("i")
                .font(.custom("Georgia-BoldItalic", size: 11))
                .foregroundStyle(DS3.muted)
                .frame(width: 22, height: 22)
                .background(Circle().fill(open ? DS3.lens : Color.clear))
                .ds3InsetRims(Circle(), ring: DS3.lineStrong)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .frame(width: 30, alignment: .trailing)
        .frame(minHeight: 36)
        .overlay(alignment: .top) { Rectangle().fill(DS3.line).frame(height: 1) }
        .accessibilityLabel(L.sysEnergyInfoA11y(row.spec.label))
        .accessibilityIdentifier("system-energy-info-\(row.id)")
    }

    @ViewBuilder
    private func valueCell(_ row: EnergyRow, _ bucket: EnergyBucket, column: String) -> some View {
        let cell = bucket == .battery ? row.battery : row.ac
        let label = "\(row.spec.label), \(column)"
        Group {
            if cell.raw == nil {
                Text(SystemPageModel.dash)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(DS3.muted)
            } else {
                switch row.spec.kind {
                case .number:
                    EnergyNumberField(value: cell.raw ?? "", isDirty: cell.dirty, a11y: label) { text in
                        edit(bucket: bucket, key: row.spec.key, value: text)
                    }
                case .toggle:
                    DS3Switch(isOn: Binding(
                        get: { cell.raw == "1" },
                        set: { edit(bucket: bucket, key: row.spec.key, value: $0 ? "1" : "0") }
                    ), dirty: cell.dirty, label: label)
                case .text:
                    Text(cell.shown)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(DS3.ink)
                case .readOnly:
                    Text(cell.shown)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(DS3.muted)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 96, alignment: .trailing)
        .frame(minHeight: 36)
        .overlay(alignment: .top) { Rectangle().fill(DS3.line).frame(height: 1) }
    }

    /// Stages (or un-stages, when the value equals the saved one) one edit; a further edit after «Applied ✓»
    /// clears that mark.
    private func edit(bucket: EnergyBucket, key: String, value: String) {
        guard let energy = model.report.energy else { return }
        let original = SystemPageModel.rawValue(bucket: bucket, key: key, energy: energy)
        let new = SystemPageModel.updatedPending(pending, bucket: bucket, key: key, value: value, original: original)
        guard new != pending else { return }
        withAnimation(curve) { pending = new }
        if model.energyApply == .applied { model.dismissEnergyApplyResult() }
    }
}

// MARK: - Number field

/// Digits-only field (at most 4), committed on Return or focus loss. Ported from the retired `EnergySleepField`.
private struct EnergyNumberField: View {
    let value: String
    let isDirty: Bool
    let a11y: String
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(width: 56, height: 24)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS3.field))
            .ds3InsetRims(RoundedRectangle(cornerRadius: 8, style: .continuous), ring: DS3.line, ringWidth: 1)
            .overlay {
                if isDirty {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS3.amber, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .focused($focused)
            .accessibilityLabel(a11y)
            .onChange(of: text) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(4))
                if digits != newValue { text = digits }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in
                if !focused { text = newValue }
            }
    }

    /// Empty text commits the previous value; otherwise the number clamped to 0…9999.
    private func commit() {
        let digits = text.filter(\.isNumber)
        guard let n = Int(digits) else {
            text = value
            return
        }
        let clamped = min(max(n, 0), 9999)
        text = String(clamped)
        onCommit(text)
    }
}
