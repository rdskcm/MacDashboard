// Views/IPhoneFirmwareCard.swift
// IPHONE-IPSW: the «Firmware» card of the iPhone page. Installed iOS, the two lookups (Apple, ipsw.me), the build
// rows, the confirm sheet and the download panel (progress, stop / resume / discard, result). Drawn in the import
// card's vocabulary (DS3 only). The card owns no timer and no repeating animation: spinners and the indeterminate
// bar mount only while the card is inside the page's scroll viewport (no-unseen-work).

import AppKit
import SwiftUI

struct IPhoneFirmwareCard: View {
    let model: IPhoneModel
    let deviceKey: String

    /// False while the card is scrolled out of the page's viewport or unmounted (D14).
    @State private var inViewport = true

    private var ipsw: IPSWModel { model.ipsw }
    private var record: IPhoneDeviceRecord? { model.devices.first { $0.id == deviceKey } }
    private var snapshot: IPhoneSnapshot? { model.lastSnapshot[deviceKey] }
    private var productType: String? {
        let pt = snapshot?.productType ?? record?.productType
        return (pt?.isEmpty ?? true) ? nil : pt
    }

    /// The installed iOS: the connected phone's snapshot (with build), else the record (version only).
    private var installed: (version: String, build: String?, fromPhone: Bool)? {
        if let s = snapshot, let v = s.osVersion { return (v, s.build, true) }
        if let v = record?.osVersion { return (v, nil, false) }
        return nil
    }

    private var appleState: IPSWModel.Lookup<IPSWAppleTarget?>? { productType.flatMap { ipsw.apple[$0] } }
    private var meState: IPSWModel.Lookup<IPSWThirdParty>? { productType.flatMap { ipsw.ipswMe[$0] } }
    private var appleLoading: Bool { if case .loading? = appleState { return true } else { return false } }
    private var meLoading: Bool { if case .loading? = meState { return true } else { return false } }

    /// The `.ready` confirm that belongs to this model's page.
    private var readyConfirm: IPSWConfirm? {
        guard case .ready(let c)? = ipsw.confirm, let pt = productType, c.build.apple?.identifier == pt else { return nil }
        return c
    }

    var body: some View {
        DS3Card(title: L.ipswCardTitle) {
            VStack(alignment: .leading, spacing: 16) {
                installedRow
                actionRow
                statusLines
                sourceMessages
                buildRows
                downloadPanel
            }
            .onScrollVisibilityChange(threshold: 0.01) { inViewport = $0 }
            .onAppear { inViewport = true }
            .onDisappear { inViewport = false; ipsw.cancelConfirm() }
            .sheet(isPresented: Binding(get: { readyConfirm != nil }, set: { shown in
                if !shown { ipsw.cancelConfirm() }
            })) {
                if let c = readyConfirm {
                    IPSWConfirmSheet(c: c, onCancel: { ipsw.cancelConfirm() }, onDownload: { ipsw.confirmDownload() })
                }
            }
        }
    }

    // MARK: Spinner

    /// 14 pt slot: the spinner while the card is in the viewport, an empty square of the same size otherwise.
    @ViewBuilder private var spinner: some View {
        if inViewport {
            DS3Spinner(role: .accentInkRing, size: 14)
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    // MARK: Installed row

    @ViewBuilder private var installedRow: some View {
        if let i = installed {
            HStack(spacing: 10) {
                Text(L.ipswInstalled(i.version, i.build))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS3.ink)
                    .lineLimit(1)
                Text(i.fromPhone ? L.ipswInstalledFromPhone : L.ipswInstalledLastSeen(record.map { fmtDisplayDay($0.lastSeen) } ?? "—"))
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let s = ipsw.installedSigning(productType: productType, build: i.build, version: i.version) {
                    DS3Tag(tone: signingTone(s), text: signingText(s))
                        .layoutPriority(1)
                }
            }
        } else {
            Text(L.ipswInstalledUnknown)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signingTone(_ s: InstalledSigning) -> DS3Tag.Tone {
        switch s {
        case .signed, .isAppleTarget: return .green
        default: return .neutral
        }
    }

    private func signingText(_ s: InstalledSigning) -> String {
        switch s {
        case .signed: return L.ipswSigned
        case .notSigned: return L.ipswNotSigned
        case .notListed: return L.ipswNotListed
        case .isAppleTarget: return L.ipswIsAppleTarget
        case .notAppleTarget: return L.ipswNotAppleTarget
        case .unknown: return L.ipswUnknown
        }
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { ipsw.checkApple(productType: productType) } label: {
                Text(L.ipswCheckApple).dsSwapInPlace(appleLoading) { spinner }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1))
            .disabled(appleLoading || productType == nil)
            .accessibilityLabel(appleLoading ? L.ipswChecking : L.ipswCheckAppleA11y)
            Button { ipsw.askIPSWMe(productType: productType) } label: {
                Text(L.ipswAskIPSWMe).dsSwapInPlace(meLoading) { spinner }
            }
            .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1))
            .disabled(meLoading || productType == nil)
            .accessibilityLabel(meLoading ? L.ipswChecking : L.ipswAskIPSWMeA11y(productType ?? ""))
            if let pt = productType {
                Text(L.ipswAskSends(pt))
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Hint and checked lines

    @ViewBuilder private var statusLines: some View {
        let checked = checkedLine
        if productType == nil {
            Text(L.ipswErrNoIdentifier)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else if checked == nil {
            Text(L.ipswHint)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let checked {
            Text(checked)
                .font(.system(size: 12.5))
                .foregroundStyle(DS3.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// «Apple: checked <time> · ipsw.me: checked <time>» for each loaded source, nil when none is loaded.
    private var checkedLine: String? {
        var parts: [String] = []
        if case .loaded(_, fetchedAt: let at)? = appleState { parts.append(L.ipswCheckedAt("Apple", fmtDisplayDateTimeShort(at))) }
        if case .loaded(_, fetchedAt: let at)? = meState { parts.append(L.ipswCheckedAt("ipsw.me", fmtDisplayDateTimeShort(at))) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Source messages

    @ViewBuilder private var sourceMessages: some View {
        if case .failed(let e)? = appleState {
            IPhoneMessagePanel(text: L.ipswSourceFailed("Apple", IPSWData.message(for: e)), tone: .error)
        }
        if case .failed(let e)? = meState {
            IPhoneMessagePanel(text: L.ipswSourceFailed("ipsw.me", IPSWData.message(for: e)), tone: .error)
        }
        if case .loaded(let target, fetchedAt: _)? = appleState, target == nil {
            IPhoneMessagePanel(text: L.ipswAppleUnknownModel)
        }
    }

    // MARK: Build rows

    /// A download of another model is running or stopped: every «Download» here is disabled.
    private var busyElsewhere: Bool { ipsw.blocksStart && ipsw.downloadPhase(for: productType) == nil }
    private var busyPaused: Bool {
        if let d = ipsw.download, case .paused = d.phase { return true }
        return false
    }

    @ViewBuilder private var buildRows: some View {
        let v = ipsw.visibleBuilds(productType: productType, installedBuild: installed?.build,
                                   installedVersion: installed?.version)
        if !v.rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(v.rows) { buildRow($0) }
            }
        }
        if v.hiddenUnsigned > 0 {
            Text(L.ipswOlderHidden(v.hiddenUnsigned))
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if busyElsewhere && !v.rows.isEmpty {
            Text(busyPaused ? L.ipswBusyPaused : L.ipswBusy)
                .font(.system(size: 13))
                .foregroundStyle(DS3.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buildRow(_ b: IPSWBuild) -> some View {
        let availability = IPSWData.availability(b)
        let date = b.ipswMe?.releaseDate ?? b.apple?.releaseDate
        let size = b.ipswMe?.fileSize ?? b.apple?.fileSize
        // One layout for every row: line 1 = version, build, date, size and the button (never truncated);
        // line 2 = the tags (they drop under each other when they do not fit side by side); line 3 = the note.
        let tags = [b.isAppleTarget ? DS3Tag(tone: .accent, text: L.ipswIsAppleTarget) : nil,
                    b.signed.map { DS3Tag(tone: $0 ? .green : .neutral, text: $0 ? L.ipswSigned : L.ipswNotSigned) }]
            .compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    Text("iOS \(b.version)")
                        .font(.system(size: 14))
                        .foregroundStyle(DS3.ink)
                    Text(b.buildID)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(DS3.muted)
                }
                .lineLimit(1)
                .layoutPriority(2)
                if let date {
                    Text(fmtDisplayDay(date)).font(.system(size: 14)).foregroundStyle(DS3.muted).lineLimit(1)
                        .layoutPriority(1)
                }
                if let size, size > 0 {
                    Text(fmtCapacity(size)).font(.system(size: 14)).foregroundStyle(DS3.muted).lineLimit(1)
                        .layoutPriority(1)
                }
                Spacer(minLength: 0)
                if case .available = availability { downloadButton(b).layoutPriority(2) }
            }
            if !tags.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { ForEach(0..<tags.count, id: \.self) { tags[$0] } }
                    VStack(alignment: .leading, spacing: 6) { ForEach(0..<tags.count, id: \.self) { tags[$0] } }
                }
            }
            switch availability {
            case .available: EmptyView()
            case .noSecureAppleLink: sentence(L.ipswNoSecureAppleLink)
            case .notFromApple: sentence(L.ipswNotFromApple)
            }
        }
        .monospacedDigit()
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .ds3RowPanel(cornerRadius: 20)
    }

    private func sentence(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(DS3.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func downloadButton(_ b: IPSWBuild) -> some View {
        let preparing = ipsw.confirm == .preparing(b)
        return Button { ipsw.requestDownload(b) } label: {
            Text(L.ipswDownload).dsSwapInPlace(preparing) { spinner }
        }
        .buttonStyle(DS3ButtonStyle(kind: .primary, height: 32, hPad: 14))
        .disabled(ipsw.blocksStart || ipsw.confirm != nil)
        .help(busyElsewhere ? (busyPaused ? L.ipswBusyPaused : L.ipswBusy) : "")
        .accessibilityLabel(L.ipswDownloadA11y(b.version, b.buildID))
    }

    // MARK: Download panel

    @ViewBuilder private var downloadPanel: some View {
        if let phase = ipsw.downloadPhase(for: productType), let d = ipsw.download {
            panel(phase, build: d.build)
        }
    }

    private func panel(_ phase: IPSWDownloadPhase, build b: IPSWBuild) -> some View {
        let t = panelText(phase, build: b)
        return HStack(alignment: .center, spacing: 12) {
            Color.clear.frame(width: 14, height: 14)
                .overlay {
                    if t.spins && inViewport {
                        DS3Spinner(role: .accentInkRing, size: 14)
                    } else if t.check {
                        // The completed-operation look of IdentifierRevealControls / the Logs card «Saved» (:44-48).
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS3.accentInk)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(t.title)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(t.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(t.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(size: line.small ? 12.5 : 13.5))
                        .foregroundStyle(line.small ? DS3.muted : DS3.inkSoft)
                        .lineLimit(line.oneLine ? 1 : nil)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: !line.oneLine)
                }
                bar(phase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            buttons(phase, build: b)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FirmwarePanelSurface(surface: t.surface))
        .ds3Appear(offset: CGSize(width: 0, height: -6), scale: 1)
    }

    private struct Line { var text: String; var small = false; var oneLine = false }

    private func panelText(_ phase: IPSWDownloadPhase, build b: IPSWBuild)
        -> (title: String, ink: Color, lines: [Line], surface: FirmwareSurface, spins: Bool, check: Bool) {
        switch phase {
        case .preparing:
            return (L.ipswPreparing, DS3.accentInk, [], .tint, true, false)
        case .downloading(let w, let t):
            return (L.ipswDownloading(fmtCapacity(w), fmtCapacity(t)), DS3.accentInk, [], .tint, true, false)
        case .verifying(let h, let t):
            return (L.ipswVerifyingProgress(fmtCapacity(h), fmtCapacity(t)), DS3.accentInk, [], .tint, true, false)
        case .paused(let w, let t, let interruption):
            var lines = [Line(text: "iOS \(b.version) (\(b.buildID))")]
            lines.append(Line(text: interruption.map { IPSWData.message(for: $0) + " " + L.ipswPausedBody } ?? L.ipswPausedBody))
            if let at = ipsw.stoppedAt { lines.append(Line(text: L.ipswStoppedOn(fmtDisplayDateTimeShort(at)), small: true)) }
            if let n = ipsw.outdatedNote(productType: productType) {
                lines.append(Line(text: L.ipswParkedOutdated(n.version, n.buildID)))
            }
            if interruption != nil {
                return (L.ipswInterruptedTitle(fmtCapacity(w), fmtCapacity(t)), DS3.inkSoft, lines, .cancelled, false, false)
            }
            return (L.ipswPausedTitle(fmtCapacity(w), fmtCapacity(t)), DS3.ink, lines, .stopped, false, false)
        case .finished(let url, _) where ipsw.fileIsGone(url):
            return (L.ipswFileGone, DS3.inkSoft, [], .stopped, false, false)
        case .finished(let url, let verified):
            return (L.ipswFinished, DS3.accentInk,
                    [Line(text: url.lastPathComponent, oneLine: true), Line(text: IPSWData.verifiedText(verified))],
                    .tint, false, true)
        case .failed(.cancelled):
            return (L.ipswCancelled, DS3.inkSoft, [], .cancelled, false, false)
        case .failed(.resumeRejected):
            return (L.ipswErrResumeRejected, DS3.hotInk, [], .error, false, false)
        case .failed(let e):
            return (IPSWData.message(for: e), DS3.hotInk, [], .error, false, false)
        }
    }

    @ViewBuilder private func bar(_ phase: IPSWDownloadPhase) -> some View {
        switch phase {
        case .preparing:
            // The indeterminate bar animates, so it exists only inside the viewport (no-unseen-work).
            if inViewport { ProgressView().progressViewStyle(.linear).tint(DS3.accent) }
            else { ProgressView(value: 0, total: 1).progressViewStyle(.linear).tint(DS3.accent) }
        case .downloading(let w, let t):
            ProgressView(value: Double(w), total: Double(max(t, 1))).progressViewStyle(.linear).tint(DS3.accent)
        case .verifying(let h, let t):
            ProgressView(value: Double(h), total: Double(max(t, 1))).progressViewStyle(.linear).tint(DS3.accent)
        case .paused(let w, let t, _):
            ProgressView(value: Double(w), total: Double(max(t, 1))).progressViewStyle(.linear).tint(DS3.accent)
        case .finished, .failed:
            EmptyView()
        }
    }

    @ViewBuilder private func buttons(_ phase: IPSWDownloadPhase, build b: IPSWBuild) -> some View {
        switch phase {
        case .preparing:
            secondary(L.ipswStop, L.ipswCancelA11y) { ipsw.cancelDownload() }
        case .downloading, .verifying:
            secondary(L.ipswStop, L.ipswStopA11y) { ipsw.cancelDownload() }
        case .paused:
            let outdated = ipsw.outdatedNote(productType: productType) != nil
            button(L.ipswResume, L.ipswResumeA11y, primary: !outdated) { ipsw.resumeDownload() }
            button(L.ipswDiscard, L.ipswDiscardA11y, primary: outdated) { ipsw.discardDownload() }
        case .finished(let url, _) where ipsw.fileIsGone(url):
            secondary(L.ipswClose, L.ipswCloseA11y) { ipsw.dismissDownload() }
        case .finished(let url, _):
            secondary(L.reportShowInFinder, L.ipswRevealA11y(url.lastPathComponent)) { AdviceActionRunner.reveal(url.path) }
            secondary(L.ipswClose, L.ipswCloseA11y) { ipsw.dismissDownload() }
        case .failed(.resumeRejected):
            button(L.ipswStartOver, L.ipswStartOverA11y, primary: true) { ipsw.startOver() }
            secondary(L.ipswClose, L.ipswCloseA11y) { ipsw.dismissDownload() }
        case .failed:
            secondary(L.ipswClose, L.ipswCloseA11y) { ipsw.dismissDownload() }
        }
    }

    private func secondary(_ title: String, _ a11y: String, _ action: @escaping () -> Void) -> some View {
        button(title, a11y, primary: false, action)
    }

    private func button(_ title: String, _ a11y: String, primary: Bool, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(DS3ButtonStyle(kind: primary ? .primary : .secondary, height: 32, hPad: 14, topRim: primary ? 0.5 : 1))
            .accessibilityLabel(a11y)
    }
}

/// The panel looks copied from `IPhoneImportCard` (its `RequestPanelSurface` is private): progress and result tint,
/// stopped row, interrupted / cancelled (row + hot ring 0.4) and error (hot 0.10 + ring).
private enum FirmwareSurface { case tint, stopped, cancelled, error }

private struct FirmwarePanelSurface: ViewModifier {
    let surface: FirmwareSurface

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        switch surface {
        case .tint:
            content.ds3TintPanel(DS3.accent, from: 0.14, to: 0.05, ring: 0.28, cornerRadius: 20)
        case .stopped:
            content.ds3RowPanel(cornerRadius: 20)
        case .cancelled:
            content.background(shape.fill(DS3.row)).ds3InsetRims(shape, ring: DS3.hot.opacity(0.4))
        case .error:
            content.background(shape.fill(DS3.hot.opacity(0.10))).ds3InsetRims(shape, ring: DS3.hot.opacity(0.4))
        }
    }
}

/// Confirm step before any firmware byte (internal so the harness can render it).
struct IPSWConfirmSheet: View {
    let c: IPSWConfirm
    let onCancel: () -> Void
    let onDownload: () -> Void

    private var warns: Bool { c.lowSpace != nil && c.blocked == nil }
    private var freeAfter: Int64? {
        guard let a = c.available, let s = c.size else { return nil }
        return a - s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.ipswConfirmTitle(c.build.version, c.build.buildID))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS3.ink)
                .fixedSize(horizontal: false, vertical: true)
            facts
            Text(L.ipswConfirmChecks(IPSWData.digestList(c.checks)))
                .font(.system(size: 13))
                .foregroundStyle(DS3.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if warns, let free = freeAfter {
                HStack(spacing: 10) {
                    Text("!")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(DS3.amberInk)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS3.amber.opacity(0.18)))
                        .ds3InsetRims(RoundedRectangle(cornerRadius: 10, style: .continuous), ring: DS3.amber.opacity(0.45))
                    Text(L.ipswLowSpaceWarning(fmtCapacity(free), c.lowPercent))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DS3.amberInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let e = c.blocked {
                Text(IPSWData.message(for: e))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS3.hotInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if c.blocked != nil {
                    Button(L.ipswClose, action: onCancel)
                        .buttonStyle(DS3ButtonStyle(kind: .primary, height: 34, hPad: 15, topRim: 0.5))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel(L.ipswCloseA11y)
                } else {
                    Button(L.ipswCancel, action: onCancel)
                        .buttonStyle(DS3ButtonStyle(kind: warns ? .primary : .secondary, height: 34, hPad: 15, topRim: warns ? 0.5 : 0))
                        .keyboardShortcut(warns ? .defaultAction : .cancelAction)
                        .accessibilityLabel(L.ipswCancelA11y)
                    Button(warns ? L.ipswDownloadAnyway : L.ipswDownload, action: onDownload)
                        .buttonStyle(DS3ButtonStyle(kind: warns ? .secondary : .primary, height: 34, hPad: 15, topRim: warns ? 0 : 0.5))
                        .keyboardShortcut(warns ? nil : .defaultAction)
                        .accessibilityLabel(L.ipswDownloadA11y(c.build.version, c.build.buildID))
                }
            }
        }
        .padding(22)
        .frame(width: 540)
    }

    private var facts: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), alignment: .leading, spacing: 8) {
            cell(L.ipswConfirmSize, c.size.map { fmtCapacity($0) } ?? "—")
            cell(L.ipswConfirmDestination, c.destination.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "—")
            cell(L.ipswConfirmHost, c.host)
            cell(L.ipswConfirmFreeAfter, freeAfter.map { fmtCapacity(max($0, 0)) } ?? "—")
        }
        .padding(12)
        .ds3RowPanel(cornerRadius: 18)
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DS3.inkSoft)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13.5))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
