// Tests/MacDashboardTests/CrashDismissTests.swift
// CRASH-REPORT-DISMISS: report paths per group, the hidden/visible split, the hidden list rules and the injected delete.
// Every delete runs on temp folders with fake trash and privilege calls — never real reports, the Trash or sudo.
import Foundation
import Testing
@testable import MacDashboard

private let now: Date = Date(timeIntervalSince1970: 1_800_000_000)
private let recent = now.addingTimeInterval(-3600)

private func listing(_ dir: String, _ names: [String]) -> ReportCollector.CrashDirectoryListing {
    (directory: dir, files: names.map { (name: $0, mtime: recent) })
}

private func group(_ process: String, _ paths: [String], count: Int? = nil, panic: Bool = false) -> CrashGroup {
    CrashGroup(process: process, count: count ?? paths.count, isPanic: panic, directory: "/d", reportPaths: paths)
}

private final class Recorder: @unchecked Sendable {
    var trashed: [URL] = []
    var commands: [String] = []
}

private struct Fixture {
    let root: URL
    var user: String { root.appendingPathComponent("user").path }
    var system: String { root.appendingPathComponent("system").path }

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("crash-dismiss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: root.appendingPathComponent("user").path, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root.appendingPathComponent("system").path, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func make(_ dir: String, _ name: String) -> String {
        let p = dir + "/" + name
        FileManager.default.createFile(atPath: p, contents: Data("x".utf8))
        return p
    }

    func run(_ paths: [String], userDirectory: String? = nil, rec: Recorder,
             outcome: PrivilegedRunner.Outcome = .success, trashFails: Set<String> = []) -> CrashDeleteResult {
        CrashDismiss.delete(
            paths: paths,
            userDirectory: userDirectory ?? user, systemDirectory: system,
            trash: { url in
                if trashFails.contains(url.lastPathComponent) {
                    throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "no trash"])
                }
                rec.trashed.append(url)
                try FileManager.default.removeItem(at: url)
            },
            privileged: { cmd in
                rec.commands.append(cmd)
                if outcome == .success {
                    for p in paths where (p as NSString).deletingLastPathComponent == system { try? FileManager.default.removeItem(atPath: p) }
                }
                return outcome
            })
    }
}

extension SerialTests {
    struct CrashDismissTests {
        // 1
        @Test func reportPathsIncludeEveryCopy() {
            let a14 = "a-2026-01-14-101010.ips", a13 = "a-2026-01-13-101010.ips"
            let groups = ReportCollector.crashGroups(
                byDirectory: [listing("/U", [a14, a13]), listing("/S", [a14])], now: now)
            #expect(groups.count == 1)
            #expect(groups[0].count == 2)
            #expect(groups[0].reportPaths.sorted() == ["/U/\(a14)", "/U/\(a13)", "/S/\(a14)"].sorted())
            #expect(groups[0].directory == "/U")
        }

        // 2
        @Test func scanSplitsHiddenByFileName() {
            let a1 = "a-2026-01-14-101010.ips", a2 = "a-2026-01-13-101010.ips"
            let byDir = [listing("/U", [a1, a2])]
            let s = ReportCollector.crashScan(byDirectory: byDir, now: now, hidden: [a1])
            #expect(s.visible.map(\.process) == ["a"] && s.visible[0].count == 1)
            #expect(s.hidden.map(\.process) == ["a"] && s.hidden[0].count == 1)
            #expect(s.visible[0].reportPaths == ["/U/\(a2)"] && s.hidden[0].reportPaths == ["/U/\(a1)"])

            let panic = "Kernel-2026-01-14-101010.panic"
            let p = ReportCollector.crashScan(byDirectory: [listing("/S", [panic])], now: now, hidden: [panic])
            #expect(!p.visible.contains { ReportCollector.crashRaisesAttention($0) })
            #expect(p.hidden.count == 1 && p.hidden[0].isPanic)
            let q = ReportCollector.crashScan(byDirectory: [listing("/S", [panic])], now: now, hidden: ["other.panic"])
            #expect(q.visible.count == 1 && q.hidden.isEmpty)
        }

        // 3
        @Test func scanCapAppliesToVisibleOnly() {
            let names = (1...16).map { String(format: "p%02d-2026-01-14-101010.ips", $0) }
            let s = ReportCollector.crashScan(byDirectory: [listing("/U", names)], now: now, hidden: [names[0]])
            #expect(s.visible.count == 15)
            #expect(s.visible.contains { $0.process == "p16" })
            #expect(s.hidden.count == 1 && s.hidden[0].process == "p01")
        }

        // 4
        @Test func hidingAndPruning() {
            let g = group("a", ["/U/a1.ips", "/S/a1.ips", "/U/a2.ips"])
            let once = CrashDismiss.hiding(g, in: [], now: now)
            #expect(once.map(\.name) == ["a1.ips", "a2.ips"] && once.allSatisfy { $0.hiddenAt == now })
            #expect(CrashDismiss.hiding(g, in: once, now: now) == once)

            let day: TimeInterval = 24 * 60 * 60
            let entries = [HiddenCrashReport(name: "old", hiddenAt: now.addingTimeInterval(-7 * day)),
                           HiddenCrashReport(name: "future", hiddenAt: now.addingTimeInterval(60)),
                           HiddenCrashReport(name: "ok", hiddenAt: now.addingTimeInterval(-6 * day))]
            #expect(CrashDismiss.pruned(entries, now: now).map(\.name) == ["ok"])

            let mixed = once + [HiddenCrashReport(name: "b1.ips", hiddenAt: now)]
            #expect(CrashDismiss.unhiding(g, in: mixed, now: now).map(\.name) == ["b1.ips"])
        }

        // 5
        @Test func codec() {
            let e = [HiddenCrashReport(name: "a.ips", hiddenAt: Date(timeIntervalSince1970: 1_700_000_000)),
                     HiddenCrashReport(name: "b.ips", hiddenAt: Date(timeIntervalSince1970: 1_700_000_100))]
            #expect(CrashDismiss.decode(CrashDismiss.encode(e)) == e)
            #expect(CrashDismiss.decode(nil) == [])
            #expect(CrashDismiss.decode(Data("x".utf8)) == [])
            let dup = [e[0], HiddenCrashReport(name: "a.ips", hiddenAt: Date(timeIntervalSince1970: 1_700_000_500)), e[1]]
            #expect(CrashDismiss.decode(CrashDismiss.encode(dup)) == e)
        }

        // 6
        @Test func isReportPathRules() {
            let dirs = ["/D/u", "/D/s"]
            for ok in ["/D/u/x.ips", "/D/s/k.panic", "/D/u/y.crash"] {
                #expect(CrashDismiss.isReportPath(ok, directories: dirs), "\(ok)")
            }
            for bad in ["/D/other/x.ips", "/D/u/../x.ips", "/D/u//x.ips", "/D/u/sub/x.ips", "/D/u/x.ips/",
                        "/D/u/.x.ips", "/D/u/x.txt", "/D/u/x.IPS", "x.ips", ""] {
                #expect(!CrashDismiss.isReportPath(bad, directories: dirs), "\(bad)")
            }
        }

        // 7
        @Test func fileKinds() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let file = fx.make(fx.user, "r.ips")
            let link = fx.user + "/link.ips"
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: file)
            #expect(CrashDismiss.fileKind(atPath: file) == .regular)
            #expect(CrashDismiss.fileKind(atPath: link) == .other)
            #expect(CrashDismiss.fileKind(atPath: fx.user + "/missing.ips") == .missing)
            #expect(CrashDismiss.fileKind(atPath: fx.user) == .other)
        }

        // 8
        @Test func deleteMixedSuccess() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let u1 = fx.make(fx.user, "a1.ips"), u2 = fx.make(fx.user, "a2.ips"), s1 = fx.make(fx.system, "a1.ips")
            let rec = Recorder()
            let r = fx.run([u1, u2, s1], rec: rec)
            #expect(rec.commands == [PrivilegedRunner.removeCommand(paths: [s1])])
            #expect(Set(rec.trashed.map(\.path)) == [u1, u2])
            #expect(r.removed.count == 3 && r.failure == nil)
        }

        // 9
        @Test func privilegedFailureLeavesEverything() throws {
            let cases: [(PrivilegedRunner.Outcome, CrashDeleteFailure)] = [
                (.cancelled, .cancelled), (.timedOut, .timedOut), (.failed("boom"), .error("boom"))]
            for (outcome, expected) in cases {
                let fx = try Fixture(); defer { fx.remove() }
                let paths = [fx.make(fx.user, "a1.ips"), fx.make(fx.user, "a2.ips"), fx.make(fx.system, "a1.ips")]
                let rec = Recorder()
                let r = fx.run(paths, rec: rec, outcome: outcome)
                #expect(r.failure == expected)
                #expect(rec.trashed.isEmpty)
                #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0) })
            }
        }

        // 10
        @Test func userOnlyNeverAsksForPrivileges() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let u1 = fx.make(fx.user, "a1.ips")
            let rec = Recorder()
            let r = fx.run([u1], rec: rec)
            #expect(rec.commands.isEmpty && rec.trashed.count == 1 && r.failure == nil)
        }

        // 11
        @Test func symlinkedFileIsRefused() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let outside = fx.make(fx.root.path, "outside.ips")
            let link = fx.user + "/link.ips"
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: outside)
            let good = fx.make(fx.user, "a1.ips")
            let rec = Recorder()
            let r = fx.run([good, link], rec: rec)
            #expect(r.failure == .refused("link.ips") && r.removed.isEmpty)
            #expect(rec.trashed.isEmpty && rec.commands.isEmpty)
            #expect(FileManager.default.fileExists(atPath: outside) && FileManager.default.fileExists(atPath: good))
        }

        // 12
        @Test func symlinkedFolderIsRefused() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let linkDir = fx.root.appendingPathComponent("userlink").path
            try FileManager.default.createSymbolicLink(atPath: linkDir, withDestinationPath: fx.user)
            let real = fx.make(fx.user, "a1.ips")
            let rec = Recorder()
            let r = CrashDismiss.delete(
                paths: [linkDir + "/a1.ips"], userDirectory: linkDir, systemDirectory: fx.system,
                trash: { rec.trashed.append($0) },
                privileged: { rec.commands.append($0); return .success })
            #expect(r.failure == .refused("a1.ips"))
            #expect(rec.trashed.isEmpty && rec.commands.isEmpty && FileManager.default.fileExists(atPath: real))
        }

        // 13
        @Test func otherFolderIsRefused() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let elsewhere = fx.root.appendingPathComponent("elsewhere").path
            try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
            let p = fx.make(elsewhere, "x.ips")
            let rec = Recorder()
            let r = fx.run([p], rec: rec)
            #expect(r.failure == .refused("x.ips"))
            #expect(rec.trashed.isEmpty && rec.commands.isEmpty && FileManager.default.fileExists(atPath: p))
        }

        // 14
        @Test func missingPathCountsAsRemoved() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let gone = fx.user + "/gone.ips"
            let present = fx.make(fx.user, "a1.ips")
            let rec = Recorder()
            let r = fx.run([gone, present], rec: rec)
            #expect(Set(r.removed) == [gone, present] && r.failure == nil)
            #expect(rec.trashed.map(\.path) == [present] && rec.commands.isEmpty)
        }

        // 15
        @Test func trashErrorDoesNotStopTheRest() throws {
            let fx = try Fixture(); defer { fx.remove() }
            let u1 = fx.make(fx.user, "a1.ips"), u2 = fx.make(fx.user, "a2.ips")
            let rec = Recorder()
            let r = fx.run([u1, u2], rec: rec, trashFails: ["a1.ips"])
            #expect(r.failure == .error("no trash"))
            #expect(rec.trashed.map(\.path) == [u2] && r.removed == [u2])
        }
    }
}

/// CRASH-REPORT-DISMISS fix wave 2: the crash-scan ordering rule (findings C1, C3, R3). No real folders.
struct CrashScanSequencerTests {
    typealias Landing = CrashScanSequencer.Landing

    // Mutating calls are made outside `#expect` (the macro may wrap its operands in closures).

    // T1 (C1): a Refresh requested inside the delete window never writes last, in either landing order.
    @Test func deleteWindowRefreshNeverWritesLast() {
        var a = CrashScanSequencer()
        let r = a.request(completing: nil, collecting: false)!          // Refresh, files not yet deleted
        let d = a.request(completing: .idle, collecting: false)!        // the delete returned
        let ad = a.landed(ticket: d, collecting: false)
        let ar = a.landed(ticket: r, collecting: false)                 // Refresh lands last
        #expect(ad == Landing(write: true, outcome: .idle))
        #expect(ar == Landing(write: false, outcome: nil))

        var b = CrashScanSequencer()
        let r2 = b.request(completing: nil, collecting: false)!
        let d2 = b.request(completing: .failed(.cancelled), collecting: false)!
        let br = b.landed(ticket: r2, collecting: false)                // Refresh lands first
        let bd = b.landed(ticket: d2, collecting: false)
        #expect(br == Landing(write: false, outcome: nil))
        #expect(bd == Landing(write: true, outcome: .failed(.cancelled)))
    }

    // T2 (R3): a Refresh after an action delivers the action's outcome once; it never replaces it with idle.
    @Test func actionOutcomeIsDeliveredOnce() {
        var s = CrashScanSequencer()
        let d = s.request(completing: .failed(.error("x")), collecting: false)!
        let r = s.request(completing: nil, collecting: false)!
        let ld = s.landed(ticket: d, collecting: false)
        let lr = s.landed(ticket: r, collecting: false)
        let r2 = s.request(completing: nil, collecting: false)!
        let lr2 = s.landed(ticket: r2, collecting: false)
        #expect(ld == Landing(write: false, outcome: nil))
        #expect(lr == Landing(write: true, outcome: .failed(.error("x"))))
        #expect(lr2 == Landing(write: true, outcome: nil))
    }

    // T3 (C3, D10): a request or a landing during a pass is parked; the pass end (completed or cancelled — the
    // sequencer has no cancel input) asks for exactly one rerun, whose landing delivers the outcome.
    @Test func parkedDuringPassRerunsAtPassEnd() {
        var s = CrashScanSequencer()
        let parked = s.request(completing: .idle, collecting: true)
        let end1 = s.passEnded(), end1Again = s.passEnded()
        let rerun = s.request(completing: nil, collecting: false)!
        let l1 = s.landed(ticket: rerun, collecting: false)
        #expect(parked == nil && end1 && !end1Again)
        #expect(l1 == Landing(write: true, outcome: .idle))

        let inFlight = s.request(completing: .failed(.timedOut), collecting: false)!
        let lParked = s.landed(ticket: inFlight, collecting: true)      // a pass began meanwhile
        let end2 = s.passEnded()
        let rerun2 = s.request(completing: nil, collecting: false)!
        let l2 = s.landed(ticket: rerun2, collecting: false)
        let end3 = s.passEnded()
        #expect(lParked == Landing(write: false, outcome: nil))
        #expect(end2 && !end3)
        #expect(l2 == Landing(write: true, outcome: .failed(.timedOut)))
    }

    // T4: three overlapping requests, every landing order → exactly one write, by the newest, one outcome.
    @Test func onlyTheNewestOfOverlappingScansWrites() {
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            var s = CrashScanSequencer()
            let tickets = [s.request(completing: .idle, collecting: false)!,
                           s.request(completing: nil, collecting: false)!,
                           s.request(completing: nil, collecting: false)!]
            var writers: [Int] = [], outcomes: [CrashActionState] = []
            for i in order {
                let l = s.landed(ticket: tickets[i], collecting: false)
                if l.write { writers.append(i) }
                if let o = l.outcome { outcomes.append(o) }
            }
            #expect(writers == [2], "order \(order)")
            #expect(outcomes == [.idle], "order \(order)")
        }
    }

    // T5 (C1 with real listings): a temp folder is listed by a stale Refresh scan, the file is deleted, the delete
    // requests its scan; the Refresh lands last; the written list must not contain the deleted report.
    @Test func deletedReportNeverReappears() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("crash-seq-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let victim = root.appendingPathComponent("Victim-2026-10-24-120000.ips").path
        FileManager.default.createFile(atPath: victim, contents: Data("x".utf8))
        FileManager.default.createFile(atPath: root.appendingPathComponent("Other-2026-10-24-120001.ips").path,
                                       contents: Data("x".utf8))
        func scan() -> CrashScan {   // lists the folder at call time, like `collectCrashScan`
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            return ReportCollector.crashScan(byDirectory: [(directory: root.path, files: names.map { (name: $0, mtime: recent) })],
                                             now: now, hidden: [])
        }
        var s = CrashScanSequencer()
        var written: CrashScan? = nil
        let r = s.request(completing: nil, collecting: false)!   // Refresh inside the delete window
        let stale = scan()
        try FileManager.default.removeItem(atPath: victim)       // the delete ends
        let d = s.request(completing: .idle, collecting: false)!
        let fresh = scan()
        if s.landed(ticket: d, collecting: false).write { written = fresh }
        if s.landed(ticket: r, collecting: false).write { written = stale }   // the Refresh lands last
        #expect(stale.visible.contains { $0.process == "Victim" })            // the race really happened
        #expect(written?.visible.map(\.process) == ["Other"])
    }
}
