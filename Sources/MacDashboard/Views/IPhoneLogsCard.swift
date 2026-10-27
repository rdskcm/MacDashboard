// Views/IPhoneLogsCard.swift
// IPHONE-DESIGN: crash logs as a two-column browser (categories left, the category's files right).
// Rows are not buttons: expansion and actions are deferred (IPHONE-CRASHLOG-ACTIONS).

import SwiftUI

struct IPhoneLogsCard: View {
    enum Source: Hashable { case live, archive }

    let model: IPhoneModel
    let deviceKey: String
    @State private var source: Source
    @State private var selected: LogCategory?

    /// `initialSource` exists for the harness render; the page always starts on the phone's list.
    init(model: IPhoneModel, deviceKey: String, initialSource: Source = .live) {
        self.model = model
        self.deviceKey = deviceKey
        _source = State(initialValue: initialSource)
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
        .onChange(of: source) { selected = nil }
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
                    selected = cat
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
                    ForEach(items) { IPhoneLogFileRow(entry: $0) }
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
        .background(DS3.overlay)
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
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Text((entry.path as NSString).lastPathComponent)
                .font(.system(size: 14))
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
        .background(hover ? DS3.row : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(DS3.line).frame(height: 1) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
