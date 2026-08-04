// Views/SettingsView.swift
// App settings (⌘,): interface language and fast-loop polling interval.
import AppKit
import SwiftUI

enum SettingsSection: Hashable {
    case general, monitoring
    // Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
    #if AI_ENABLED
    case ai
    #endif
}

/// System-Settings-style sidebar row: a colored rounded-square icon badge
/// followed by the section title, plus the selection highlight itself (a plain
/// `Button` rather than `List` selection, so we control the sidebar's exact
/// width/height instead of NavigationSplitView's toolbar-driven chrome).
private struct SettingsSidebarRow: View {
    let icon: String
    let color: Color
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
            .foregroundStyle(selected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
/// AI assistant settings (Block AI, Wave 2): provider/base URL/model config in
/// `AppSettings`, API key kept out of UserDefaults entirely — it round-trips
/// through Keychain via `KeychainStore` only, never bound to a persisted property.
private struct AISettingsForm: View {
    @Bindable var settings: AppSettings

    @State private var keyInput: String = ""
    @State private var keyExists: Bool = false

    private static let anthropicModels = ["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5-20251001"]
    private static let openaiModels = ["gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o", "gpt-4o-mini", "o3-mini"]
    private static let customModelTag = "__custom__"

    private static func presetModels(for provider: AIProvider) -> [String] {
        provider == .anthropic ? anthropicModels : openaiModels
    }

    private var modelSelectionBinding: Binding<String> {
        Binding(
            get: {
                let presets = Self.presetModels(for: settings.aiProvider)
                return presets.contains(settings.aiModelId) ? settings.aiModelId : Self.customModelTag
            },
            set: { newValue in
                settings.aiModelId = newValue == Self.customModelTag ? "" : newValue
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Label(L.aiSettingsInDevelopmentNote, systemImage: "hammer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L.aiSettingsProviderLabel, selection: $settings.aiProvider) {
                    Text(verbatim: "Anthropic").tag(AIProvider.anthropic)
                    Text(verbatim: "OpenAI-compatible").tag(AIProvider.openaiCompatible)
                }
                .pickerStyle(.menu)
                .onChange(of: settings.aiProvider) { _, newProvider in
                    let presets = Self.presetModels(for: newProvider)
                    if !presets.contains(settings.aiModelId), let first = presets.first {
                        settings.aiModelId = first
                    }
                }

                HStack(spacing: 6) {
                    TextField(L.aiSettingsBaseURLLabel, text: $settings.aiBaseURL)
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .hoverTip(L.aiSettingsBaseURLPlaceholder)
                        .accessibilityLabel(L.aiSettingsBaseURLPlaceholder)
                }

                Picker(L.aiSettingsModelLabel, selection: modelSelectionBinding) {
                    ForEach(Self.presetModels(for: settings.aiProvider), id: \.self) { id in
                        Text(verbatim: id).tag(id)
                    }
                    Text(L.aiSettingsModelCustom).tag(Self.customModelTag)
                }
                .pickerStyle(.menu)

                if !Self.presetModels(for: settings.aiProvider).contains(settings.aiModelId) {
                    TextField(L.aiSettingsModelCustomPlaceholder, text: $settings.aiModelId)
                }
            }

            Section {
                SecureField(L.aiSettingsKeyLabel, text: $keyInput)

                HStack {
                    Button(L.aiSettingsKeySave) {
                        if KeychainStore.save(keyInput) {
                            keyInput = ""
                        }
                        keyExists = KeychainStore.exists()
                    }
                    .disabled(keyInput.isEmpty)

                    Button(L.aiSettingsKeyDelete) {
                        KeychainStore.delete()
                        keyExists = KeychainStore.exists()
                    }
                    .disabled(!keyExists)
                }

                if keyExists {
                    Label(L.aiSettingsKeyStored, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(L.aiSettingsKeyMissing, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text(L.aiSettingsPrivacyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { keyExists = KeychainStore.exists() }
    }
}
#endif

struct SettingsView: View {
    // Harness-only init param so offscreen renders can show any section without
    // clicks (same precedent as BatteryDetailView.startLifetimeExpanded).
    init(startSection: SettingsSection = .general) {
        _section = State(initialValue: startSection)
    }

    @State private var section: SettingsSection
    @Bindable private var store = L10nStore.shared
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 680, height: 420)
        .navigationTitle(L.settingsWindowTitle)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingsSidebarRow(
                icon: "gearshape.fill", color: .gray, title: L.settingsSectionGeneral,
                selected: section == .general
            ) { section = .general }
            SettingsSidebarRow(
                icon: "gauge.with.needle.fill", color: .blue, title: L.settingsSectionMonitoring,
                selected: section == .monitoring
            ) { section = .monitoring }
            #if AI_ENABLED
            SettingsSidebarRow(
                icon: "sparkles", color: .purple, title: L.settingsSectionAI,
                selected: section == .ai
            ) { section = .ai }
            #endif
            Spacer()
        }
        .padding(10)
        .frame(width: 190, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .general:
            Form {
                Section {
                    Picker(L.settingsLanguageLabel, selection: $store.language) {
                        Text(verbatim: "Русский").tag(AppLanguage.ru)
                        Text(verbatim: "English").tag(AppLanguage.en)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: store.language) { syncAppleLanguages() }

                    if store.language != L10nStore.launchLanguage {
                        Text(L.settingsMenuLanguageHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        RainbowCapsuleButton(title: L.settingsRelaunchNow, size: .primary) { relaunchApp() }
                    }
                }

                Section {
                    LabeledContent(L.settingsVersionLabel, value: appVersionString)
                }
            }
            .formStyle(.grouped)
        case .monitoring:
            Form {
                Section {
                    Picker(L.settingsIntervalLabel, selection: $settings.fastIntervalSeconds) {
                        ForEach(AppSettings.allowedIntervals, id: \.self) { s in
                            Text(L.settingsIntervalOption(s)).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
        #if AI_ENABLED
        case .ai:
            AISettingsForm(settings: settings)
        #endif
        }
    }

    /// Same write as `MacDashboardApp.syncAppleLanguages()` (duplicated rather
    /// than shared across files: that one is file-private by design, and Engine
    /// must stay free of AppleLanguages writes since Checks links Engine too).
    private func syncAppleLanguages() {
        let want = [store.language == .en ? "en" : "ru"]
        if UserDefaults.standard.stringArray(forKey: "AppleLanguages") != want {
            UserDefaults.standard.set(want, forKey: "AppleLanguages")
        }
    }

    private func relaunchApp() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    /// Reads the version straight from the built bundle's Info.plist (set from
    /// `VERSION`/`CODENAME` in build_app.sh) — never hard-coded in source.
    private var appVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }
}
