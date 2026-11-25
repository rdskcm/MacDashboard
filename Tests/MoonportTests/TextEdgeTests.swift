// Tests/MoonportTests/TextEdgeTests.swift
// ARCH-TEXT-EDGE: the two functions that derive text from a committed report take the language as a
// parameter, so their output does not depend on the process-wide UI language. Each test flips the global
// (hence SerialTests) and compares the output under both settings.
import Foundation
import Testing
@testable import Moonport

extension SerialTests {
    @MainActor struct TextEdgeTests {
        @Test func assessIgnoresGlobalLanguage() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }

            var report = FullReport()
            report.security = SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true)

            L10nStore.shared.language = .en
            let a1 = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            L10nStore.shared.language = .ru
            let a2 = Assess.assess(report: report, live: LiveSnapshot(), language: .ru)
            #expect(a1 == a2)
            #expect(a1.items.first { $0.kind == .fileVaultOff }?.label == StringsRU().attnLabelFileVaultOff)

            // Paths that reach the BackupLog / WakeHolders / memory formatters: a failed Claude backup attempt, a wake
            // holder, a swap-heavy memory state and a big Downloads folder.
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var rich = report
            rich.homeDirs = [DirSize(path: "/Users/x/Downloads", bytes: 11 * GIB)]
            var live = LiveSnapshot()
            live.disk = DiskInfo(size: 256 * GIB, avail: 25 * GIB, dataUsed: nil, sysUsed: nil)
            let attempt = ClaudeBackupAttempt(at: now - 3600, result: .failed(exit: 23, reason: .filesChanged), mount: nil)
            let holders = [WakeHolder(owner: "caffeinate", requester: "claude", ageSeconds: 4902)]
            func richAssess(_ global: AppLanguage, _ language: AppLanguage) -> Assessment {
                L10nStore.shared.language = global
                return Assess.assess(report: rich, live: live, language: language, wakeHolders: holders,
                                     claudeBackup: .lastSuccess(now - 4 * 86_400), claudeAttempt: attempt,
                                     backupStaleHours: 48, now: now)
            }
            for language in AppLanguage.allCases {
                let onEN = richAssess(.en, language), onRU = richAssess(.ru, language)
                #expect(onEN == onRU, "Assess (\(language)): output does not depend on the global language")
                #expect(onEN.items.contains { $0.kind == .claudeBackup } && onEN.items.contains { $0.kind == .wakeHolders },
                        "Assess (\(language)): the rich input reaches the backup and wake-holder branches")
            }
        }

        @Test func renderIgnoresGlobalLanguage() {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }

            // One input, built once: its task lines are text made at the edge (HomeModel.tasks) and are part of the input.
            var input = fullInput()
            input.thermal = .serious
            input.claudeAttempt = ClaudeBackupAttempt(at: input.now, result: .failed(exit: 23, reason: .filesChanged), mount: nil)
            input.details = ReportDetails(report: FullReport(), live: LiveSnapshot())

            for language in AppLanguage.allCases {
                L10nStore.shared.language = .ru
                let underRU = ReportWriter.render(input, language: language)
                L10nStore.shared.language = .en
                let underEN = ReportWriter.render(input, language: language)
                #expect(underRU == underEN, "ReportWriter.render (\(language)): output does not depend on the global language")
            }
            #expect(ReportWriter.render(input, language: .en) != ReportWriter.render(input, language: .ru),
                    "the two languages differ, so the comparison above is not vacuous")
        }

        /// Isolated model over a temp data folder; the closure removes the defaults and the folder.
        private func makeModel() throws -> (AppModel, URL, () -> Void) {
            let (d, name) = makeIsolatedDefaults()
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MoonportTests.textedge.\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let m = AppModel(dataDirectory: dir, settings: AppSettings(defaults: d), time: VirtualClock().source)
            return (m, dir, { removeIsolatedDefaults(d, name); try? FileManager.default.removeItem(at: dir) })
        }

        /// R4: a language switch re-derives the assessment from the data already collected and starts no pass.
        @Test @MainActor func relocalizeDoesNotCollect() throws {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            let (m, dir, cleanup) = try makeModel()
            defer { cleanup() }
            m.report.security = SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true)
            let security = m.report.security

            L10nStore.shared.language = .ru
            m.relocalize()
            #expect(m.assessment.items.first { $0.kind == .fileVaultOff }?.label == StringsRU().attnLabelFileVaultOff)
            L10nStore.shared.language = .en
            m.relocalize()
            #expect(m.assessment.items.first { $0.kind == .fileVaultOff }?.label == StringsEN().attnLabelFileVaultOff)
            #expect(m.isCollectingReport == false)
            #expect(m.report.security == security)
            #expect(m.reportText == nil)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            #expect(!files.contains { $0.lowercased().contains("report") }, "no report file written: \(files)")
        }

        /// With a report text on screen, a language switch re-renders it and writes it to the report file.
        @Test @MainActor func relocalizeReRendersAndWritesTheReport() throws {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            let (m, _, cleanup) = try makeModel()
            defer { cleanup() }
            m.report.security = SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true)
            m.reportText = "stale"
            L10nStore.shared.language = .en
            m.relocalize()
            let en = m.reportText
            L10nStore.shared.language = .ru
            m.relocalize()
            let ru = m.reportText
            #expect(en != "stale")
            #expect(ru != en)
            #expect(ru == (try? String(contentsOf: m.reportURL, encoding: .utf8)))
            #expect(m.isCollectingReport == false)
        }

        /// A pass in flight owns the report text: a language switch leaves it and writes nothing.
        @Test @MainActor func relocalizeSkipsTheReportTextDuringAPass() throws {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            let (m, _, cleanup) = try makeModel()
            defer { m.isCollectingReport = false; cleanup() }
            m.reportText = "stale"
            m.isCollectingReport = true
            L10nStore.shared.language = saved == .en ? .ru : .en
            m.relocalize()
            #expect(m.reportText == "stale")
            #expect(!FileManager.default.fileExists(atPath: m.reportURL.path))
        }

        /// Fixture mode: relocalize() returns at once, nothing is re-derived or written.
        @Test @MainActor func relocalizeIsANoOpInFixtureMode() throws {
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            let (m, _, cleanup) = try makeModel()
            defer { cleanup() }
            m.report.security = SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true)
            m.reportText = "stale"
            let before = m.assessment
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            L10nStore.shared.language = saved == .en ? .ru : .en
            m.relocalize()
            #expect(m.assessment == before)
            #expect(m.reportText == "stale")
            #expect(!FileManager.default.fileExists(atPath: m.reportURL.path))
        }
    }
}
