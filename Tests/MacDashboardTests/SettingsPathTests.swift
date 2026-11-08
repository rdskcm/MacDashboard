// Tests/MacDashboardTests/SettingsPathTests.swift
// ARCH-SETTINGS-PATH: every assessment setting re-assesses the model on write, however it is written.
// Models run on an isolated AppSettings and a temp data directory — never the real defaults or App Support.
import Foundation
import SwiftUI
import Testing
@testable import MacDashboard

extension SerialTests {
    @MainActor struct SettingsPathTests {
        /// A model over an isolated settings instance and a fresh temp data directory.
        private func makeModel() -> (AppModel, AppSettings, () -> Void) {
            let (d, name) = makeIsolatedDefaults()
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-settings-path-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let s = AppSettings(defaults: d)
            let m = AppModel(dataDirectory: dir, settings: s)
            return (m, s, { removeIsolatedDefaults(d, name); try? FileManager.default.removeItem(at: dir) })
        }
        private func kinds(_ m: AppModel) -> Set<AttentionKind> { Set(m.assessment.items.map(\.kind)) }

        private let ref = Date(timeIntervalSince1970: 1_800_000_000)

        @Test func lowSpacePercentReassesses() {
            let (m, s, cleanup) = makeModel(); defer { cleanup() }
            m.disk = DiskInfo(size: 100 * GIB, avail: 12 * GIB)
            s.lowSpacePercent = 15
            #expect(m.assessment.items.contains { $0.kind == .diskFullSoon })
            Bindable(s).lowSpacePercent.wrappedValue = 10
            #expect(!m.assessment.items.contains { $0.kind == .diskFullSoon })
        }

        @Test func batteryShowsRawMacReassesses() {
            let (m, s, cleanup) = makeModel(); defer { cleanup() }
            m.report.battery = BatteryInfo(source: nil, charge: nil, state: nil, cycles: 100, condition: "Normal", maxCapacity: 82)
            var d = VisualFixture.batteryDetail; d.healthPercent = 78
            m.applyFixtureBattery(d, block: BlockState(.battery))   // a detail exists, so the flip starts no ioreg read
            s.lowSpacePercent = 15   // first assessment
            #expect(!kinds(m).contains(.batteryCapacity) && m.assessment.battShownPercent == 82, "Apple's 82 % is healthy")
            s.batteryShowsRawMac = true
            #expect(kinds(m).contains(.batteryCapacity) && m.assessment.battShownPercent == 78, "raw 78 % is judged (D5)")
            Bindable(s).batteryShowsRawMac.wrappedValue = false
            #expect(!kinds(m).contains(.batteryCapacity) && m.assessment.battShownPercent == 82)
        }

        @Test func backupStaleDaysReassesses() {
            let (m, s, cleanup) = makeModel(); defer { cleanup() }
            m.fixtureNow = ref
            m.claudeBackup = .lastSuccess(ref.addingTimeInterval(-3 * 86_400))
            s.backupStaleDays = 7
            #expect(!kinds(m).contains(.claudeBackup))
            s.backupStaleDays = 2
            #expect(kinds(m).contains(.claudeBackup))
        }

        @Test func wakeHolderIgnoreReassesses() {
            let (m, s, cleanup) = makeModel(); defer { cleanup() }
            let h = WakeHolder(owner: "caffeinate", requester: "Terminal", ageSeconds: 5400)
            m.applyFixtureWakeHolders(user: [h], system: [], sampled: true)
            s.lowSpacePercent = 10   // first assessment
            #expect(kinds(m).contains(.wakeHolders))
            s.setWakeHolderIgnored(h.key, ignored: true)
            #expect(!kinds(m).contains(.wakeHolders))
            s.setWakeHolderIgnored(h.key, ignored: false)
            #expect(kinds(m).contains(.wakeHolders))
        }

        @Test func claudeLogPathRereadsThenReassesses() async throws {
            let (m, s, cleanup) = makeModel(); defer { cleanup() }
            m.fixtureNow = ref
            m.claudeBackup = .lastSuccess(ref.addingTimeInterval(-3 * 86_400))
            s.backupStaleDays = 1
            #expect(kinds(m).contains(.claudeBackup))
            s.claudeLogPath = m.reportURL.deletingLastPathComponent().appendingPathComponent("missing.log").path
            for _ in 0..<60 {
                if m.claudeBackup == nil, !kinds(m).contains(.claudeBackup) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(m.claudeBackup == nil)
            #expect(!kinds(m).contains(.claudeBackup))
        }
    }
}
