// Views/StorageCards.swift
// Папки (домашняя | служебные) / Диски (SMART) cards.

import SwiftUI
import AppKit

// MARK: - Папки (report-time, merged home/service tab card)

/// Reveal a folder in Finder; silently no-op if it no longer exists (deleted
/// between report collection and the click).
private func revealInFinder(_ path: String) {
    guard FileManager.default.fileExists(atPath: path) else { return }
    AdviceActionRunner.reveal(path)
}

private func stripHome(_ path: String, home: String) -> String {
    var p = path
    var h = home
    if p.hasSuffix("/") { p.removeLast() }
    if h.hasSuffix("/") { h.removeLast() }
    if p == h { return "~" }
    if p.hasPrefix(h + "/") { return "~" + p.dropFirst(h.count) }
    return p
}

// MARK: - Row (compact, gauge behind content) — mirrors ProcessRowView's recipe

private struct DirBarRow: View {
    let label: String
    let bytes: Int64
    let maxBytes: Int64
    let onTap: () -> Void

    @State private var hovering = false
    // Row width, captured once via `onGeometryChange` instead of read live from
    // a `GeometryReader` inside the ZStack — see ProcessRowView's rationale in
    // Views/ProcessCards.swift (settled precedent, not relitigated here).
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9).fill(DS.row)
            if maxBytes > 0 {
                RoundedRectangle(cornerRadius: 9)
                    .fill(DS.amber.opacity(0.18))
                    .frame(width: max(0, rowWidth * CGFloat(min(Double(bytes) / Double(maxBytes), 1))))
            }
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(DS.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(fmtBytes(bytes))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(DS.inkSoft)
                Text("›")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
            }
            .padding(.horizontal, 9)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { newWidth in
            rowWidth = newWidth
        }
        .frame(height: 27)
        .background(hovering ? DS.track : Color.clear)
        .animation(.easeInOut(duration: 0.14), value: hovering)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                hovering = true
                NSCursor.pointingHand.push()
            } else {
                hovering = false
                NSCursor.pop()
            }
        }
        .onTapGesture { onTap() }
    }
}

/// Row list for a `[DirSize]` list, shared by both tabs of `FoldersCard`: each
/// folder is a thick clickable row with a proportional gauge behind the
/// content (widths relative to the largest entry), label left, size right, and
/// a trailing chevron signalling that a click reveals it in Finder.
private struct DirBarList: View {
    let dirs: [DirSize]
    let label: (DirSize) -> String

    var body: some View {
        let maxBytes = dirs.map(\.bytes).max() ?? 0
        VStack(alignment: .leading, spacing: 4) {
            ForEach(dirs) { d in
                DirBarRow(label: label(d), bytes: d.bytes, maxBytes: maxBytes) {
                    revealInFinder(d.path)
                }
            }
        }
    }
}

private enum FolderTab: Hashable { case home, service }

@MainActor
struct FoldersCard: View {
    let model: DashboardModel
    @State private var folderTab: FolderTab = .home
    private var home: String { NSHomeDirectory() }

    private var homeDirs: [DirSize] { model.report.homeDirs ?? [] }
    private var chartDirs: [DirSize] {
        let h = home
        return homeDirs.filter { stripHome($0.path, home: h) != "~" && $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
            .prefix(10)
            .map { $0 }
    }

    private func label(for path: String) -> String {
        let h = home
        if path == h + "/.Trash" || path == h + "/.Trash/" { return L.storageTrashLabel }
        if path == "/Applications" { return L.storageAppsLabel }
        return stripHome(path, home: h)
    }

    private var title: String {
        folderTab == .home ? L.storageHomeDirsTitle : L.storageServiceDirsTitle
    }
    private var caption: String {
        folderTab == .home ? L.storageHomeDirsCaption : L.storageServiceDirsCaption
    }

    private var segmentedControl: some View {
        DSSlidingSegmented(options: [FolderTab.home, .service], selection: $folderTab) { t in
            t == .home ? L.folderTabHome : L.folderTabSvc
        }
        .frame(width: 168, height: 26)
    }

    // `CardChrome`/`segmentedControl` must sit OUTSIDE the folderTab switch:
    // branching the whole card on `folderTab` gave the segmented control a
    // fresh identity on every tap, so `DSSlidingSegmented`'s thumb spring
    // (keyed on `value: selection`, DesignSystem.swift) never animates — the
    // new instance just mounts pre-selected. Only the row content varies.
    var body: some View {
        CardChrome(title: title, caption: caption, trailing: { segmentedControl }) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch folderTab {
        case .home:
            if model.report.homeDirs == nil {
                SectionStateView(done: model.report.progress["homeDirs"] ?? false)
            } else if homeDirs.isEmpty {
                Text(L.sharedUnavailable).font(.callout).foregroundStyle(.secondary)
            } else {
                DirBarList(dirs: chartDirs) { stripHome($0.path, home: home) }
            }
        case .service:
            if model.report.serviceDirs == nil {
                SectionStateView(done: model.report.progress["serviceDirs"] ?? false)
            } else {
                let dirs = model.report.serviceDirs ?? []
                let sorted = dirs.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
                if sorted.isEmpty {
                    Text(L.sharedUnavailable).font(.callout).foregroundStyle(.secondary)
                } else {
                    DirBarList(dirs: sorted) { label(for: $0.path) }
                }
            }
        }
    }
}

// MARK: - Диски (SMART)

@MainActor
struct SmartDisksCard: View {
    let model: DashboardModel

    /// «обновлено HH:MM» — time of the last SMART collection (launch report, manual
    /// refresh, or periodic sampler), whichever most recently landed.
    private var updatedCaption: String? {
        model.smartUpdatedAt.map { L.storageSmartUpdatedCaption($0.formatted(date: .omitted, time: .shortened)) }
    }

    var body: some View {
        CardChrome(title: L.storageSmartTitle, caption: updatedCaption, trailing: {
            RainbowCapsuleButton(title: L.storageSmartRefreshButton, busy: model.smartRefreshing) {
                model.refreshSmartNow()
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                // Install-smartmontools affordance (Block N8): only relevant when
                // external-disk SMART is degraded by missing tooling, never for the
                // internal-only-disks case (spec §4 "above the disk list").
                switch model.smartToolsState {
                case .installed:
                    EmptyView()
                case .installable:
                    VStack(alignment: .leading, spacing: 4) {
                        RainbowCapsuleButton(title: L.storageSmartInstallButton, busy: model.smartInstalling) {
                            model.installSmartmontoolsNow()
                        }
                        if let err = model.smartInstallError {
                            Text(err).font(.caption2).foregroundStyle(.red)
                        }
                    }
                case .needsHomebrew:
                    Text(L.storageSmartNeedsHomebrew).font(.caption).foregroundStyle(.secondary)
                }

                if let disks = model.report.smart {
                    if disks.isEmpty {
                        Text(L.sharedUnavailable).font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(disks.enumerated()), id: \.element.id) { index, disk in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(disk.title).font(.callout.weight(.semibold))
                                    HStack(spacing: 6) {
                                        SeverityDot(sev: disk.severity)
                                        Text(smartLocalizedLabel(disk.status)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if !disk.attrs.isEmpty {
                                        SimpleTable(
                                            headers: [L.storageSmartColAttribute, L.storageSmartColValue],
                                            rows: disk.attrs.map { [smartLocalizedLabel($0.0), $0.0 == "Critical Warning" ? smartCriticalWarningRU($0.1) : $0.1] },
                                            numericColumns: [1]
                                        )
                                        .padding(.top, 2)
                                    }
                                }
                                if index != disks.count - 1 { Divider() }
                            }
                        }
                    }
                } else {
                    SectionStateView(done: model.report.progress["smart"] ?? false)
                }
            }
        }
    }
}
