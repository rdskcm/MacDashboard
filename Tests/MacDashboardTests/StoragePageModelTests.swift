// Tests/MacDashboardTests/StoragePageModelTests.swift
// REDESIGN-STORAGE stage 1: the low-space rule, tag priority, notes, rows, phases, FDA table, SMART state and tiles.
import Foundation
import Testing
@testable import MacDashboard

private let home = "/Users/x"
private let GB: Int64 = 1_000_000_000

private func withLang(_ lang: AppLanguage, _ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

private func health(_ field: WritableKeyPath<SmartHealth, Int?>? = nil, _ v: Int? = nil,
                    _ field64: WritableKeyPath<SmartHealth, UInt64?>? = nil, _ v64: UInt64? = nil) -> SmartHealth {
    var h = SmartHealth(temperatureC: 39, percentageUsed: 4, availableSpare: 100, spareThreshold: 10, powerOnHours: 1234,
                        powerCycles: 120, unsafeShutdowns: 3, dataUnitsRead: 74_609_375, dataUnitsWritten: 1000,
                        mediaErrors: 0, errorLogEntries: 0, criticalWarning: 0)
    if let field { h[keyPath: field] = v }
    if let field64 { h[keyPath: field64] = v64 }
    return h
}

private func disk(_ device: String, _ h: SmartHealth?) -> SmartDisk {
    SmartDisk(device: device, title: device, status: "OK", health: h)
}

extension SerialTests {
    struct StoragePageModelTests {
        @Test func spaceLevel() {
            let size: Int64 = 1000
            #expect(StorageSpace.level(avail: 250, size: size, lowPercent: 20) == .ok)
            #expect(StorageSpace.level(avail: 200, size: size, lowPercent: 20) == .ok, "exactly 20 % is OK")
            #expect(StorageSpace.level(avail: 199, size: size, lowPercent: 20) == .low)
            #expect(StorageSpace.level(avail: 100, size: size, lowPercent: 20) == .low, "exactly 10 % is low")
            #expect(StorageSpace.level(avail: 99, size: size, lowPercent: 20) == .critical)
            #expect(StorageSpace.level(avail: 120, size: size, lowPercent: 10) == .ok)
            #expect(StorageSpace.level(avail: 100, size: size, lowPercent: 10) == .ok, "setting 10: no amber band")
            #expect(StorageSpace.level(avail: 99, size: size, lowPercent: 10) == .critical)
            #expect(StorageSpace.level(avail: 140, size: size, lowPercent: 15) == .low)
            #expect(StorageSpace.level(avail: 5, size: 0, lowPercent: 20) == nil)
        }

        @Test func tagPriority() {
            #expect(StoragePageModel.tag(space: .critical, smartFailing: true, smartWorn: false) == .driveFailing)
            #expect(StoragePageModel.tag(space: .critical, smartFailing: false, smartWorn: true) == .almostFull)
            #expect(StoragePageModel.tag(space: .low, smartFailing: false, smartWorn: true) == .driveWorn)
            #expect(StoragePageModel.tag(space: .low, smartFailing: false, smartWorn: false) == .lowSpace)
            #expect(StoragePageModel.tag(space: .ok, smartFailing: false, smartWorn: false) == .ok)
            #expect(StoragePageModel.tag(space: nil, smartFailing: false, smartWorn: false) == .loading)
            #expect(StoragePageModel.tag(space: nil, smartFailing: false, smartWorn: true) == .driveWorn)
        }

        @Test func subAndHero() {
            withLang(.en) {
                #expect(StoragePageModel.sub(internalName: "Macintosh HD", size: 500 * GB) == "Macintosh HD · 500 GB")
                #expect(StoragePageModel.sub(internalName: nil, size: nil) == "Internal drive")
                #expect(StoragePageModel.heroNote(size: 500 * GB, usedFraction: 0.874) == "of 500 GB · 87% used")
            }
        }

        @Test func freeableAndDiskNote() {
            let dirs = [DirSize(path: home + "/Downloads", bytes: 11 * GB), DirSize(path: home + "/.Trash", bytes: 2 * GB),
                        DirSize(path: home + "/Movies", bytes: 90 * GB)]
            let caches = DirSize(path: home + "/Library/Caches", bytes: 4 * GB)
            let items = StoragePageModel.freeable(homeDirs: dirs, homeCaches: caches, home: home)
            #expect(items.map(\.kind) == [.downloads, .caches, .trash])
            let small = StoragePageModel.freeable(homeDirs: [DirSize(path: home + "/Downloads", bytes: 99_999_999),
                                                             DirSize(path: home + "/.Trash", bytes: 100_000_000)],
                                                  homeCaches: nil, home: home)
            #expect(small.map(\.kind) == [.trash], "threshold is 100 MB")
            withLang(.en) {
                #expect(StoragePageModel.diskNote(level: .ok, lowPercent: 20, items: items) == nil)
                #expect(StoragePageModel.diskNote(level: .low, lowPercent: 20, items: items)
                        == "Less than 20% free. What you can free up: Downloads 11 GB, Caches 4 GB, Trash 2 GB.")
                #expect(StoragePageModel.diskNote(level: .low, lowPercent: 15, items: [])
                        == "Less than 15% free.")
                #expect(StoragePageModel.diskNote(level: .critical, lowPercent: 15, items: Array(items.prefix(1)))
                        == "Less than 10% free. macOS may stop saving files and growing swap. Free up space: Downloads 11 GB.")
                #expect(StoragePageModel.diskNote(level: .critical, lowPercent: 20, items: [])
                        == "Less than 10% free. macOS may stop saving files and growing swap.")
            }
            withLang(.ru) {
                #expect(StoragePageModel.diskNote(level: .low, lowPercent: 15, items: [])
                        == "Свободно меньше 15 %.")
            }
        }

        @Test func rows() {
            withLang(.en) {
                var dirs = (1...10).map { DirSize(path: home + "/d\($0)", bytes: Int64($0) * GB) }
                dirs.append(DirSize(path: home, bytes: 500 * GB))
                dirs.append(DirSize(path: home + "/Downloads", bytes: 20 * GB))
                dirs.append(DirSize(path: home + "/Empty", bytes: 0))
                dirs.append(DirSize(path: home + "/.Trash", bytes: 3 * GB))
                let caches = DirSize(path: home + "/Library/Caches", bytes: 5 * GB)
                let rows = StoragePageModel.homeRows(homeDirs: dirs, homeCaches: caches, home: home, trashHidden: false)
                #expect(rows.count == 8 + 2, "top 8 + caches + trash")
                #expect(rows.map(\.bytes) == rows.map(\.bytes).sorted(by: >), "sorted desc")
                #expect(rows.first?.label == "Downloads" && rows.first?.action == .show(path: home + "/Downloads"))
                #expect(rows.first?.fraction == 1.0)
                #expect(rows.first { $0.label == "~/Library/Caches" }?.action == .show(path: home + "/Library/Caches"))
                #expect(rows.first { $0.label == "Trash" }?.action == .emptyTrash)
                #expect(rows.contains { $0.label == "~/d10" } && !rows.contains { $0.label == "~/d1" })
                #expect(!rows.contains { $0.label == "~/Empty" } && !rows.contains { $0.id == home })
                let hidden = StoragePageModel.homeRows(homeDirs: dirs, homeCaches: caches, home: home, trashHidden: true)
                #expect(!hidden.contains { $0.action == .emptyTrash })
                let sys = StoragePageModel.systemRows([DirSize(path: "/Applications", bytes: 40 * GB), DirSize(path: "/opt/homebrew", bytes: 0),
                                                       DirSize(path: "/Library", bytes: 10 * GB)])
                #expect(sys.map(\.label) == ["/Applications", "/Library"] && sys[0].fraction == 1.0 && sys[1].fraction == 0.25)
            }
        }

        @Test func phaseAndCaption() {
            let t = Date(timeIntervalSince1970: 1000)
            #expect(StoragePageModel.foldersPhase(block: .loading(since: t), hasCount: false) == .wait)
            #expect(StoragePageModel.foldersPhase(block: .failed(.timedOut, lastGoodAt: nil), hasCount: false) == .failedEmpty(.timedOut))
            #expect(StoragePageModel.foldersPhase(block: .ok(at: t), hasCount: false) == .list)
            #expect(StoragePageModel.foldersPhase(block: .loading(since: t), hasCount: true) == .list)
            #expect(StoragePageModel.foldersPhase(block: .failed(.timedOut, lastGoodAt: t), hasCount: true) == .list)
            #expect(StoragePageModel.foldersPhase(block: .failed(.noReading, lastGoodAt: t), hasCount: true) == .failedWithList(.noReading))
            withLang(.en) {
                let now = t.addingTimeInterval(7 * 60)
                func cap(_ p: FoldersPhase, counting: Bool = false, at: Date? = t, freed: Int64? = nil, hidden: Bool = false) -> String {
                    StoragePageModel.foldersCaption(phase: p, counting: counting, countedAt: at, now: now, trashFreed: freed, someHidden: hidden)
                }
                #expect(cap(.wait) == "counting folder sizes…")
                #expect(cap(.failedEmpty(.timedOut), counting: true) == "counting didn’t finish")
                #expect(cap(.list, counting: true, freed: GB, hidden: true) == "counting folder sizes…")
                #expect(cap(.list, freed: 2 * GB, hidden: true) == "top by size · Trash emptied, 2 GB freed")
                #expect(cap(.list, hidden: true) == "top by size · some folders hidden")
                #expect(cap(.list) == "top by size · counted 7 min ago")
                #expect(StoragePageModel.foldersCaption(phase: .list, counting: false, countedAt: t, now: t, trashFreed: nil, someHidden: false)
                        == "top by size · counted just now")
                #expect(cap(.list, at: nil) == "top by size")
                #expect(StoragePageModel.failureNote(.noReading) == "Couldn’t count folder sizes: du returned no result.")
                #expect(StoragePageModel.failureNote(.timedOut).hasSuffix("within 10 s."))
            }
        }

        @Test func fullDiskAccess() {
            let denied = ProtectedLocations.denied(home: home) { path in
                switch path {
                case home + "/Library/Mail", home + "/Library/Safari": return .denied
                case home + "/Library/Messages": return .missing
                default: return .readable
                }
            }
            #expect(denied.map(\.nameEN) == ["Mail", "Safari"])
            #expect(StoragePageModel.hiddenNames(denied: denied, unreadableHome: [home + "/Documents", home + "/Documents"], russian: false)
                    == ["Mail", "Safari", "~/Documents"])
            #expect(StoragePageModel.hiddenNames(denied: denied, unreadableHome: [], russian: true) == ["Почта", "Safari"])
            #expect(StoragePageModel.fdaNote([]) == nil)
            withLang(.en) {
                #expect(StoragePageModel.fdaNote(["Mail", "Messages", "Safari"])
                        == "Not shown here: Mail, Messages, Safari — MacDashboard doesn’t have Full Disk Access.")
                #expect(StoragePageModel.fdaNote(["Mail", "Messages", "Safari", "Contacts", "Notes"])
                        == "Not shown here: Mail, Messages, Safari and 2 more — MacDashboard doesn’t have Full Disk Access.")
            }
            withLang(.ru) {
                #expect(StoragePageModel.fdaNote(["Почта", "Сообщения", "Safari", "Контакты", "Заметки"])?.contains("Safari и ещё 2 —") == true)
            }
        }

        @Test func driveStates() {
            #expect(StoragePageModel.driveState(disk("internal", health(nil, nil, \.criticalWarning, 4)), smartctlPresent: true) == .failing)
            #expect(StoragePageModel.driveState(disk("internal", health(nil, nil, \.mediaErrors, 1)), smartctlPresent: true) == .failing)
            #expect(StoragePageModel.driveState(disk("internal", health(\.percentageUsed, 80)), smartctlPresent: true) == .worn(80))
            #expect(StoragePageModel.driveState(disk("internal", health(\.percentageUsed, 79)), smartctlPresent: true) == .ok)
            #expect(StoragePageModel.driveState(disk("internal", nil), smartctlPresent: true) == .unavailable)
            #expect(StoragePageModel.driveState(disk("internal", nil), smartctlPresent: false) == .noData)
            withLang(.en) {
                #expect(StoragePageModel.driveSub(.worn(82), isInternal: true) == "INTERNAL · worn 82%")
                #expect(StoragePageModel.driveSub(.unavailable, isInternal: false) == "EXTERNAL · no data")
                #expect(StoragePageModel.driveSub(.ok, isInternal: true) == "INTERNAL · OK")
                #expect(StoragePageModel.statusLine(.failing)?.hot == true)
                #expect(StoragePageModel.statusLine(.unavailable)?.hot == false)
                #expect(StoragePageModel.statusLine(.ok) == nil)
                #expect(StoragePageModel.wearNote(.worn(85))?.contains("85%") == true)
                #expect(StoragePageModel.wearNote(.ok) == nil)
            }
            let ok = health(), bad = health(nil, nil, \.mediaErrors, 3)
            #expect(StoragePageModel.defaultSelection([disk("internal", ok), disk("/dev/disk4", bad), disk("/dev/disk5", bad)], smartctlPresent: true) == "/dev/disk4")
            #expect(StoragePageModel.defaultSelection([disk("internal", ok), disk("/dev/disk4", nil)], smartctlPresent: true) == "/dev/disk4")
            #expect(StoragePageModel.defaultSelection([disk("/dev/disk4", ok), disk("internal", ok)], smartctlPresent: true) == "internal")
            #expect(StoragePageModel.defaultSelection([disk("/dev/disk4", ok)], smartctlPresent: true) == "/dev/disk4")
            #expect(StoragePageModel.defaultSelection([], smartctlPresent: true) == nil)
        }

        @Test func kvTones() {
            withLang(.en) {
                func tones(_ h: SmartHealth) -> [KVTone] { StoragePageModel.kvTiles(h).map(\.tone) }
                #expect(StoragePageModel.kvTiles(health()).count == 12)
                #expect(tones(health(\.temperatureC, 69))[0] == .plain && tones(health(\.temperatureC, 70))[0] == .amber)
                #expect(tones(health(\.percentageUsed, 79))[1] == .plain && tones(health(\.percentageUsed, 80))[1] == .amber)
                #expect(tones(health(\.percentageUsed, 100))[1] == .hot && tones(health(\.percentageUsed, 104))[1] == .hot)
                #expect(tones(health(\.availableSpare, 4))[2] == .hot && tones(health(\.availableSpare, 10))[2] == .plain)
                #expect(tones(health(nil, nil, \.mediaErrors, 0))[9] == .good && tones(health(nil, nil, \.mediaErrors, 27))[9] == .hot)
                #expect(tones(health(nil, nil, \.errorLogEntries, 0))[10] == .good && tones(health(nil, nil, \.errorLogEntries, 112))[10] == .plain)
                let c0 = StoragePageModel.kvTiles(health()), c1 = StoragePageModel.kvTiles(health(nil, nil, \.criticalWarning, 1))
                #expect(c0[11].value == "no" && c0[11].tone == .good && c1[11].value == "yes" && c1[11].tone == .hot)
                #expect(c0[0].value == "39 °C" && c0[4].value == "1,234" && c0[7].value == "38.2 TB")
                let none = StoragePageModel.kvTiles(nil)
                #expect(none.count == 12 && none.allSatisfy { $0.value == "—" && $0.tone == .muted })
                let partial = StoragePageModel.kvTiles(health(nil, nil, \.dataUnitsRead, nil))
                #expect(partial[7].value == "—" && partial[7].tone == .muted)
            }
        }

        @Test func installAndLayout() {
            withLang(.en) {
                #expect(StoragePageModel.installFailureText(.exitCode(1)) == "Couldn’t install smartmontools: brew exited with code 1.")
                #expect(StoragePageModel.installFailureText(.timedOut).contains("5 min"))
                #expect(StoragePageModel.installFailureText(.noBrew).contains("Homebrew"))
            }
            #expect(StoragePageModel.splitLeftWidth(wide: true) == 240 && StoragePageModel.splitLeftWidth(wide: false) == 200)
            #expect(StoragePageModel.kvColumns(wide: true) == 3 && StoragePageModel.kvColumns(wide: false) == 2)
        }
    }
}
