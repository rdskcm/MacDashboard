// Views/SecurityPage.swift
// REDESIGN-SECURITY: the Security section page (handoff 07-security) on the shared §8 blocks. Every text, tone and
// row comes from the pure SecurityPageModel; this file only draws them and forwards actions to DashboardModel.
// No live loop: the data arrives with the report pass, the page's Refresh and the privileged enable flow.

import SwiftUI

@MainActor
struct SecurityPage: View {
    let model: DashboardModel
    let router: NavigationRouter
    let windowWidth: CGFloat
    let onBack: () -> Void

    @State private var pulse: CardID? = nil

    private var narrow: Bool { windowWidth < 1000 }

    /// Reads no live model field (only `router.navigationSerial` / `destination`): the bar and the cards do the reading.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SecurityProtectionCard(model: model, narrow: narrow)
                        .id(CardID.protect)
                        .sectionFocusPulse(pulse == .protect)
                        .ds3Appear(delay: 0.08)
                    SecurityUpdatesCard(model: model)
                        .id(CardID.updates)
                        .sectionFocusPulse(pulse == .updates)
                        .ds3Appear(delay: 0.14)
                    SecurityCrashesCard(model: model)
                        .id(CardID.crashes)
                        .sectionFocusPulse(pulse == .crashes)
                        .ds3Appear(delay: 0.20)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) { SecurityPageBar(model: model, onBack: onBack) }
            .task(id: router.navigationSerial) {
                // Deep link: scroll the focused card under the bar (Protection is already on top) and pulse it.
                let d = router.destination
                guard d.page == .security, let f = d.focus else { return }
                if f != .protect { proxy.scrollTo(f, anchor: .top) }
                pulse = f
                try? await Task.sleep(for: .seconds(3))
                pulse = nil
            }
        }
        .ds3Appear(offset: CGSize(width: 28, height: 0), scale: 1, animation: DS3Motion.page)
    }
}

// MARK: - Input and mapping helpers

@MainActor
private func securityInput(_ model: DashboardModel, fileVaultOpened: Bool = false,
                           openedReportPath: String? = nil) -> SecurityPageModel.Input {
    .init(security: model.report.security, action: model.securityAction, fileVaultOpened: fileVaultOpened,
          updates: model.report.updates, updatesCheckedAt: model.report.updatesCheckedAt,
          checkingUpdates: model.isCheckingUpdates, crashes: model.report.crashes,
          openedReportPath: openedReportPath, now: model.fixtureNow ?? Date())
}

private func toneColor(_ t: SecurityTone) -> Color {
    switch t {
    case .green: return DS3.green
    case .amber: return DS3.amber
    case .hot: return DS3.hot
    case .neutral: return DS3.muted
    case .accent: return DS3.accent
    }
}

private func toneInk(_ t: SecurityTone?) -> Color {
    switch t {
    case nil: return DS3.ink
    case .green?: return DS3.greenInk
    case .amber?: return DS3.amberInk
    case .hot?: return DS3.hotInk
    case .neutral?: return DS3.muted
    case .accent?: return DS3.accentInk
    }
}

private func tagTone(_ t: SecurityTone) -> DS3Tag.Tone {
    switch t {
    case .green: return .green
    case .amber: return .amber
    case .hot: return .hot
    case .neutral: return .neutral
    case .accent: return .accent
    }
}

// MARK: - Page bar

/// Internal (not private): the visual fixture renders it.
@MainActor
struct SecurityPageBar: View {
    let model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        let m = SecurityPageModel.make(securityInput(model))
        SectionPageBar(symbol: Page.security.symbol, title: Page.security.title, sub: m.sub, onBack: onBack) {
            DS3Tag(tone: tagTone(m.tag), text: m.tagText).help(m.tagText)
        } trailing: {
            refresh
        }
    }

    /// Opacity ZStack: «Refresh» ↔ «Refreshing…» without a width change (`swap-in-place`).
    private var refresh: some View {
        let busy = model.securityRefreshing || model.isCheckingUpdates
        return Button { model.refreshSecurityNow() } label: {
            ZStack {
                Text(L.commonRefresh).opacity(busy ? 0 : 1)
                Text(L.commonRefreshing).opacity(busy ? 1 : 0)
            }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14))
        .disabled(busy)
        .accessibilityLabel(L.secRefreshA11y)
        .accessibilityIdentifier("security-refresh")
    }
}

// MARK: - Protection card

@MainActor
struct SecurityProtectionCard: View {
    let model: DashboardModel
    let narrow: Bool
    @State private var fileVaultOpened: Bool

    init(model: DashboardModel, narrow: Bool, initialFileVaultOpened: Bool = false) {
        self.model = model
        self.narrow = narrow
        _fileVaultOpened = State(initialValue: initialFileVaultOpened)
    }

    var body: some View {
        let m = SecurityPageModel.make(securityInput(model, fileVaultOpened: fileVaultOpened))
        DS3Card(title: L.commonProtection, caption: m.protectionCaption) {
            if m.protectionWait {
                SectionWait(text: L.commonCollectingData)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    EqualColumnsLayout(columns: narrow ? 2 : 4, spacing: 8) {
                        ForEach(m.tiles, id: \.protection) { t in
                            ProtectionTile(tile: t) { run(t) }
                        }
                    }
                    if let b = m.banner {
                        SecurityBanner(text: b)
                            .id(b)
                            .ds3Appear()
                    }
                }
            }
        }
    }

    private func run(_ t: SecurityTileModel) {
        switch t.button {
        case .enable?:
            model.enableProtectionNow(t.protection)
        case .openSettings?:
            AdviceActionRunner.openPane(AdvicePanes.fileVault)
            fileVaultOpened = true
        case nil:
            break
        }
    }
}

private struct ProtectionTile: View {
    let tile: SecurityTileModel
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(tile.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS3.inkSoft)
                    .lineLimit(1)
                if let dot = tile.dot {
                    let c = toneColor(dot)
                    Circle().fill(c)
                        .frame(width: 7, height: 7)
                        .background(Circle().fill(c.opacity(0.22)).frame(width: 13, height: 13))
                }
            }
            Text(tile.value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(toneInk(tile.valueTone))
                .lineLimit(1)
            if let note = tile.note {
                Text(note)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tile.noteTone == nil ? DS3.muted : toneInk(tile.noteTone))
                    .lineLimit(2)
            }
            if let button = tile.button {
                Button(action: action) {
                    // Label hidden (kept as the width determinant) and a centred spinner while busy (`swap-in-place`).
                    Text(buttonTitle(button)).dsSwapInPlace(tile.busy) { ProgressView().controlSize(.small) }
                }
                .buttonStyle(DS3ButtonStyle(kind: .primary, height: 30, hPad: 13, fontSize: 12.5))
                .disabled(tile.busy)
                .accessibilityLabel(buttonA11y(button))
                .accessibilityIdentifier(buttonIdentifier(button))
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The surface branches inside the background only: the button above keeps its identity across on/off.
        .background {
            if tile.error {
                Color.clear.ds3TintPanel(DS3.hot, from: 0.14, to: 0.05, ring: 0.45, cornerRadius: 20)
            } else {
                Color.clear
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS3.row))
                    .ds3InsetRims(RoundedRectangle(cornerRadius: 20, style: .continuous), top: DS3.rimLo, ring: DS3.line)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func buttonTitle(_ b: SecurityTileButton) -> String {
        switch b {
        case .enable: return L.commonEnable
        case .openSettings: return L.secOpenSettings
        }
    }

    private func buttonA11y(_ b: SecurityTileButton) -> String {
        switch b {
        case .enable: return L.secEnableA11y(tile.label)
        case .openSettings: return L.secOpenFileVaultA11y
        }
    }

    private func buttonIdentifier(_ b: SecurityTileButton) -> String {
        switch b {
        case .enable: return "security-enable-\(tile.protection.rawValue)"
        case .openSettings: return "security-filevault-settings"
        }
    }
}

private struct SecurityBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(DS3.hot).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS3.hotInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 18)
        .ds3TintPanel(DS3.hot, from: 0.12, to: 0.12, ring: 0.40, cornerRadius: 999)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Updates card

@MainActor
struct SecurityUpdatesCard: View {
    let model: DashboardModel

    var body: some View {
        let m = SecurityPageModel.make(securityInput(model))
        DS3Card(title: L.commonUpdates, caption: m.updatesCaption, trailing: { openSettings }) {
            VStack(alignment: .leading, spacing: 16) {
                if m.updatesWait {
                    SectionWait(text: m.updatesWaitText)
                } else {
                    if let n = m.updatesNote {
                        SectionNote(tone: toneColor(n.tone), text: n.text,
                                    button: n.showsInstall
                                        ? (L.commonInstall, L.secInstallA11y, false,
                                           { AdviceActionRunner.openPane(AdvicePanes.softwareUpdate) })
                                        : nil,
                                    buttonIdentifier: "security-updates-install", primary: true)
                    }
                    if !m.updateRows.isEmpty {
                        SecurityList {
                            ForEach(m.updateRows, id: \.id) { r in
                                SecurityListRow(dot: DS3.amber, name: r.name, sub: r.sub, value: r.value)
                            }
                        }
                    }
                }
            }
        }
    }

    private var openSettings: some View {
        Button { AdviceActionRunner.openPane(AdvicePanes.softwareUpdate) } label: {
            Text(L.maintenanceOpenSoftwareUpdate)
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 32, hPad: 14))
        .accessibilityLabel(L.secOpenSoftwareUpdateA11y)
        .accessibilityIdentifier("security-updates-settings")
    }
}

// MARK: - Crashes card

@MainActor
struct SecurityCrashesCard: View {
    let model: DashboardModel
    @State private var openedReportPath: String?

    init(model: DashboardModel, initialOpenedReport: String? = nil) {
        self.model = model
        _openedReportPath = State(initialValue: initialOpenedReport)
    }

    var body: some View {
        let m = SecurityPageModel.make(securityInput(model, openedReportPath: openedReportPath))
        DS3Card(title: L.secCrashesTitle, caption: m.crashesCaption) {
            if m.crashesWait {
                SectionWait(text: L.commonCollectingData)
            } else if m.crashesNone {
                SecurityList {
                    SecurityListRow(dot: DS3.green, name: L.secNoCrashes, sub: "", value: "✓")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SecurityList {
                        ForEach(m.crashRows, id: \.id) { r in
                            CrashRow(row: r, opened: r.path != nil && r.path == openedReportPath) {
                                guard let p = r.path else { return }
                                AdviceActionRunner.openInConsole(p)
                                openedReportPath = p
                            }
                        }
                    }
                    Text(m.crashFoot)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS3.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 6)
                }
            }
        }
    }
}

/// A crash row that opens its newest report in Console; without a path it is plain (no hover, no focus).
private struct CrashRow: View {
    let row: SecurityCrashRow
    let opened: Bool
    let open: () -> Void

    @State private var hover = false

    private var clickable: Bool { row.path != nil }

    var body: some View {
        SecurityListRow(dot: toneColor(row.tone), name: row.name, sub: row.sub, value: row.value)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hover || opened ? DS3.lens : Color.clear)
                    .animation(.easeOut(duration: 0.16), value: hover)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .pointingHandOnHover(isEnabled: clickable, hovering: $hover)
            .onTapGesture { if clickable { open() } }
            .help(clickable ? L.secOpenInConsole : "")
            .focusable(clickable)
            .onKeyPress(.return) { if clickable { open(); return .handled }; return .ignored }
            .onKeyPress(.space) { if clickable { open(); return .handled }; return .ignored }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(clickable ? .isButton : [])
            .accessibilityLabel(L.secCrashRowA11y(row.name, row.value))
            .accessibilityIdentifier("security-crash-\(row.id)")
            .accessibilityAction { if clickable { open() } }
    }
}

// MARK: - List blocks

/// The `BatteryHistoryCard.list` container: padding 6, radius 22, `DS3.row`, rows spaced 4.
private struct SecurityList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 4) { content() }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS3.row))
    }
}

private struct SecurityListRow: View {
    let dot: Color
    let name: String
    let sub: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .help(name)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DS3.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }
}
