// Tests/MacDashboardTests/SysdiagnoseExtractorTests.swift
// Port of Checks/SysdiagnoseExtractorChecks.swift (CHECKS-SWIFT-TESTING).
// IPHONE-IMPORT-IOS27: pure selection/pattern/error-mapping checks and end-to-end extraction
// over archives synthesized at run time in a fresh temp dir. Never touches App Support.
import Foundation
import Testing
@testable import MacDashboard

func sdFiles(under dir: URL) -> Set<String> {
    var out = Set<String>()
    guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return out }
    let base = dir.resolvingSymlinksInPath().path
    for case let u as URL in en {
        guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
        let full = u.resolvingSymlinksInPath().path
        out.insert(String(full.dropFirst(base.count + 1)))
    }
    return out
}

private func sdMakeArchive(root: URL, case name: String, files: [String], base: String, item: String) async -> URL {
    let fm = FileManager.default
    let caseDir = root.appendingPathComponent(name)
    let src = caseDir.appendingPathComponent("src")
    for f in files {
        let u = src.appendingPathComponent(f)
        try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("x\n".utf8).write(to: u)
    }
    let archive = caseDir.appendingPathComponent("a.tar.gz")
    let cwd = base.isEmpty ? src.path : src.path + "/" + base
    let o = await CommandRunner.run("/usr/bin/tar", ["-czf", archive.path, "-C", cwd, item], timeout: 30,
                                    environment: CommandRunner.defaultEnvironment.merging(["COPYFILE_DISABLE": "1"]) { $1 })
    #expect(o.termination == .exited(0), "sysdiag: build archive \(name)")
    return archive
}

private func sdExtractDir(_ root: URL, _ name: String) -> URL {
    let x = root.appendingPathComponent(name).appendingPathComponent("x")
    try? FileManager.default.createDirectory(at: x, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return x
}

extension SerialTests {
    struct SysdiagnoseExtractorTests {
        @Test func sysdiagnoseExtractor() async {
            typealias X = SysdiagnoseExtractor
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("MacDashboardChecks-sysdiag-\(UUID().uuidString)")
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }

            // isWanted
            let bdc = "sysdiagnose_X/logs/BatteryBDC/BDC_Daily_version3.3_2026-09-16_21:25:49.csv"
            #expect(X.isWanted(bdc), "sysdiag: isWanted full BDC path")
            #expect(X.isWanted("./logs/BatteryBDC/BDC_Daily_a.csv"), "sysdiag: isWanted ./ BDC")
            #expect(X.isWanted("logs/BatteryBDC/BDC_Daily_a.csv"), "sysdiag: isWanted no top BDC")
            #expect(!X.isWanted("top/logs/BatteryBDC/BDC_Daily_a.txt"), "sysdiag: isWanted BDC wrong ext")
            #expect(!X.isWanted("top/logs/BatteryBDC/Other_a.csv"), "sysdiag: isWanted BDC wrong prefix")
            #expect(!X.isWanted("top/logs/BatteryBDC/sub/BDC_Daily_a.csv"), "sysdiag: isWanted BDC subfolder")
            #expect(!X.isWanted("top/BatteryBDC/BDC_Daily_a.csv"), "sysdiag: isWanted BDC without logs")
            #expect(X.isWanted("sysdiagnose_X/logs/BatteryBDC/BDC_Once_version3.3_2026-09-16_21:25:58.csv"), "sysdiag: isWanted BDC_Once")
            #expect(!X.isWanted("top/logs/BatteryBDC/BDC_Once_a.txt"), "sysdiag: isWanted BDC_Once wrong ext")
            #expect(!X.isWanted("top/BatteryBDC/BDC_Once_a.csv"), "sysdiag: isWanted BDC_Once without logs")
            #expect(X.isWanted("top/crashes_and_spins/a.ips"), "sysdiag: isWanted crash ips")
            #expect(X.isWanted("top/crashes_and_spins/Retired/b.ips"), "sysdiag: isWanted retired ips")
            #expect(X.isWanted("crashes_and_spins/a.ips"), "sysdiag: isWanted crash ips no top")
            #expect(!X.isWanted("top/crashes_and_spins/Other/c.ips"), "sysdiag: isWanted other subfolder")
            #expect(!X.isWanted("top/other/a.ips"), "sysdiag: isWanted other parent")
            #expect(!X.isWanted("top/crashes_and_spins.ips"), "sysdiag: isWanted file named like folder")
            #expect(!X.isWanted("top/crashes_and_spins/") && !X.isWanted("top/crashes_and_spins/a.ips/"), "sysdiag: isWanted directories")
            #expect(!X.isWanted(""), "sysdiag: isWanted empty")

            // pattern
            #expect(X.pattern(forListed: "top/crashes_and_spins/a-1_b.ips") == "top/crashes_and_spins/a-1_b.ips", "sysdiag: pattern safe chars")
            #expect(X.pattern(forListed: "top/x y.ips") == "top/x?y.ips", "sysdiag: pattern space")
            #expect(X.pattern(forListed: "top/a[1]*.ips") == "top/a?1??.ips", "sysdiag: pattern brackets and star")
            #expect(X.pattern(forListed: "top/a\\\\b.ips") == "top/a?b.ips", "sysdiag: pattern escaped backslash")
            #expect(X.pattern(forListed: "top/\\320\\237x.ips") == "top/??x.ips", "sysdiag: pattern octal escapes")
            #expect(X.pattern(forListed: "top/a\\n.ips") == "top/a?.ips", "sysdiag: pattern char escape")
            #expect(X.pattern(forListed: "top/П.ips") == "top/??.ips", "sysdiag: pattern raw UTF-8")
            #expect(X.pattern(forListed: "./logs/BatteryBDC/BDC_Daily_21:25:49.csv") == "./logs/BatteryBDC/BDC_Daily_21?25?49.csv", "sysdiag: pattern colon and ./")
            #expect(X.pattern(forListed: "-top/crashes_and_spins/a.ips") == "?top/crashes_and_spins/a.ips", "sysdiag: pattern leading dash")
            #expect(X.pattern(forListed: "./-top/a-b.ips") == "./-top/a-b.ips", "sysdiag: pattern inner dash kept")
            #expect(X.memberPatterns(listing: "top/crashes_and_spins/a.ips\r\ntop/crashes_and_spins/b.ips\r\n")
                  == ["top/crashes_and_spins/a.ips", "top/crashes_and_spins/b.ips"], "sysdiag: memberPatterns CRLF")
            #expect(X.memberPatterns(listing: "top/\ntop/logs/BatteryBDC/BDC_Daily_a.csv\ntop/x.txt\ntop/crashes_and_spins/a.ips\ntop/crashes_and_spins/a.ips\n")
                  == ["top/logs/BatteryBDC/BDC_Daily_a.csv", "top/crashes_and_spins/a.ips"], "sysdiag: memberPatterns select and dedupe")
            #expect(X.memberPatterns(listing: "").isEmpty, "sysdiag: memberPatterns empty")
            #expect(X.listArguments(archive: "/t/a.tar.gz") == ["-tzf", "/t/a.tar.gz"], "sysdiag: listArguments")
            #expect(X.extractArguments(archive: "/t/a.tar.gz", into: "/t/x", memberList: "/t/m.txt")
                  == ["-xzf", "/t/a.tar.gz", "-C", "/t/x", "-T", "/t/m.txt"], "sysdiag: extractArguments")

            // importError
            func oc(_ t: CommandOutcome.Termination, _ err: String) -> CommandOutcome {
                CommandOutcome(termination: t, stdout: "", stdoutTruncated: false, stderrHead: err)
            }
            #expect(X.importError(for: oc(.exited(0), "tar: warning\n")) == nil, "sysdiag: importError clean exit")
            #expect(X.importError(for: oc(.cancelled, "")) == .cancelled, "sysdiag: importError cancelled")
            #expect(X.importError(for: oc(.exited(1), "tar: x: Not found in archive\ntar: Error exit delayed from previous errors.\n"))
                  == .tarFailed(.message("tar: x: Not found in archive")), "sysdiag: importError first stderr line")
            #expect(X.importError(for: oc(.exited(1), "\n   \n")) == .tarFailed(.exitCode(1)), "sysdiag: importError blank stderr")
            #expect(X.importError(for: oc(.signaled(9), "")) == .tarFailed(.signal(9)), "sysdiag: importError signal")
            #expect(X.importError(for: oc(.launchFailed(2), "")) == .tarFailed(.launchFailed(2)), "sysdiag: importError launch failed")
            #expect(X.importError(for: oc(.timedOut, "partial\n")) == .tarFailed(.timedOut), "sysdiag: importError timeout beats stderr")
            #expect(X.importError(for: oc(.exited(1), String(repeating: "a", count: 500)))
                  == .tarFailed(.message(String(repeating: "a", count: 200))), "sysdiag: importError caps at 200")

            // strings
            #expect(StringsRU().iphoneImportErrorDetail(.tarFailed(.message("tar: boom"))) == "tar: boom", "sysdiag: RU detail message verbatim")
            #expect(StringsRU().iphoneImportErrorDetail(.copyFailed) == nil && StringsRU().iphoneImportErrorDetail(.cancelled) == nil,
                  "sysdiag: RU detail nil for other errors")
            #expect(StringsRU().iphoneImportErrorDetail(.tarFailed(.timedOut)) == "tar не завершился вовремя.", "sysdiag: RU detail timeout")
            #expect(StringsEN().iphoneImportErrorDetail(.tarFailed(.exitCode(1))) == "tar exited with code 1.", "sysdiag: EN detail exit code")
            #expect(StringsRU().iphoneImportError(.tarFailed(.timedOut)) == "Не удалось распаковать архив.", "sysdiag: RU sentence unchanged")

            // end-to-end
            func run(_ name: String, _ a: URL) async -> (Result<Int, ImportError>, Set<String>, URL) {
                let x = sdExtractDir(root, name)
                let list = root.appendingPathComponent(name).appendingPathComponent("members.txt")
                let r = await X.extract(archive: a, into: x, memberList: list)
                return (r, sdFiles(under: x), list)
            }
            func eq(_ r: Result<Int, ImportError>, _ n: Int) -> Bool { if case .success(let m) = r { return m == n }; return false }

            let allFiles = ["top/logs/BatteryBDC/BDC_Daily_version3.3_2026-09-16_21:25:49.csv",
                            "top/logs/BatteryBDC/BDC_Once_version3.0_2026-03-26_17:37:52.csv",
                            "top/crashes_and_spins/stacks-1.ips", "top/crashes_and_spins/Retired/old-1.ips"]
            let aAll = await sdMakeArchive(root: root, case: "all",
                                     files: allFiles + ["top/logs/BatteryBDC/notes.txt", "top/crashes_and_spins/Other/x.ips",
                                                        "top/summaries/crashes_and_spins.log"], base: "", item: "top")
            let rAll = await run("all", aAll)
            #expect(eq(rAll.0, 4), "sysdiag: all result")
            #expect(rAll.1 == Set(allFiles), "sysdiag: all files")

            let wanted2 = ["top/logs/BatteryBDC/BDC_Daily_a.csv", "top/crashes_and_spins/stacks-1.ips"]
            let rNR = await run("noRetired", await sdMakeArchive(root: root, case: "noRetired", files: wanted2 + ["top/summaries/x.log"], base: "", item: "top"))
            #expect(eq(rNR.0, 2), "sysdiag: noRetired result")
            #expect(rNR.1 == Set(wanted2), "sysdiag: noRetired files")

            let noBDC = ["top/crashes_and_spins/stacks-1.ips", "top/crashes_and_spins/Retired/old-1.ips"]
            let rNB = await run("noBDC", await sdMakeArchive(root: root, case: "noBDC", files: noBDC, base: "", item: "top"))
            #expect(eq(rNB.0, 2), "sysdiag: noBDC result")
            #expect(rNB.1 == Set(noBDC), "sysdiag: noBDC files")

            let rNo = await run("nothing", await sdMakeArchive(root: root, case: "nothing", files: ["top/summaries/x.log", "top/logs/other.txt"], base: "", item: "top"))
            #expect(eq(rNo.0, 0), "sysdiag: nothing result")
            #expect(rNo.1.isEmpty, "sysdiag: nothing extracts nothing")
            #expect(!fm.fileExists(atPath: rNo.2.path), "sysdiag: nothing writes no member list")

            let rDot = await run("dotPrefix", await sdMakeArchive(root: root, case: "dotPrefix", files: wanted2, base: "top", item: "."))
            #expect(eq(rDot.0, 2), "sysdiag: dotPrefix result")
            #expect(rDot.1 == ["logs/BatteryBDC/BDC_Daily_a.csv", "crashes_and_spins/stacks-1.ips"], "sysdiag: dotPrefix files")

            let odd = ["top/crashes_and_spins/Приложение [beta] *x?.ips", "top/crashes_and_spins/back\\slash.ips", "top/crashes_and_spins/a b.ips"]
            let rOdd = await run("oddNames", await sdMakeArchive(root: root, case: "oddNames", files: odd, base: "", item: "top"))
            #expect(eq(rOdd.0, 3), "sysdiag: oddNames result")
            #expect(rOdd.1 == Set(odd), "sysdiag: oddNames files")

            let naDir = root.appendingPathComponent("notArchive")
            try? fm.createDirectory(at: naDir, withIntermediateDirectories: true)
            let na = naDir.appendingPathComponent("a.tar.gz")
            try? Data("not an archive\n".utf8).write(to: na)
            let rNA = await run("notArchive", na)
            if case .failure(.tarFailed(.message(let m))) = rNA.0 { #expect(!m.isEmpty, "sysdiag: notArchive message") }
            else { Issue.record("sysdiag: notArchive fails with message") }

            let trDir = root.appendingPathComponent("truncated")
            try? fm.createDirectory(at: trDir, withIntermediateDirectories: true)
            let tr = trDir.appendingPathComponent("a.tar.gz")
            if let d = try? Data(contentsOf: aAll) { try? d.prefix(d.count / 2).write(to: tr) }
            let rTr = await run("truncated", tr)
            if case .failure(.tarFailed) = rTr.0 { #expect(Bool(true), "sysdiag: truncated fails as tarFailed") }
            else { Issue.record("sysdiag: truncated fails as tarFailed") }

            let rMi = await run("missing", root.appendingPathComponent("missing/none.tar.gz"))
            if case .failure(.tarFailed(.message(let m))) = rMi.0 { #expect(!m.isEmpty, "sysdiag: missing message") }
            else { Issue.record("sysdiag: missing fails with message") }
        }
    }
}
