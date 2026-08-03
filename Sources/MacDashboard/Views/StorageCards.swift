// Views/StorageCards.swift
// Домашняя папка / Служебные папки / Диски (SMART) cards.

import SwiftUI
import AppKit

// MARK: - Домашняя папка (report-time, chart/table)

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

/// Process-card-style bar list for a `[DirSize]` list, reused by HomeDirsCard and
/// ServiceDirsCard: each folder is a thick clickable row with a proportional gauge
/// behind the content (widths relative to the largest entry), label left, size
/// right, and a trailing chevron signalling that a click reveals it in Finder.
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

// MARK: - Row (compact, gauge behind content) — mirrors ProcessRowView's recipe

private struct DirBarRow: View {
    let label: String
    let bytes: Int64
    let maxBytes: Int64
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.035))
            GeometryReader { geo in
                if maxBytes > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SeriesPalette.s3.opacity(0.18))
                        .frame(width: max(0, geo.size.width * CGFloat(min(Double(bytes) / Double(maxBytes), 1))))
                }
            }
            HStack(spacing: 6) {
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(fmtBytes(bytes))
                    .font(.callout.monospacedDigit().weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 24)
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
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

@MainActor
struct HomeDirsCard: View {
    let model: DashboardModel
    private var home: String { NSHomeDirectory() }

    private var dirs: [DirSize] { model.report.homeDirs ?? [] }
    private var totalBytes: Int64 {
        let h = home
        if let total = dirs.first(where: { stripHome($0.path, home: h) == "~" })?.bytes { return total }
        return dirs.map(\.bytes).max() ?? 0
    }
    private var chartDirs: [DirSize] {
        let h = home
        return dirs.filter { stripHome($0.path, home: h) != "~" && $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        if model.report.homeDirs == nil {
            CardChrome(title: L.storageHomeDirsTitle) {
                SectionStateView(done: model.report.progress["homeDirs"] ?? false)
            }
        } else if dirs.isEmpty {
            CardChrome(title: L.storageHomeDirsTitle) {
                Text(L.sharedUnavailable).font(.callout).foregroundStyle(.secondary)
            }
        } else {
            ChartOrTableCard(title: L.storageHomeDirsTitle, caption: L.storageHomeDirsCaption) {
                DirBarList(dirs: chartDirs) { stripHome($0.path, home: home) }
            } table: {
                let total = max(totalBytes, 1)
                let sorted = dirs.sorted { $0.bytes > $1.bytes }
                SimpleTable(
                    headers: [L.storageColFolder, L.storageColSize, L.storageColShare],
                    rows: sorted.map { d in
                        [stripHome(d.path, home: home), fmtBytes(d.bytes),
                         fmtNum(Double(d.bytes) / Double(total) * 100, decimals: 1) + "%"]
                    },
                    numericColumns: [1, 2],
                    rowAction: { r in revealInFinder(sorted[r].path) },
                    sortableColumns: [1, 2],
                    sortValues: sorted.map { d in
                        let bytes = Double(d.bytes)
                        return [0, bytes, bytes / Double(total) * 100]
                    }
                )
            }
        }
    }
}

// MARK: - Служебные папки (report-time, table only)

struct ServiceDirsCard: View {
    let model: DashboardModel
    private var home: String { NSHomeDirectory() }

    private func label(for path: String) -> String {
        let h = home
        if path == h + "/.Trash" || path == h + "/.Trash/" { return L.storageTrashLabel }
        if path == "/Applications" { return L.storageAppsLabel }
        return stripHome(path, home: h)
    }

    var body: some View {
        if model.report.serviceDirs == nil {
            CardChrome(title: L.storageServiceDirsTitle, caption: L.storageServiceDirsCaption) {
                SectionStateView(done: model.report.progress["serviceDirs"] ?? false)
            }
        } else {
            let dirs = model.report.serviceDirs ?? []
            let sorted = dirs.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
            if sorted.isEmpty {
                CardChrome(title: L.storageServiceDirsTitle, caption: L.storageServiceDirsCaption) {
                    Text(L.sharedUnavailable).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ChartOrTableCard(title: L.storageServiceDirsTitle, caption: L.storageServiceDirsCaption) {
                    DirBarList(dirs: sorted) { label(for: $0.path) }
                } table: {
                    SimpleTable(
                        headers: [L.storageColFolder, L.storageColSize],
                        rows: sorted.map { [label(for: $0.path), fmtBytes($0.bytes)] },
                        numericColumns: [1],
                        rowAction: { r in revealInFinder(sorted[r].path) },
                        sortableColumns: [1],
                        sortValues: sorted.map { [0, Double($0.bytes)] }
                    )
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
