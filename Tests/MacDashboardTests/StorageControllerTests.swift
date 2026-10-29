// Tests/MacDashboardTests/StorageControllerTests.swift
// ARCH-MODEL-SPLIT block 7: the update check, the folder-size count and the Full Disk Access state through injected
// closures — no softwareupdate, no du, no probe, no disk, no coordinator (except test 17b, over a temp data folder).
// Host and clock fakes: ControllerTestSupport.swift.
import Foundation
import Testing
@testable import MacDashboard

@MainActor final class FakeStorage {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)          // == VirtualClock.base
    static func sizes(countedAt: Date) -> FolderSizes {
        var s = VisualFixture.folderSizes(unreadable: []); s.countedAt = countedAt; return s
    }
    var updatesResult: UpdatesCache? = UpdatesCache(items: [], checkedAt: FakeStorage.t0, durationSeconds: 3)
    var sizesResult: FolderSizes? = FakeStorage.sizes(countedAt: FakeStorage.t0)
    var storedUpdates: UpdatesCache? = nil
    var storedSizes: FolderSizes? = nil
    var denied: [ProtectedLocation] = []
    /// When set, `checkUpdates` / `countFolderSizes` park until released (not cancellation-aware, like a running process).
    var holdCheck = false
    var holdCount = false
    private(set) var checkCalls = 0
    private(set) var countTriggers: [CollectTrigger] = []
    private(set) var probeCalls = 0
    private(set) var openedPanes: [String] = []
    private(set) var updatesSaves: [UpdatesCache] = []
    private(set) var sizesSaves: [FolderSizes] = []
    private(set) var checkParked = false
    private(set) var countParked = false
    private var checkGate: CheckedContinuation<Void, Never>?
    private var countGate: CheckedContinuation<Void, Never>?

    func releaseCheck() { checkGate?.resume(); checkGate = nil }
    func releaseCount() { countGate?.resume(); countGate = nil }

    var deps: StorageController.Dependencies {
        StorageController.Dependencies(
            checkUpdates: {
                self.checkCalls += 1
                if self.holdCheck { await withCheckedContinuation { self.checkGate = $0; self.checkParked = true } }
                return self.updatesResult
            },
            countFolderSizes: { trigger in
                self.countTriggers.append(trigger)
                if self.holdCount { await withCheckedContinuation { self.countGate = $0; self.countParked = true } }
                return self.sizesResult
            },
            deniedLocations: { self.probeCalls += 1; return self.denied },
            openSettingsPane: { self.openedPanes.append($0) },
            loadUpdates: { self.storedUpdates },
            saveUpdates: { self.updatesSaves.append($0) },
            loadFolderSizes: { self.storedSizes },
            saveFolderSizes: { self.sizesSaves.append($0) })
    }
}

extension SerialTests {
    @MainActor struct StorageControllerTests {
        private let t0 = FakeStorage.t0
        private let watched = FakeHost.BlockCall.begin(.folders, showsLoading: true, armsWatchdog: true)
        private let quiet = FakeHost.BlockCall.begin(.folders, showsLoading: false, armsWatchdog: false)

        /// `configure` runs before the controller is built, because `init` loads the caches.
        private func make(_ configure: (FakeStorage) -> Void = { _ in }) -> (StorageController, FakeHost, FakeStorage, VirtualClock) {
            let host = FakeHost(), fake = FakeStorage(), clock = VirtualClock()
            configure(fake)
            return (StorageController(host: host.host, time: clock.source, deps: fake.deps), host, fake, clock)
        }
        private func overlay(_ c: StorageController) -> FullReport {
            var r = FullReport(); c.applyBackground(to: &r); return r
        }
        private let updatesKey = ReportSection.updates.rawValue
        private let homeKey = ReportSection.homeDirs.rawValue
        private let serviceKey = ReportSection.serviceDirs.rawValue

        // 1 (R3, R4)
        @Test func initLoadsBothCachesAndTheOverlayAppliesThem() {
            let stored = FakeStorage.sizes(countedAt: t0 - 1800)
            let (c, host, fake, _) = make {
                $0.storedUpdates = UpdatesCache(items: [], checkedAt: self.t0 - 3600, durationSeconds: 3)
                $0.storedSizes = stored
            }
            let r = overlay(c)
            #expect(r.updates == [] && r.updatesCheckedAt == t0 - 3600 && r.updatesCheckDuration == 3)
            #expect(r.homeDirs == stored.homeDirs && r.serviceDirs == stored.serviceDirs && r.homeCaches == stored.homeCaches)
            #expect(r.folderSizesCountedAt == t0 - 1800 && r.folderSizesCountDuration == 12)
            #expect(r.progress[updatesKey] == true && r.progress[homeKey] == true && r.progress[serviceKey] == true)
            #expect(c.folderSizesCountedAt == t0 - 1800)
            #expect(host.updateCalls == 0 && fake.probeCalls == 0 && fake.checkCalls == 0 && fake.countTriggers.isEmpty)
        }

        // 2 (R3)
        @Test func withoutCachesTheOverlayIsNotDoneOnlyWhileInFlight() async {
            let (c, host, fake, _) = make()
            let r = overlay(c)
            #expect(r.updates == nil && r.homeDirs == nil && r.homeDirsUnreadable == [])
            #expect(r.progress[updatesKey] == true && r.progress[homeKey] == true)
            fake.holdCheck = true; fake.holdCount = true
            c.startUpdateCheckIfNeeded(trigger: .automatic)
            c.startSizeCountIfNeeded(trigger: .automatic)
            #expect(host.report.progress[updatesKey] == false)
            #expect(host.report.progress[homeKey] == false && host.report.progress[serviceKey] == false)
            #expect(host.updateCalls == 2)
            await settle { fake.checkParked && fake.countParked }
            fake.releaseCheck(); fake.releaseCount()
            await c.updateCheckTask?.value; await c.sizeCountTask?.value
        }

        // 3 (R3)
        @Test func updateCheckStartsOnlyWhenNeededAndNeverTwice() async {
            let (c, _, fake, clock) = make { $0.storedUpdates = UpdatesCache(items: [], checkedAt: self.t0 - 3600, durationSeconds: 3) }
            c.startUpdateCheckIfNeeded(trigger: .automatic)
            #expect(fake.checkCalls == 0 && c.updateCheckTask == nil)
            fake.holdCheck = true
            c.startUpdateCheckIfNeeded(trigger: .button)
            await settle { fake.checkParked }
            #expect(fake.checkCalls == 1 && c.isCheckingUpdates)
            c.startUpdateCheckIfNeeded(trigger: .button)
            #expect(fake.checkCalls == 1)
            fake.holdCheck = false
            fake.releaseCheck()
            await c.updateCheckTask?.value
            #expect(!c.isCheckingUpdates)
            await clock.source.sleep(.seconds(7 * 3600))
            c.startUpdateCheckIfNeeded(trigger: .automatic)
            await settle { fake.checkCalls == 2 }
            #expect(fake.checkCalls == 2)
            await c.updateCheckTask?.value
        }

        // 4 (R3)
        @Test func updateCheckSuccessSavesAndMerges() async {
            let (c, host, fake, _) = make()
            c.startUpdateCheckIfNeeded(trigger: .button)
            await c.updateCheckTask?.value
            #expect(fake.updatesSaves == [fake.updatesResult!] && host.mergeCalls == 1 && !c.isCheckingUpdates)
            let r = overlay(c)
            #expect(r.updatesCheckedAt == t0 && r.progress[updatesKey] == true)
        }

        // 5 (R3)
        @Test func updateCheckFailureKeepsTheCacheAndStillMerges() async {
            let (c, host, fake, _) = make {
                $0.storedUpdates = UpdatesCache(items: [], checkedAt: self.t0 - 3600, durationSeconds: 3)
                $0.updatesResult = nil
            }
            c.startUpdateCheckIfNeeded(trigger: .button)
            await c.updateCheckTask?.value
            #expect(fake.updatesSaves.isEmpty && host.mergeCalls == 1)
            #expect(overlay(c).updatesCheckedAt == t0 - 3600 && !c.isCheckingUpdates)
        }

        // 6 (R2, R3)
        @Test func countWithoutCacheShowsTheWaitArmsTheWatchdogAndLands() async {
            let (c, host, fake, _) = make()
            fake.holdCount = true
            c.startSizeCountIfNeeded(trigger: .automatic)
            #expect(host.blockCalls == [watched] && c.isCountingSizes)
            await settle { fake.countParked }
            #expect(fake.countTriggers == [.automatic])
            fake.releaseCount()
            await c.sizeCountTask?.value
            #expect(host.blockCalls.last == .succeed(.folders) && fake.sizesSaves.count == 1)
            #expect(host.mergeCalls == 1 && fake.probeCalls == 1 && !c.isCountingSizes)
            #expect(overlay(c).homeDirs == fake.sizesResult?.homeDirs)
        }

        // 7 (R3)
        @Test func countWithCacheKeepsTheListWithoutWatchdog() async {
            let (c, host, _, _) = make { $0.storedSizes = FakeStorage.sizes(countedAt: self.t0 - 7200) }
            c.startSizeCountIfNeeded(trigger: .automatic)
            #expect(host.blockCalls == [quiet])
            await c.sizeCountTask?.value
        }

        // 8 (R3, R10)
        @Test func countFailureBacksOffAutomaticTriggersForOneHour() async {
            let (c, host, fake, clock) = make { $0.sizesResult = nil }
            c.startSizeCountIfNeeded(trigger: .automatic)
            await c.sizeCountTask?.value
            #expect(host.blockCalls == [watched, .fail(.folders, .noReading)])
            #expect(fake.sizesSaves.isEmpty && host.mergeCalls == 1 && fake.probeCalls == 1)
            c.startSizeCountIfNeeded(trigger: .automatic)
            #expect(fake.countTriggers.count == 1)
            await clock.source.sleep(.seconds(59 * 60))
            c.startSizeCountIfNeeded(trigger: .automatic)
            #expect(fake.countTriggers.count == 1)
            await clock.source.sleep(.seconds(2 * 60))
            c.startSizeCountIfNeeded(trigger: .automatic)
            await settle { fake.countTriggers.count == 2 }
            #expect(fake.countTriggers.count == 2)
            await c.sizeCountTask?.value
            c.startSizeCountIfNeeded(trigger: .button)
            await settle { fake.countTriggers.count == 3 }
            #expect(fake.countTriggers.count == 3)
            await c.sizeCountTask?.value
        }

        // 9 (R3)
        @Test func retryRearmsTheWaitWhileCountingAndOtherwiseForcesAWatchedCount() async {
            let (c, host, fake, _) = make {
                $0.storedSizes = FakeStorage.sizes(countedAt: self.t0 - 600)
                $0.holdCount = true
            }
            c.retryFolderCount()
            #expect(host.blockCalls == [watched])
            await settle { fake.countParked }
            #expect(fake.countTriggers == [.button])
            c.retryFolderCount()
            #expect(host.blockCalls == [watched, watched] && fake.countTriggers.count == 1)
            fake.releaseCount()
            await c.sizeCountTask?.value
            #expect(host.blockCalls.last == .succeed(.folders))
        }

        // 10 (R3, D8)
        @Test func refreshNowIsAButtonCount() async {
            let (c, host, fake, _) = make { $0.storedSizes = FakeStorage.sizes(countedAt: self.t0 - 600) }
            c.refreshNow()
            #expect(host.blockCalls == [quiet])
            await settle { fake.countTriggers.count == 1 }
            #expect(fake.countTriggers == [.button])
            await c.sizeCountTask?.value
        }

        // 11 (R8, R9, R10)
        @Test func scheduleSleeps60sAndSkipsWhilePaused() async {
            let (c, host, fake, clock) = make()
            host.paused = true
            clock.onSleep = { n in
                if n == 2 { host.paused = false }
                if n == 3 { c.stop() }
            }
            c.startSizeSchedule()
            let task = c.scheduleTask
            await task?.value
            #expect(clock.sleeps == [.seconds(60), .seconds(60), .seconds(60)])
            await settle { fake.countTriggers.count == 1 }
            #expect(fake.countTriggers == [.automatic])
            #expect(c.scheduleTask == nil && task?.isCancelled == true)
        }

        // 12 (R3)
        @Test func trashWasEmptiedDropsTheEntrySavesMergesAndTheNextCountClears() async {
            let stored = FakeStorage.sizes(countedAt: t0 - 600)
            let trash = FileManager.default.homeDirectoryForCurrentUser.path + "/.Trash"
            let trashBytes = stored.homeDirs.first { $0.path == trash }?.bytes
            #expect(trashBytes != nil)
            let (c, host, fake, clock) = make { $0.storedSizes = stored }
            c.trashWasEmptied()
            #expect(c.trashFreedBytes == trashBytes && c.trashEmptiedAt == clock.now)
            #expect(fake.sizesSaves.count == 1 && !fake.sizesSaves[0].homeDirs.contains { $0.path.hasSuffix("/.Trash") })
            #expect(host.mergeCalls == 1)
            #expect(overlay(c).homeDirs?.contains { $0.path.hasSuffix("/.Trash") } == false)
            c.trashWasEmptied()
            #expect(fake.sizesSaves.count == 1 && host.mergeCalls == 2 && c.trashFreedBytes == trashBytes)
            c.refreshNow()
            await c.sizeCountTask?.value
            #expect(c.trashFreedBytes == nil && c.trashEmptiedAt == nil)
        }

        // 13 (R3)
        @Test func trashWasEmptiedWithoutACountOnlyStampsAndMerges() {
            let (c, host, fake, clock) = make()
            c.trashWasEmptied()
            #expect(c.trashFreedBytes == nil && c.trashEmptiedAt == clock.now)
            #expect(fake.sizesSaves.isEmpty && host.mergeCalls == 1)
        }

        // 14 (R3)
        @Test func reprobeRecountsOnlyWhenAccessWasGranted() async {
            let (c, _, fake, _) = make { $0.storedSizes = FakeStorage.sizes(countedAt: self.t0 - 600) }
            let table = ProtectedLocations.table
            fake.denied = Array(table.prefix(3))
            c.reprobeProtectedLocations()
            #expect(c.fdaDenied.count == 3 && fake.countTriggers.isEmpty)
            fake.denied = Array(table.prefix(1))
            c.reprobeProtectedLocations()
            await settle { fake.countTriggers.count == 1 }
            #expect(fake.countTriggers == [.button] && c.fdaDenied.count == 1)
            await c.sizeCountTask?.value
            fake.denied = Array(table.prefix(3))
            c.reprobeProtectedLocations()
            #expect(fake.countTriggers.count == 1)
            fake.denied = []
            c.reprobeProtectedLocations()
            await settle { fake.countTriggers.count == 2 }
            #expect(fake.countTriggers.count == 2)
            await c.sizeCountTask?.value
        }

        // 15 (R3)
        @Test func fullDiskAccessButtonWaitsForTheReturn() {
            let (c, _, fake, _) = make()
            c.openFullDiskAccessSettings()
            #expect(c.fdaAwaitingReturn && fake.openedPanes == [AdvicePanes.fullDiskAccess])
            c.appDidBecomeActive()
            #expect(!c.fdaAwaitingReturn && fake.probeCalls == 1)
        }

        // 16 (R8)
        @Test func stopCancelsTheCheckAndTheCountAndNothingLands() async {
            let (c, host, fake, _) = make()
            fake.holdCheck = true; fake.holdCount = true
            c.startUpdateCheckIfNeeded(trigger: .button)
            c.startSizeCountIfNeeded(trigger: .button)
            await settle { fake.checkParked && fake.countParked }
            let checkTask = c.updateCheckTask, countTask = c.sizeCountTask
            c.stop()
            #expect(c.updateCheckTask == nil && c.sizeCountTask == nil)
            #expect(checkTask?.isCancelled == true && countTask?.isCancelled == true)
            #expect(!c.isCheckingUpdates && !c.isCountingSizes)
            fake.releaseCheck(); fake.releaseCount()
            await checkTask?.value; await countTask?.value
            #expect(fake.updatesSaves.isEmpty && fake.sizesSaves.isEmpty && host.mergeCalls == 0)
            #expect(host.blockCalls == [watched] && fake.probeCalls == 0)
            fake.holdCheck = false; fake.holdCount = false
            c.startUpdateCheckIfNeeded(trigger: .button)
            c.startSizeCountIfNeeded(trigger: .button)
            await settle { fake.checkCalls == 2 && fake.countTriggers.count == 2 }
            #expect(fake.checkCalls == 2 && fake.countTriggers.count == 2)
            await c.updateCheckTask?.value; await c.sizeCountTask?.value
            #expect(host.mergeCalls == 2)
        }

        // 17 (R4, R11, R2, R5)
        @Test func fixturesAndTheCoordinatorWiring() {
            // a. controller fixtures
            let (c, host, _, _) = make()
            c.applyFixture(checkingUpdates: true)
            #expect(c.isCheckingUpdates && host.updateCalls == 0)
            c.applyFixture(fdaDenied: Array(ProtectedLocations.table.prefix(2)))
            #expect(c.fdaDenied.count == 2)
            host.report.updatesCheckedAt = t0 - 99
            let s = VisualFixture.folderSizes()
            c.applyFixture(folderSizes: s)
            #expect(host.report.homeDirs == s.homeDirs && host.report.folderSizesCountedAt == s.countedAt)
            #expect(host.report.updatesCheckedAt == t0 - 99 && host.updateCalls == 1)
            #expect(c.folderSizesCountedAt == s.countedAt)
            c.applyFixture(folderSizes: nil)
            #expect(host.report.homeDirs == nil && host.report.progress[homeKey] == true)

            // b. the coordinator over a temp data folder holding both cache files
            let (d, name) = makeIsolatedDefaults()
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-storage-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { removeIsolatedDefaults(d, name); try? FileManager.default.removeItem(at: dir) }
            let ref = VisualFixture.referenceDate
            try? FolderSizesCacheStore.save(VisualFixture.folderSizes(), to: dir.appendingPathComponent("folder_sizes_cache.json"))
            try? UpdatesCacheStore.save(UpdatesCache(items: [], checkedAt: ref, durationSeconds: 4),
                                        to: dir.appendingPathComponent("updates_cache.json"))
            let m = AppModel(dataDirectory: dir, settings: AppSettings(defaults: d), time: VirtualClock().source)
            #expect(m.storage.folderSizesCountedAt == ref)
            #expect(m.blockState(.folders).phase == .ok(at: ref))
            m.report = FullReport()
            m.reportHost.mergeBackgroundIntoCommitted()
            #expect(m.report.updatesCheckedAt == ref && m.report.homeDirs != nil)
            m.reportHost.beginBlock(.folders, false, false)           // no watchdog: armsWatchdog true would arm a real 10 s sleep
            #expect(m.blockState(.folders).phase == .ok(at: ref) && m.blockState(.folders).deadline != nil)
            m.reportHost.failBlock(.folders, .noReading)
            #expect(m.blockState(.folders).phase == .failed(.noReading, lastGoodAt: ref))
            m.reportHost.succeedBlock(.folders)
            if case .ok = m.blockState(.folders).phase {} else { Issue.record("folders block is not .ok after succeedBlock") }
        }

        // 18 (R13) Opt-in: MACDASH_LIVE=1 swift test --filter liveCanaryStorage
        // Reads only. Writes its two cache files into a temp folder, never Application Support. softwareupdate contacts Apple (pre-existing, disclosed network use).
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryStorage() async {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-storage-live-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let live = StorageController.Dependencies.live(directory: dir, openSettingsPane: { _ in })
            let host = FakeHost()
            let c = StorageController(host: host.host, time: .live, deps: live)

            // FDA: the probe against /bin/ls on each existing protected directory.
            let denied = live.deniedLocations()
            print("liveCanary fdaDenied=\(denied.map(\.relativePath))")
            var refused: Set<String> = []
            for loc in ProtectedLocations.table {
                let path = NSHomeDirectory() + "/" + loc.relativePath
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let out = await CommandRunner.run("/bin/ls", [path], timeout: 10)
                let isRefused = out.termination != .exited(0) && out.stderrHead.contains("Operation not permitted")
                print("liveCanary ls \(loc.relativePath) -> \(out.termination) refused=\(isRefused)")
                if isRefused { refused.insert(loc.relativePath) }
            }
            #expect(Set(denied.map(\.relativePath)) == refused)

            // Count.
            c.startSizeCountIfNeeded(trigger: .button)
            await c.sizeCountTask?.value
            var r = FullReport(); c.applyBackground(to: &r)
            let homeDirs = r.homeDirs ?? []
            print("liveCanary count countedAt=\(String(describing: r.folderSizesCountedAt)) duration=\(String(describing: r.folderSizesCountDuration)) homeDirs=\(homeDirs.count) top3=\(homeDirs.prefix(3).map { "\($0.path):\($0.bytes)" }) serviceDirs=\(r.serviceDirs?.count ?? -1) homeUnreadable=\(r.homeDirsUnreadable.count) homeNotMeasured=\(r.homeDirsNotMeasured.count) serviceNotMeasured=\(r.serviceDirsNotMeasured.count) blockCalls=\(host.blockCalls)")
            #expect(host.blockCalls.last == .succeed(.folders) && host.mergeCalls == 1)
            #expect(!homeDirs.isEmpty)
            #expect(zip(homeDirs, homeDirs.dropFirst()).allSatisfy { $0.bytes >= $1.bytes })
            #expect(homeDirs.allSatisfy { $0.bytes >= 0 })
            #expect((r.folderSizesCountDuration ?? .infinity) <= ReportCollector.folderSizesDeadline + 5)
            // (1) the smallest measured home folder against du.
            if let smallest = homeDirs.filter({ !r.homeDirsNotMeasured.contains($0.path) }).min(by: { $0.bytes < $1.bytes }) {
                let du = await CommandRunner.run("/usr/bin/du", ["-sk", smallest.path], timeout: 60)
                let kib = Int64(du.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? "") ?? -1
                let duBytes = kib * 1024
                print("liveCanary du \(smallest.path) controller=\(smallest.bytes) du=\(duBytes)")
                #expect(kib >= 0 && abs(duBytes - smallest.bytes) <= max(smallest.bytes / 10, 64 << 20))
            } else {
                Issue.record("no measured home folder to compare with du")
            }
            // (2) the sum against the home volume's capacity.
            let capacity = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity
            let sum = homeDirs.reduce(Int64(0)) { $0 + $1.bytes }
            print("liveCanary sum=\(sum) volumeTotalCapacity=\(String(describing: capacity))")
            #expect(capacity != nil && sum <= Int64(capacity ?? 0))
            // (3) the saved cache.
            let saved = FolderSizesCacheStore.load(from: dir.appendingPathComponent("folder_sizes_cache.json"))
            #expect(saved != nil)
            if let saved, let at = c.folderSizesCountedAt { #expect(abs(saved.countedAt.timeIntervalSince(at)) < 1) }

            // Update check.
            c.startUpdateCheckIfNeeded(trigger: .button)
            await c.updateCheckTask?.value
            c.applyBackground(to: &r)
            if r.updatesCheckedAt == nil {
                print("liveCanary updates: check failed (offline?)")
            } else {
                let items = r.updates ?? []
                print("liveCanary updates n=\(items.count) titles=\(items.map(\.title)) checkedAt=\(String(describing: r.updatesCheckedAt)) duration=\(String(describing: r.updatesCheckDuration))")
                let sw = await CommandRunner.run("/usr/sbin/softwareupdate", ["-l"], timeout: 120)
                let labels = sw.stdout.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("* Label:") }.count
                print("liveCanary softwareupdate -l labels=\(labels)")
                #expect(labels == items.count)
                #expect(UpdatesCacheStore.load(from: dir.appendingPathComponent("updates_cache.json")) != nil)
            }
            c.stop()
        }
    }
}
