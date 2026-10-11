// Views/IPhoneImportCard.swift
// Sysdiagnose import: archives on the phone, a Mac file picker, the parse-only / parse-and-
// keep choice, progress, the summary line and the kept archives (layout only, no animation).

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
    }
    @State private var pending: Pending?

    private var isConnected: Bool { model.connected[deviceKey] != nil }
    private var running: ImportProgress? { model.importing[deviceKey] }
    private var kept: [String] { model.devices.first { $0.id == deviceKey }?.keptArchives ?? [] }

    /// Phone archives: from the crash-log listing, newest first. Empty when not connected.
    private var phoneArchives: [IPhoneAFCEntry] {
        guard isConnected, let logs = model.logs[deviceKey] else { return [] }
        let all = logs.map { IPhoneAFCEntry(path: $0.path, isDirectory: false, size: $0.size, modified: $0.modified) }
        return IPhoneData.sysdiagnoseArchives(in: all)
    }

    var body: some View {
        CardChrome(title: L.iphoneImportTitle) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(phoneArchives, id: \.path) { a in archiveRow(a) }
                HStack(spacing: 12) {
                    RainbowCapsuleButton(title: L.iphoneImportPickFile, size: .card) { pickFile() }
                        .disabled(running != nil)
                        .accessibilityLabel(L.iphoneImportPickA11y)
                    if phoneArchives.isEmpty {
                        Text(L.iphoneImportHint).font(.caption).foregroundStyle(DS.muted)
                    }
                }
                status
                if !kept.isEmpty { keptList }
            }
        }
        .confirmationDialog(pending.map { L.iphoneImportConfirmTitle($0.name) } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { p in
            Button(L.iphoneImportParseOnly) { start(p, keep: false) }
                .accessibilityLabel(L.iphoneImportParseOnlyA11y)
            Button(L.iphoneImportParseKeep) { start(p, keep: true) }
                .accessibilityLabel(L.iphoneImportParseKeepA11y)
            Button(L.iphoneImportCancel, role: .cancel) { pending = nil }
                .accessibilityLabel(L.iphoneImportCancelA11y)
        }
    }

    private func archiveRow(_ a: IPhoneAFCEntry) -> some View {
        let name = (a.path as NSString).lastPathComponent
        return HStack(spacing: 12) {
            Text(name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(a.modified.map { fmtDisplayDay($0) } ?? "—")
                .font(.system(size: 12.5)).foregroundStyle(DS.muted).monospacedDigit()
            Text(fmtBytes(a.size))
                .font(.system(size: 12.5)).foregroundStyle(DS.muted).monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
            if let h = model.connected[deviceKey] {
                RainbowCapsuleButton(title: L.iphoneImportButton, size: .card) {
                    pending = Pending(name: name, source: .phone(handle: h, remotePath: a.path, size: a.size))
                }
                .disabled(running != nil)
                .accessibilityLabel(L.iphoneImportArchiveA11y(name))
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let p = running {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L.iphoneImportProgress(p)).font(.callout).foregroundStyle(DS.muted)
            }
        } else if let r = model.importResult[deviceKey] {
            switch r {
            case .success(let ok):
                Text("\(ok.name): \(L.iphoneImportSummary(ok.summary))").font(.callout).foregroundStyle(DS.ink)
            case .failure(let e):
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.iphoneImportError(e)).font(.callout).foregroundStyle(DS.muted)
                    if let detail = L.iphoneImportErrorDetail(e) {
                        Text(detail).font(.caption).foregroundStyle(DS.muted).lineLimit(3)
                    }
                }
            }
        }
    }

    private var keptList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.iphoneImportKeptTitle).font(.system(size: 12.5, weight: .semibold))
            ForEach(Array(kept.enumerated()), id: \.offset) { _, name in
                HStack(spacing: 12) {
                    Text(name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    RainbowCapsuleButton(title: L.reportShowInFinder, size: .card) {
                        AdviceActionRunner.reveal(keptURL(name).path)
                    }
                    .accessibilityLabel(L.iphoneImportRevealA11y(name))
                }
            }
        }
    }

    /// The path `SysdiagnoseImporter.keepArchive` writes to.
    private func keptURL(_ name: String) -> URL {
        IPhoneStore.defaultURL().deletingLastPathComponent()
            .appendingPathComponent("iphones", isDirectory: true)
            .appendingPathComponent(deviceKey, isDirectory: true)
            .appendingPathComponent("sysdiagnose", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gzip]
        panel.prompt = L.iphoneImportPickPrompt
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.lastPathComponent.hasSuffix(".tar.gz") else { return }
        pending = Pending(name: url.lastPathComponent, source: .mac(url))
    }

    private func start(_ p: Pending, keep: Bool) {
        pending = nil
        model.importArchive(deviceKey: deviceKey, source: p.source, keep: keep)
    }
}
