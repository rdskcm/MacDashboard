// Tests/MacDashboardTests/DevProbeTests.swift
// Opt-in developer probes (CHECKS-SWIFT-TESTING): skipped unless their environment variable is set.
// sysdiagnoseProbe ports runSysdiagnoseProbe from Checks/SysdiagnoseExtractorChecks.swift.
import Foundation
import Testing
@testable import MacDashboard

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
        for rel in onceRel {
            if let t = try? String(contentsOf: x.appendingPathComponent(rel), encoding: .utf8) {
                design.formUnion(IPhoneData.parseBDCOnceDesignCapacities(t))
            }
        }
        let designText = design.isEmpty ? "none" : design.sorted().map(String.init).joined(separator: ",")
        print("sysdiag probe: result=success selected=\(n) csv=\(csv) once=\(onceRel.count) designMAh=\(designText) ips=\(ips) seconds=\(String(format: "%.1f", secs)) tmp=\(dir.path)")
        code = 0
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
            let code = await MacDashboardTests.sysdiagnoseProbe(path)
            #expect(code == 0, "sysdiagnose probe exit code \(code) (2 = temp dir, 1 = extraction failed)")
        }
    }
}
