// Views/IPhoneImportCard.swift
// Sysdiagnose import: archives on the phone, a Mac file picker, the parse-only / parse-and-
// keep choice, progress, the summary line and the kept archives (IPHONE-DESIGN: DS3), the «Create new
// sysdiagnose» request and the phone-side delete outcome.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IPhoneImportCard: View {
    let model: IPhoneModel
    let deviceKey: String

    /// The archive waiting for the user's choice.
    private struct Pending: Identifiable {
        var id: String { name }
        var name: String
        var source: SysdiagnoseImporter.Source
        var deletesFromPhone = false
    }
    @State private var pending: Pending?
    /// False once the card has left the screen (page switch): the dialog's dismissal then is not an answer;
    /// also gates the request poll (DEVICE-ARCHIVE-CLEANUP).
    @State private var onScreen = true

    private var isConnected: Bool { model.connected[deviceKey] != nil }
    private var running: ImportProgress? { model.importing[deviceKey] }
    /// Kept names whose file still exists (display-only: the record keeps every name, so an unmounted archive
    /// folder does not make the app forget archives).
    private var kept: [(name: String, url: URL)] {
        (model.devices.first { $0.id == deviceKey }?.keptArchives ?? []).compactMap { name in
            model.keptArchiveURL(deviceKey: deviceKey, name: name).map { (name, $0) }
        }
    }
    private var targetName: String {
        model.devices.first { $0.id == deviceKey }.map(IPhoneData.displayName) ?? L.iphoneUnknownDevice
    }
    private var question: ImportIdentityQuestion? { model.importQuestion[deviceKey] }
    private var record: IPhoneDeviceRecord? { model.devices.first { $0.id == deviceKey } }
    /// Names of the archives this app requested on this phone (only these are ever deleted there).
    private var ownNames: Set<String> { Set(record?.ownArchives?.map(\.name) ?? []) }
    private func deletes(_ name: String) -> Bool { ownNames.contains(name) && !AppSettings.shared.iphoneKeepRequestedOnPhone }

    /// Phone archives: from the crash-log listing, newest first. Empty when not connected.
    private var phoneArchives: [IPhoneAFCEntry] {
        guard isConnected, let logs = model.logs[deviceKey] else { return [] }
        let all = logs.map { IPhoneAFCEntry(path: $0.path, isDirectory: false, size: $0.size, modified: $0.modified) }
        return IPhoneData.sysdiagnoseArchives(in: all)
    }

    var body: some View {
        let items = kept
        return DS3Card(title: L.iphoneImportTitle) {
            VStack(alignment: .leading, spacing: 16) {
                if !phoneArchives.isEmpty { phoneSection }
                pickRow
                requestPanel
                status
                if !items.isEmpty { keptSection(items) }
            }
            .onAppear { onScreen = true; model.setRequestPanelShown(deviceKey: deviceKey, true) }
            .onDisappear { onScreen = false; model.setRequestPanelShown(deviceKey: deviceKey, false) }
            // A sheet, not a confirmationDialog/alert (macOS 27, checked with real key events): a system dialog
            // cannot have Cancel as both the Return default and the Escape button without a third, auto-added
            // Cancel (`role: .cancel` + `.defaultAction` leaves Escape dead; no role adds a system Cancel).
            .sheet(isPresented: Binding(get: { question != nil }, set: { shown in
                // Escape dismisses the sheet without running a button action: that is Cancel. A button click
                // runs its action first (the question is then already nil); a page switch runs onDisappear
                // first, whose `setRequestPanelShown(…, false)` answers Cancel (the question is then already nil).
                if !shown, onScreen, question != nil {
                    model.answerImportQuestion(deviceKey: deviceKey, proceed: false)
                }
            })) {
                if let q = question {
                    IPhoneMismatchSheet(
                        q: q,
                        onProceed: { model.answerImportQuestion(deviceKey: deviceKey, proceed: true) },
                        onCancel: { model.answerImportQuestion(deviceKey: deviceKey, proceed: false) })
                }
            }
        }
        // The parse-only / parse-and-keep choice is a sheet like the mismatch dialog; an Escape dismissal
        // clears `pending` through the item binding, which is Cancel.
        .sheet(item: $pending) { p in
            IPhoneImportChoiceSheet(
                title: L.iphoneImportConfirmTitle(into: targetName),
                archiveName: p.name,
                keepDefault: AppSettings.shared.keepImportedArchives,
                deleteNote: p.deletesFromPhone ? L.iphoneImportDeleteNote : nil,
                onCancel: { pending = nil },
                onParse: { start(p, keep: false) },
                onKeep: { start(p, keep: true) })
        }
    }

    // MARK: Sections

    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.iphoneImportOnPhone)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS3.muted)
            ForEach(phoneArchives, id: \.path) { archiveRow($0) }
        }
    }

    private func archiveRow(_ a: IPhoneAFCEntry) -> some View {
        let name = (a.path as NSString).lastPathComponent
        return HStack(spacing: 14) {
            Text(name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(a.modified.map { fmtDisplayDay($0) } ?? "—").foregroundStyle(DS3.muted)
            Text(fmtBytes(a.size)).foregroundStyle(DS3.muted)
            if let h = model.connected[deviceKey] {
                Button(L.iphoneImportButton) {
                    pending = Pending(name: name, source: .phone(handle: h, remotePath: a.path, size: a.size),
                                      deletesFromPhone: deletes(name))
                }
                .buttonStyle(DS3ButtonStyle(kind: .primary, height: 32, hPad: 14))
                .disabled(running != nil)
                .accessibilityLabel(L.iphoneImportArchiveA11y(name))
            }
        }
        .font(.system(size: 14))
        .monospacedDigit()
        .foregroundStyle(DS3.ink)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .ds3RowPanel(cornerRadius: 20)
    }

    private var pickRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(L.iphoneImportPickFile) { pickFile() }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1))
                .disabled(running != nil)
                .accessibilityLabel(L.iphoneImportPickA11y)
            if isConnected {
                Button(L.iphoneRequestButton) { model.requestSysdiagnose(deviceKey: deviceKey) }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 1))
                    .disabled(running != nil || model.sysdiagnoseRequest[deviceKey]?.isActive == true)
                    .accessibilityLabel(L.iphoneRequestButtonA11y)
            }
            if phoneArchives.isEmpty {
                Text(L.iphoneImportHint)
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let p = running {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    DS3Spinner(role: .accentInkRing, size: 14)
                    Text(L.iphoneImportProgress(p))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS3.accentInk)
                }
                bar(p)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ds3TintPanel(DS3.accent, from: 0.14, to: 0.05, ring: 0.28, cornerRadius: 20)
            .ds3Appear(offset: CGSize(width: 0, height: -6), scale: 1)
        } else if let r = model.importResult[deviceKey] {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            switch r {
            case .success(let ok):
                let cleanup = model.phoneCleanup[deviceKey].map { " " + L.iphonePhoneCleanup($0) } ?? ""
                resultPanel(text: "\(ok.name): \(L.iphoneImportSummary(ok.summary))\(cleanup)", ink: DS3.accentInk, detail: nil)
                    .ds3TintPanel(DS3.accent, from: 0.14, to: 0.05, ring: 0.28, cornerRadius: 20)
            case .failure(.cancelled):
                resultPanel(text: L.iphoneImportError(.cancelled), ink: DS3.inkSoft, detail: nil)
                    .background(shape.fill(DS3.row))
                    .ds3InsetRims(shape, ring: DS3.hot.opacity(0.4))
            case .failure(let e):
                resultPanel(text: L.iphoneImportError(e), ink: DS3.hotInk, detail: L.iphoneImportErrorDetail(e))
                    .background(shape.fill(DS3.hot.opacity(0.10)))
                    .ds3InsetRims(shape, ring: DS3.hot.opacity(0.4))
            }
        }
    }

    // DEVICE-ARCHIVE-CLEANUP: the «Create new sysdiagnose» request (same panel recipe as the import progress).
    @ViewBuilder private var requestPanel: some View {
        if let phase = model.sysdiagnoseRequest[deviceKey] {
            let text = requestText(phase)
            HStack(alignment: .center, spacing: 12) {
                Color.clear.frame(width: 14, height: 14)
                    .overlay { if phase.isActive { DS3Spinner(role: .accentInkRing, size: 14) } }
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(text.bad ? DS3.inkSoft : DS3.accentInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let body = text.body {
                        Text(body)
                            .font(.system(size: 13.5))
                            .foregroundStyle(DS3.inkSoft)
                            .lineLimit(text.isName ? 1 : nil)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: !text.isName)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                requestButtons(phase)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(RequestPanelSurface(bad: text.bad))
            .ds3Appear(offset: CGSize(width: 0, height: -6), scale: 1)
        }
    }

    private func requestText(_ p: SysdiagnoseRequestPhase) -> (title: String, body: String?, bad: Bool, isName: Bool) {
        let away = !isConnected
        switch p {
        case .preparing: return (L.iphoneRequestPreparing, nil, false, false)
        case .waiting: return (L.iphoneRequestWaitingTitle, away ? L.iphoneRequestReconnect : L.iphoneRequestWaitingBody, false, false)
        case .creating: return (L.iphoneRequestCreatingTitle, away ? L.iphoneRequestReconnect : L.iphoneRequestCreatingBody, false, false)
        case .ready(let own): return (L.iphoneRequestReadyTitle, own.name, false, true)
        case .ambiguous: return (L.iphoneRequestAmbiguousTitle, L.iphoneRequestAmbiguousBody, true, false)
        case .expired: return (L.iphoneRequestExpiredTitle, L.iphoneRequestExpiredBody, true, false)
        case .timedOut: return (L.iphoneRequestTimedOutTitle, L.iphoneRequestTimedOutBody, true, false)
        case .failed: return (L.iphoneRequestFailedTitle, L.iphoneRequestFailedBody, true, false)
        }
    }

    @ViewBuilder private func requestButtons(_ p: SysdiagnoseRequestPhase) -> some View {
        if case .ready(let own) = p, let h = model.connected[deviceKey] {
            Button(L.iphoneImportButton) {
                pending = Pending(name: own.name,
                                  source: .phone(handle: h, remotePath: SysdiagnoseDir.remotePath(own.name), size: own.size),
                                  deletesFromPhone: deletes(own.name))
            }
            .buttonStyle(DS3ButtonStyle(kind: .primary, height: 32, hPad: 14))
            .disabled(running != nil)
            .accessibilityLabel(L.iphoneImportArchiveA11y(own.name))
        }
        Button {
            model.cancelSysdiagnoseRequest(deviceKey: deviceKey)
        } label: {
            Text(L.iphoneRequestStop).dsSwapInPlace(!p.isActive) { Text(L.iphoneRequestClose) }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 1))
        .accessibilityLabel(p.isActive ? L.iphoneRequestStopA11y : L.iphoneRequestCloseA11y)
    }

    @ViewBuilder private func bar(_ p: ImportProgress) -> some View {
        switch p {
        case .copying(let done, let total):
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .progressViewStyle(.linear).tint(DS3.accent)
        case .extracting, .parsing:
            ProgressView().progressViewStyle(.linear).tint(DS3.accent)
        }
    }

    private func resultPanel(text: String, ink: Color, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(DS3.muted)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keptSection(_ items: [(name: String, url: URL)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.iphoneImportKeptTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS3.muted)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let name = item.name
                HStack(spacing: 14) {
                    Text(name)
                        .font(.system(size: 14))
                        .foregroundStyle(DS3.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L.reportShowInFinder) { AdviceActionRunner.reveal(item.url.path) }
                        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 1))
                        .accessibilityLabel(L.iphoneImportRevealA11y(name))
                    Button(L.iphoneImportKeptTrash) {
                        model.trashKeptArchive(deviceKey: deviceKey, name: name, url: item.url)
                    }
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14, topRim: 1))
                    .accessibilityLabel(L.iphoneImportKeptTrashA11y(name))
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .ds3RowPanel(cornerRadius: 20)
                if model.keptTrashFailed[deviceKey] == name {
                    let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                    resultPanel(text: L.iphoneImportKeptTrashFailed, ink: DS3.hotInk, detail: nil)
                        .background(shape.fill(DS3.hot.opacity(0.10)))
                        .ds3InsetRims(shape, ring: DS3.hot.opacity(0.4))
                }
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gzip]
        panel.prompt = L.iphoneImportPickPrompt
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pending = Pending(name: url.lastPathComponent, source: .mac(url))
    }

    private func start(_ p: Pending, keep: Bool) {
        pending = nil
        model.importArchive(deviceKey: deviceKey, source: p.source, keep: keep, deletesFromPhone: p.deletesFromPhone)
    }
}

/// The request panel's surface: the import progress tint, or the cancelled-result look for an ended request.
private struct RequestPanelSurface: ViewModifier {
    let bad: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if bad {
            content.background(shape.fill(DS3.row)).ds3InsetRims(shape, ring: DS3.hot.opacity(0.4))
        } else {
            content.ds3TintPanel(DS3.accent, from: 0.14, to: 0.05, ring: 0.28, cornerRadius: 20)
        }
    }
}

/// Parse-only / parse-and-keep choice (internal so the harness can render it).
struct IPhoneImportChoiceSheet: View {
    let title: String
    let archiveName: String
    /// `AppSettings.keepImportedArchives`: which of the two actions is primary and answers Return.
    let keepDefault: Bool
    var deleteNote: String? = nil
    let onCancel: () -> Void
    let onParse: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS3.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(archiveName)
                    .font(.system(size: 13))
                    .foregroundStyle(DS3.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.iphoneImportChoiceBody)
                    .font(.system(size: 13.5))
                    .foregroundStyle(DS3.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let deleteNote {
                    Text(deleteNote)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DS3.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L.iphoneImportCancel, action: onCancel)
                    .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 34, hPad: 15, topRim: 0))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(L.iphoneImportCancelA11y)
                Button(L.iphoneImportParseOnly, action: onParse)
                    .buttonStyle(DS3ButtonStyle(kind: keepDefault ? .secondary : .primary, height: 34, hPad: 15, topRim: keepDefault ? 0 : 0.5))
                    .keyboardShortcut(keepDefault ? nil : .defaultAction)
                    .accessibilityLabel(L.iphoneImportParseOnlyA11y)
                Button(L.iphoneImportParseKeep, action: onKeep)
                    .buttonStyle(DS3ButtonStyle(kind: keepDefault ? .primary : .secondary, height: 34, hPad: 15, topRim: keepDefault ? 0.5 : 0))
                    .keyboardShortcut(keepDefault ? .defaultAction : nil)
                    .accessibilityLabel(L.iphoneImportParseKeepA11y)
            }
        }
        .padding(22)
        .frame(width: 540)
    }
}

/// «Another phone» warning with both battery capacities side by side (internal so the harness can render it).
struct IPhoneMismatchSheet: View {
    let q: ImportIdentityQuestion
    let onProceed: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("!")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(DS3.amberInk)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS3.amber.opacity(0.18)))
                    .ds3InsetRims(RoundedRectangle(cornerRadius: 10, style: .continuous), ring: DS3.amber.opacity(0.45))
                Text(L.iphoneImportMismatchTitle(q.targetName))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS3.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L.iphoneImportMismatchMessage(file: q.archiveName, owner: q.ownerName, archiveMAh: q.archiveMAh,
                                               deviceMAh: q.deviceMAh, target: q.targetName))
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(DS3.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            comparison
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L.iphoneImportMismatchProceed, action: onProceed)
                    .buttonStyle(DS3ButtonStyle(kind: .danger, height: 34, hPad: 15))
                    .accessibilityLabel(L.iphoneImportMismatchProceedA11y)
                Button(L.iphoneImportCancel, action: onCancel)
                    .buttonStyle(DS3ButtonStyle(kind: .primary, height: 34, hPad: 15))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(L.iphoneImportCancelA11y)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 400)
    }

    private var comparison: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), alignment: .leading, spacing: 8) {
            cell(L.iphoneImportInArchive, q.archiveMAh.map { L.batteryMAh($0) }.joined(separator: ", "), DS3.amberInk)
            cell(q.targetName, L.batteryMAh(q.deviceMAh), DS3.ink)
        }
        .padding(12)
        .ds3RowPanel(cornerRadius: 18)
    }

    private func cell(_ label: String, _ value: String, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DS3.inkSoft)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
