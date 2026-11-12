// Tests/MoonportTests/IPhoneModelPollTests.swift
// DEVICE-ARCHIVE-CLEANUP Stage B: the request poll loop does not exist without a request, a connected phone and a
// shown panel (`no-unseen-work`). The full decision table is `SysdiagnoseRequestTests.pollGate`. The default transport
// (`.shared`) is never started here, so no phone job runs. Temp paths only.
import Foundation
import Testing
@testable import Moonport

@Suite struct IPhoneModelPollTests {
    @MainActor
    private func makeModel() -> (IPhoneModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-poll-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = IPhoneModel(store: IPhoneStore(url: dir.appendingPathComponent("iphones.json")),
                            archiveRoot: dir.appendingPathComponent("archive"),
                            oldDefaultArchiveRoot: dir.appendingPathComponent("archive-old"),
                            logTypeStore: IPhoneLogTypeStore(url: dir.appendingPathComponent(IPhoneLogTypeStore.fileName)))
        return (m, dir)
    }

    @Test @MainActor func pollStopsWhenHidden() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!m.isPolling(deviceKey: "k"))
        m.setRequestPanelShown(deviceKey: "k", true)
        #expect(!m.isPolling(deviceKey: "k"), "a shown panel alone starts nothing")
        m.setPaused(false)
        #expect(!m.isPolling(deviceKey: "k"), "an active window alone starts nothing")
        m.cancelSysdiagnoseRequest(deviceKey: "k")
        #expect(!m.isPolling(deviceKey: "k"))
        m.requestSysdiagnose(deviceKey: "k")
        #expect(m.sysdiagnoseRequest["k"] == nil, "no connected handle: no request")
        #expect(!m.isPolling(deviceKey: "k"))
    }

    /// Decision 13: with no request open, a connected phone and a shown panel start the list watch; a hidden panel, a
    /// paused window or a running import stop it. `logs` stays nil, so the tick lists nothing and no phone job runs.
    @Test @MainActor func listWatchFollowsGate() {
        let (m, dir) = makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        m.connected["k"] = IPhoneHandle(raw: 1)
        m.setRequestPanelShown(deviceKey: "k", true)
        #expect(m.isPolling(deviceKey: "k"), "no request, connected, shown: list mode")
        m.importing["k"] = .extracting
        m.setRequestPanelShown(deviceKey: "k", true)
        #expect(!m.isPolling(deviceKey: "k"), "stops during an import")
        m.importing["k"] = nil
        m.setRequestPanelShown(deviceKey: "k", true)
        #expect(m.isPolling(deviceKey: "k"), "returns after it")
        m.setPaused(true)
        #expect(!m.isPolling(deviceKey: "k"), "stops while the window is paused")
        m.setPaused(false)
        #expect(m.isPolling(deviceKey: "k"))
        m.setRequestPanelShown(deviceKey: "k", false)
        #expect(!m.isPolling(deviceKey: "k"))
    }
}
