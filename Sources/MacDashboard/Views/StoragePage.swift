// Views/StoragePage.swift
// REDESIGN-STORAGE: the Storage section page (handoff 05-storage) on the shared §8 blocks (SectionPageBlocks.swift):
// page bar (Back, icon, title, sub line, space / SMART tag, Refresh), Disk card (hero + four tiles + low-space
// note), Folders card (Home | System list, Counting / timeout states, Full Disk Access note, inline Empty Trash
// confirm) and the Disks (SMART) card (drive list + 12 health tiles, smartmontools states). All texts, tones and
// thresholds come from the pure `StoragePageModel`; this file only draws them.

import SwiftUI

@MainActor
struct StoragePage: View {
    let model: DashboardModel
    let router: NavigationRouter
    let breakpoints: PageBreakpoints

    @State private var pulse: CardID? = nil

    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the cards do the
    /// reading, so a 2 s tick never re-evaluates the page itself (same rule as `CPUPage` / `MemoryPage`).
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StorageDiskCard(model: model)
                        .id(CardID.disk)
                        .sectionFocusPulse(pulse == .disk)
                        .ds3Appear(delay: 0.08)
                    StorageFoldersCard(model: model, router: router, initialSegment: router.destination.foldersSegment ?? .home,
                                       scrollTo: { proxy.scrollTo($0, anchor: .bottom) })
                        .id(CardID.folders)
                        .sectionFocusPulse(pulse == .folders)
                        .ds3Appear(delay: 0.14)
                    StorageSmartCard(model: model, breakpoints: breakpoints)
                        .id(CardID.smart)
                        .sectionFocusPulse(pulse == .smart)
                        .ds3Appear(delay: 0.20)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { StoragePageBar(model: model, onBack: { _ = router.back() }) }
            .task(id: router.navigationSerial) {
                // Deep link: scroll the focused card under the bar (Disk is already on top) and pulse it.
                let d = router.destination
                guard d.page == .storage, let f = d.focus else { return }
                if f != .disk { proxy.scrollTo(f, anchor: .top) }
                pulse = f
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
        .onDisappear { router.isInlineConfirmOpen = false }
    }
}

/// The page's low-space verdict: the one `StorageSpace.level` call site of the views (page bar + Disk card).
@MainActor
private func storageSpaceLevel(_ model: DashboardModel) -> SpaceLevel? {
    model.disk.flatMap { StorageSpace.level(avail: $0.avail, size: $0.size, lowPercent: AppSettings.shared.lowSpacePercent) }
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it.
@MainActor
struct StoragePageBar: View {
    let model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        let internalName = model.homeReport.smart?.first { $0.device == "internal" }?.title
        let kind = StoragePageModel.tag(
            space: storageSpaceLevel(model),
            smartFailing: model.assessment.items.contains { $0.kind == .smartErrors },
            smartWorn: model.assessment.items.contains { $0.kind == .smartWear })
        let text = StoragePageModel.tagText(kind)
        SectionPageBar(symbol: Page.storage.symbol, title: Page.storage.title,
                       sub: StoragePageModel.sub(internalName: internalName, size: model.disk?.size), onBack: onBack) {
            DS3Tag(tone: tone(kind), text: text).help(text)
        } trailing: {
            refresh
        }
    }

    private func tone(_ k: StorageTagKind) -> DS3Tag.Tone {
        switch k {
        case .driveFailing, .almostFull: return .hot
        case .driveWorn, .lowSpace: return .amber
        case .ok: return .green
        case .loading: return .neutral
        }
    }

    /// Opacity ZStack: «Refresh» ↔ «Refreshing…» without a width change (`swap-in-place`).
    private var refresh: some View {
        let busy = model.isCountingSizes
        return Button { model.refreshStorageNow() } label: {
            ZStack {
                Text(L.commonRefresh).opacity(busy ? 0 : 1)
                Text(L.commonRefreshing).opacity(busy ? 1 : 0)
            }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14))
        .disabled(busy)
        .accessibilityLabel(L.storageRefreshA11y)
        .accessibilityIdentifier("storage-refresh")
    }
}

// MARK: - Disk card

/// Internal: the visual fixture renders it.
@MainActor
struct StorageDiskCard: View {
    let model: DashboardModel

    var body: some View {
        let disk = model.disk
        DS3Card(title: L.storageDiskTitle,
                caption: disk == nil ? nil : L.storageSmartUpdatedCaption(HomeModel.hhmm(model.lastSampleAt))) {
            if let disk {
                content(disk)
            } else {
                SectionWait(text: L.commonCollectingData)
            }
        }
    }

    private func content(_ disk: DiskInfo) -> some View {
        let level = storageSpaceLevel(model) ?? .ok
        let tone: Color = level == .ok ? DS3.accent : (level == .low ? DS3.amber : DS3.hot)
        let toneInk: Color = level == .ok ? DS3.accentInk : (level == .low ? DS3.amberInk : DS3.hotInk)
        let health = model.homeReport.smart?.first { $0.device == "internal" }?.health
        let items = StoragePageModel.freeable(homeDirs: model.report.homeDirs, homeCaches: model.report.homeCaches,
                                              home: FileManager.default.homeDirectoryForCurrentUser.path)
        let note = StoragePageModel.diskNote(level: level, lowPercent: AppSettings.shared.lowSpacePercent, items: items)
        return VStack(alignment: .leading, spacing: 16) {
            HeroSplitLayout {
                SectionHero(label: L.storageFree, value: fmtCapacity(disk.avail), fraction: disk.pct,
                            note: StoragePageModel.heroNote(size: disk.size, usedFraction: disk.pct),
                            tone: tone, toneInk: toneInk)
                EqualColumnsLayout(columns: 2, spacing: 8) {
                    sizeTile(L.storageData, disk.dataUsed)
                    sizeTile(L.storageSystem, disk.sysUsed)
                    sizeTile(L.storagePurgeable, disk.purgeable)
                    tempTile(health?.temperatureC)
                }
            }
            if let note {
                SectionNote(tone: level == .critical ? DS3.hot : DS3.amber, text: note,
                            button: (L.storageSettingsButton, L.storageSettingsA11y, false,
                                     { AdviceActionRunner.openPane(AdvicePanes.storage) }))
            }
        }
    }

    private func sizeTile(_ label: String, _ bytes: Int64?) -> some View {
        SectionTile(label: label, value: bytes.map { fmtCapacity($0) } ?? "—", valueInk: bytes == nil ? DS3.muted : DS3.ink)
    }

    /// D19: dot + note «normal» green below 70 °C, amber «high» at 70 °C and above, «—» muted with no reading.
    private func tempTile(_ t: Int?) -> some View {
        guard let t else {
            return SectionTile(label: L.storageNVMeTemp, value: "—", valueInk: DS3.muted)
        }
        let high = t >= StoragePageModel.temperatureHighC
        return SectionTile(label: L.storageNVMeTemp, value: L.storageCelsius(t),
                           note: high ? L.storageTempHigh : L.storageTempNormal,
                           noteInk: high ? DS3.amberInk : DS3.greenInk,
                           dot: high ? DS3.amber : DS3.green)
    }
}

// MARK: - Folders card

/// Inline Empty Trash confirm preset for the visual fixture (`count` nil = Finder gave no count).
struct StorageTrashConfirmFixture {
    var count: Int?
}

/// Internal: the visual fixture renders it (`initialSegment` / `initialConfirm` exist for the snapshots and the
/// deep link).
@MainActor
struct StorageFoldersCard: View {
    let model: DashboardModel
    let router: NavigationRouter
    @State private var segment: FoldersSegment
    /// End of the 0.9 s Counting wait a segment switch shows (D7); nil = none.
    @State private var waitUntil: Date?
    @State private var dispatch: AdviceActionDispatch
    @FocusState private var cancelFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the card draws; mirrors `dispatch.showTrashConfirm`, committed through an explicit `withAnimation`
    /// so the panel's transition runs (the dispatch flag flips outside any animation).
    @State private var confirmShown: Bool
    /// The page's `ScrollViewReader` proxy (the one the CardID focus scroll uses); nil in the snapshots.
    private let scrollTo: ((String) -> Void)?
    private static let confirmPanelID = "storage-trash-confirm"

    init(model: DashboardModel, router: NavigationRouter, initialSegment: FoldersSegment = .home,
         initialConfirm: StorageTrashConfirmFixture? = nil, initialCounting: Bool = false,
         scrollTo: ((String) -> Void)? = nil) {
        self.model = model
        self.router = router
        self.scrollTo = scrollTo
        _confirmShown = State(initialValue: initialConfirm != nil)
        _segment = State(initialValue: initialSegment)
        let d = AdviceActionDispatch(model: model)
        if let initialConfirm { d.applyFixtureConfirm(count: initialConfirm.count) }
        if initialCounting { d.applyFixtureCounting() }
        _dispatch = State(initialValue: d)
    }

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            card(now: model.fixtureNow ?? ctx.date)
        }
    }

    private func card(now: Date) -> some View {
        let report = model.report
        let phase = StoragePageModel.foldersPhase(block: model.foldersBlock.phase, hasCount: report.homeDirs != nil)
        let names = StoragePageModel.hiddenNames(denied: model.fdaDenied, unreadableHome: report.homeDirsUnreadable,
                                                 russian: L10nStore.shared.language == .ru)
        let fda = StoragePageModel.fdaNote(names)
        let caption = StoragePageModel.foldersCaption(phase: phase, counting: model.isCountingSizes,
                                                      countedAt: report.folderSizesCountedAt, now: now,
                                                      trashFreed: model.trashFreedBytes, someHidden: fda != nil)
        return DS3Card(title: L.storageFoldersTitle, caption: caption, trailing: { segmentControl }) {
            content(phase: phase, fda: fda)
        }
        .onChange(of: segment) { waitUntil = Date().addingTimeInterval(0.9) }
        .task(id: waitUntil) {
            guard let until = waitUntil else { return }
            try? await Task.sleep(for: .seconds(0.9))
            if !Task.isCancelled, waitUntil == until { waitUntil = nil }
        }
        .onChange(of: dispatch.showTrashConfirm) { _, new in
            router.isInlineConfirmOpen = new
            // tmin (00-shared.md): opacity + offset 14 + scale .98 with a spring; Reduce Motion: opacity only.
            let curve: Animation = reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.7)
            withAnimation(curve) { confirmShown = new }
            // The panel's `.id` exists only after the insertion commits: scroll on the next main-queue turn.
            if new {
                DispatchQueue.main.async { withAnimation(curve) { scrollTo?(Self.confirmPanelID) } }
            }
        }
    }

    /// Outside the wait / list branch (`control-identity-branch`).
    private var segmentControl: some View {
        DSSlidingSegmented(options: [FoldersSegment.home, .system], selection: $segment, size: .section,
                           groupLabel: L.storageSegA11y) { $0 == .home ? L.storageSegHome : L.storageSegSystem }
    }

    // MARK: Content

    private func content(phase: FoldersPhase, fda: String?) -> some View {
        let report = model.report
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let rows = segment == .home
            ? StoragePageModel.homeRows(homeDirs: report.homeDirs ?? [], homeCaches: report.homeCaches, home: home, trashHidden: false)
            : StoragePageModel.systemRows(report.serviceDirs ?? [])
        let trashBytes = report.homeDirs?.first { $0.path == home + "/.Trash" }?.bytes ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            if waitUntil != nil || phase == .wait {
                SectionWait(text: L.storageCounting)
            } else {
                switch phase {
                case .failedEmpty(let f):
                    failureNote(f)
                case .failedWithList(let f):
                    failureNote(f)
                    list(rows)
                case .list:
                    list(rows)
                case .wait:
                    EmptyView()
                }
            }
            if segment == .home, let fda {
                SectionNote(tone: DS3.amber, text: fda,
                            button: (L.commonOpenPrivacySettings, L.storageFDAButtonA11y, model.fdaAwaitingReturn,
                                     { model.openFullDiskAccessSettings() }))
            }
            if confirmShown {
                confirmPanel(size: fmtCapacity(trashBytes))
                    .id(Self.confirmPanelID)
                    .transition(reduceMotion ? .opacity
                                : .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.98)))
            }
            if let e = dispatch.trashError {
                SectionNote(tone: DS3.hot, text: e, button: automationButton(dispatch.trashErrorPane))
            }
        }
    }

    private func failureNote(_ f: BlockFailure) -> some View {
        SectionNote(tone: DS3.hot, text: StoragePageModel.failureNote(f),
                    button: (L.commonTryAgain, L.storageCountTryAgainA11y, false, { model.retryFolderCount() }))
    }

    private func automationButton(_ pane: String?) -> (title: String, a11y: String, busy: Bool, action: () -> Void)? {
        guard let pane else { return nil }
        return (L.adviceTrashOpenAutomation, L.adviceTrashOpenAutomation, false, { AdviceActionRunner.openPane(pane) })
    }

    // MARK: List (the `MemoryCompositionCard.list` container recipe)

    @ViewBuilder
    private func list(_ rows: [FolderRow]) -> some View {
        if rows.isEmpty {
            Text(L.storageNoFolders)
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.muted)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
        } else {
            VStack(spacing: 4) {
                ForEach(rows, id: \.id) { row($0) }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
        }
    }

    private func row(_ r: FolderRow) -> some View {
        HStack(spacing: 10) {
            Text(r.label).font(.system(size: 14)).foregroundStyle(DS3.ink)
                .lineLimit(1).truncationMode(.tail).help(r.label)
            Spacer(minLength: 8)
            Text(r.value).font(.system(size: 13, weight: .semibold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(DS3.ink)
                .lineLimit(1).frame(minWidth: 64, alignment: .trailing)
            rowButton(r)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(alignment: .leading) {
            BarFillLayer(spans: [BarSpan(key: "share", fraction: CGFloat(min(r.fraction, 1)), alpha: 0.16, color: DS3.amber)],
                         layout: .single(minWidth: 0, cornerRadius: 16), animated: !reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func rowButton(_ r: FolderRow) -> some View {
        switch r.action {
        case .show(let path):
            Button(L.commonShow) { AdviceActionRunner.reveal(path) }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 28, hPad: 12, fontSize: 12.5))
                .accessibilityLabel(L.storageShowA11y(r.label))
        case .emptyTrash:
            let busy = dispatch.busy(for: .emptyTrash)
            Button { dispatch.requestEmptyTrash(id: "storage-trash") } label: {
                Text(L.storageEmptyTrashButton).dsSwapInPlace(busy) { ProgressView().controlSize(.small) }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 28, hPad: 12, fontSize: 12.5))
            .disabled(busy)
            .accessibilityLabel(L.storageEmptyTrashA11y)
        case nil:
            EmptyView()
        }
    }

    // MARK: Empty Trash confirm (inline; the ProcessCards force-quit panel recipe)

    /// Cancel is the default action (Return). Esc cancels through `.onExitCommand` on the panel (Cancel takes
    /// focus on appear) and through a hidden `.cancelAction` button, which needs no focus. While it is open
    /// `router.isInlineConfirmOpen` removes the Back shortcuts (REDESIGN-CPU D17).
    private func confirmPanel(size: String) -> some View {
        let text = dispatch.trashItemCount.map { L.storageConfirmText($0, size) } ?? L.storageConfirmTextNoCount(size)
        let busy = dispatch.busy(for: .emptyTrash)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L.storageConfirmTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS3.ink)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DS3.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L.storageConfirmCancel) { dispatch.cancelEmptyTrash() }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                    .keyboardShortcut(.defaultAction)
                    .focused($cancelFocused)
                    .accessibilityLabel(L.storageConfirmCancel)
                    .background {
                        Button("") { dispatch.cancelEmptyTrash() }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                Button { dispatch.confirmEmptyTrash() } label: {
                    Text(L.storageConfirmEmpty).dsSwapInPlace(busy) { ProgressView().controlSize(.small).tint(.white) }
                }
                .buttonStyle(DS3ButtonStyle(kind: .dangerSolid, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(busy)
                .accessibilityLabel(L.storageConfirmEmpty)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.overlay))
        .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimMid, ring: DS3.lineStrong)
        .onExitCommand { dispatch.cancelEmptyTrash() }
        .onAppear { cancelFocused = true }
    }
}

// MARK: - SMART card

/// Internal: the visual fixture renders it (`initialSelection` exists for the snapshots only).
@MainActor
struct StorageSmartCard: View {
    let model: DashboardModel
    let breakpoints: PageBreakpoints
    @State private var selected: String?

    init(model: DashboardModel, breakpoints: PageBreakpoints, initialSelection: String? = nil) {
        self.model = model
        self.breakpoints = breakpoints
        _selected = State(initialValue: initialSelection)
    }

    var body: some View {
        let report = model.homeReport
        let present = report.smartctlPresent
        let failing = (report.smart ?? []).contains { StoragePageModel.driveState($0, smartctlPresent: present) == .failing }
        DS3Card(title: L.storageSmartCardTitle,
                caption: model.smartUpdatedAt.map { L.storageSmartUpdatedCaption(HomeModel.hhmm($0)) },
                trailing: { refresh }) {
            if let disks = report.smart {
                if disks.isEmpty {
                    Text(L.sharedUnavailable)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS3.muted)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
                } else {
                    split(disks, present: present)
                }
            } else {
                SectionWait(text: L.commonCollectingData)
            }
        }
        .homeHotRing(failing)
    }

    /// Opacity ZStack: «Refresh» ↔ «Refreshing…» without a width change (`swap-in-place`).
    private var refresh: some View {
        let busy = model.smartRefreshing
        return Button { model.refreshSmartNow() } label: {
            ZStack {
                Text(L.commonRefresh).opacity(busy ? 0 : 1)
                Text(L.commonRefreshing).opacity(busy ? 1 : 0)
            }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14))
        .disabled(busy)
        .accessibilityLabel(L.storageSmartRefreshA11y)
        .accessibilityIdentifier("storage-smart-refresh")
    }

    // MARK: Split block

    private func split(_ disks: [SmartDisk], present: Bool) -> some View {
        let current = selected.flatMap { s in disks.contains { $0.device == s } ? s : nil }
            ?? StoragePageModel.defaultSelection(disks, smartctlPresent: present)
        let disk = disks.first { $0.device == current } ?? disks[0]
        return HStack(alignment: .top, spacing: 12) {
            driveList(disks, present: present, current: disk.device)
                .frame(width: StoragePageModel.splitLeftWidth(wide: breakpoints.storageWide))
            detail(disk, present: present)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func driveList(_ disks: [SmartDisk], present: Bool, current: String) -> some View {
        VStack(spacing: 4) {
            ForEach(disks) { d in
                let state = StoragePageModel.driveState(d, smartctlPresent: present)
                DriveItem(title: d.title,
                          sub: StoragePageModel.driveSub(state, isInternal: d.device == "internal"),
                          dot: dotColor(state), isSelected: d.device == current) { selected = d.device }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
    }

    private func dotColor(_ s: DriveState) -> Color {
        switch s {
        case .ok: return DS3.green
        case .worn: return DS3.amber
        case .failing: return DS3.hot
        case .noData, .unavailable: return DS3.muted
        }
    }

    @ViewBuilder
    private func detail(_ disk: SmartDisk, present: Bool) -> some View {
        let state = StoragePageModel.driveState(disk, smartctlPresent: present)
        VStack(alignment: .leading, spacing: 8) {
            if model.smartToolsState != .installed {
                StorageToolsNote(model: model, narrow: breakpoints.narrow)
            } else {
                if let line = StoragePageModel.statusLine(state) {
                    Text(line.text)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(line.hot ? DS3.hotInk : DS3.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let wear = StoragePageModel.wearNote(state) {
                    SectionNote(tone: DS3.amber, text: wear)
                }
                let tiles = StoragePageModel.kvTiles(disk.health)
                EqualColumnsLayout(columns: StoragePageModel.kvColumns(wide: breakpoints.storageWide), spacing: 8) {
                    ForEach(tiles.indices, id: \.self) { i in
                        kvTile(tiles[i]).ds3Appear(delay: 0.08 + 0.06 * Double(i))
                    }
                }
            }
        }
    }

    private func kvTile(_ t: KVTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let toned = t.tone != .plain && t.tone != .muted
        return VStack(alignment: .leading, spacing: 4) {
            Text(t.label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DS3.inkSoft)
                .lineLimit(1)
            Text(t.value)
                .font(.system(size: 16, weight: toned ? .bold : .semibold))
                .foregroundStyle(ink(t.tone))
                .lineLimit(1)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(DS3.row))
        .ds3InsetRims(shape, top: DS3.rimLo, ring: DS3.line)
    }

    private func ink(_ t: KVTone) -> Color {
        switch t {
        case .plain: return DS3.ink
        case .good: return DS3.greenInk
        case .amber: return DS3.amberInk
        case .hot: return DS3.hotInk
        case .muted: return DS3.muted
        }
    }
}

/// One drive in the left list: dot + name, sub line below. Selected = lens fill (IPhoneLogsCard category row).
private struct DriveItem: View {
    let title: String
    let sub: String
    let dot: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? DS3.ink : DS3.inkSoft)
                        .lineLimit(1)
                }
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
                    .padding(.leading, 14)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    shape.fill(DS3.lens).ds3Elevation(.lens, in: shape)
                } else if hover {
                    shape.fill(DS3.lens)
                }
            }
            .overlay {
                if isSelected { Color.clear.ds3InsetRims(shape, top: DS3.rimHi, ring: DS3.rimMid) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .accessibilityLabel("\(title), \(sub)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - smartmontools states

/// The right-side Note that replaces the tiles while smartctl is missing: installable / installing / failed /
/// needs Homebrew. Layout switches on the page breakpoint passed down (`PageBreakpoints.narrow`), never on a measured size (D23).
@MainActor
private struct StorageToolsNote: View {
    let model: DashboardModel
    let narrow: Bool

    var body: some View {
        let needsBrew = model.smartToolsState == .needsHomebrew
        let failure = needsBrew ? nil : model.smartInstallFailure
        let text = failure.map { StoragePageModel.installFailureText($0) }
            ?? (needsBrew ? L.storageToolsNeedsBrew : L.storageToolsInstallable)
        let tone = failure != nil ? DS3.hot : DS3.muted
        let oneRow = !narrow
        Group {
            if oneRow {
                HStack(alignment: .top, spacing: 12) {
                    dotAndText(text, tone: tone)
                    Spacer(minLength: 0)
                    buttons(needsBrew: needsBrew, failed: failure != nil)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    dotAndText(text, tone: tone)
                    buttons(needsBrew: needsBrew, failed: failure != nil)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ds3TintPanel(tone, from: 0.16, to: 0.06, ring: 0.42, cornerRadius: 20)
    }

    private func dotAndText(_ text: String, tone: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(tone).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func buttons(needsBrew: Bool, failed: Bool) -> some View {
        if needsBrew {
            Button(L.storageToolsHowToBrew) {
                if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
            .accessibilityLabel(L.storageToolsHowToBrewA11y)
        } else if failed {
            Button(L.commonTryAgain) { model.installSmartmontoolsNow() }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 13, fontSize: 12.5))
                .accessibilityLabel(L.storageInstallRetryA11y)
        } else {
            let installing = model.smartInstalling
            VStack(alignment: .trailing, spacing: 6) {
                Button { model.installSmartmontoolsNow() } label: {
                    Text(L.storageToolsInstall).dsSwapInPlace(installing) { ProgressView().controlSize(.small).tint(.white) }
                }
                .buttonStyle(DS3ButtonStyle(kind: .primary, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(installing)
                .accessibilityLabel(L.storageToolsInstallA11y)
                if installing {
                    Text("brew install smartmontools")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(DS3.muted)
                }
            }
        }
    }
}
