// Tests/MacDashboardTests/NotificationEngineTests.swift
// REDESIGN-NOTIFY: edge detector, category table, defaults and settings resolver. No process-wide state.
import Foundation
import Testing
@testable import MacDashboard

struct NotificationEngineTests {
    private func item(_ k: AttentionKind, detail: String = "") -> AttentionItem {
        AttentionItem(kind: k, sev: .warn, label: k.rawValue, detail: detail, fullText: "t", verb: "")
    }
    private let all = Set(NotifyCategory.allCases)
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = NotificationEdgeDetector.renotifyCooldown

    @Test func seedIsSilent() {
        var d = NotificationEdgeDetector()
        #expect(d.update(items: [item(.firewallOff), item(.diskFull)], enabled: all, now: t0).isEmpty)
        #expect(d.present == [.firewallOff, .diskFull])
        #expect(d.seeded)
    }

    @Test func appearsOnce() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [item(.diskFull)], enabled: all, now: t0)
        let r = d.update(items: [item(.diskFull), item(.firewallOff)], enabled: all, now: t0)
        #expect(r.map(\.kind) == [.firewallOff])
        #expect(d.update(items: [item(.diskFull), item(.firewallOff)], enabled: all, now: t0).isEmpty)
    }

    @Test func clearAndReturn() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [item(.diskFull)], enabled: all, now: t0)
        _ = d.update(items: [item(.diskFull), item(.firewallOff)], enabled: all, now: t0)
        #expect(d.update(items: [item(.diskFull)], enabled: all, now: t0 + day + 1).isEmpty)
        #expect(d.update(items: [item(.diskFull), item(.firewallOff)], enabled: all, now: t0 + day + 2).map(\.kind) == [.firewallOff])
    }

    @Test func detailChangeDoesNotRefire() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [item(.diskFull, detail: "92 %")], enabled: all, now: t0)
        #expect(d.update(items: [item(.diskFull, detail: "93 %")], enabled: all, now: t0).isEmpty)
    }

    @Test func disabledCategoryRecordedNotReturned() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        #expect(d.update(items: [item(.firewallOff)], enabled: all.subtracting([.protection]), now: t0).isEmpty)
        #expect(d.update(items: [item(.firewallOff)], enabled: all, now: t0).isEmpty)
    }

    @Test func cooldownBlocksQuickReturn() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        #expect(d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + 1).map(\.kind) == [.diskFullSoon])
        #expect(d.update(items: [], enabled: all, now: t0 + 2).isEmpty)
        #expect(d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + 3).isEmpty, "inside the cooldown")
        #expect(d.update(items: [], enabled: all, now: t0 + 4).isEmpty)
        #expect(d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + day + 3).map(\.kind) == [.diskFullSoon])
    }

    @Test func cooldownBoundaryIsStrict() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        _ = d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + 1)
        _ = d.update(items: [], enabled: all, now: t0 + 2)
        #expect(d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + 1 + day).map(\.kind) == [.diskFullSoon], "exactly 24 h later")
    }

    @Test func clockMovedBackDoesNotSuppress() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        #expect(d.update(items: [item(.diskFull)], enabled: all, now: t0).map(\.kind) == [.diskFull])
        #expect(d.update(items: [], enabled: all, now: t0 + 1).isEmpty)
        #expect(d.update(items: [item(.diskFull)], enabled: all, now: t0 - 3600).map(\.kind) == [.diskFull], "negative interval is not a cooldown")
    }

    @Test func diskFamilyStepDown() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        #expect(d.update(items: [item(.diskFull)], enabled: all, now: t0 + 1).map(\.kind) == [.diskFull])
        #expect(d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + 2).isEmpty, "step down never notifies")
        #expect(d.update(items: [item(.diskFull)], enabled: all, now: t0 + 3).isEmpty, "own cooldown")
        #expect(d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + 4).isEmpty)
        #expect(d.update(items: [item(.diskFull)], enabled: all, now: t0 + 5).isEmpty)
    }

    @Test func diskFamilyStepUp() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        #expect(d.update(items: [item(.diskFullSoon)], enabled: all, now: t0 + 1).map(\.kind) == [.diskFullSoon])
        #expect(d.update(items: [item(.diskFull)], enabled: all, now: t0 + 2).map(\.kind) == [.diskFull])
    }

    @Test func disabledCategoryDoesNotSetCooldown() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        #expect(d.update(items: [item(.firewallOff)], enabled: all.subtracting([.protection]), now: t0 + 1).isEmpty)
        #expect(d.lastNotified.isEmpty)
        #expect(d.update(items: [], enabled: all, now: t0 + 2).isEmpty)
        #expect(d.update(items: [item(.firewallOff)], enabled: all, now: t0 + 3).map(\.kind) == [.firewallOff])
    }

    @Test func uncategorisedNeverReturned() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        #expect(d.update(items: [item(.swapHigh), item(.smartErrors), item(.smartWear), item(.wakeHolders)], enabled: all, now: t0).isEmpty)
    }

    @Test func onePerKind() {
        var d = NotificationEdgeDetector()
        _ = d.update(items: [], enabled: all, now: t0)
        let r = d.update(items: [item(.smartWear, detail: "a"), item(.diskFull, detail: "x"), item(.diskFull, detail: "y")], enabled: all, now: t0)
        #expect(r.count == 1)
        #expect(r.first?.detail == "x")
    }

    @Test func categoryTable() {
        let expected: [AttentionKind: NotifyCategory?] = [
            .fileVaultOff: .protection, .gatekeeperOff: .protection, .sipOff: .protection, .firewallOff: .protection,
            .diskFull: .disk, .diskFullSoon: .disk,
            .batteryCapacity: .battery, .batteryCondition: .battery,
            .timeMachine: .backup, .timeMachineOverdue: .backup, .claudeBackup: .backup,
            .updates: .updates,
            .crashes: .crashes,
            .swapHigh: nil, .smartErrors: nil, .smartWear: nil, .wakeHolders: nil,
        ]
        #expect(expected.count == AttentionKind.allCases.count)
        for k in AttentionKind.allCases { #expect(NotifyCategory.category(for: k) == expected[k]!, "\(k)") }
    }

    @Test func defaultsAndKeys() {
        #expect(NotifyCategory.allOnByDefault == Set(NotifyCategory.allCases).subtracting([.crashes]))
        let keys = NotifyCategory.allCases.map(\.defaultsKey)
        #expect(keys == ["notifyProtection", "notifyDisk", "notifyBattery", "notifyBackup", "notifyUpdates", "notifyCrashes"])
        #expect(NotifyCategory.protection.page == .security)
        #expect(NotifyCategory.updates.page == .security)
        #expect(NotifyCategory.crashes.page == .security)
        #expect(NotifyCategory.disk.page == .storage)
        #expect(NotifyCategory.battery.page == .battery)
        #expect(NotifyCategory.backup.page == .backups)
    }

    @Test func resolveNotifyEnabled() {
        let name = "test.notify.\(UUID())"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        #expect(AppSettings.resolveNotifyEnabled(in: d) == NotifyCategory.allOnByDefault)
        d.set(true, forKey: "notifyCrashes")
        d.set(false, forKey: "notifyDisk")
        let r = AppSettings.resolveNotifyEnabled(in: d)
        #expect(r.contains(.crashes))
        #expect(!r.contains(.disk))
    }
}
