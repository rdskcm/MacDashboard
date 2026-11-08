// Tests/MacDashboardTests/TMDestinationLiveCanaryTests.swift
// REDESIGN-INFO-RESTORE opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanaryTMDestinationKind
// Reads only: tmutil destinationinfo (-X through ReportCollector, and the plain-text form).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    @MainActor struct TMDestinationLiveCanaryTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryTMDestinationKind() async {
            let dest = await ReportCollector().collectTMDestInfo()
            let plain = await CommandRunner.run("/usr/bin/tmutil", ["destinationinfo"], timeout: 15).text ?? ""
            func field(_ key: String) -> String? {
                plain.split(separator: "\n").first { $0.hasPrefix(key) }
                    .flatMap { l in l.range(of: ": ").map { String(l[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } }
            }
            let plainKind = field("Kind"), plainQuota = field("Quota")
            #expect(dest != nil, "tmutil destinationinfo -X could not be read")
            guard case .some(.some(let d)) = dest else {
                print("liveCanary no Time Machine destination configured, plain Kind=\(plainKind ?? "nil")")
                #expect(plainKind == nil)
                return
            }
            let saved = L10nStore.shared.language
            defer { L10nStore.shared.language = saved }
            L10nStore.shared.language = .en
            let facts = BackupsPageModel.destinationFacts(d)
            print("liveCanary kind parsed=\(d.kind ?? "nil") plain=\(plainKind ?? "nil") quotaBytes=\(String(describing: d.quotaBytes)) plainQuota=\(plainQuota ?? "nil") facts=\(facts.map { "\($0.label): \($0.text)" })")
            #expect(d.kind == plainKind)
            #expect(d.kind == "Local" || d.kind == "Network")
            #expect(facts.first?.label == "Type" && facts.first?.text != d.kind)   // translated, not passed through
            #expect((d.quotaBytes != nil) == (plainQuota != nil))
        }
    }
}
