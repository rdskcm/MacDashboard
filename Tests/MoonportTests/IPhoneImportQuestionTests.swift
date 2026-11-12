// Tests/MoonportTests/IPhoneImportQuestionTests.swift
// FIX-LEFTOVERS (IPHONE-MIXUP): the «another phone» question cannot hold an import once its card has left the screen.
// A real continuation through `confirmIdentity`; temp paths only, the transport is never started.
import Foundation
import Testing
@testable import Moonport

@Suite struct IPhoneImportQuestionTests {
    /// k17 (5030 mAh) and k15 (4395 mAh): an archive with 4395 mAh imported into k17 is a mismatch.
    @MainActor
    private func makeModel() -> (IPhoneModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-question-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = IPhoneModel(store: IPhoneStore(url: dir.appendingPathComponent("iphones.json")),
                            archiveRoot: dir.appendingPathComponent("archive"),
                            oldDefaultArchiveRoot: dir.appendingPathComponent("archive-old"),
                            logTypeStore: IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName)))
        func rec(_ id: String, _ marketing: String, _ design: Int) -> IPhoneDeviceRecord {
            IPhoneDeviceRecord(id: id, name: "iPhone", marketingName: marketing, productType: nil, enclosureColor: nil,
                               osVersion: nil, lastSeen: Date(timeIntervalSince1970: 1_700_000_000),
                               battery: [BatteryPoint(day: "2026-10-12", cycles: 1, healthPercent: 98, maxCapacityMAh: nil,
                                                      designCapacityMAh: design, source: "live")],
                               keptArchives: [])
        }
        m.devices = [rec("k17", "iPhone 17 Pro Max", 5030), rec("k15", "iPhone 15 Pro Max", 4395)]
        return (m, dir)
    }

    /// Starts `confirmIdentity` for k17 with k15's capacity and waits (at most 1 s) until the question is published.
    @MainActor
    private func ask(_ m: IPhoneModel) async throws -> Task<Bool, Never> {
        let answer = Task { await m.confirmIdentity(deviceKey: "k17", archiveName: "a.tar.gz", archiveMAh: [4395]) }
        var waited = 0
        while m.importQuestion["k17"] == nil, waited < 200 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waited += 1
        }
        try #require(m.importQuestion["k17"] != nil)
        return answer
    }

    @Test @MainActor func leavingTheCardCancelsTheQuestion() async throws {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.setRequestPanelShown(deviceKey: "k17", true)
        let answer = try await ask(m)
        m.setRequestPanelShown(deviceKey: "k17", false)
        #expect(m.importQuestion["k17"] == nil)
        #expect(await answer.value == false)
    }

    @Test @MainActor func detachLeavesTheQuestionOpen() async throws {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = IPhoneHandle(raw: 3)
        m.connected["k17"] = h
        m.setRequestPanelShown(deviceKey: "k17", true)
        let answer = try await ask(m)
        m.handle(.detached(h))
        #expect(m.importQuestion["k17"] != nil, "the archive is already local: a cable bump must not cancel the import")
        m.answerImportQuestion(deviceKey: "k17", proceed: true)
        #expect(await answer.value == true)
    }

    @Test @MainActor func questionAskedWhileTheCardIsAwayWaitsForIt() async throws {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.setRequestPanelShown(deviceKey: "k17", false)   // the card left before the question: nothing to answer
        let answer = try await ask(m)
        m.setRequestPanelShown(deviceKey: "k17", true)
        #expect(m.importQuestion["k17"] != nil, "showing the card does not answer")
        m.answerImportQuestion(deviceKey: "k17", proceed: true)
        #expect(await answer.value == true)
    }
}
