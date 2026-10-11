// Checks/SysdiagnoseExtractorChecks.swift
// IPHONE-IMPORT-IOS27: pure selection/pattern/error-mapping checks and end-to-end extraction
// over archives synthesized at run time in a fresh temp dir. Never touches App Support.

import Foundation

private func sdFiles(under dir: URL) -> Set<String> {
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

private func sdMakeArchive(root: URL, case name: String, files: [String], base: String, item: String) -> URL {
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
    let o = runAsyncBlocking {
        await CommandRunner.run("/usr/bin/tar", ["-czf", archive.path, "-C", cwd, item], timeout: 30,
                                environment: CommandRunner.defaultEnvironment.merging(["COPYFILE_DISABLE": "1"]) { $1 })
    }
    check(o.termination == .exited(0), "sysdiag: build archive \(name)")
    return archive
}

private func sdExtractDir(_ root: URL, _ name: String) -> URL {
    let x = root.appendingPathComponent(name).appendingPathComponent("x")
    try? FileManager.default.createDirectory(at: x, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return x
}

func runSysdiagnoseExtractorChecks() {
    typealias X = SysdiagnoseExtractor
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("MacDashboardChecks-sysdiag-\(UUID().uuidString)")
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    // isWanted
    let bdc = "sysdiagnose_X/logs/BatteryBDC/BDC_Daily_version3.3_2026-09-16_21:25:49.csv"
    check(X.isWanted(bdc), "sysdiag: isWanted full BDC path")
    check(X.isWanted("./logs/BatteryBDC/BDC_Daily_a.csv"), "sysdiag: isWanted ./ BDC")
    check(X.isWanted("logs/BatteryBDC/BDC_Daily_a.csv"), "sysdiag: isWanted no top BDC")
    check(!X.isWanted("top/logs/BatteryBDC/BDC_Daily_a.txt"), "sysdiag: isWanted BDC wrong ext")
    check(!X.isWanted("top/logs/BatteryBDC/Other_a.csv"), "sysdiag: isWanted BDC wrong prefix")
    check(!X.isWanted("top/logs/BatteryBDC/sub/BDC_Daily_a.csv"), "sysdiag: isWanted BDC subfolder")
    check(!X.isWanted("top/BatteryBDC/BDC_Daily_a.csv"), "sysdiag: isWanted BDC without logs")
    check(X.isWanted("top/crashes_and_spins/a.ips"), "sysdiag: isWanted crash ips")
    check(X.isWanted("top/crashes_and_spins/Retired/b.ips"), "sysdiag: isWanted retired ips")
    check(X.isWanted("crashes_and_spins/a.ips"), "sysdiag: isWanted crash ips no top")
    check(!X.isWanted("top/crashes_and_spins/Other/c.ips"), "sysdiag: isWanted other subfolder")
    check(!X.isWanted("top/other/a.ips"), "sysdiag: isWanted other parent")
    check(!X.isWanted("top/crashes_and_spins.ips"), "sysdiag: isWanted file named like folder")
    check(!X.isWanted("top/crashes_and_spins/") && !X.isWanted("top/crashes_and_spins/a.ips/"), "sysdiag: isWanted directories")
    check(!X.isWanted(""), "sysdiag: isWanted empty")

    // pattern
    check(X.pattern(forListed: "top/crashes_and_spins/a-1_b.ips") == "top/crashes_and_spins/a-1_b.ips", "sysdiag: pattern safe chars")
    check(X.pattern(forListed: "top/x y.ips") == "top/x?y.ips", "sysdiag: pattern space")
    check(X.pattern(forListed: "top/a[1]*.ips") == "top/a?1??.ips", "sysdiag: pattern brackets and star")
    check(X.pattern(forListed: "top/a\\\\b.ips") == "top/a?b.ips", "sysdiag: pattern escaped backslash")
    check(X.pattern(forListed: "top/\\320\\237x.ips") == "top/??x.ips", "sysdiag: pattern octal escapes")
    check(X.pattern(forListed: "top/a\\n.ips") == "top/a?.ips", "sysdiag: pattern char escape")
    check(X.pattern(forListed: "top/П.ips") == "top/??.ips", "sysdiag: pattern raw UTF-8")
    check(X.pattern(forListed: "./logs/BatteryBDC/BDC_Daily_21:25:49.csv") == "./logs/BatteryBDC/BDC_Daily_21?25?49.csv", "sysdiag: pattern colon and ./")
    check(X.pattern(forListed: "-top/crashes_and_spins/a.ips") == "?top/crashes_and_spins/a.ips", "sysdiag: pattern leading dash")
    check(X.pattern(forListed: "./-top/a-b.ips") == "./-top/a-b.ips", "sysdiag: pattern inner dash kept")
    check(X.memberPatterns(listing: "top/crashes_and_spins/a.ips\r\ntop/crashes_and_spins/b.ips\r\n")
          == ["top/crashes_and_spins/a.ips", "top/crashes_and_spins/b.ips"], "sysdiag: memberPatterns CRLF")
    check(X.memberPatterns(listing: "top/\ntop/logs/BatteryBDC/BDC_Daily_a.csv\ntop/x.txt\ntop/crashes_and_spins/a.ips\ntop/crashes_and_spins/a.ips\n")
          == ["top/logs/BatteryBDC/BDC_Daily_a.csv", "top/crashes_and_spins/a.ips"], "sysdiag: memberPatterns select and dedupe")
    check(X.memberPatterns(listing: "").isEmpty, "sysdiag: memberPatterns empty")
    check(X.listArguments(archive: "/t/a.tar.gz") == ["-tzf", "/t/a.tar.gz"], "sysdiag: listArguments")
    check(X.extractArguments(archive: "/t/a.tar.gz", into: "/t/x", memberList: "/t/m.txt")
          == ["-xzf", "/t/a.tar.gz", "-C", "/t/x", "-T", "/t/m.txt"], "sysdiag: extractArguments")

    // importError
    func oc(_ t: CommandOutcome.Termination, _ err: String) -> CommandOutcome {
        CommandOutcome(termination: t, stdout: "", stdoutTruncated: false, stderrHead: err)
    }
    check(X.importError(for: oc(.exited(0), "tar: warning\n")) == nil, "sysdiag: importError clean exit")
    check(X.importError(for: oc(.cancelled, "")) == .cancelled, "sysdiag: importError cancelled")
    check(X.importError(for: oc(.exited(1), "tar: x: Not found in archive\ntar: Error exit delayed from previous errors.\n"))
          == .tarFailed(.message("tar: x: Not found in archive")), "sysdiag: importError first stderr line")
    check(X.importError(for: oc(.exited(1), "\n   \n")) == .tarFailed(.exitCode(1)), "sysdiag: importError blank stderr")
    check(X.importError(for: oc(.signaled(9), "")) == .tarFailed(.signal(9)), "sysdiag: importError signal")
    check(X.importError(for: oc(.launchFailed(2), "")) == .tarFailed(.launchFailed(2)), "sysdiag: importError launch failed")
    check(X.importError(for: oc(.timedOut, "partial\n")) == .tarFailed(.timedOut), "sysdiag: importError timeout beats stderr")
    check(X.importError(for: oc(.exited(1), String(repeating: "a", count: 500)))
          == .tarFailed(.message(String(repeating: "a", count: 200))), "sysdiag: importError caps at 200")

    // strings
    check(StringsRU().iphoneImportErrorDetail(.tarFailed(.message("tar: boom"))) == "tar: boom", "sysdiag: RU detail message verbatim")
    check(StringsRU().iphoneImportErrorDetail(.copyFailed) == nil && StringsRU().iphoneImportErrorDetail(.cancelled) == nil,
          "sysdiag: RU detail nil for other errors")
    check(StringsRU().iphoneImportErrorDetail(.tarFailed(.timedOut)) == "tar не завершился вовремя.", "sysdiag: RU detail timeout")
    check(StringsEN().iphoneImportErrorDetail(.tarFailed(.exitCode(1))) == "tar exited with code 1.", "sysdiag: EN detail exit code")
    check(StringsRU().iphoneImportError(.tarFailed(.timedOut)) == "Не удалось распаковать архив.", "sysdiag: RU sentence unchanged")

    // end-to-end
    func run(_ name: String, _ a: URL) -> (Result<Int, ImportError>, Set<String>, URL) {
        let x = sdExtractDir(root, name)
        let list = root.appendingPathComponent(name).appendingPathComponent("members.txt")
        let r = runAsyncBlocking { await X.extract(archive: a, into: x, memberList: list) }
        return (r, sdFiles(under: x), list)
    }
    func eq(_ r: Result<Int, ImportError>, _ n: Int) -> Bool { if case .success(let m) = r { return m == n }; return false }

    let allFiles = ["top/logs/BatteryBDC/BDC_Daily_version3.3_2026-09-16_21:25:49.csv",
                    "top/crashes_and_spins/stacks-1.ips", "top/crashes_and_spins/Retired/old-1.ips"]
    let aAll = sdMakeArchive(root: root, case: "all",
                             files: allFiles + ["top/logs/BatteryBDC/notes.txt", "top/crashes_and_spins/Other/x.ips",
                                                "top/summaries/crashes_and_spins.log"], base: "", item: "top")
    let rAll = run("all", aAll)
    check(eq(rAll.0, 3), "sysdiag: all result")
    check(rAll.1 == Set(allFiles), "sysdiag: all files")

    let wanted2 = ["top/logs/BatteryBDC/BDC_Daily_a.csv", "top/crashes_and_spins/stacks-1.ips"]
    let rNR = run("noRetired", sdMakeArchive(root: root, case: "noRetired", files: wanted2 + ["top/summaries/x.log"], base: "", item: "top"))
    check(eq(rNR.0, 2), "sysdiag: noRetired result")
    check(rNR.1 == Set(wanted2), "sysdiag: noRetired files")

    let noBDC = ["top/crashes_and_spins/stacks-1.ips", "top/crashes_and_spins/Retired/old-1.ips"]
    let rNB = run("noBDC", sdMakeArchive(root: root, case: "noBDC", files: noBDC, base: "", item: "top"))
    check(eq(rNB.0, 2), "sysdiag: noBDC result")
    check(rNB.1 == Set(noBDC), "sysdiag: noBDC files")

    let rNo = run("nothing", sdMakeArchive(root: root, case: "nothing", files: ["top/summaries/x.log", "top/logs/other.txt"], base: "", item: "top"))
    check(eq(rNo.0, 0), "sysdiag: nothing result")
    check(rNo.1.isEmpty, "sysdiag: nothing extracts nothing")
    check(!fm.fileExists(atPath: rNo.2.path), "sysdiag: nothing writes no member list")

    let rDot = run("dotPrefix", sdMakeArchive(root: root, case: "dotPrefix", files: wanted2, base: "top", item: "."))
    check(eq(rDot.0, 2), "sysdiag: dotPrefix result")
    check(rDot.1 == ["logs/BatteryBDC/BDC_Daily_a.csv", "crashes_and_spins/stacks-1.ips"], "sysdiag: dotPrefix files")

    let odd = ["top/crashes_and_spins/Приложение [beta] *x?.ips", "top/crashes_and_spins/back\\slash.ips", "top/crashes_and_spins/a b.ips"]
    let rOdd = run("oddNames", sdMakeArchive(root: root, case: "oddNames", files: odd, base: "", item: "top"))
    check(eq(rOdd.0, 3), "sysdiag: oddNames result")
    check(rOdd.1 == Set(odd), "sysdiag: oddNames files")

    let naDir = root.appendingPathComponent("notArchive")
    try? fm.createDirectory(at: naDir, withIntermediateDirectories: true)
    let na = naDir.appendingPathComponent("a.tar.gz")
    try? Data("not an archive\n".utf8).write(to: na)
    let rNA = run("notArchive", na)
    if case .failure(.tarFailed(.message(let m))) = rNA.0 { check(!m.isEmpty, "sysdiag: notArchive message") }
    else { check(false, "sysdiag: notArchive fails with message") }

    let trDir = root.appendingPathComponent("truncated")
    try? fm.createDirectory(at: trDir, withIntermediateDirectories: true)
    let tr = trDir.appendingPathComponent("a.tar.gz")
    if let d = try? Data(contentsOf: aAll) { try? d.prefix(d.count / 2).write(to: tr) }
    let rTr = run("truncated", tr)
    if case .failure(.tarFailed) = rTr.0 { check(true, "sysdiag: truncated fails as tarFailed") }
    else { check(false, "sysdiag: truncated fails as tarFailed") }

    let rMi = run("missing", root.appendingPathComponent("missing/none.tar.gz"))
    if case .failure(.tarFailed(.message(let m))) = rMi.0 { check(!m.isEmpty, "sysdiag: missing message") }
    else { check(false, "sysdiag: missing fails with message") }
}

func runSysdiagnoseProbe(_ archivePath: String) -> Int32 {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("MacDashboardChecks-sysdiag-probe-\(UUID().uuidString)")
    let x = dir.appendingPathComponent("x")
    do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: x, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    } catch { return 2 }
    let start = Date()
    let r = runAsyncBlocking {
        await SysdiagnoseExtractor.extract(archive: URL(fileURLWithPath: archivePath), into: x,
                                           memberList: dir.appendingPathComponent("members.txt"))
    }
    let secs = Date().timeIntervalSince(start)
    var code: Int32 = 1
    switch r {
    case .success(let n):
        let names = sdFiles(under: x).map { ($0 as NSString).lastPathComponent }
        let csv = names.filter { $0.hasPrefix("BDC_Daily_") && $0.hasSuffix(".csv") }.count
        let ips = names.filter { $0.hasSuffix(".ips") }.count
        print("sysdiag probe: result=success selected=\(n) csv=\(csv) ips=\(ips) seconds=\(String(format: "%.1f", secs)) tmp=\(dir.path)")
        code = 0
    case .failure(let e):
        print("sysdiag probe: result=failure error=\(String(describing: e)) tmp=\(dir.path)")
    }
    try? fm.removeItem(at: dir)
    return code
}
