// Tests/MoonportTests/DevProbeTests.swift
// Opt-in developer probes (CHECKS-SWIFT-TESTING): skipped unless their environment variable is set.
// sysdiagnoseProbe ports runSysdiagnoseProbe from Checks/SysdiagnoseExtractorChecks.swift.
// liveCanary ports runLiveCanary from Checks/LiveCanary.swift.
import Foundation
import Testing
@testable import Moonport

private func sysdiagnoseProbe(_ archivePath: String) async -> Int32 {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("MacDashboardChecks-sysdiag-probe-\(UUID().uuidString)")
    let x = dir.appendingPathComponent("x")
    do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: x, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    } catch { return 2 }
    let start = Date()
    let r = await SysdiagnoseExtractor.extract(archive: URL(fileURLWithPath: archivePath), into: x,
                                               memberList: dir.appendingPathComponent("members.txt"))
    let secs = Date().timeIntervalSince(start)
    var code: Int32 = 1
    switch r {
    case .success(let n):
        let names = sdFiles(under: x).map { ($0 as NSString).lastPathComponent }
        let csv = names.filter { $0.hasPrefix("BDC_Daily_") && $0.hasSuffix(".csv") }.count
        let ips = names.filter { $0.hasSuffix(".ips") }.count
        let onceRel = sdFiles(under: x).filter {
            let n = ($0 as NSString).lastPathComponent
            return n.hasPrefix("BDC_Once_") && n.hasSuffix(".csv")
        }
        var design = Set<Int>()
        var texts: [String] = []
        for rel in onceRel {
            if let t = try? String(contentsOf: x.appendingPathComponent(rel), encoding: .utf8) {
                design.formUnion(IPhoneData.parseBDCOnceDesignCapacities(t))
                texts.append(t)
            }
        }
        // IPHONE-MANUFACTURE-DATE (R11): the decoded week and the calendar month of its ISO Monday.
        let mfg = IPhoneData.batteryManufacture(fromBDCOnce: texts)
        var mfgText = "mfg=none"
        var mfgMonth = "none"
        if let m = mfg {
            var c = DateComponents()
            c.weekOfYear = m.week
            c.yearForWeekOfYear = m.year
            c.weekday = 2
            let cal = Calendar(identifier: .iso8601)
            if let d = cal.date(from: c) {
                mfgMonth = String(format: "%04d-%02d", cal.component(.year, from: d), cal.component(.month, from: d))
            }
            mfgText = String(format: "mfg=%04d-W%02d", m.year, m.week)
        }
        let designText = design.isEmpty ? "none" : design.sorted().map(String.init).joined(separator: ",")
        print("sysdiag probe: result=success selected=\(n) csv=\(csv) once=\(onceRel.count) designMAh=\(designText) ips=\(ips) \(mfgText) mfgMonth=\(mfgMonth) seconds=\(String(format: "%.1f", secs)) tmp=\(dir.path)")
        code = 0
        if let want = ProcessInfo.processInfo.environment["MACDASH_SYSDIAGNOSE_MFG_MONTH"], want != mfgMonth { code = 3 }
    case .failure(let e):
        print("sysdiag probe: result=failure error=\(String(describing: e)) tmp=\(dir.path)")
    }
    try? fm.removeItem(at: dir)
    return code
}

extension SerialTests {
    struct DevProbeTests {
        /// Opt-in: MACDASH_SYSDIAGNOSE_ARCHIVE=<archive.tar.gz> swift test --filter sysdiagnoseProbe
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_SYSDIAGNOSE_ARCHIVE"] != nil))
        func sysdiagnoseProbe() async {
            let path = ProcessInfo.processInfo.environment["MACDASH_SYSDIAGNOSE_ARCHIVE"] ?? ""
            let code = await MoonportTests.sysdiagnoseProbe(path)
            #expect(code == 0, "sysdiagnose probe exit code \(code) (3 = manufacture month differs from MACDASH_SYSDIAGNOSE_MFG_MONTH, 2 = temp dir, 1 = extraction failed)")
        }

        /// Opt-in: MACDASH_LIVE=1 swift test --filter liveVolumeUsage
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveVolumeUsage() async {
            let usage = LiveCollector.volumeUsage()
            let size = (try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity
            print("liveVolumeUsage: sysUsed=\(String(describing: usage.sys)) dataUsedRaw=\(String(describing: usage.data)) size=\(String(describing: size))")
            #expect(usage.sys != nil && usage.data != nil, "both volume used values are non-nil")
            if let sys = usage.sys, let data = usage.data, let size {
                #expect(sys < data && data < Int64(size), "sysUsed < dataUsedRaw < size")
            }
        }

        /// Opt-in: MACDASH_LIVE=1 swift test --filter liveCanary
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanary() async {
            let hasBattery = LiveCollector().collectFast().battery != nil
            var ok = 0, rejected = 0, noOutput = 0, skipped = 0
            for cmd in ParsedCommand.allCases {
                let label = cmd.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0)
                if cmd.requiresBattery && !hasBattery {
                    print("SKIP      \(label)no battery on this Mac"); skipped += 1; continue
                }
                let executable: String? = cmd == .smartctl ? ReportCollector.findSmartctl() : nil
                if cmd == .smartctl && executable == nil {
                    print("NO-OUTPUT \(label)smartctl not installed"); noOutput += 1; continue
                }
                let outcome = await cmd.run(executable: executable)
                let line = cmd.commandLine(executable: executable)
                guard let text = outcome.nonEmptyText else {
                    print("NO-OUTPUT \(label)\(line) — \(outcome.termination)"); noOutput += 1; continue
                }
                if cmd.parses(text) { print("OK        \(label)\(line)"); ok += 1; continue }
                print("NIL       \(label)\(line)"); rejected += 1
                ParseFailure(cmd, executable: executable, stdout: text)?.excerpt.forEach { print("          | " + $0) }
            }
            print("")
            print("live canary: \(ok) ok, \(rejected) nil, \(noOutput) no output, \(skipped) skipped")
            #expect(rejected == 0, "live canary: \(rejected) parser(s) rejected real command output")
        }
    }
}
