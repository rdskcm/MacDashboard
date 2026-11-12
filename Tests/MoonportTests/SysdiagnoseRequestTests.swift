// Tests/MoonportTests/SysdiagnoseRequestTests.swift
// DEVICE-ARCHIVE-CLEANUP Stage A: the pure request/ownership rules (Engine/SysdiagnoseRequest.swift).
import Foundation
import Testing
@testable import Moonport

@Suite struct SysdiagnoseRequestTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let req = SysdiagnoseRequest(id: UUID(), requestedAt: Date(timeIntervalSince1970: 1_800_000_000), baseline: ["old.tar.gz"])

    func name(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy.MM.dd_HH-mm-ss"
        return "sysdiagnose_\(f.string(from: d))+0000_iPhone-OS_iPhone_23E254.tar.gz"
    }
    func e(_ n: String, _ size: Int64 = 100) -> IPhoneAFCEntry {
        IPhoneAFCEntry(path: SysdiagnoseDir.remotePath(n), isDirectory: false, size: size, modified: nil)
    }
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    func inProg(_ d: Date, ext: String = ".tmp") -> String { "IN_PROGRESS_" + name(d).replacingOccurrences(of: ".tar.gz", with: "") + ext }

    @Test func startDateParses() {
        let d = SysdiagnoseDir.startDate(ofArchive: "sysdiagnose_2026.10.09_01-34-55+0300_iPhone-OS_iPhone_23E254.tar.gz")
        #expect(d == ISO8601DateFormatter().date(from: "2026-10-08T22:34:55Z"))
        let m = SysdiagnoseDir.startDate(ofArchive: "sysdiagnose_2026.10.09_01-34-55-0700_iPhone-OS_iPhone_23E254.tar.gz")
        #expect(m == ISO8601DateFormatter().date(from: "2026-10-09T08:34:55Z"))
        for bad in ["IN_PROGRESS_sysdiagnose_2026.10.09_01-34-55+0300_iPhone-OS_iPhone_23E254.tar.gz", "sysdiagnose_2026.10.09.tar.gz",
                    "sysdiagnose_2026.13.40_99-99-99+0300_x.tar.gz", "sysdiagnose_2026.10.09_01-34-55+0300_x.tmp", ""] {
            #expect(SysdiagnoseDir.startDate(ofArchive: bad) == nil, "\(bad)")
        }
    }

    @Test func finalNameOfInProgress() {
        #expect(SysdiagnoseDir.finalName(ofInProgress: "IN_PROGRESS_sysdiagnose_X.tar.gz") == "sysdiagnose_X.tar.gz")
        #expect(SysdiagnoseDir.finalName(ofInProgress: "IN_PROGRESS_sysdiagnose_X.tmp") == "sysdiagnose_X.tar.gz")
        #expect(SysdiagnoseDir.finalName(ofInProgress: "sysdiagnose_X.tar.gz") == nil)
        #expect(SysdiagnoseDir.finalName(ofInProgress: "IN_PROGRESS_") == nil)
    }

    @Test func ownPathGuard() {
        let n = name(t0)
        #expect(SysdiagnoseDir.isOwnArchivePath(SysdiagnoseDir.remotePath(n)))
        for bad in ["/DiagnosticLogs/sysdiagnose/sub/" + n, "/Retired/" + n, "/DiagnosticLogs/sysdiagnose/../x/" + n,
                    SysdiagnoseDir.remotePath("IN_PROGRESS_" + n), SysdiagnoseDir.remotePath("notes.tar.gz"),
                    SysdiagnoseDir.path, SysdiagnoseDir.path + "/"] {
            #expect(!SysdiagnoseDir.isOwnArchivePath(bad), "\(bad)")
        }
    }

    @Test func waitingThenExpired() {
        #expect(SysdiagnoseDir.step(req, listing: [], now: at(60)).1 == .waiting)
        #expect(SysdiagnoseDir.step(req, listing: [], now: at(15 * 60 + 1)).1 == .expired)
        #expect(SysdiagnoseDir.step(req, listing: [e("old.tar.gz")], now: at(60)).1 == .waiting)
    }

    @Test func inProgressThenReady() {
        let (r1, p1) = SysdiagnoseDir.step(req, listing: [e(inProg(at(20)))], now: at(30))
        #expect(p1 == .creating && r1.creatingSince == at(30))
        let (r2, p2) = SysdiagnoseDir.step(r1, listing: [e(name(at(20)), 500)], now: at(40))
        #expect(p2 == .creating)
        let (_, p3) = SysdiagnoseDir.step(r2, listing: [e(name(at(20)), 500)], now: at(50))
        guard case .ready(let own) = p3 else { Issue.record("expected ready, got \(p3)"); return }
        #expect(own.name == name(at(20)) && own.size == 500 && own.requestID == req.id)
        let (_, p3b) = SysdiagnoseDir.step(r2, listing: [e(name(at(20)), 600)], now: at(50))
        #expect(p3b == .creating)
    }

    @Test func notReadyWhileInProgressSiblingRemains() {
        let list = [e(name(at(20)), 500), e(inProg(at(20), ext: ".tar.gz"))]
        let (r1, p1) = SysdiagnoseDir.step(req, listing: list, now: at(30))
        let (_, p2) = SysdiagnoseDir.step(r1, listing: list, now: at(40))
        #expect(p1 == .creating && p2 == .creating)
    }

    @Test func zeroSizeNeverReady() {
        let (r1, p1) = SysdiagnoseDir.step(req, listing: [e(name(at(20)), 0)], now: at(30))
        let (_, p2) = SysdiagnoseDir.step(r1, listing: [e(name(at(20)), 0)], now: at(40))
        #expect(p1 == .creating && p2 == .creating)
    }

    @Test func ambiguousTwoNewArchives() {
        #expect(SysdiagnoseDir.step(req, listing: [e(name(at(20))), e(name(at(100)))], now: at(200)).1 == .ambiguous)
        #expect(SysdiagnoseDir.step(req, listing: [e(name(at(20))), e(inProg(at(100)))], now: at(200)).1 == .ambiguous)
        #expect(SysdiagnoseDir.step(req, listing: [e(inProg(at(20))), e(inProg(at(100)))], now: at(200)).1 == .ambiguous)
    }

    @Test func outOfWindowIgnored() {
        #expect(SysdiagnoseDir.step(req, listing: [e(name(at(-300)))], now: at(60)).1 == .waiting)
        #expect(SysdiagnoseDir.step(req, listing: [e(name(at(16 * 60)))], now: at(60)).1 == .waiting)
        #expect(SysdiagnoseDir.step(req, listing: [e(name(at(-50)))], now: at(60)).1 == .creating)
    }

    @Test func baselineIgnored() {
        var r = req
        r.baseline.insert(name(at(20)))
        let (r1, p1) = SysdiagnoseDir.step(r, listing: [e(name(at(20)), 100)], now: at(30))
        let (_, p2) = SysdiagnoseDir.step(r1, listing: [e(name(at(20)), 200)], now: at(40))
        #expect(p1 == .waiting && p2 == .waiting)
    }

    @Test func finishTimeout() {
        var r = req
        r.creatingSince = at(30)
        let only = [e(inProg(at(20)))]
        #expect(SysdiagnoseDir.step(r, listing: only, now: at(30 * 60 + 1)).1 == .timedOut)
        #expect(SysdiagnoseDir.step(r, listing: [], now: at(30 * 60 - 1)).1 == .creating)
        #expect(SysdiagnoseDir.step(r, listing: [], now: at(30 * 60 + 1)).1 == .timedOut)
        let (r1, p1) = SysdiagnoseDir.step(req, listing: [e(name(at(20)), 700)], now: at(30 * 60 + 1))
        #expect(p1 == .creating)
        guard case .ready = SysdiagnoseDir.step(r1, listing: [e(name(at(20)), 700)], now: at(30 * 60 + 11)).1 else {
            Issue.record("a finished candidate must not time out"); return
        }
    }

    @Test func reconnectAfterFinish() {
        for first in [12 * 60.0, 45 * 60.0] {
            let list = [e(name(at(20)), 900)]
            let (r1, p1) = SysdiagnoseDir.step(req, listing: list, now: at(first))
            #expect(p1 == .creating)
            guard case .ready = SysdiagnoseDir.step(r1, listing: list, now: at(first + 10)).1 else {
                Issue.record("expected ready after the second poll (first sight at \(first))"); continue
            }
        }
    }

    @Test func pollGate() {
        for p in [SysdiagnoseRequestPhase.waiting, .creating] {
            #expect(SysdiagnoseDir.shouldPoll(phase: p, panelShown: true, windowPaused: false, connected: true))
            #expect(!SysdiagnoseDir.shouldPoll(phase: p, panelShown: false, windowPaused: false, connected: true))
            #expect(!SysdiagnoseDir.shouldPoll(phase: p, panelShown: true, windowPaused: true, connected: true))
            #expect(!SysdiagnoseDir.shouldPoll(phase: p, panelShown: true, windowPaused: false, connected: false))
        }
        let own = OwnSysdiagnose(name: name(t0), size: 1, requestID: UUID(), requestedAt: t0)
        for p: SysdiagnoseRequestPhase? in [.preparing, .ready(own), .ambiguous, .expired, .timedOut, .failed, nil] {
            #expect(!SysdiagnoseDir.shouldPoll(phase: p, panelShown: true, windowPaused: false, connected: true))
        }
    }

    @Test func fullParseRule() {
        #expect(SysdiagnoseDir.importAllowsDelete(ImportSummary(batteryPoints: 1, skippedRows: 3, logFiles: 0, keptPath: nil), identityAsked: false))
        #expect(!SysdiagnoseDir.importAllowsDelete(ImportSummary(batteryPoints: 0, skippedRows: 0, logFiles: 5, keptPath: nil), identityAsked: false))
        #expect(!SysdiagnoseDir.importAllowsDelete(ImportSummary(batteryPoints: 4, skippedRows: 0, logFiles: 0, keptPath: nil), identityAsked: true))
    }

    @Test func cleanupStrings() {
        let all: [PhoneCleanup] = [.deleting, .deleted, .keptBySetting, .keptIncomplete, .notConnected, .alreadyGone, .changed, .unavailable, .failed(7)]
        for s in [StringsEN() as AppStrings, StringsRU()] {
            let texts = all.map { s.iphonePhoneCleanup($0) }
            #expect(texts.allSatisfy { !$0.isEmpty } && Set(texts).count == all.count)
            #expect(s.iphonePhoneCleanup(.failed(7)).contains("7"))
        }
    }

    // MARK: Decision 13: «On the iPhone» watches the folder

    @Test func listWatchGate() {
        #expect(SysdiagnoseDir.shouldWatchList(panelShown: true, windowPaused: false, connected: true, importing: false))
        #expect(!SysdiagnoseDir.shouldWatchList(panelShown: false, windowPaused: false, connected: true, importing: false))
        #expect(!SysdiagnoseDir.shouldWatchList(panelShown: true, windowPaused: true, connected: true, importing: false))
        #expect(!SysdiagnoseDir.shouldWatchList(panelShown: true, windowPaused: false, connected: false, importing: false))
        #expect(!SysdiagnoseDir.shouldWatchList(panelShown: true, windowPaused: false, connected: true, importing: true))
    }

    @Test func finishedArchiveComparison() {
        func e(_ name: String, _ size: Int64) -> IPhoneAFCEntry {
            IPhoneAFCEntry(path: SysdiagnoseDir.path + "/" + name, isDirectory: false, size: size, modified: nil)
        }
        let a = e("sysdiagnose_a.tar.gz", 100), b = e("sysdiagnose_b.tar.gz", 200)
        let base = SysdiagnoseDir.finishedArchives([a])
        #expect(base == SysdiagnoseDir.finishedArchives([a]), "same list: no difference")
        #expect(SysdiagnoseDir.finishedArchives([a, b]) != base, "new final archive")
        #expect(SysdiagnoseDir.finishedArchives([]) != base, "removed archive")
        #expect(SysdiagnoseDir.finishedArchives([a, e("IN_PROGRESS_sysdiagnose_c.tar.gz", 5)]) == base, "in progress ignored")
        #expect(SysdiagnoseDir.finishedArchives([e("sysdiagnose_a.tar.gz", 150)]) != base, "size change")
        #expect(SysdiagnoseDir.finishedArchives([a, e("sub/x.tar.gz", 7)]) == base, "nested path ignored")
    }
}
