// Tests/MacDashboardTests/IPhoneCrashLogTests.swift
// IPHONE-CRASHLOG-ACTIONS Stage A: header fields, created time, process fallback, Console eligibility, copy
// folder, save write and strings. Fixtures are read from ipsFixturesRoot; writes go to a temp dir only.
import Foundation
import Testing
@testable import MacDashboard

struct IPhoneCrashLogTests {
    let utc = TimeZone(identifier: "UTC")!
    let msk = TimeZone(secondsFromGMT: 3 * 3600)!

    func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func header(_ name: String) throws -> IPhoneLogHeader {
        let data = try Data(contentsOf: ipsFixturesRoot.appendingPathComponent(name))
        return IPhoneCrashLog.logHeader(fromHeader: data.prefix(4096))
    }

    func tempDir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("md-tests-crashlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func header309() throws {
        let h = try header("ServiceExtension-2026-10-12-044145-synthetic.ips")
        #expect(h.bugType == "309")
        #expect(h.process == "ServiceExtension")
        #expect(h.timestamp == utcDate(2026, 10, 12, 1, 41, 45))
    }

    @Test func header308() throws {
        let h = try header("ExcUserFault_Telegram-2026-10-11-101500-synthetic.ips")
        #expect(h.bugType == "308")
        #expect(h.process == "Telegram")
    }

    @Test func header298() throws {
        let h = try header("JetsamEvent-2026-10-08-231105-synthetic.ips")
        #expect(h.process == nil)
        #expect(h.timestamp == utcDate(2026, 10, 8, 20, 11, 5))
    }

    @Test func header145() throws {
        let h = try header("Photos.diskwrites_resource-2026-10-07-120000-synthetic.ips")
        #expect(h.process == "Photos")
        #expect(h.timestamp == utcDate(2026, 10, 7, 9, 0, 0))
    }

    @Test func headerPlainLog() throws {
        #expect(try header("log-aggregated-2026-10-06-090000-synthetic.log") == IPhoneLogHeader())
    }

    @Test func timestampParsing() {
        let a = IPhoneCrashLog.ipsTimestamp("2026-10-12 04:41:45.00 +0300")
        let b = IPhoneCrashLog.ipsTimestamp("2026-10-12 04:41:45 +0300")
        #expect(a != nil && a == b)
        #expect(IPhoneCrashLog.ipsTimestamp("12.10.2026") == nil)
        #expect(IPhoneCrashLog.ipsTimestamp("") == nil)
    }

    @Test func fileNameStamp() {
        #expect(IPhoneCrashLog.fileNameTimestamp("ServiceExtension-2026-10-12-044145.ips", timeZone: msk)
                == utcDate(2026, 10, 12, 1, 41, 45))
        #expect(IPhoneCrashLog.fileNameTimestamp("JetsamEvent-2026-13-40-990000.ips") == nil)
        #expect(IPhoneCrashLog.fileNameTimestamp("stacks.ips") == nil)
    }

    @Test func processFromName() {
        typealias C = IPhoneCrashLog
        #expect(C.processFromFileName("ExcUserFault_Safari-2026-10-11-101500.ips", category: .exceptionFault) == "Safari")
        #expect(C.processFromFileName("Maps.diskwrites_resource-2026-10-07-120000.ips", category: .diskWrites) == "Maps")
        #expect(C.processFromFileName("Instagram.cpu_resource-2026-10-01-000000.ips", category: .cpuResource) == "Instagram")
        #expect(C.processFromFileName("MiHomeDesktopWidgetExtension-2026-10-12-144255.ips", category: .appCrash)
                == "MiHomeDesktopWidgetExtension")
        #expect(C.processFromFileName("JetsamEvent-2026-10-08-231105.ips", category: .jetsam) == nil)
        #expect(C.processFromFileName("Analytics-Journal-2026-10-01.ips.ca", category: .analytics) == nil)
    }

    @Test func logEntryPrecedence() {
        let path = "/ServiceExtension-2026-10-12-044145.ips"
        let mtime = Date(timeIntervalSince1970: 1000)
        let ts = Date(timeIntervalSince1970: 2000)
        let stamp = IPhoneCrashLog.fileNameTimestamp("ServiceExtension-2026-10-12-044145.ips", timeZone: msk)
        let withTS = IPhoneCrashLog.logEntry(path: path, size: 1, modified: mtime,
                                             header: IPhoneLogHeader(bugType: "309", process: "P", timestamp: ts),
                                             source: .live, timeZone: msk)
        #expect(withTS.created == ts && withTS.process == "P")
        let noTS = IPhoneCrashLog.logEntry(path: path, size: 1, modified: mtime,
                                           header: IPhoneLogHeader(bugType: "309"), source: .live, timeZone: msk)
        #expect(noTS.created == stamp)
        #expect(noTS.process == "ServiceExtension")   // file-name process for an app crash with no header process
        let noStamp = IPhoneCrashLog.logEntry(path: "/stacks.ips", size: 1, modified: mtime,
                                              header: IPhoneLogHeader(bugType: "288"), source: .live, timeZone: msk)
        #expect(noStamp.created == mtime)
        let failed = IPhoneCrashLog.logEntry(path: path, size: 1, modified: mtime, header: nil, source: .live, timeZone: msk)
        #expect(failed.bugType == nil && failed.category == .other && failed.process == nil && failed.created == stamp)
    }

    @Test func consoleEligibility() {
        typealias C = IPhoneCrashLog
        #expect(C.canOpenInConsole(name: "a.ips", size: 1))
        #expect(C.canOpenInConsole(name: "a.ips", size: 32 << 20))
        #expect(!C.canOpenInConsole(name: "a.ips", size: (32 << 20) + 1))
        #expect(!C.canOpenInConsole(name: "a.ips.ca.synced", size: 10))
        #expect(!C.canOpenInConsole(name: "sysdiagnose_x.tar.gz", size: 10))
        #expect(!C.canOpenInConsole(name: "a.ips", size: 0))
    }

    @Test func room() {
        let size: Int64 = 5000
        let gib: Int64 = 1 << 30
        #expect(IPhoneCrashLog.hasRoom(available: nil, size: size))
        #expect(IPhoneCrashLog.hasRoom(available: size + gib, size: size))
        #expect(!IPhoneCrashLog.hasRoom(available: size + gib - 1, size: size))
    }

    @Test func copyDirAndSweep() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let copy = try #require(IPhoneCrashLog.makeCopyDir(in: dir))
        #expect(copy.lastPathComponent.hasPrefix(IPhoneCrashLog.tempPrefix))
        #expect(IPhoneCrashLog.tempPrefix == "md-crashlog-")
        let perms = (try fm.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int) ?? -1
        #expect(perms == 0o700)
        try fm.createDirectory(at: dir.appendingPathComponent("MacDashboard-sysdiag-x"), withIntermediateDirectories: false)
        try Data("x".utf8).write(to: dir.appendingPathComponent("other.txt"))
        IPhoneData.removeStaleImportRoots(in: dir, prefix: IPhoneCrashLog.tempPrefix)
        #expect(!fm.fileExists(atPath: copy.path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("MacDashboard-sysdiag-x").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("other.txt").path))
        IPhoneData.removeStaleImportRoots(in: dir)
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("MacDashboard-sysdiag-x").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("other.txt").path))
    }

    @Test func writeSaved() throws {
        let dir = try tempDir()
        let fm = FileManager.default
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.appendingPathComponent("ro").path)
            try? fm.removeItem(at: dir)
        }
        let src = dir.appendingPathComponent("src.ips")
        try Data("new bytes".utf8).write(to: src)
        let dest = dir.appendingPathComponent("dest.ips")
        #expect(IPhoneCrashLog.writeSaved(from: src, to: dest))
        #expect(try Data(contentsOf: dest) == Data("new bytes".utf8))
        #expect(try fm.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasSuffix(".part") })
        try Data("old".utf8).write(to: dest)
        #expect(IPhoneCrashLog.writeSaved(from: src, to: dest))
        #expect(try Data(contentsOf: dest) == Data("new bytes".utf8))
        let ro = dir.appendingPathComponent("ro")
        try fm.createDirectory(at: ro, withIntermediateDirectories: false)
        let existing = ro.appendingPathComponent("keep.ips")
        try Data("keep".utf8).write(to: existing)
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ro.path)
        #expect(!IPhoneCrashLog.writeSaved(from: src, to: existing))
        #expect(!IPhoneCrashLog.writeSaved(from: src, to: ro.appendingPathComponent("fresh.ips")))
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    }

    @Test func strings() {
        func check(_ s: some IPhoneLogsStrings) {
            for c in LogCategory.allCases { #expect(!s.iphoneLogsType(c, bugType: nil).isEmpty) }
            #expect(s.iphoneLogsType(.otherReport, bugType: "999").hasSuffix("(999)"))
            #expect(s.iphoneLogsType(.pending, bugType: nil) == s.iphoneLogsCategory(.pending))
            let errs = IPhoneLogActionError.allCases.map { s.iphoneLogsActionError($0) }
            #expect(errs.allSatisfy { !$0.isEmpty })
            #expect(Set(errs).count == errs.count)
        }
        check(StringsEN())
        check(StringsRU())
    }

    @Test func pendingEntry() {
        let e = IPhoneCrashLog.pendingEntry(path: "/ServiceExtension-2026-10-12-044145.ips", size: 5,
                                            modified: nil, timeZone: msk)
        #expect(e.category == .pending && e.process == nil)
        #expect(e.created == utcDate(2026, 10, 12, 1, 41, 45))
        let d = Date(timeIntervalSince1970: 77)
        #expect(IPhoneCrashLog.pendingEntry(path: "/stacks.ips", size: 5, modified: d).created == d)
    }
}
