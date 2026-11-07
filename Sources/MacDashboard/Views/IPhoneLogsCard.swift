// Views/IPhoneLogsCard.swift
// IPHONE-DESIGN: crash logs as a two-column browser (categories left, the category's files right).
// Rows expand on click (one at a time) with details and the Console / Save actions (IPHONE-CRASHLOG-ACTIONS).

import AppKit
import SwiftUI

struct IPhoneLogsCard: View {
    enum Source: Hashable { case live, archive }

    let model: IPhoneModel
    let deviceKey: String
    @State private var source: Source
    @State private var selected: LogCategory?
    @State private var expanded: String?
    @State private var animateOpen: String?

    /// `initialSource`, `initialCategory`, `initialExpanded` exist for the harness render; the page always starts on the phone's list.
    init(model: IPhoneModel, deviceKey: String, initialSource: Source = .live,
         initialCategory: LogCategory? = nil, initialExpanded: String? = nil) {
        self.model = model
        self.deviceKey = deviceKey
        _source = State(initialValue: initialSource)
        _selected = State(initialValue: initialCategory)
        _expanded = State(initialValue: initialExpanded)
    }

    private var isConnected: Bool { model.connected[deviceKey] != nil }
    private var entries: [IPhoneLogEntry]? { model.logs[deviceKey] }
    private var loading: Bool { model.logsLoading.contains(deviceKey) }
    private var archive: [IPhoneLogEntry] { model.archiveLogs[deviceKey] ?? [] }
    private var showArchive: Bool { source == .archive && !archive.isEmpty }

    var body: some View {
        DS3Card(title: L.iphoneLogsTitle, caption: caption, trailing: {
            HStack(spacing: 10) {
                if !archive.isEmpty {
                    DSSlidingSegmented(options: [Source.live, .archive], selection: $source, size: .section,
                                       groupLabel: L.iphoneLogsSourceA11y) {
                        $0 == .live ? L.iphoneLogsSourceLive : L.iphoneLogsSourceArchive
                    }
                }
                Button(L.iphoneRefresh) { model.loadLogs(deviceKey: deviceKey) }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 1))
                    .disabled(!isConnected || loading)
                    .accessibilityLabel(L.iphoneLogsRefreshA11y)
            }
        }) {
            content
        }
        .onChange(of: source) { selected = nil; expanded = nil }
        // First appearance for a connected phone, and every time its connection (handle) changes.
        .task(id: model.connected[deviceKey]) {
            if isConnected, model.logs[deviceKey] == nil { model.loadLogs(deviceKey: deviceKey) }
        }
    }

    private var caption: String? {
        showArchive ? L.iphoneLogsCaption(archive.count) : entries.map { L.iphoneLogsCaption($0.count) }
    }

    @ViewBuilder private var content: some View {
        if showArchive {
            VStack(alignment: .leading, spacing: 16) {
                Text(L.iphoneLogsFromArchive(archiveName))
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.muted)
                    .padding(.top, -6)
                browser(archive)
            }
        } else if let entries {
            if entries.isEmpty {
                IPhoneMessagePanel(text: L.iphoneLogsEmpty)
            } else {
                browser(entries)
            }
        } else if loading {
            IPhoneMessagePanel(text: L.sharedCollectingData, tone: .loading)
        } else if !isConnected {
            IPhoneMessagePanel(text: L.iphoneLogsConnectToRead)
        } else if model.logsFailed.contains(deviceKey) {
            IPhoneMessagePanel(text: L.iphoneSectionReadFailed, tone: .error)
        } else {
            IPhoneMessagePanel(text: L.sharedCollectingData, tone: .loading)
        }
    }

    private var archiveName: String {
        if case .archive(let n) = archive[0].source { return n }
        return ""
    }

    // MARK: Browser

    private func browser(_ items: [IPhoneLogEntry]) -> some View {
        let groups = IPhoneData.grouped(items)
        let current = groups.first { $0.0 == selected } ?? groups[0]
        return categoryList(groups, current: current.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The file pane takes the list's height through an overlay, no measurement (D20).
            .overlay(alignment: .topLeading) {
                fileList(current).padding(.leading, 242)
            }
    }

    private func categoryList(_ groups: [(LogCategory, [IPhoneLogEntry])], current: LogCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groups, id: \.0) { cat, list in
                IPhoneLogCategoryRow(category: cat, count: list.count, isSelected: cat == current) {
                    selected = cat; expanded = nil
                }
            }
        }
        .padding(6)
        .frame(width: 230, alignment: .topLeading)
        .frame(minHeight: 240, alignment: .top)
        .ds3RowPanel(cornerRadius: 22)
    }

    private func fileList(_ group: (LogCategory, [IPhoneLogEntry])) -> some View {
        let (cat, items) = group
        return ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(items) { e in
                        IPhoneLogFileRow(entry: e, model: model, deviceKey: deviceKey,
                                         isOpen: expanded == e.id, playOpen: animateOpen == e.id,
                                         onPlayed: { animateOpen = nil }) {
                            if expanded == e.id {
                                expanded = nil
                                model.clearLogActionResult(deviceKey: deviceKey, entry: e)
                            } else {
                                if let old = items.first(where: { $0.id == expanded }) {
                                    model.clearLogActionResult(deviceKey: deviceKey, entry: old)
                                }
                                expanded = e.id
                                animateOpen = e.id
                            }
                        }
                    }
                } header: {
                    headerRow(cat)
                }
            }
        }
        .background(Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DS3.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func headerRow(_ cat: LogCategory) -> some View {
        HStack(spacing: 12) {
            Text(L.iphoneLogsCategory(cat)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(L.iphoneHistoryColDate).frame(width: 96, alignment: .trailing)
            Text(L.iphoneLogsColSize).frame(width: 72, alignment: .trailing)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(DS3.muted)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(DS3.overlaySolid)
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
    }
}

private struct IPhoneLogCategoryRow: View {
    let category: LogCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                Text(L.iphoneLogsCategory(category))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? DS3.ink : DS3.inkSoft)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS3.muted)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
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
        .accessibilityLabel(L.iphoneLogsCategory(category))
        .accessibilityValue(L.iphoneLogsCaption(count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct IPhoneLogFileRow: View {
    let entry: IPhoneLogEntry
    let model: IPhoneModel
    let deviceKey: String
    let isOpen: Bool
    let playOpen: Bool
    let onPlayed: () -> Void
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Text((entry.path as NSString).lastPathComponent)
                        .font(.system(size: 14, weight: isOpen ? .semibold : .medium))
                        .foregroundStyle(DS3.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.modified.map { fmtDisplayDay($0) } ?? "—")
                        .font(.system(size: 14)).monospacedDigit().foregroundStyle(DS3.muted).lineLimit(1)
                        .frame(width: 96, alignment: .trailing)
                    Text(fmtBytes(entry.size))
                        .font(.system(size: 14)).monospacedDigit().foregroundStyle(DS3.muted).lineLimit(1)
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 16)
                .background(hover && !isOpen ? DS3.row : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
            .accessibilityLabel((entry.path as NSString).lastPathComponent)
            .accessibilityHint(L.iphoneLogsRowHint)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            if isOpen {
                IPhoneLogDetails(entry: entry, model: model, deviceKey: deviceKey)
                    .modifier(IPhoneLogDetailsAppear(play: playOpen, onPlayed: onPlayed))
            }
        }
        .background(isOpen ? DS3.row : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
    }
}

/// Mockup `mdgrow`: opacity 0 → 1 and 6 pt drop, `DS3Motion.rowExpand`. Plays only for the click that opened the
/// row (`play`), so a lazy remount on scroll shows the details at once. Reduce Motion and `-visualFixture`: at once.
private struct IPhoneLogDetailsAppear: ViewModifier {
    let onPlayed: () -> Void
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(play: Bool, onPlayed: @escaping () -> Void) {
        self.onPlayed = onPlayed
        _shown = State(initialValue: !play)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -6)
            .onAppear {
                guard !shown else { return }
                if reduceMotion || DS3Motion.isFrozen { shown = true } else {
                    withAnimation(DS3Motion.rowExpand) { shown = true }
                }
                onPlayed()
            }
    }
}

private struct IPhoneLogDetails: View {
    let entry: IPhoneLogEntry
    let model: IPhoneModel
    let deviceKey: String

    private var name: String { (entry.path as NSString).lastPathComponent }
    private var key: String { IPhoneModel.logActionKey(deviceKey: deviceKey, entry: entry) }
    private var state: IPhoneModel.LogActionState? { model.logAction[key] }
    private var busy: Bool { model.isLogActionBusy(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { fields }
                VStack(alignment: .leading, spacing: 6) { fields }
            }
            HStack(spacing: 8) {
                if IPhoneCrashLog.canOpenInConsole(name: name, size: entry.size) {
                    // CrashRow.actionButton recipe (SecurityPage.swift :499-512), mockup sizes (32 / 14 / 13 pt).
                    Button {
                        model.openLogInConsole(deviceKey: deviceKey, entry: entry) { url, done in
                            AdviceActionRunner.openInConsole(url.path, completion: done)   // the one Console opener app-wide
                        }
                    } label: {
                        Text(L.iphoneLogsOpenInConsole)
                            .dsSwapInPlace(consoleBusy) { DS3Spinner(role: .onSolid, size: 12) }
                    }
                    .buttonStyle(DS3ButtonStyle(kind: .primary, height: 32, hPad: 14, disabledOpacity: consoleBusy ? 1 : 0.45))
                    .disabled(busy)
                    .help(L.iphoneLogsOpenInConsoleA11y(name))
                    .accessibilityLabel(L.iphoneLogsOpenInConsoleA11y(name))
                    .ds3BusyValue(consoleBusy)
                }
                Button(action: pickDestination) {
                    Text(L.iphoneLogsSaveToMac)
                        .dsSwapInPlace(saveBusy || state == .saved) {
                            if state == .saved {
                                // IdentifierRevealControls' confirmation look (:44-48).
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                    Text(L.iphoneLogsSaved)
                                }
                                .foregroundStyle(DS3.accentInk)
                            } else {
                                DS3Spinner(role: .softRing, size: 12)
                            }
                        }
                }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 1,
                                            disabledOpacity: saveBusy ? 1 : 0.45))
                .disabled(busy)
                .help(L.iphoneLogsSaveA11y(name))
                .accessibilityLabel(L.iphoneLogsSaveA11y(name))
                .ds3BusyValue(saveBusy)
            }
            statusLine
        }
        .padding(EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16))
    }

    private var consoleBusy: Bool { if case .copying(.console, _, _)? = state { return true }; return false }
    private var saveBusy: Bool {
        switch state { case .copying(.save, _, _)?, .saving?: return true; default: return false }
    }

    /// A `.pending` entry (type batch not arrived yet, D3) shows «Identifying type…» as its Type and no Process line;
    /// Created is always present for a live row (file-name stamp or mtime; nil only when the AFC gave no mtime).
    @ViewBuilder private var fields: some View {
        if let p = entry.process { field(L.iphoneLogsDetailProcess, p) }
        field(L.iphoneLogsDetailType, L.iphoneLogsType(entry.category, bugType: entry.bugType))
        if let c = entry.created { field(L.iphoneLogsDetailCreated, fmtDisplayDateTime(c)) }
    }

    private func field(_ label: String, _ value: String) -> some View {
        (Text(label).foregroundStyle(DS3.inkSoft) + Text(" ")
            + Text(value).fontWeight(.semibold).foregroundStyle(DS3.ink))
            .font(.system(size: 13))
            .lineLimit(1)
    }

    @ViewBuilder private var statusLine: some View {
        switch state {
        case .copying(_, let done, let total)? where total >= IPhoneCrashLog.progressLineMinBytes:
            Text(L.iphoneImportProgress(.copying(done: done, total: total)))
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(DS3.inkSoft).lineLimit(1)
        case .failed(let e)?:
            Text(L.iphoneLogsActionError(e))
                .font(.system(size: 13)).foregroundStyle(DS3.hotInk).lineLimit(2)
        default:
            EmptyView()
        }
    }

    private func pickDestination() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = L.iphoneLogsSavePanelTitle
        panel.prompt = L.iphoneLogsSavePrompt
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.saveLog(deviceKey: deviceKey, entry: entry, to: url)
    }
}
