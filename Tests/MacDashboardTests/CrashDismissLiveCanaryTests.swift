// Tests/MacDashboardTests/CrashDismissLiveCanaryTests.swift
// CRASH-REPORT-DISMISS opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanaryCrashReports
// Lists the real DiagnosticReports folders through the production scan and checks what delete relies on. Reads only — deletes nothing.
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct CrashDismissLiveCanaryTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryCrashReports() async {
            let dirs = [CrashDismiss.userDirectory, CrashDismiss.systemDirectory]
            var found = Set<String>()
            for d in dirs {
                let exists = FileManager.default.fileExists(atPath: d)
                let resolved = CrashDismiss.resolvedDirectory(d)
                print("liveCanary dir \(d) exists=\(exists) resolved=\(resolved)")
                #expect(resolved == d, "a DiagnosticReports folder is a symlink — delete would refuse every report")
                let out = await runCommand("/usr/bin/find", [d, "-maxdepth", "1", "-type", "f", "(", "-name", "*.ips", "-o", "-name", "*.crash", "-o", "-name", "*.panic", ")", "-mmin", "-10080"], timeout: 15)
                let listed = Set(out.stdout.split(separator: "\n").map(String.init))
                found.formUnion(listed)
                print("liveCanary find \(d): \(listed.count) report files in the last 7 days")
            }
            let scan = ReportCollector().collectCrashScan()
            print("liveCanary visible=\(scan.visible.count) hidden=\(scan.hidden.count)")
            for g in scan.visible + scan.hidden {
                print("liveCanary group \(g.process) count=\(g.count) panic=\(g.isPanic) paths=\(g.reportPaths.count)")
                #expect(Set(CrashDismiss.names(of: g)).count == g.count)
                for p in g.reportPaths {
                    let kind = CrashDismiss.fileKind(atPath: p)
                    let inFind = found.contains(p)
                    print("liveCanary   \(p) kind=\(kind) inFind=\(inFind)")
                    #expect(CrashDismiss.isReportPath(p, directories: dirs))
                    #expect(kind == .regular)
                    #expect(inFind, "scanned report not listed by find — a symlink, or a file at the 7-day edge (re-run)")
                }
            }
        }
    }
}
