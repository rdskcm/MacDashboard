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
    // The gauge plate + bar live in a `.background` (see `body`), never as a
    // sibling inside the row's own layout — see ProcessRowView's rationale in
    // Views/ProcessCards.swift (settled precedent, not relitigated here): a
    // `.background` can't feed its size back into the row, which is what
    // breaks the one-way measurement ratchet that used to inflate the whole
    // card on live-drag window resize. A `GeometryReader` must still never
    // sit as a sibling in that background `ZStack`'s content.

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(DS.inkSoft)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                let parts = fmtBytesParts(bytes)
                Text(parts.value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(DS.inkSoft)
                if let unit = parts.unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(.leading, 1.5)
                        .foregroundStyle(DS.inkSoft)
                }
            }
            Text("›")
                .font(.system(size: 12))
                .foregroundStyle(DS.muted)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 27)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9).fill(DS.row)
                if maxBytes > 0 {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 9)
                            .fill(DS.amber.opacity(0.18))
                            .frame(width: max(0, geo.size.width * CGFloat(min(Double(bytes) / Double(maxBytes), 1))))
                    }
                }
            }
        }
        .background(hovering ? DS.track : Color.clear)
        // V2-FIX-REDUCE-MOTION-GAPS: not the lone outlier — SettingsView.swift:81, LanguageDropdown.swift:85/320
        // and ProcessCards.swift:258 are also ungated hover fades, so this stays a literal rather than being
        // forced into a gated form the rest of the codebase doesn't follow.
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

/// SMART status dot/text tone (spec §5.9, DO:642) — a literal hex per status,
/// same value in light/dark (mirrors `Severity.color`'s existing single-hex
/// convention in Theme.swift, NOT the appearance-aware `DS`/`tone(for:)`
/// tables). `fail` is its OWN literal `#E6784E` — a documented correction from
/// a prior planning session, deliberately distinct from `DS.hot`; do not
/// "fix" it to route through `tone(for:)`.
private func smartStatusColor(_ sev: Severity) -> Color {
    switch sev {
    case .good: return Color(hex: 0x2BBD8F)
    case .warn: return Color(hex: 0xEDA100)
    case .crit, .serious: return Color(hex: 0xE6784E)
    case .info: return Color(hex: 0x7E8896)
    }
}

/// One disk capsule (spec §5.9): 6 pt status dot · name · uppercase kind
/// sublabel. Internal disks tint `DS.accent`, external `DS.amber`. Selection
/// state drives fill/border opacity + an inset 30%-tint selection ring;
/// unselected capsules dim (whole-capsule opacity, so the kind sublabel's
/// "own ink color at full strength" in light theme still reads correctly
/// dimmed together with everything else, never separately washed out).
private struct SmartDiskCapsule: View {
    let disk: SmartDisk
    let isInternal: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var cursorPushed = false

    private var tint: Color { isInternal ? DS.accent : DS.amber }
    private var kindLabel: String { isInternal ? L.storageSmartKindInternal : L.storageSmartKindExternal }

    /// `DS.muted` in dark; the capsule's own -ink variant at full strength in
    /// light (grey fails 4.5:1 on the tinted fill in light theme — see the
    /// light-theme ink-role rule in Theme.swift).
    private var kindLabelColor: Color {
        guard colorScheme == .light else { return DS.muted }
        return isInternal ? DS.accentInk : DS.amberInk
    }

    private var fillOpacity: Double {
        switch (colorScheme, isSelected) {
        case (.light, true): return 0.22
        case (.light, false): return 0.11
        case (_, true): return 0.20
        default: return 0.09
        }
    }

    private var borderOpacity: Double {
        switch (colorScheme, isSelected) {
        case (.light, true): return 0.62
        case (.light, false): return 0.32
        case (_, true): return 0.55
        default: return 0.24
        }
    }

    private var dimOpacity: Double {
        guard !isSelected else { return 1.0 }
        return colorScheme == .light ? 0.96 : 0.62
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(smartStatusColor(disk.severity)).frame(width: 6, height: 6)
            Text(disk.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.ink)
                .lineLimit(1)
            Text(kindLabel)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.63)   // 0.06em @ 10.5 pt
                .foregroundStyle(kindLabelColor)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(Capsule().fill(tint.opacity(fillOpacity)))
        .overlay(Capsule().strokeBorder(tint.opacity(borderOpacity), lineWidth: 1))
        .overlay {
            if isSelected {
                Capsule().inset(by: 1).strokeBorder(tint.opacity(0.30), lineWidth: 1)
            }
        }
        .opacity(dimOpacity)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
                cursorPushed = true
            } else if cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
        .accessibilityLabel("\(disk.title), \(kindLabel)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

@MainActor
struct SmartDisksCard: View {
    let model: DashboardModel
    var balanceSpacer: CGFloat = 0

    /// Click-to-select capsule state; the attribute table below follows this.
    /// Defaults (when nil) to the first disk in report order — internal disks
    /// are always collected first, so a lone/just-loaded disk list opens on
    /// the internal disk. A single disk is therefore always selected, per spec.
    @State private var selectedDevice: String? = nil

    /// «обновлено HH:MM» — time of the last SMART collection (launch report, manual
    /// refresh, or periodic sampler), whichever most recently landed.
    private var updatedCaption: String? {
        model.smartUpdatedAt.map { L.storageSmartUpdatedCaption($0.formatted(date: .omitted, time: .shortened)) }
    }

    private var disks: [SmartDisk] { model.report.smart ?? [] }
    private var internalDisk: SmartDisk? { disks.first { $0.device == "internal" } }
    private var externalDisks: [SmartDisk] { disks.filter { $0.device != "internal" } }

    private var selectedDisk: SmartDisk? {
        if let selectedDevice, let found = disks.first(where: { $0.device == selectedDevice }) {
            return found
        }
        return disks.first
    }

    var body: some View {
        CardChrome(title: L.storageSmartTitle, caption: updatedCaption, trailing: {
            RainbowCapsuleButton(title: L.storageSmartRefreshButton, busy: model.smartRefreshing, size: .card) {
                model.refreshSmartNow()
            }
            .accessibilityLabel(L.storageSmartRefreshButton)
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
                        RainbowCapsuleButton(title: L.storageSmartInstallButton, busy: model.smartInstalling, size: .card) {
                            model.installSmartmontoolsNow()
                        }
                        .accessibilityLabel(L.storageSmartInstallButton)
                        if let err = model.smartInstallError {
                            Text(err).font(.caption2).foregroundStyle(.red)
                        }
                    }
                case .needsHomebrew:
                    Text(L.storageSmartNeedsHomebrew).font(.caption).foregroundStyle(.secondary)
                }

                if model.report.smart != nil {
                    if disks.isEmpty {
                        Text(L.sharedUnavailable).font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 7) {
                            // Internal disk ALWAYS alone on the first line under the
                            // card title; externals flow left→right below it.
                            if let internalDisk {
                                SmartDiskCapsule(
                                    disk: internalDisk, isInternal: true,
                                    isSelected: selectedDisk?.device == internalDisk.device
                                ) { selectedDevice = internalDisk.device }
                            }
                            if !externalDisks.isEmpty {
                                FlowLayout(spacing: 7) {
                                    ForEach(externalDisks) { disk in
                                        SmartDiskCapsule(
                                            disk: disk, isInternal: false,
                                            isSelected: selectedDisk?.device == disk.device
                                        ) { selectedDevice = disk.device }
                                    }
                                }
                            }
                        }

                        if balanceSpacer > 0 { Color.clear.frame(height: balanceSpacer) }

                        if let sel = selectedDisk {
                            // Problem/error text only on an actual SMART failure (not on
                            // wear/warn or unknown) — spec §5.9 correction.
                            let isFailing = sel.severity == .crit || sel.severity == .serious
                            if isFailing || !sel.attrs.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    if isFailing {
                                        Text(smartLocalizedLabel(sel.status))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(smartStatusColor(sel.severity))
                                    }
                                    if !sel.attrs.isEmpty {
                                        SimpleTable(
                                            headers: [L.storageSmartColAttribute, L.storageSmartColValue],
                                            rows: sel.attrs.map { [smartLocalizedLabel($0.0), $0.0 == "Critical Warning" ? smartCriticalWarningRU($0.1) : $0.1] },
                                            numericColumns: [1]
                                        )
                                    }
                                }
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
