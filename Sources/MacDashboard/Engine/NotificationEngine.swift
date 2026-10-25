// Engine/NotificationEngine.swift
// REDESIGN-NOTIFY: which attention kinds may notify (six user-facing categories), and the edge detector that turns a
// stream of committed assessments into "kind appeared" events. Pure; covered by Tests/MacDashboardTests/NotificationEngineTests.
import Foundation

/// The six Settings toggles (handoff 11-settings.md :26). `rawValue` is part of the UserDefaults key — never rename a case.
enum NotifyCategory: String, CaseIterable, Hashable {
    case protection, disk, battery, backup, updates, crashes

    /// Default switch position: all on except crashes (handoff: «New crash reports (default off)»).
    var defaultOn: Bool { self != .crashes }
    /// UserDefaults key: notifyProtection, notifyDisk, notifyBattery, notifyBackup, notifyUpdates, notifyCrashes.
    var defaultsKey: String { "notify" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// Page a click on this category's notification opens (R5).
    var page: Page {
        switch self {
        case .protection, .updates, .crashes: return .security
        case .disk: return .storage
        case .battery: return .battery
        case .backup: return .backups
        }
    }
    /// Kinds without a category are never notified (D8).
    static func category(for kind: AttentionKind) -> NotifyCategory? {
        switch kind {
        case .fileVaultOff, .gatekeeperOff, .sipOff, .firewallOff: return .protection
        case .diskFull, .diskFullSoon: return .disk
        case .batteryCapacity, .batteryCondition: return .battery
        case .timeMachine, .claudeBackup: return .backup
        case .updates, .brewOutdated: return .updates
        case .crashes: return .crashes
        case .swapHigh, .smartErrors, .smartWear, .wakeHolders: return nil
        }
    }
    static let allOnByDefault: Set<NotifyCategory> = Set(allCases.filter(\.defaultOn))
}

/// One edge-triggered detector over committed assessments. Value type: the model owns one; tests make their own.
/// `update` must be called only with assessments the model considers complete (R2); the first call seeds and reports nothing.
struct NotificationEdgeDetector: Equatable {
    private(set) var seeded = false
    private(set) var present: Set<AttentionKind> = []

    /// Records `items`' kinds as present and returns the items (one per kind, first wins, in `items` order) whose kind
    /// was absent before AND whose category is in `enabled`. Kinds of disabled categories still become present (a later
    /// switch-on does not back-fire). Kinds with no category are recorded but never returned.
    mutating func update(items: [AttentionItem], enabled: Set<NotifyCategory>) -> [AttentionItem] {
        var next = Set<AttentionKind>()
        var fresh: [AttentionItem] = []
        for item in items where !next.contains(item.kind) {
            next.insert(item.kind)
            guard seeded, !present.contains(item.kind),
                  let cat = NotifyCategory.category(for: item.kind), enabled.contains(cat) else { continue }
            fresh.append(item)
        }
        present = next
        seeded = true
        return fresh
    }
}
