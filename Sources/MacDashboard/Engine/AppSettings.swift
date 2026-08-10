// Engine/AppSettings.swift
// Non-language app settings. Foundation + Observation only — compiled into Checks.
import Foundation
import Observation

/// User-tunable settings backed by UserDefaults. Mirrors L10nStore's pattern.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let fastIntervalKey = "fastIntervalSeconds"
    /// Allowed fast-loop polling intervals, seconds. 2 = historical default.
    static let allowedIntervals = [1, 2, 3, 5, 10]
    static let processLimitKey = "processListLimit"
    /// Rows shown in the process list. 12 = the pre-V2-SETTINGS-PROCLIMIT hardcoded value.
    static let allowedProcessLimits = [5, 10, 15]

    // Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
    #if AI_ENABLED
    static let aiProviderKey = "aiProvider"
    static let aiBaseURLKey = "aiBaseURL"
    static let aiModelIdKey = "aiModelId"
    #endif

    /// Sleep interval of DashboardModel's fast task (native CPU/RAM/disk/battery
    /// gauges). Read by the loop on every iteration, so a change applies on the
    /// next tick without restarting the task.
    var fastIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(fastIntervalSeconds, forKey: Self.fastIntervalKey) }
    }

    /// Length of the CPU-/memory-sorted process tables. Read by LiveCollector on
    /// every slow sample, so a change applies on the next tick without a restart.
    var processListLimit: Int {
        didSet { UserDefaults.standard.set(processListLimit, forKey: Self.processLimitKey) }
    }

    #if AI_ENABLED
    /// AI provider selection (Block AI, Wave 2). The API key itself is NEVER
    /// stored here / in UserDefaults — only in Keychain via `KeychainStore`.
    var aiProvider: AIProvider {
        didSet { UserDefaults.standard.set(aiProvider.rawValue, forKey: Self.aiProviderKey) }
    }

    var aiBaseURL: String {
        didSet { UserDefaults.standard.set(aiBaseURL, forKey: Self.aiBaseURLKey) }
    }

    var aiModelId: String {
        didSet { UserDefaults.standard.set(aiModelId, forKey: Self.aiModelIdKey) }
    }

    var aiConfig: AIProviderConfig { AIProviderConfig(provider: aiProvider, baseURL: aiBaseURL, model: aiModelId) }
    #endif

    private init() {
        let raw = UserDefaults.standard.integer(forKey: Self.fastIntervalKey) // 0 if unset
        fastIntervalSeconds = Self.allowedIntervals.contains(raw) ? raw : 2

        let rawLimit = UserDefaults.standard.integer(forKey: Self.processLimitKey) // 0 if unset
        processListLimit = Self.allowedProcessLimits.contains(rawLimit) ? rawLimit : 10

        #if AI_ENABLED
        let providerRaw = UserDefaults.standard.string(forKey: Self.aiProviderKey)
        aiProvider = providerRaw.flatMap(AIProvider.init(rawValue:)) ?? .anthropic
        aiBaseURL = UserDefaults.standard.string(forKey: Self.aiBaseURLKey) ?? ""
        aiModelId = UserDefaults.standard.string(forKey: Self.aiModelIdKey) ?? "claude-opus-4-8"
        #endif
    }
}
