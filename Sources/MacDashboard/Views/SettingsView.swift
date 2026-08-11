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

/// Same rounded-rect/hairline-border/top-sheen-highlight/soft-shadow treatment
/// as the shared `.dsCardSurface()` (DesignSystem.swift), but filled with a
/// plain `DS.glass` color instead of `.regularMaterial` — kept private to this
/// file rather than added to `DesignSystem.swift` since it exists for exactly
/// one call site (`SettingsView.languageCard`, Trap 2 / README §6.6: that card
/// must carry no backdrop blur of its own, see its doc comment).
private struct SolidCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.glass))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [.init(color: DS.sheenLine, location: 0), .init(color: .clear, location: 0.15)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 8)
    }
}
private extension View {
    func dsSolidCardSurface() -> some View { modifier(SolidCardSurface()) }
}

/// System-Settings-style sidebar row (Spec §7.1, SW:17-31): a 22×22 icon badge
/// followed by the section title, plus the selection highlight itself (a plain
/// `Button` rather than `List` selection, so we control the sidebar's exact
/// width/height instead of NavigationSplitView's toolbar-driven chrome).
private struct SettingsSidebarRow: View {
    let icon: SettingsSidebarIconKind
    let title: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                iconBadge
                Text(title)
                    .font(.system(size: 14))
                    .tracking(14 * -0.005)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? DS.accentInk : DS.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? DS.accent.opacity(0.15) : (hovering ? DS.glass3 : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? DS.accent.opacity(0.34) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DSMotion.cardHover, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 22×22, radius 7 — concentric with the row's own radius 10 (Spec §7.1).
    /// `.gear`/`.pulse` use the new selected/unselected DS-token badge; the
    /// legacy `.symbol` case (AI row only, out of scope) keeps its old solid-
    /// tint-square look so it still compiles without adopting either new shape.
    @ViewBuilder
    private var iconBadge: some View {
        switch icon {
        case .gear, .pulse:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? DS.accent.opacity(0.22) : DS.muted.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? DS.accent.opacity(0.40) : DS.muted.opacity(0.30), lineWidth: 1)
                )
                .frame(width: 22, height: 22)
                .overlay(glyph.padding(4))
        case .symbol(let name, let tint):
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                )
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .gear:
            SettingsGearIconShape()
                .stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                .foregroundStyle(selected ? DS.accentInk : DS.inkSoft)
        case .pulse:
            SettingsPulseIconShape()
                .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(selected ? DS.accentInk : DS.inkSoft)
        case .symbol:
            EmptyView()
        }
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
    init(model: DashboardModel, startSection: SettingsSection = .general) {
        self.model = model
        _section = State(initialValue: startSection)
    }

    var model: DashboardModel
    @State private var section: SettingsSection
    @Bindable private var store = L10nStore.shared
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VisualEffectBackground()
            OrbLayer()
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(DS.line).frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        // NO `.ignoresSafeArea()` here: the window keeps its system titlebar, so
        // ignoring the safe area stretches the layout region by the titlebar height
        // while this root stays pinned to 420 — the content slides up under the
        // titlebar (top card clipped) and leaves an uncovered strip along the bottom,
        // transparent because `VisualEffectBackground` sets the window background clear.
        .frame(width: 680, height: 420)
    }

    /// Spec §7.1 (SW:14-35): 196 pt fixed, never scrolls; column gap 2, padding
    /// 12/10; fill `glass-2` over `.regularMaterial`, border-right `DS.line`
    /// (drawn by the shared `HStack` divider above), 1 pt inset top sheen highlight.
    private var sidebar: some View {
        // No "SETTINGS" kicker: the prototype (SW:15) has one, but with the system
        // titlebar already naming the window it is redundant — removed by user
        // decision at acceptance (V2-SETTINGS-CHROME, 2026-08-11), rows start at the
        // sidebar's own top padding.
        VStack(alignment: .leading, spacing: 2) {
            SettingsSidebarRow(icon: .gear, title: L.settingsSectionGeneral, selected: section == .general) {
                section = .general
            }
            SettingsSidebarRow(icon: .pulse, title: L.settingsSectionMonitoring, selected: section == .monitoring) {
                section = .monitoring
            }
            #if AI_ENABLED
            SettingsSidebarRow(icon: .symbol(name: "sparkles", tint: .purple), title: L.settingsSectionAI, selected: section == .ai) {
                section = .ai
            }
            #endif
            Spacer(minLength: 0)
        }
        .padding(.top, 12).padding(.bottom, 12).padding(.horizontal, 10)
        .frame(width: 196, alignment: .topLeading)
        .frame(maxHeight: .infinity)
        .background(sidebarChrome)
    }

    /// `DS.glass2` layered over `.regularMaterial`, same two-layer technique
    /// `MainDashboardView.toolbarChrome` uses for its own glass-2 surface, plus
    /// the shared top-edge sheen-fade highlight (SW:14's `inset 0 1px 0 sheen-line`).
    private var sidebarChrome: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle().fill(DS.glass2)
        }
        .overlay(
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        stops: [.init(color: DS.sheenLine, location: 0), .init(color: .clear, location: 0.15)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .general:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    languageCard
                    versionCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .monitoring:
            ScrollView {
                monitoringCard
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        #if AI_ENABLED
        case .ai:
            AISettingsForm(settings: settings)
        #endif
        }
    }

    /// Spec §7.2 (SW:40-77): standard card padding/gap, but — Trap 2, README
    /// §6.6 — **no backdrop blur of its own** (`.dsSolidCardSurface()` below,
    /// not the shared `.dsCardSurface()`): a blurred card behind
    /// `LanguageDropdown`'s trigger would leave its floating `.regularMaterial`
    /// menu nothing to frost, rendering it as a flat color instead.
    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                Text(L.settingsLanguageLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.inkSoft)
                Spacer(minLength: 0)
                LanguageDropdown(selection: $store.language) { syncAppleLanguages() }
            }
            .frame(minHeight: 30)

            if store.language != L10nStore.launchLanguage {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(DS.line).frame(height: 1)
                    HStack(alignment: .center, spacing: 12) {
                        Text(L.settingsMenuLanguageHint)
                            .font(.system(size: 11.5))
                            .lineSpacing(11.5 * 0.4)
                            .foregroundStyle(DS.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        RainbowCapsuleButton(title: L.settingsRelaunchNow, recipe: .settings, size: .primary) {
                            relaunchApp()
                        }
                        .accessibilityLabel(L.settingsRelaunchNow)
                    }
                    .padding(.top, 11)
                }
                .transition(.dsDisclosure(reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSolidCardSurface()
        .animation(
            reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
            value: store.language != L10nStore.launchLanguage
        )
    }

    /// Spec §7.2 (SW:79-82): separate card, WITH blur — the shared
    /// `.dsCardSurface()` is fine here since nothing frosted floats above it.
    private var versionCard: some View {
        HStack(spacing: 12) {
            Text(L.settingsVersionLabel)
                .font(.system(size: 14))
                .foregroundStyle(DS.inkSoft)
            Spacer(minLength: 0)
            Text(appVersionString)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DS.muted)
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface()
    }

    /// Spec §7.3 (SW:85-101): one card, padding 14/16, gap 11, blur. Label sits
    /// ABOVE the segmented control unconditionally (never fits beside it in
    /// DE/FR) — the control itself (`DSSlidingSegmented`) stays structurally
    /// stable, outside any data-dependent switch/if, so its identity survives
    /// selection changes and the thumb slides instead of remounting
    /// pre-selected (the V2-CARD-FOLD trap). Only the note row below switches.
    private var monitoringCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.settingsIntervalLabel)
                    .font(.system(size: 14))
                    .lineSpacing(14 * 0.3)
                    .foregroundStyle(DS.inkSoft)

                DSSlidingSegmented(
                    options: AppSettings.allowedIntervals,
                    selection: $settings.fastIntervalSeconds,
                    size: .settingsInterval
                ) { s in L.settingsIntervalOption(s) }
                .accessibilityLabel(L.settingsIntervalLabel)
            }

            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(DS.line).frame(height: 1)
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(intervalNoteTone)
                        .frame(width: 6, height: 6)
                    Text(intervalNoteText)
                        .font(.system(size: 11.5))
                        .lineSpacing(11.5 * 0.4)
                        .foregroundStyle(DS.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 11)
                .animation(
                    reduceMotion ? .easeInOut(duration: DSMotion.reduceMotionFallback) : DSMotion.expand,
                    value: settings.fastIntervalSeconds
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(DS.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.settingsProcessLimitLabel)
                        .font(.system(size: 14))
                        .lineSpacing(14 * 0.3)
                        .foregroundStyle(DS.inkSoft)

                    DSSlidingSegmented(
                        options: AppSettings.allowedProcessLimits,
                        selection: $settings.processListLimit,
                        size: .settingsInterval
                    ) { n in L.settingsProcessLimitOption(n) }
                    .accessibilityLabel(L.settingsProcessLimitLabel)

                    HStack {
                        Spacer(minLength: 0)
                        RainbowCapsuleButton(
                            title: L.settingsProcessLimitApply,
                            busy: model.processesRefreshing,
                            size: .card
                        ) {
                            model.refreshProcessesNow()
                        }
                        .accessibilityLabel(L.settingsProcessLimitApply)
                    }
                }
                .padding(.top, 11)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface()
    }

    /// Per-value note under the interval control (SW:96-99, SW:234-255): text
    /// switches at the 1 / 2-3 / 5-10 s bands; the leading dot's tint follows
    /// the same band (amber at 1 s — the responsive-but-loaded end, green
    /// otherwise), per the prototype (`Settings Window.dc.html:288`) rather
    /// than a flat accent tint.
    private var intervalNoteText: String {
        switch settings.fastIntervalSeconds {
        case ...1: return L.settingsIntervalNoteFast
        case 2...3: return L.settingsIntervalNoteBalanced
        default: return L.settingsIntervalNoteEconomy
        }
    }
    private var intervalNoteTone: Color {
        settings.fastIntervalSeconds <= 1 ? DS.amber : DS.green
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
