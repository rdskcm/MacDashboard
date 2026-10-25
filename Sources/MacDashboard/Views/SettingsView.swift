// Views/SettingsView.swift
// REDESIGN-SETTINGS: the Settings window content (⌘,) — sidebar of five sections and a detail column of grouped rows,
// a literal port of `Settings.dc.html`. The window itself is `SettingsWindowController`.
import AppKit
import SwiftUI

/// Borderless `NSDatePicker` (hour and minute, no stepper): the system `.field` style draws its own bezel
/// inside our capsule. The capsule (frame, fill, stroke) is drawn by the caller.
private struct SettingsTimeField: NSViewRepresentable {
    @Binding var selection: Date

    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSDatePicker {
        let p = NSDatePicker()
        p.datePickerStyle = .textField
        p.datePickerElements = .hourMinute
        p.isBezeled = false
        p.isBordered = false
        p.drawsBackground = false
        p.font = Self.font
        p.textColor = NSColor(DS3.ink)
        p.dateValue = selection
        p.target = context.coordinator
        p.action = #selector(Coordinator.changed(_:))
        p.setAccessibilityLabel(L.settingsSnapshotLabel)
        return p
    }

    func updateNSView(_ p: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        if p.dateValue != selection { p.dateValue = selection }
    }

    // Keep the picker at its natural 21 pt height; the baseline alignment guide at the call site assumes that frame.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? natural.width, height: natural.height)
    }

    final class Coordinator: NSObject {
        var parent: SettingsTimeField
        init(_ parent: SettingsTimeField) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.selection = sender.dateValue }
    }
}

enum SettingsSection: Hashable {
    case general, monitoring, backup, iphone, about
}

/// Nav row press feedback: scale 0.97 on `DS3Motion.press`, none under Reduce Motion.
private struct SettingsNavRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : DS3Motion.press, value: configuration.isPressed)
    }
}

/// One row of a group (`Settings.dc.html:76-85`): label (+ optional sub line) left, fixed control right.
private struct SettingsRow<Control: View>: View {
    let label: String
    var sub: String? = nil
    var subColor: Color? = nil
    var separator = true
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            if separator { SettingsRowSeparator() }
            HStack(alignment: .center, spacing: 16) {
                SettingsRowLabel(label: label, sub: sub, subColor: subColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                control().fixedSize()
            }
            .frame(minHeight: 32)
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 14))
        }
    }
}

/// A path row (`Settings.dc.html:169`): single column, the path field and its button below the label (gap 8).
private struct SettingsPathRow: View {
    let label: String
    var sub: String? = nil
    var subColor: Color? = nil
    var separator = true
    let path: String
    var invalid = false
    let buttonTitle: String
    var busy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if separator { SettingsRowSeparator() }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRowLabel(label: label, sub: sub, subColor: subColor)
                HStack(spacing: 8) {
                    pathField
                    SettingsSecondaryButton(title: buttonTitle, busy: busy, disabled: disabled, action: action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 14))
        }
    }

    private var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }

    private var pathField: some View {
        Text(displayPath)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .tracking(0.25)
            .foregroundStyle(invalid ? DS3.hotInk : DS3.inkSoft)
            .lineLimit(1)
            .truncationMode(.head)
            .help(displayPath)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS3.field))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(invalid ? DS3.hot : DS3.line, lineWidth: invalid ? 1.5 : 1))
    }
}

private struct SettingsRowSeparator: View {
    var body: some View {
        Rectangle().fill(DS3.line).frame(height: 1).padding(.horizontal, 16)
    }
}

private struct SettingsRowLabel: View {
    let label: String
    let sub: String?
    let subColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS3.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(label)
            if let sub {
                Text(sub)
                    .font(.system(size: 12.5))
                    .lineSpacing(12.5 * 0.35)
                    .foregroundStyle(subColor ?? DS3.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// `Settings.dc.html:114`: 28 pt secondary button; `busy` swaps the label for a spinner in place.
private struct SettingsSecondaryButton: View {
    let title: String
    var busy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).dsSwapInPlace(busy) { ProgressView().controlSize(.small) }
        }
        .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 28, hPad: 13, fontSize: 13))
        .disabled(busy || disabled)
        .accessibilityLabel(title)
    }
}

/// A rounded group of rows (`Settings.dc.html:69-74`). No caption is used in this build (the captioned group was the
/// notification group, REDESIGN-NOTIFY).
private struct SettingsGroup<Content: View>: View {
    var caption: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption {
                Text(caption)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS3.muted)
                    .padding(.horizontal, 16)
            }
            VStack(spacing: 0) { content() }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .ds3GlassGroup(cornerRadius: 22)
        }
    }
}

struct SettingsView: View {
    @MainActor init(model: DashboardModel, state: SettingsWindowState, iphone: IPhoneModel? = nil,
         launchLanguage: AppLanguage = L10nStore.launchLanguage) {
        self.model = model
        self.iphone = iphone ?? .shared
        self.state = state
        self.launchLanguage = launchLanguage
        _relaunchRowShown = State(initialValue: L10nStore.shared.language != launchLanguage)
        _bannerShown = State(initialValue: model.claudeBackup == .unreadable)
    }

    // Harness-only init param so offscreen renders can show any section without
    // clicks (same precedent as MemoryCompositionCard.initialView).
    @MainActor init(model: DashboardModel, startSection: SettingsSection = .general, iphone: IPhoneModel? = nil,
         launchLanguage: AppLanguage = L10nStore.launchLanguage) {
        self.init(model: model, state: SettingsWindowState(section: startSection), iphone: iphone, launchLanguage: launchLanguage)
    }

    var model: DashboardModel
    var iphone: IPhoneModel
    @Bindable var state: SettingsWindowState
    let launchLanguage: AppLanguage
    @Bindable private var store = L10nStore.shared
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var relaunchRowShown: Bool
    @State private var relaunching = false
    @State private var bannerShown: Bool
    @State private var loginStatus: LoginItem.Status = VisualFixture.isRequested ? .enabled : LoginItem.status()
    /// REDESIGN-NOTIFY (R8): system authorization; fixture renders `fixtureStatus` or authorized without touching the system.
    @State private var notifyAuth: NotificationAuthorization =
        VisualFixture.isRequested ? (NotificationCenterClient.fixtureStatus ?? .authorized) : .notDetermined
    @State private var loginError: String?

    /// The chosen (or default) log file is not there: red path, red sidebar dot.
    private var pathMissing: Bool { model.claudeBackup == nil }
    private var rowAnim: Animation { reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.25) }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                detail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ds3Backdrop(orbs: DS3OrbSpec.settings)
        .onChange(of: store.language) { _, l in
            withAnimation(rowAnim) { relaunchRowShown = l != launchLanguage }
        }
        .onChange(of: model.claudeBackup) { _, s in
            withAnimation(rowAnim) { bannerShown = s == .unreadable }
        }
        .onAppear { refreshLoginStatus(); refreshNotifyStatus() }
        // The window is kept alive when closed, so `onAppear` does not fire again: re-read the system status each time
        // it is brought forward (R8).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshLoginStatus(); refreshNotifyStatus() }
    }

    private func refreshLoginStatus() {
        if !VisualFixture.isRequested { loginStatus = LoginItem.status() }
    }

    private func refreshNotifyStatus() {
        guard !VisualFixture.isRequested else { return }
        NotificationCenterClient.shared.status { s in withAnimation(rowAnim) { notifyAuth = s } }
    }

    // MARK: Sidebar (`Settings.dc.html:33-49`)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            navRow(.general, title: L.settingsSectionGeneral)
            navRow(.monitoring, title: L.settingsSectionMonitoring)
            navRow(.backup, title: L.settingsSectionBackup,
                   dot: pathMissing ? DS3.hot : (bannerShown ? DS3.amber : nil))
            navRow(.iphone, title: L.settingsSectionIPhone)
            navRow(.about, title: L.settingsSectionAbout)
            Spacer(minLength: 0)
            Text(L.settingsInstantNote)
                .font(.system(size: 12))
                .foregroundStyle(DS3.muted)
                .padding(.horizontal, 12)
        }
        .padding(.top, 50)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 184)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS3GlassBar())
        .overlay(alignment: .trailing) { Rectangle().fill(DS3.line).frame(width: 1) }
    }

    private func navRow(_ section: SettingsSection, title: String, dot: Color? = nil) -> some View {
        let selected = state.section == section
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { state.section = section } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? DS3.ink : DS3.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)
                Spacer(minLength: 0)
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                        .background(Circle().fill(dot.opacity(0.22)).frame(width: 13, height: 13))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Colour/opacity only: the pill fades between rows, nothing resizes.
                ZStack {
                    if selected {
                        shape.fill(DS3.lens)
                            .ds3InsetRims(shape, top: DS3.rimHi, ring: DS3.rimMid)
                            .ds3Elevation(.lens, in: shape)
                    }
                }
                .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.2), value: selected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsNavRowStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Detail (D20: the title sits outside the scroll view)

    private var sectionTitle: String {
        switch state.section {
        case .general: L.settingsSectionGeneral
        case .monitoring: L.settingsSectionMonitoring
        case .backup: L.settingsSectionBackup
        case .iphone: L.settingsSectionIPhone
        case .about: L.settingsSectionAbout
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sectionTitle)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.44)
                .foregroundStyle(DS3.ink)
                .padding(EdgeInsets(top: 16, leading: 24, bottom: 12, trailing: 24))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) { groups(for: state.section) }
                    .padding(EdgeInsets(top: 2, leading: 24, bottom: 24, trailing: 24))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func groups(for section: SettingsSection) -> some View {
        switch section {
        case .general: generalGroup
        case .monitoring: monitoringGroup
        case .backup: backupGroups
        case .iphone: iphoneGroup
        case .about: aboutGroup
        }
    }

    // MARK: General (`:171-181`)

    private var generalGroup: some View {
        SettingsGroup {
            SettingsRow(label: L.settingsLanguageLabel, separator: false) {
                DSSlidingSegmented(
                    options: LanguageChoice.allCases,
                    // AppleLanguages first: `Locale.preferredLanguages` includes the app-domain override, and `choice`'s didSet
                    // resolves `.system` against it (a stale explicit "ru" there would keep the app Russian).
                    selection: Binding(get: { store.choice }, set: { syncAppleLanguages(for: $0); store.choice = $0 }),
                    size: .settingsRow,
                    groupLabel: L.settingsLanguageLabel
                ) { c in
                    switch c {
                    case .system: L.settingsOptionSystem
                    case .en: "English"
                    case .ru: "Русский"
                    }
                }
            }
            if relaunchRowShown {
                VStack(spacing: 0) {
                    SettingsRowSeparator()
                    HStack(spacing: 16) {
                        Text(L.settingsMenuLanguageHint)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DS3.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SettingsSecondaryButton(title: L.settingsRelaunchNow, busy: relaunching) {
                            relaunching = true
                            relaunchApp()
                        }
                        .fixedSize()
                    }
                    .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 14))
                }
                .transition(.dsDisclosure(reduceMotion: reduceMotion))
            }
            SettingsRow(label: L.settingsThemeLabel) {
                DSSlidingSegmented(
                    options: AppAppearance.allCases,
                    selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0; $0.apply() }),
                    size: .settingsRow,
                    groupLabel: L.settingsThemeLabel
                ) { a in
                    switch a {
                    case .system: L.settingsOptionSystem
                    case .light: L.settingsThemeLight
                    case .dark: L.settingsThemeDark
                    }
                }
            }
            SettingsRow(label: L.settingsOrbsLabel, sub: L.settingsOrbsSub) {
                DS3Switch(isOn: $settings.orbsEnabled, label: L.settingsOrbsLabel, metrics: .settings)
            }
            SettingsRow(label: L.settingsLaunchAtLoginLabel,
                        sub: loginError ?? (loginStatus == .requiresApproval ? L.settingsLaunchAtLoginApproval : nil),
                        subColor: loginError != nil ? DS3.hotInk : nil) {
                DS3Switch(isOn: loginBinding, label: L.settingsLaunchAtLoginLabel, metrics: .settings)
            }
        }
    }

    /// R8: the switch shows the system's real status; a failure or «requires approval» is shown under the row.
    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled },
            set: { on in
                if VisualFixture.isRequested { loginStatus = on ? .enabled : .disabled; return }
                do { try LoginItem.setEnabled(on); loginError = nil } catch { loginError = error.localizedDescription }
                loginStatus = LoginItem.status()
                if loginStatus == .requiresApproval { LoginItem.openLoginItemsSettings() }
            }
        )
    }

    // MARK: Monitoring (`:183-187`)

    @ViewBuilder private var monitoringGroup: some View {
        SettingsGroup {
            SettingsRow(label: L.settingsIntervalLabel, separator: false) {
                DSSlidingSegmented(
                    options: AppSettings.allowedIntervals,
                    selection: $settings.fastIntervalSeconds,
                    size: .settingsRow,
                    groupLabel: L.settingsIntervalLabel
                ) { s in L.settingsIntervalOption(s) }
            }
            SettingsRow(label: L.settingsSnapshotLabel, sub: L.settingsSnapshotSub) {
                SettingsTimeField(selection: timeBinding)
                    // The picker's 21 pt cell keeps the bezel's asymmetric insets (about 1.4 pt above the line, 4.3 pt below) with the
                    // bezel off, so centring the frame leaves the text ~1 pt high. Centre the digits' cap height instead, from the baseline.
                    .alignmentGuide(VerticalAlignment.center) { d in d[.firstTextBaseline] - SettingsTimeField.font.capHeight / 2 }
                    .padding(.horizontal, 10)
                    .frame(width: 100, height: 28)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS3.field))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS3.line, lineWidth: 1))
                    .accessibilityLabel(L.settingsSnapshotLabel)
            }
            SettingsRow(label: L.settingsLowSpaceLabel) {
                DSSlidingSegmented(
                    options: AppSettings.allowedLowSpacePercents,
                    selection: Binding(get: { settings.lowSpacePercent }, set: { model.setLowSpacePercent($0) }),
                    size: .settingsRow,
                    groupLabel: L.settingsLowSpaceLabel
                ) { p in L.settingsLowSpaceOption(p) }
            }
        }
        notifyGroup
    }

    // MARK: Notify about attention items (`Settings.dc.html:188-195`, handoff 11-settings.md :26)

    private var notifyGroup: some View {
        SettingsGroup(caption: L.settingsNotifyCaption) {
            if notifyAuth == .denied {
                HStack(spacing: 16) {
                    Text(L.settingsNotifyDenied)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS3.amberInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsSecondaryButton(title: L.settingsNotifyOpen) { AdviceActionRunner.openPane(AdvicePanes.notifications) }
                        .accessibilityLabel(L.settingsNotifyOpenA11y)
                        .fixedSize()
                }
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 14))
                .transition(.dsDisclosure(reduceMotion: reduceMotion))
            }
            ForEach(Array(NotifyCategory.allCases.enumerated()), id: \.element) { i, c in
                SettingsRow(label: L.settingsNotifyLabel(c), separator: i > 0 || notifyAuth == .denied) {
                    DS3Switch(isOn: notifyBinding(c), label: L.settingsNotifyLabel(c), metrics: .settings)
                }
            }
            .disabled(notifyAuth == .denied)
        }
    }

    /// A switch turned on while the system has not been asked yet asks now (R6, D3).
    private func notifyBinding(_ c: NotifyCategory) -> Binding<Bool> {
        Binding(
            get: { settings.notifyEnabled.contains(c) },
            set: { on in
                if on { settings.notifyEnabled.insert(c) } else { settings.notifyEnabled.remove(c) }
                if on, notifyAuth == .notDetermined, !VisualFixture.isRequested {
                    NotificationCenterClient.shared.requestAuthorization { _ in refreshNotifyStatus() }
                }
            }
        )
    }

    /// Minutes since midnight ↔ a `Date` today at that time (only hour and minute are shown and read back).
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let m = settings.snapshotMinutes
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                settings.snapshotMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    // MARK: Backups (`:197-205`)

    @ViewBuilder
    private var backupGroups: some View {
        if bannerShown { permissionBanner.transition(.dsDisclosure(reduceMotion: reduceMotion)) }
        SettingsGroup {
            SettingsPathRow(
                label: L.settingsClaudeLogLabel,
                sub: pathMissing ? L.settingsPathMissing : nil,
                subColor: DS3.hotInk,
                separator: false,
                path: model.claudeLogPath,
                invalid: pathMissing,
                buttonTitle: L.settingsChoose,
                action: chooseLogFile
            )
            SettingsRow(label: L.settingsWarnAfterLabel, sub: L.settingsWarnAfterSub) { stepper }
        }
    }

    private var stepper: some View {
        let days = settings.backupStaleDays
        return HStack(spacing: 8) {
            Button("−") { model.setBackupStaleDays(days - 1) }
                .buttonStyle(DS3CircleButtonStyle(diameter: 28, ring: DS3.lineStrong, topRim: DS3.rimMid))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS3.ink)
                .disabled(days <= AppSettings.backupStaleDaysRange.lowerBound)
                .accessibilityLabel(L.settingsWarnAfterFewer)
            Text(L.settingsWarnAfterDays(days))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DS3.ink)
                .frame(minWidth: 64)
            Button("+") { model.setBackupStaleDays(days + 1) }
                .buttonStyle(DS3CircleButtonStyle(diameter: 28, ring: DS3.lineStrong, topRim: DS3.rimMid))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS3.ink)
                .disabled(days >= AppSettings.backupStaleDaysRange.upperBound)
                .accessibilityLabel(L.settingsWarnAfterMore)
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L.settingsPermTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS3.amberInk)
                Text(L.settingsPermBody)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS3.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(L.bkOpenPrivacy) { AdviceActionRunner.openPane(AdvicePanes.fullDiskAccess) }
                .buttonStyle(DS3ButtonStyle(kind: .secondary, height: 30, hPad: 14, fontSize: 13))
                .accessibilityLabel(L.bkOpenPrivacyA11y)
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [DS3.amber.opacity(0.13), DS3.amber.opacity(0.04)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DS3.amber.opacity(0.34), lineWidth: 0.5))
    }

    private func chooseLogFile() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.showsHiddenFiles = true
        p.directoryURL = URL(fileURLWithPath: model.claudeLogPath).deletingLastPathComponent()
        guard let w = NSApp.keyWindow else { return }
        p.beginSheetModal(for: w) { response in
            if response == .OK, let url = p.url { model.setClaudeLogPath(url.path) }
        }
    }

    // MARK: iPhone (`Settings.dc.html:206-209`)

    private var archiveFolderSub: String? {
        iphone.archiveFolderError.map { if case .couldNotMove(let n) = $0 { return L.settingsArchiveFolderMoveFailed(n) } else { return "" } }
    }

    private var iphoneGroup: some View {
        SettingsGroup {
            SettingsRow(label: L.settingsAutoReadLabel, sub: L.settingsAutoReadSub, separator: false) {
                DS3Switch(isOn: $settings.iphoneAutoRead, label: L.settingsAutoReadLabel, metrics: .settings)
            }
            SettingsRow(label: L.settingsKeepArchivesLabel) {
                DS3Switch(isOn: $settings.keepImportedArchives, label: L.settingsKeepArchivesLabel, metrics: .settings)
            }
            SettingsPathRow(
                label: L.settingsArchiveFolderLabel,
                sub: archiveFolderSub,
                subColor: DS3.hotInk,
                path: iphone.archiveRoot.path,
                invalid: iphone.archiveFolderError != nil,
                buttonTitle: L.settingsChoose,
                busy: iphone.archiveFolderBusy,
                // importArchive captures the keep root at its start; a move mid-import would leave it writing to the old folder.
                disabled: !iphone.importing.isEmpty,
                action: chooseArchiveFolder
            )
        }
    }

    private func chooseArchiveFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        let current = iphone.archiveRoot
        p.directoryURL = FileManager.default.fileExists(atPath: current.path) ? current : current.deletingLastPathComponent()
        guard let w = NSApp.keyWindow else { return }
        p.beginSheetModal(for: w) { response in
            if response == .OK, let url = p.url { Task { await iphone.setArchiveFolder(url) } }
        }
    }

    // MARK: About (`:212-216`)

    private var aboutGroup: some View {
        SettingsGroup {
            SettingsRow(label: L.settingsVersionLabel, separator: false) {
                Text(AppInfo.versionText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(0.26)
                    .monospacedDigit()
                    .foregroundStyle(DS3.inkSoft)
            }
            SettingsPathRow(
                label: L.settingsReportFolderLabel,
                path: AppInfo.supportFolderURL.path,
                buttonTitle: L.commonShowInFinder,
                action: { AdviceActionRunner.reveal(AppInfo.supportFolderURL.path) }
            )
        }
    }

    /// Same write as `MacDashboardApp.syncAppleLanguages()` (duplicated rather
    /// than shared across files: that one is file-private by design, and Engine
    /// must stay free of AppleLanguages writes since the tests cover Engine too).
    private func syncAppleLanguages(for choice: LanguageChoice) {
        switch choice {
        case .system:
            if UserDefaults.standard.object(forKey: "AppleLanguages") != nil {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        case .en, .ru:
            let want = [choice.rawValue]
            if UserDefaults.standard.stringArray(forKey: "AppleLanguages") != want {
                UserDefaults.standard.set(want, forKey: "AppleLanguages")
            }
        }
    }

    private func relaunchApp() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }
}
