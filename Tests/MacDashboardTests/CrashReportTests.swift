// Tests/MacDashboardTests/CrashReportTests.swift
// Port of Checks/main.swift lines 2604-2902 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct CrashReportTests {
        @Test func crashSignal() async {
            // =====================================================================
            // MARK: - Block V2-CRASH-SIGNAL: crash filename parsing, age window, grouping
            // =====================================================================
            do {
                typealias RC = ReportCollector
                #expect(RC.crashProcessName(from: "diffscore-2026-08-11-163444.ips") == "diffscore",
                      "crashProcessName: plain .ips -> process name")
                #expect(RC.crashProcessName(from: "MacDashboard-2026-08-11-163444.ips") == "MacDashboard",
                      "crashProcessName: own app -> MacDashboard")
                #expect(RC.crashProcessName(from: "Kernel-2026-08-11-163444.panic") == "Kernel",
                      "crashProcessName: .panic extension handled")
                #expect(RC.crashProcessName(from: "Google Chrome Helper-2026-08-11-163444.crash") == "Google Chrome Helper",
                      "crashProcessName: spaces in the process name survive")
                #expect(RC.crashProcessName(from: "com.apple.WebKit.WebContent-2026-08-11-163444.ips") == "com.apple.WebKit.WebContent",
                      "crashProcessName: dots in the process name survive")
                #expect(RC.crashProcessName(from: "xpc-service-2026-08-11-163444.ips") == "xpc-service",
                      "crashProcessName: dashes in the process name survive")
                #expect(RC.crashProcessName(from: "weird.ips") == "weird",
                      "crashProcessName: no date suffix -> stem")
                #expect(RC.crashProcessName(from: "diffscore-2026-08-11.ips") == "diffscore-2026-08-11",
                      "crashProcessName: partial date suffix does not match -> whole stem")
                #expect(RC.crashProcessName(from: "-2026-08-11-163444.ips") == "-2026-08-11-163444",
                      "crashProcessName: empty process part -> falls back to the stem, never empty")
                #expect(RC.crashProcessName(from: "") == "", "crashProcessName: empty input -> empty, no trap")

                #expect(RC.crashIsPanic(from: "Kernel-2026-08-11-163444.panic"), "crashIsPanic: .panic -> true")
                #expect(!RC.crashIsPanic(from: "diffscore-2026-08-11-163444.ips"), "crashIsPanic: .ips -> false")
                #expect(!RC.crashIsPanic(from: "diffscore-2026-08-11-163444.crash"), "crashIsPanic: .crash -> false")
                #expect(!RC.crashIsPanic(from: "panic"), "crashIsPanic: no extension at all -> false, no trap")
                #expect(!RC.crashIsPanic(from: ""), "crashIsPanic: empty input -> false, no trap")

                let now = Date(timeIntervalSince1970: 1_760_000_000)
                #expect(RC.crashAgeWindow == 7 * 24 * 60 * 60, "crashAgeWindow: 7 days")
                #expect(RC.isCrashRecent(mtime: now.addingTimeInterval(-3600), now: now), "isCrashRecent: 1 h old -> true")
                #expect(RC.isCrashRecent(mtime: now.addingTimeInterval(-6 * 86400), now: now), "isCrashRecent: 6 d old -> true")
                #expect(!RC.isCrashRecent(mtime: now.addingTimeInterval(-7 * 86400), now: now),
                      "isCrashRecent: exactly 7 d old -> false (strict <)")
                #expect(!RC.isCrashRecent(mtime: now.addingTimeInterval(-8 * 86400), now: now), "isCrashRecent: 8 d old -> false")
                #expect(!RC.isCrashRecent(mtime: now.addingTimeInterval(60), now: now),
                      "isCrashRecent: future mtime (clock rollback) -> false")

                let files: [(name: String, mtime: Date)] = [
                    ("diffscore-2026-08-11-163444.ips", now.addingTimeInterval(-3600)),
                    ("diffscore-2026-08-12-101010.ips", now.addingTimeInterval(-7200)),
                    ("diffscore-2026-08-13-101010.panic", now.addingTimeInterval(-10800)),
                    ("activatehelper-2026-08-14-101010.ips", now.addingTimeInterval(-4000)),
                    ("MacDashboard-2026-08-14-101010.ips", now.addingTimeInterval(-5000)),
                    ("ancient-2025-08-14-101010.ips", now.addingTimeInterval(-400 * 86400)),
                ]
                let groups = RC.crashGroups(byDirectory: [(directory: userCrashDir, files: files)], now: now)
                #expect(groups.count == 3, "crashGroups: 6 files, 1 stale -> 3 groups")
                #expect(groups.map(\.process) == ["diffscore", "MacDashboard", "activatehelper"],
                      "crashGroups: count desc, then name asc for ties")
                #expect(groups.map(\.count) == [3, 1, 1], "crashGroups: repeats collapse into a count (mixed extensions included)")
                #expect(groups.first { $0.process == "diffscore" }?.isPanic == true,
                      "crashGroups: one .panic among the files marks the whole group as a panic group")
                #expect(groups.first { $0.process == "MacDashboard" }?.isPanic == false,
                      "crashGroups: .ips-only group is not a panic group")
                #expect(!groups.contains { $0.process == "ancient" }, "crashGroups: file older than the window is dropped")
                let diff = groups.first { $0.process == "diffscore" }
                #expect(diff?.lastReportAt == now.addingTimeInterval(-3600),
                      "crashGroups: lastReportAt is the max mtime of the group's files")
                #expect(diff?.newestReportPath == userCrashDir + "/diffscore-2026-08-11-163444.ips",
                      "crashGroups: newestReportPath = directory + / + name of the newest file")
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir, files: [("Kernel-2026-08-11-163444.panic", now)])], now: now)
                        .map { ($0.process, $0.count, $0.isPanic) }.first.map { $0 == ("Kernel", 1, true) } == true,
                      "crashGroups: lone kernel panic -> one panic group")
                #expect(RC.crashGroups(byDirectory: [], now: now).isEmpty, "crashGroups: no files -> []")
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir, files: [("old-2025-01-01-000000.ips", now.addingTimeInterval(-90 * 86400))])], now: now).isEmpty,
                      "crashGroups: only stale files -> []")
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir, files: [("Kernel-2019-01-01-000000.panic", now.addingTimeInterval(-90 * 86400))])], now: now).isEmpty,
                      "crashGroups: a panic older than the window is dropped too (age filter applies to panics)")
                let many: [(name: String, mtime: Date)] = (0..<20).map {
                    (name: "p\($0)-2026-08-11-163444.ips", mtime: now.addingTimeInterval(-3600))
                }
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir, files: many)], now: now).count == RC.crashMaxGroups,
                      "crashGroups: caps at crashMaxGroups (15) groups")

                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }
                for lang in AppLanguage.allCases {
                    L10nStore.shared.language = lang
                    #expect(L.maintenanceCrashRow("diffscore", 6) == "diffscore \u{00D7}6",
                          "maintenanceCrashRow (\(lang)): repeats -> 'diffscore ×6'")
                    #expect(L.maintenanceCrashRow("solo", 1) == "solo",
                          "maintenanceCrashRow (\(lang)): single report -> bare process name")
                    #expect(!L.assessKernelPanicsRecent(1).isEmpty
                          && L.assessKernelPanicsRecent(1) != L.assessOwnCrashesRecent(AppInfo.name, 1),
                          "assessKernelPanicsRecent (\(lang)): present and distinct from the own-app sentence")
                }
            }
        }

        @Test func crashDetect() async {
            // =====================================================================
            // MARK: - Block V2-CRASH-DETECT: both report directories, cap keeps what matters
            // =====================================================================
            do {
                typealias RC = ReportCollector
                let now = Date(timeIntervalSince1970: 1_760_000_000)
                let fresh = now.addingTimeInterval(-3600)

                // --- A1: the system directory is scanned at all ---
                let dirs = RC.crashReportDirectories.map(\.path)
                #expect(dirs.count == 2, "crashReportDirectories: exactly two directories")
                #expect(dirs.contains("/Library/Logs/DiagnosticReports"),
                      "crashReportDirectories: the SYSTEM directory is scanned (kernel panics land only there)")
                #expect(dirs.first == FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs/DiagnosticReports",
                      "crashReportDirectories: the per-user directory comes first (dedup priority)")

                // --- dedup: the same report listed by both directories ---
                let dupByDir: [RC.CrashDirectoryListing] = [
                    (directory: userCrashDir, files: [("\(AppInfo.name)-2026-08-11-163444.ips", fresh),
                                                      ("diffscore-2026-08-11-163444.ips", fresh)]),
                    (directory: systemCrashDir, files: [("\(AppInfo.name)-2026-08-11-163444.ips", fresh.addingTimeInterval(-60))]),
                ]
                #expect(RC.crashDedup(byDirectory: dupByDir).map(\.name)
                        == ["\(AppInfo.name)-2026-08-11-163444.ips", "diffscore-2026-08-11-163444.ips"],
                      "crashDedup: a name listed twice collapses to one entry, input order preserved")
                #expect(RC.crashDedup(byDirectory: dupByDir).first?.mtime == fresh,
                      "crashDedup: the FIRST occurrence wins (per-user copy before the system one)")
                #expect(RC.crashDedup(byDirectory: []).isEmpty, "crashDedup: no files -> []")
                #expect(RC.crashGroups(byDirectory: dupByDir, now: now).first { $0.process == AppInfo.name }?.count == 1,
                      "crashGroups: a report present in both directories is counted once, not twice")
                #expect(RC.crashGroups(byDirectory: dupByDir, now: now).first { $0.process == AppInfo.name }?.newestReportPath
                        == userCrashDir + "/\(AppInfo.name)-2026-08-11-163444.ips",
                      "crashGroups: the per-user copy's path wins when both directories list the same name")

                // --- the shared predicate ---
                #expect(RC.crashRaisesAttention(CrashGroup(process: "Kernel", count: 1, isPanic: true, directory: systemCrashDir)),
                      "crashRaisesAttention: kernel panic from any process -> true")
                #expect(RC.crashRaisesAttention(CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir)),
                      "crashRaisesAttention: our own crash -> true")
                #expect(!RC.crashRaisesAttention(CrashGroup(process: "diffscore", count: 9, directory: userCrashDir)),
                      "crashRaisesAttention: a loud third-party process -> false")

                // --- A2: 20 louder foreign groups must not push out the panic and our own crash ---
                var many: [(name: String, mtime: Date)] = []
                for i in 0..<20 {
                    for d in 11...13 { many.append((name: "p\(i)-2026-08-\(d)-163444.ips", mtime: fresh)) }
                }
                many.append((name: "Kernel-2026-08-11-163444.panic", mtime: fresh))
                many.append((name: "Kernel-2026-08-12-163444.panic", mtime: fresh))
                many.append((name: "\(AppInfo.name)-2026-08-11-163444.ips", mtime: fresh))
                let capped = RC.crashGroups(byDirectory: [(directory: userCrashDir, files: many)], now: now)
                #expect(capped.count == RC.crashMaxGroups, "crashGroups: still capped at crashMaxGroups (15) groups")
                #expect(capped.contains { $0.isPanic }, "crashGroups: the panic group survives the cap (finding A2)")
                #expect(capped.contains { $0.process == AppInfo.name },
                      "crashGroups: the own-app group survives the cap (finding A2)")
                #expect(capped.prefix(2).map(\.process) == ["Kernel", AppInfo.name],
                      "crashGroups: notable groups lead the list, ordered count desc (panic 2, own 1)")
                #expect(capped.dropFirst(2).count == 13 && capped.dropFirst(2).allSatisfy { $0.count == 3 },
                      "crashGroups: the remaining 13 slots go to the loudest ordinary groups")

                // --- ordering is untouched when nothing is notable ---
                let ordinary: [(name: String, mtime: Date)] = [
                    ("aaa-2026-08-11-163444.ips", fresh),
                    ("bbb-2026-08-11-163444.ips", fresh),
                    ("bbb-2026-08-12-163444.ips", fresh),
                ]
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir, files: ordinary)], now: now).map(\.process) == ["bbb", "aaa"],
                      "crashGroups: no notable group -> order unchanged (count desc, then name asc)")

                // --- degenerate: more notable groups than the cap ---
                let allPanics: [(name: String, mtime: Date)] = (0..<20).map {
                    (name: "k\($0)-2026-08-11-163444.panic", mtime: fresh)
                }
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir, files: allPanics)], now: now).count == RC.crashMaxGroups,
                      "crashGroups: more notable groups than the cap -> still 15, the cap is never exceeded")
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir, files: [("\(AppInfo.name)-2026-08-11-163444.panic", fresh)])], now: now).count == 1,
                      "crashGroups: a group that is both a panic AND our own app appears exactly once")
            }
        }

        @Test func crashReveal() async {
            // =====================================================================
            // MARK: - Block V2-CRASH-REVEAL: source directory on the group, JetsamEvent is not a crash
            // =====================================================================
            do {
                typealias RC = ReportCollector
                let now = Date(timeIntervalSince1970: 1_760_000_000)
                let fresh = now.addingTimeInterval(-3600)
                let stale = now.addingTimeInterval(-30 * 86400)

                // --- item 3: JetsamEvent is not a crash ---
                #expect(RC.nonCrashReportPrefixes == ["jetsamevent-"],
                      "nonCrashReportPrefixes: exactly one explicit lowercase prefix, no speculative list")
                #expect(RC.crashIsProcessCrash(from: "diffscore-2026-08-11-163444.ips"),
                      "crashIsProcessCrash: an ordinary .ips is a crash")
                #expect(RC.crashIsProcessCrash(from: "Kernel-2026-08-11-163444.panic"),
                      "crashIsProcessCrash: a kernel panic is a crash")
                #expect(!RC.crashIsProcessCrash(from: "JetsamEvent-2026-08-11-163444.ips"),
                      "crashIsProcessCrash: JetsamEvent- is excluded (memory-pressure kill, not a crash)")
                #expect(!RC.crashIsProcessCrash(from: "jetsamevent-2026-08-11-163444.ips"),
                      "crashIsProcessCrash: the prefix match is case-insensitive")
                #expect(RC.crashIsProcessCrash(from: "JetsamEventLogger-2026-08-11-163444.ips"),
                      "crashIsProcessCrash: the trailing dash keeps a real process named JetsamEventLogger a crash")
                #expect(RC.crashIsProcessCrash(from: ""),
                      "crashIsProcessCrash: empty filename -> treated as a crash, no trap")

                let mixed: [RC.CrashDirectoryListing] = [
                    (directory: userCrashDir, files: [("JetsamEvent-2026-08-11-163444.ips", fresh),
                                                      ("diffscore-2026-08-11-163444.ips", fresh)]),
                ]
                #expect(RC.crashGroups(byDirectory: mixed, now: now).map(\.process) == ["diffscore"],
                      "crashGroups: JetsamEvent forms no group")
                #expect(RC.crashGroups(byDirectory: mixed, now: now).reduce(0) { $0 + $1.count } == 1,
                      "crashGroups: JetsamEvent adds nothing to the crash total")
                let onlyJetsam: [RC.CrashDirectoryListing] = [
                    (directory: systemCrashDir, files: [("JetsamEvent-2026-08-11-163444.ips", fresh)]),
                ]
                #expect(RC.crashGroups(byDirectory: onlyJetsam, now: now).isEmpty,
                      "crashGroups: a JetsamEvent-only machine reports zero crashes (the card stays quiet)")

                // --- item 1: the directory travels with the group ---
                #expect(RC.crashGroups(byDirectory: [(directory: systemCrashDir,
                                                    files: [("Kernel-2026-08-11-163444.panic", fresh)])], now: now)
                        .first?.directory == systemCrashDir,
                      "crashGroups: a system-directory panic carries the SYSTEM directory")
                #expect(RC.crashGroups(byDirectory: [(directory: userCrashDir,
                                                    files: [("diffscore-2026-08-11-163444.ips", fresh)])], now: now)
                        .first?.directory == userCrashDir,
                      "crashGroups: a per-user report carries the PER-USER directory")

                let bothDirs: [RC.CrashDirectoryListing] = [
                    (directory: userCrashDir, files: [("diffscore-2026-08-11-163444.ips", fresh)]),
                    (directory: systemCrashDir, files: [("diffscore-2026-08-12-163444.ips", fresh)]),
                ]
                let bothGroup = RC.crashGroups(byDirectory: bothDirs, now: now).first
                #expect(bothGroup?.count == 2,
                      "crashGroups: one process crashing in both directories -> one group of 2")
                #expect(bothGroup?.directory == userCrashDir,
                      "crashGroups: a group spanning both directories reveals the FIRST one (per-user), which does contain a report")

                let firstStale: [RC.CrashDirectoryListing] = [
                    (directory: userCrashDir, files: [("diffscore-2025-01-01-000000.ips", stale)]),
                    (directory: systemCrashDir, files: [("diffscore-2026-08-12-163444.ips", fresh)]),
                ]
                #expect(RC.crashGroups(byDirectory: firstStale, now: now).first?.directory == systemCrashDir,
                      "crashGroups: the directory comes from the first SURVIVING report — a stale per-user report does not claim it")
                #expect(RC.crashGroups(byDirectory: firstStale, now: now).first?.count == 1,
                      "crashGroups: the stale per-user report is still dropped from the count")

                // --- dedup keeps the winning copy's directory ---
                let sameName: [RC.CrashDirectoryListing] = [
                    (directory: userCrashDir, files: [("diffscore-2026-08-11-163444.ips", fresh)]),
                    (directory: systemCrashDir, files: [("diffscore-2026-08-11-163444.ips", fresh.addingTimeInterval(-60))]),
                ]
                #expect(RC.crashDedup(byDirectory: sameName).count == 1,
                      "crashDedup: the same filename in both directories collapses to one entry")
                #expect(RC.crashDedup(byDirectory: sameName).first?.directory == userCrashDir,
                      "crashDedup: the surviving entry carries the FIRST listing's directory")
                #expect(RC.crashDedup(byDirectory: []).isEmpty, "crashDedup: no listings -> []")
                #expect(RC.crashDedup(byDirectory: sameName.reversed()).first?.directory == systemCrashDir,
                      "crashDedup: listing order IS the priority order, nothing else decides")

                // --- the directory does not leak into the attention predicate or into identity ---
                #expect(RC.crashRaisesAttention(CrashGroup(process: "Kernel", count: 1, isPanic: true, directory: userCrashDir))
                      == RC.crashRaisesAttention(CrashGroup(process: "Kernel", count: 1, isPanic: true, directory: systemCrashDir)),
                      "crashRaisesAttention: the source directory does not change whether a group raises attention")
                #expect(CrashGroup(process: "a", count: 1, directory: userCrashDir)
                      != CrashGroup(process: "a", count: 1, directory: systemCrashDir),
                      "CrashGroup: Equatable includes `directory` (synthesized, not hand-written)")

                // --- item 1 at the assessment layer: the reveal target is the group's own directory ---
                do {
                    var report = FullReport()
                    report.crashes = [CrashGroup(process: AppInfo.name, count: 1, directory: systemCrashDir)]
                    let a = Assess.assess(report: report, live: LiveSnapshot())
                    #expect(a.items.first { $0.kind == .crashes }?.action == .revealPath(systemCrashDir),
                          "assess crashes: an own-app crash found in the SYSTEM directory reveals the system directory")
                }
                do {
                    var report = FullReport()
                    report.crashes = [CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir)]
                    let a = Assess.assess(report: report, live: LiveSnapshot())
                    #expect(a.items.first { $0.kind == .crashes }?.action == .revealPath(userCrashDir),
                          "assess crashes: an own-app crash found in the PER-USER directory reveals the per-user directory")
                }
                do {
                    // A non-raising group listed first must not steal the target.
                    var report = FullReport()
                    report.crashes = [CrashGroup(process: "diffscore", count: 6, directory: userCrashDir),
                                      CrashGroup(process: "Kernel", count: 2, isPanic: true, directory: systemCrashDir)]
                    let a = Assess.assess(report: report, live: LiveSnapshot())
                    #expect(a.items.first { $0.kind == .crashes }?.action == .revealPath(systemCrashDir),
                          "assess crashes: the target comes from the first RAISING group, not the first group")
                    #expect(a.problems.first { $0.text == L.assessKernelPanicsRecent(2) }?.action == .revealPath(systemCrashDir),
                          "assess crashes: the Problem carries the same reveal target as the AttentionItem")
                }
                do {
                    // Two raising groups from two directories: the leading one wins, deterministically.
                    var report = FullReport()
                    report.crashes = [CrashGroup(process: "Kernel", count: 2, isPanic: true, directory: systemCrashDir),
                                      CrashGroup(process: AppInfo.name, count: 1, directory: userCrashDir)]
                    let a = Assess.assess(report: report, live: LiveSnapshot())
                    #expect(a.items.first { $0.kind == .crashes }?.action == .revealPath(systemCrashDir),
                          "assess crashes: raising groups from two directories -> the leading group's directory")
                }

                // --- item 2: the row's accessibility string exists in every language ---
                let originalLang = L10nStore.shared.language
                defer { L10nStore.shared.language = originalLang }
                for lang in AppLanguage.allCases {
                    L10nStore.shared.language = lang
                    #expect(L.maintenanceCrashRevealA11y("diffscore").contains("diffscore"),
                          "maintenanceCrashRevealA11y (\(lang)): names the process")
                    #expect(L.maintenanceCrashRevealA11y("diffscore").count > "diffscore".count + 5,
                          "maintenanceCrashRevealA11y (\(lang)): is a real sentence, not just the process name")
                }
            }
        }
    }
}
