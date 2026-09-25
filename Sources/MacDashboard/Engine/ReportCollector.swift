// Engine/ReportCollector.swift
// Full read-only system report. Each section is an independent step with its own
// timeout; a section that fails leaves its field nil and still marks progress done,
// so a denied permission or absent tool never blocks the rest. All sections run in one
// concurrent group; the macOS update check is not part of the pass (it lives in
// `checkUpdates()`, which DashboardModel runs in the background).
// SPEC §5.2. Nothing here modifies the system.
//
// Sections are async: subprocess waits suspend the caller's Task instead of
// blocking a thread, so many can run at once without starving the cooperative pool.

import Foundation

/// Who asked for a report pass (COLLECT-FASTPATH). Only the «Обновить отчёт» button is
/// `.button`; everything else (launch, language switch, coalesced follow-ups) is automatic.
enum CollectTrigger: Sendable, Equatable {
    case button, automatic
    var commandQoS: CommandQoS { self == .button ? .userInitiated : .utility }
    var taskPriority: TaskPriority { self == .button ? .userInitiated : .utility }
    /// Coalescing: a pending follow-up keeps the strongest trigger that asked for it.
    static func merged(_ pending: CollectTrigger?, _ new: CollectTrigger) -> CollectTrigger {
        (pending == .button || new == .button) ? .button : .automatic
    }
}

/// Persisted result of the last SUCCESSFUL `softwareupdate -l`
/// (~/Library/Application Support/MacDashboard/updates_cache.json).
struct UpdatesCache: Codable, Equatable {
    var items: [String]          // [] = up to date
    var checkedAt: Date
    var durationSeconds: Double
}

enum UpdatesCacheStore {
    /// Missing, unreadable or undecodable file => nil (treated as "never checked").
    static func load(from url: URL) -> UpdatesCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UpdatesCache.self, from: data)
    }

    /// Atomic write, file 0600 — same permissions rule as ReportWriter.write / HistoryStore.save.
    static func save(_ cache: UpdatesCache, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum ReportSection: String, CaseIterable {
    case system, snapshots, homeDirs, serviceDirs, security, tmDest, spotlight
    case crashes, brew, updates, autostart, smart, energy, battery
}

final class ReportCollector {

    /// A section's result: which section, and how to fold it into the report.
    private struct Outcome {
        let section: ReportSection
        let mutate: (inout FullReport) -> Void
    }

    /// Freshness window for the session brew-outdated cache (Block N5): `brew
    /// outdated` costs ~30 s and its result only changes via brew operations, so
    /// repeat manual refreshes within this window reuse the previous result.
    static let brewCacheWindow: TimeInterval = 600

    /// macOS update-check cache window (COLLECT-FASTPATH): 6 h.
    static let updatesCacheWindow: TimeInterval = 6 * 60 * 60
    /// Same rule as isBrewCacheFresh (future timestamp = stale).
    static func isUpdatesCacheFresh(checkedAt: Date?, now: Date, window: TimeInterval = updatesCacheWindow) -> Bool {
        isBrewCacheFresh(collectedAt: checkedAt, now: now, window: window)
    }
    /// Start a background update check? Never two at once; the button always wants one;
    /// automatic triggers only when the cache is absent or stale.
    static func shouldStartUpdateCheck(trigger: CollectTrigger, checkedAt: Date?, inFlight: Bool, now: Date) -> Bool {
        !inFlight && (trigger == .button || !isUpdatesCacheFresh(checkedAt: checkedAt, now: now))
    }
    /// Duration -> seconds.
    static func seconds(_ d: Duration) -> TimeInterval {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    /// Pure (Checks-tested): true iff `collectedAt` exists and lies within
    /// `[now - window, now]`. A future timestamp (clock rolled back) counts as
    /// stale so a bad clock can never pin the cache forever.
    static func isBrewCacheFresh(collectedAt: Date?, now: Date,
                                 window: TimeInterval = brewCacheWindow) -> Bool {
        guard let collectedAt else { return false }
        let age = now.timeIntervalSince(collectedAt)
        return age >= 0 && age < window
    }

    /// Age window for crash reports (V2-CRASH-SIGNAL): anything older is not
    /// collected at all, so a stale crash cannot keep a surface loud forever.
    static let crashAgeWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Upper bound on crash GROUPS kept (applied after grouping, so a runaway
    /// process keeps its true count) — the old 15-file cap, moved.
    static let crashMaxGroups = 15

    /// Both directories macOS writes crash reports to, in dedup priority order
    /// (V2-CRASH-DETECT / finding A1). The per-user one needs Full Disk Access and
    /// on many machines is empty; the system one is world-readable and is the ONLY
    /// place kernel panics (`.panic`) ever land, so reading just the per-user one
    /// meant a panic was never seen at all.
    static var crashReportDirectories: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
         URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true)]
    }

    /// Pure (Checks-tested): true iff `mtime` lies within `[now - window, now]`.
    /// A future mtime (clock rolled back) counts as stale — same rule as
    /// `isBrewCacheFresh`, so a bad clock can never pin a report in the list.
    static func isCrashRecent(mtime: Date, now: Date,
                              window: TimeInterval = crashAgeWindow) -> Bool {
        let age = now.timeIntervalSince(mtime)
        return age >= 0 && age < window
    }

    /// Pure (Checks-tested): process name out of a DiagnosticReports filename.
    /// macOS names these `<process>-<YYYY-MM-DD>-<HHMMSS>.<ips|crash|panic>`;
    /// the process part may itself contain dashes, dots and spaces, so only an
    /// end-anchored date-time suffix is stripped. Total by construction: an
    /// unrecognized shape yields the extension-stripped stem, and a stem that
    /// is only a timestamp yields that stem rather than an empty row label.
    static func crashProcessName(from filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        var name = stem
        if let r = stem.range(of: #"-\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) {
            name = String(stem[stem.startIndex..<r.lowerBound])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let fallback = stem.trimmingCharacters(in: .whitespaces)
        return fallback.isEmpty ? filename : fallback
    }

    /// Pure (Checks-tested): is this report a kernel panic (`.panic`) rather than
    /// an app-level `.ips`/`.crash`? A panic means the whole machine went down, so
    /// it raises attention whatever process logged it — and the extension is only
    /// visible here, at collection time, which is why the bit is carried into
    /// `CrashGroup.isPanic` (V2-CRASH-SIGNAL).
    static func crashIsPanic(from filename: String) -> Bool {
        (filename as NSString).pathExtension.lowercased() == "panic"
    }

    /// Pure (Checks-tested): must this group reach the user? Exactly the two cases
    /// from V2-CRASH-SIGNAL — a kernel panic, whatever process logged it, or a crash
    /// of MacDashboard itself. Single source of truth on purpose (V2-CRASH-DETECT):
    /// `crashGroups` protects these groups from the group cap and `Assessment` raises
    /// attention for them, and those two rules must never drift apart.
    static func crashRaisesAttention(_ group: CrashGroup) -> Bool {
        group.isPanic || group.process == AppInfo.name
    }

    /// Report kinds macOS writes into DiagnosticReports that are NOT process crashes.
    /// `JetsamEvent-*.ips` is the memory-pressure kill log: the kernel reclaiming
    /// memory, already visible on the memory card, and nothing the user acts on here
    /// (V2-CRASH-REVEAL, item 3). Entries MUST be lowercase — `crashIsProcessCrash`
    /// lowercases the filename before comparing. Keep this list small and evidence-
    /// backed: add a prefix only when a real report of that kind has been seen.
    static let nonCrashReportPrefixes = ["jetsamevent-"]

    /// Pure (Checks-tested): is this report an actual process/kernel crash, or one of
    /// the non-crash kinds above? Total by construction: an empty or unrecognized
    /// filename is treated as a crash (fail-visible, never fail-silent).
    static func crashIsProcessCrash(from filename: String) -> Bool {
        let lower = filename.lowercased()
        return !nonCrashReportPrefixes.contains { lower.hasPrefix($0) }
    }

    /// One directory's crash-report filenames tagged with that directory's absolute
    /// path. ARRAY ORDER IS DEDUP PRIORITY: `crashReportDirectories` puts the per-user
    /// directory first, so its copy of a report wins over the system one and its path
    /// is what the group reveals (V2-CRASH-REVEAL).
    typealias CrashDirectoryListing = (directory: String, files: [(name: String, mtime: Date)])

    /// Pure (Checks-tested): one entry per report FILE NAME, first occurrence wins.
    /// The collector concatenates two directories (see `crashReportDirectories`) and
    /// the same report could plausibly be listed by both; without this it would be
    /// counted twice and inflate a process's crash count. Input order IS the priority
    /// order, so the per-user copy wins over the system one. The surviving entry also
    /// carries the directory it was listed in, which is what `CrashGroup.directory`
    /// ends up holding.
    static func crashDedup(byDirectory: [CrashDirectoryListing]) -> [(name: String, mtime: Date, directory: String)] {
        var seen = Set<String>()
        var out: [(name: String, mtime: Date, directory: String)] = []
        for listing in byDirectory {
            for f in listing.files where seen.insert(f.name).inserted {
                out.append((name: f.name, mtime: f.mtime, directory: listing.directory))
            }
        }
        return out
    }

    /// Pure (Checks-tested): the whole crash pipeline except the directory read —
    /// drop reports listed by more than one directory, drop files outside the window,
    /// collapse repeats per process, mark a group as a panic group if ANY of its
    /// reports is a `.panic`, order by count (desc) then name (asc, so ties are
    /// deterministic), cap the group count — keeping panic/own-app groups first so the
    /// cap can never discard them (V2-CRASH-DETECT). Non-crash report kinds are dropped
    /// before grouping (item 3), and a group's `directory` is the directory of its
    /// FIRST surviving report — same "first occurrence wins" law as `crashDedup`, so a
    /// process with reports in both directories reveals the per-user one, which does
    /// contain at least one of them.
    static func crashGroups(byDirectory: [CrashDirectoryListing], now: Date,
                            window: TimeInterval = crashAgeWindow,
                            maxGroups: Int = crashMaxGroups) -> [CrashGroup] {
        var acc: [String: (count: Int, isPanic: Bool, directory: String)] = [:]
        for f in crashDedup(byDirectory: byDirectory)
            where crashIsProcessCrash(from: f.name)
                  && isCrashRecent(mtime: f.mtime, now: now, window: window) {
            let name = crashProcessName(from: f.name)
            if var prev = acc[name] {
                prev.count += 1
                prev.isPanic = prev.isPanic || crashIsPanic(from: f.name)
                acc[name] = prev                      // directory: first surviving report wins
            } else {
                acc[name] = (count: 1, isPanic: crashIsPanic(from: f.name), directory: f.directory)
            }
        }
        let sorted = acc
            .map { CrashGroup(process: $0.key, count: $0.value.count,
                              isPanic: $0.value.isPanic, directory: $0.value.directory) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.process < $1.process
            }
        // The cap must never be able to drop the groups this feature exists for
        // (V2-CRASH-DETECT / finding A2): panics and our own crashes are single by
        // nature, so ordering by count alone put them last and truncated them first.
        // They also lead the returned list, because the card renders only its first
        // five rows — surviving the cap in 14th place is still invisible.
        let notable = sorted.filter(crashRaisesAttention)
        let rest = sorted.filter { !crashRaisesAttention($0) }
        return Array((notable + rest).prefix(maxGroups))
    }

    func collect(skipSlow: Bool = false,
                 cachedBrew: (version: String??, outdated: [String]?)? = nil,
                 onSection: @escaping @MainActor (FullReport) -> Void) async -> FullReport {
        // Task cancellation of the caller propagates into the section task groups and
        // from there into every `CommandRunner.run`, which kills the group or skips the spawn.
        await collectBody(skipSlow: skipSlow, cachedBrew: cachedBrew, onSection: onSection)
    }

    private func collectBody(skipSlow: Bool,
                             cachedBrew: (version: String??, outdated: [String]?)?,
                             onSection: @escaping @MainActor (FullReport) -> Void) async -> FullReport {
        let clock = ContinuousClock()
        let passStart = clock.now
        var report = FullReport()
        report.createdAt = Date()
        let initial = report
        await MainActor.run { onSection(initial) }

        // All sections run concurrently in one group; the merges are serialized by the for-await loop.
        var jobs: [() async -> Outcome] = [
            { await self.collectSystem() },
            { await self.collectSnapshots() },
            { await self.collectSecurity() },
            { await self.collectTMDest() },
            { await self.collectSpotlight() },
            { self.collectCrashes() },
            { await self.collectAutostart() },
            { await self.collectSmart() },
            { await self.collectEnergy() },
            { await self.collectBattery() },
        ]
        if !skipSlow {
            jobs += [
                { await self.collectHomeDirs() },
                { await self.collectServiceDirs() },
                { await self.collectBrew(cached: cachedBrew) },
            ]
        }
        await withTaskGroup(of: (Outcome, TimeInterval).self) { group in
            for job in jobs {
                group.addTask {
                    let t0 = clock.now
                    let o = await job()
                    return (o, Self.seconds(clock.now - t0))
                }
            }
            for await (outcome, secs) in group {
                outcome.mutate(&report)
                report.progress[outcome.section.rawValue] = true
                report.sectionDurations[outcome.section.rawValue] = secs
                let snap = report
                await MainActor.run { onSection(snap) }
            }
        }
        report.passDuration = Self.seconds(clock.now - passStart)
        return report
    }

    // MARK: - system

    private func collectSystem() async -> Outcome {
        var info = SystemInfo()
        var failures: [ParseFailure] = []
        if let data = FileManager.default.contents(atPath: "/System/Library/CoreServices/SystemVersion.plist"),
           let parsed = Parsers.systemVersion(plist: data) {
            info.osName = parsed.osName; info.osVersion = parsed.osVersion; info.osBuild = parsed.osBuild
        }
        if let hw = await ParsedCommand.spHardware.run().text {
            if let h = Parsers.hardwareProfile(json: Data(hw.utf8)) {
                info.modelName = h.modelName; info.modelId = h.modelId; info.chip = h.chip
                info.cores = h.cores; info.memBytes = h.memBytes
            } else if let f = ParseFailure(.spHardware, stdout: hw) {
                failures.append(f)
            }
        }
        if info.chip == nil, let brand = Self.sysctlString("machdep.cpu.brand_string") {
            let s = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { info.chip = s }
        }
        if let up = await ParsedCommand.uptime.run().text {
            info.uptime = Parsers.uptimeHuman(up)
            if info.uptime == nil, let f = ParseFailure(.uptime, stdout: up) { failures.append(f) }
        }
        info.hostName = ProcessInfo.processInfo.hostName
        let has = info.osName != nil || info.modelName != nil || info.chip != nil
        return Outcome(section: .system) { $0.system = has ? info : nil; $0.parseFailures += failures }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    // MARK: - Time Machine local snapshots

    static func localSnapshotNames(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }
    }

    private func collectSnapshots() async -> Outcome {
        let out = await CommandRunner.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 15).text
        let names = out.map(Self.localSnapshotNames)
        return Outcome(section: .snapshots) { $0.snapshots = names }
    }

    // MARK: - security

    private func collectSecurity() async -> Outcome {
        let (s, failures) = await securityInfoReporting()
        return Outcome(section: .security) { $0.security = s; $0.parseFailures += failures }
    }

    /// The actual security-state collection logic, factored out of `collectSecurity()`
    /// so a manual re-check (DashboardModel's `enableFirewallNow()`, AR wave 2) can call
    /// it directly without going through the `Outcome` plumbing, mirroring
    /// `collectSmartDisks()`/`collectBrewInfo()` above.
    func collectSecurityInfo() async -> SecurityState {
        await securityInfoReporting().state
    }

    private func securityInfoReporting() async -> (state: SecurityState, failures: [ParseFailure]) {
        var s = SecurityState()
        var failures: [ParseFailure] = []
        if let t = await ParsedCommand.fdesetup.run().text {
            s.fileVault = Parsers.fileVaultStatus(t)
            if s.fileVault == nil, let f = ParseFailure(.fdesetup, stdout: t) { failures.append(f) }
        }
        if let t = await ParsedCommand.spctl.run().text {
            s.gatekeeper = Parsers.gatekeeperStatus(t)
            if s.gatekeeper == nil, let f = ParseFailure(.spctl, stdout: t) { failures.append(f) }
        }
        if let t = await ParsedCommand.csrutil.run().text {
            s.sip = Parsers.sipStatus(t)
            if s.sip == nil, let f = ParseFailure(.csrutil, stdout: t) { failures.append(f) }
        }
        let fwText = await ParsedCommand.socketfilterfw.run().text
        if let fwText, let v = Parsers.firewallStatus(fwText) {
            s.firewall = v
        } else {
            if let fwText, let f = ParseFailure(.socketfilterfw, stdout: fwText) { failures.append(f) }
            if let t = await CommandRunner.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.alf", "globalstate"], timeout: 10).text {
                s.firewall = Parsers.firewallStatus(t)
            }
        }
        return (s, failures)
    }

    // MARK: - Time Machine destination

    private func collectTMDest() async -> Outcome {
        let (value, failure) = await tmDestInfoReporting()
        guard let value else {
            return Outcome(section: .tmDest) { if let failure { $0.parseFailures.append(failure) } }   // leave .none
        }
        return Outcome(section: .tmDest) { $0.tmDest = .some(value); if let failure { $0.parseFailures.append(failure) } }
    }

    /// The actual Time Machine destination collection logic, factored out of
    /// `collectTMDest()` so the live SMART refresh loop (DashboardModel) can call it
    /// directly without going through the `Outcome` plumbing (which mutates a
    /// `FullReport` rather than returning a value), mirroring `collectSmartDisks()` above.
    ///
    /// Double optional: outer `nil` = command failed / not checked (leave `report.tmDest`
    /// untouched); `.some(nil)` = checked, no destination configured; `.some(x)` = configured.
    func collectTMDestInfo() async -> TMDestination?? {
        await tmDestInfoReporting().value
    }

    private func tmDestInfoReporting() async -> (value: TMDestination??, failure: ParseFailure?) {
        // `-X` prints a plist; empty stdout is not evidence of "no destination", so it stays "not checked".
        guard let out = await ParsedCommand.tmutilDestinationInfo.run().nonEmptyText else {
            return (nil, nil)
        }
        switch Parsers.tmDestination(plist: Data(out.utf8)) {
        case .undecodable: return (nil, ParseFailure(.tmutilDestinationInfo, stdout: out))
        case .notConfigured: return (.some(nil), nil)
        case .configured(var d):
            await applyLastBackup(to: &d)
            return (.some(d), nil)
        }
    }

    /// Fills in `dest.lastBackup` via a fallback chain, since `tmutil latestbackup`
    /// exits 0 with silently empty stdout (⇒ `CommandRunner.run` returns `""`; the
    /// `!s.isEmpty` guard below is what routes on to the next source) without Full Disk
    /// Access, which this ad-hoc-signed, non-entitled app does not have:
    ///   1. `tmutil latestbackup`'s path timestamp (works once FDA is granted).
    ///   2. `diskutil apfs listSnapshots <mount>`'s latest `.backup` snapshot name —
    ///      goes through diskarbitrationd, a DIFFERENT privilege gate than the one
    ///      that blocks `tmutil`/direct TM-file reads, so this actually works
    ///      without FDA (verified empirically on an FDA-denied build of this app;
    ///      cross-checked against `tmutil latestbackup` run with FDA — same
    ///      timestamp). This is the fallback that matters for the un-entitled app.
    ///   3. `/Library/Preferences/com.apple.TimeMachine.plist`'s `SnapshotDates`, read
    ///      directly (no `defaults`/`PlistBuddy` subprocess). NOTE: despite 644
    ///      root:wheel permissions, this file IS gated by Full Disk Access, same as
    ///      `tmutil latestbackup` — verified empirically: a fresh, FDA-denied build
    ///      of this app got `open() -> EPERM` on this exact path. So this fallback
    ///      is a no-op for a never-authorized app in practice (source #2 above
    ///      already covers the mounted case for such an app), but still earns its
    ///      keep for the case source #2 can't reach: destination UNMOUNTED (disk
    ///      unplugged) while the user *has* granted FDA — `diskutil apfs
    ///      listSnapshots` needs a live mount, the plist doesn't.
    ///   4. An honest reason no date is available at all, distinguishing three cases:
    ///      "disk not mounted" (destinationinfo omits Mount Point when unmounted, per
    ///      tmutil(8)); "mounted, diskutil ran fine, zero completed `.backup` snapshots
    ///      exist yet" (step 2 returned `.noBackupsFound` — a real fact about the
    ///      destination, not a permissions problem); and "mounted but date unreadable"
    ///      (no FDA and diskutil's output didn't even parse) — so the card never
    ///      blames Full Disk Access for a destination that's simply never been backed
    ///      up to, and never falls back to a bare "—" either.
    ///
    /// Known limitation: if FDA is granted AND the disk is unmounted, step 3 can
    /// still succeed with a (necessarily stale) cached date, so the honest "diск
    /// не подключён" message in step 4 never fires in that specific combination.
    /// This is judged acceptable — a stale-but-real date is more useful than a
    /// unmounted-disk notice once the user already trusts the app with FDA — and
    /// is moot in the common no-FDA deployment, where the plist is gated identically
    /// to everything else and step 4's mount check is what actually decides the message.
    /// V2-TM-CONNSTATE: the card no longer depends on step 4 to say so — the Time Machine
    /// card renders a separate "no connection right now" row straight off `mountPoint == nil`,
    /// so a stale-but-real date from step 3 is now shown correctly labelled as the LAST KNOWN
    /// one rather than as the current state.
    private func applyLastBackup(to dest: inout TMDestination) async {
        if let last = await CommandRunner.run("/usr/bin/tmutil", ["latestbackup"], timeout: 15).text {
            let s = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.lowercased().contains("no backup") {
                dest.lastBackupUnavailableReason = .noBackupsYet
                return
            }
            if !s.isEmpty, let date = Parsers.tmLatestBackupDate(fromPath: s) {
                dest.lastBackup = Parsers.formatTMBackupDate(date)
                return
            }
        }
        var diskutilFoundZeroBackups = false
        if let mount = dest.mountPoint,
           let out = await CommandRunner.run("/usr/sbin/diskutil", ["apfs", "listSnapshots", mount], timeout: 15).text {
            switch Parsers.tmDiskutilLatestBackupDate(out) {
            case .found(let date):
                dest.lastBackup = Parsers.formatTMBackupDate(date)
                return
            case .noBackupsFound:
                // diskutil ran fine and produced a recognizable (empty) listing — the
                // destination genuinely has zero completed backups yet, distinct from
                // "date unreadable due to no Full Disk Access" below. Don't return yet:
                // step 3 (plist) may still surface a stale-but-real date, matching this
                // function's existing FDA-granted-but-unmounted precedent.
                diskutilFoundZeroBackups = true
            case .unparseable:
                break
            }
        }
        if let plistDate = readTMPlistLatestSnapshotDate() {
            dest.lastBackup = Parsers.formatTMBackupDate(plistDate)
            return
        }
        if dest.mountPoint == nil {
            dest.lastBackupUnavailableReason = .diskNotConnected
        } else if diskutilFoundZeroBackups {
            dest.lastBackupUnavailableReason = .noCompletedBackups
        } else {
            dest.lastBackupUnavailableReason = .dateUnavailableNoFDA
        }
    }

    /// See `applyLastBackup` doc comment: reads the system TimeMachine prefs plist
    /// directly, no shell-out needed.
    private func readTMPlistLatestSnapshotDate() -> Date? {
        let path = "/Library/Preferences/com.apple.TimeMachine.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any] else { return nil }
        return Parsers.tmPlistLatestSnapshotDate(root)
    }

    // MARK: - spotlight

    private func collectSpotlight() async -> Outcome {
        let out = await CommandRunner.run("/usr/bin/mdutil", ["-s", "/"], timeout: 10).nonEmptyText
        let text: String? = out.map { raw in
            if raw.lowercased().contains("indexing enabled") { return L.reportCollectorSpotlightEnabled }
            if raw.lowercased().contains("indexing disabled") { return L.reportCollectorSpotlightDisabled }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Outcome(section: .spotlight) { $0.spotlight = text }
    }

    // MARK: - crashes (FileManager, no shell)

    private func collectCrashes() -> Outcome {
        let byDirectory = Self.crashReportDirectories.map {
            (directory: $0.path, files: Self.crashFiles(in: $0))
        }
        let groups = Self.crashGroups(byDirectory: byDirectory, now: Date())
        return Outcome(section: .crashes) { $0.crashes = groups }
    }

    /// One directory's crash reports as (name, mtime). Impure and deliberately not
    /// Checks-covered — the pure/impure seam of this section is exactly here.
    /// Non-recursive on purpose: both directories carry a `Retired/` subdirectory of
    /// reports macOS has already rotated out, which the 7-day window would drop
    /// anyway. An absent or TCC-refused directory yields [] (`try?`), which is the
    /// right degradation: the other directory still answers, and a refused per-user
    /// directory cannot hide a kernel panic — those only ever land in the system one.
    private static func crashFiles(in dir: URL) -> [(name: String, mtime: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        func mtime(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return items
            .filter { $0.pathExtension == "ips" || $0.pathExtension == "crash" || $0.pathExtension == "panic" }
            .map { (name: $0.lastPathComponent, mtime: mtime($0)) }
    }

    // MARK: - autostart

    private func collectAutostart() async -> Outcome {
        var a = AutostartInfo()
        if let li = await CommandRunner.run("/usr/bin/osascript",
            ["-e", "tell application \"System Events\" to get the name of every login item"], timeout: 15).text {
            a.loginItems = Parsers.loginItems(li)
        } else {
            a.loginItems = nil
        }
        let lang = L10nStore.shared.language
        a.userAgents = inspectDir(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"), language: lang)
        a.systemAgents = inspectDir(URL(fileURLWithPath: "/Library/LaunchAgents"), language: lang)
        a.systemDaemons = inspectDir(URL(fileURLWithPath: "/Library/LaunchDaemons"), language: lang)
        if let ll = await CommandRunner.run("/bin/launchctl", ["list"], timeout: 15).text {
            a.background = Parsers.launchctlNonApple(ll)
        }
        return Outcome(section: .autostart) { $0.autostart = a }
    }

    /// Lists `.plist` files in `url` and inspects each one (label, resolved
    /// executable, orphan status, description) via `LaunchdPlistInspector`.
    private func inspectDir(_ url: URL, language: AppLanguage) -> [LaunchdPlistInfo] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { fileURL -> LaunchdPlistInfo? in
                guard let data = FileManager.default.contents(atPath: fileURL.path) else { return nil }
                return LaunchdPlistInspector.inspect(plistPath: fileURL.path, plistData: data, language: language)
            }
    }

    // MARK: - SMART / disks (generic — no hardcoded model names)

    private func collectSmart() async -> Outcome {
        let (disks, failures) = await smartDisksReporting()
        let smartctlPresent = Self.findSmartctl() != nil
        return Outcome(section: .smart) { $0.smart = disks; $0.smartctlPresent = smartctlPresent; $0.parseFailures += failures }
    }

    /// The actual SMART/disks collection logic, factored out of `collectSmart()` so the
    /// live SMART refresh loop (DashboardModel) can call it directly without going through
    /// the `Outcome` plumbing (which mutates a `FullReport` rather than returning a value).
    func collectSmartDisks() async -> [SmartDisk] {
        await smartDisksReporting().disks
    }

    private func smartDisksReporting() async -> (disks: [SmartDisk], failures: [ParseFailure]) {
        var disks: [SmartDisk] = []
        var failures: [ParseFailure] = []
        let smartctl = Self.findSmartctl()

        // Internal boot disk.
        if let info = await ParsedCommand.diskutilInfo.run(device: "disk0").nonEmptyText {
            let (status, media) = Parsers.diskutilSmart(plist: Data(info.utf8))
            if status == nil && media == nil, let f = ParseFailure(.diskutilInfo, device: "disk0", stdout: info) {
                failures.append(f)
            }
            var disk = makeDiskutilDisk(device: "internal",
                                        fallbackTitle: L.reportCollectorInternalDiskFallbackTitle,
                                        media: media, status: status, external: false)
            // Block N7: NVMe SMART/Health attrs for the internal disk (temperature,
            // wear, etc.). MUST be -A (attributes-only): -a returns a benign nonzero
            // exit on this controller (Error Information Log fetch fails) — and exit
            // codes are ignored anyway (CommandRunner returns stdout regardless).
            // -j makes smartctl print JSON (decoded by Parsers.smartctlAttrs(json:)).
            // sudo -n first (whitelisted NOPASSWD rule) — but ONLY when the resolved
            // smartctl is a root-owned, non-group-writable regular file that a non-root
            // actor cannot swap (see isSafeToRunViaSudo); otherwise straight to the
            // unprivileged run. Both fail fast, never prompt (same chain as the external
            // path below).
            if let sc = smartctl {
                var raw: String? = nil
                if Self.isSafeToRunViaSudo(sc) {
                    raw = await CommandRunner.run("/usr/bin/sudo", ["-n", sc] + ParsedCommand.smartctl.arguments(device: "disk0"), timeout: ParsedCommand.smartctl.timeout).nonEmptyText
                }
                if raw == nil { raw = await ParsedCommand.smartctl.run(device: "disk0", executable: sc).nonEmptyText }
                if let raw {
                    let attrs = Parsers.smartctlAttrs(json: Data(raw.utf8))
                    if attrs.isEmpty {
                        if let f = ParseFailure(.smartctl, device: "disk0", executable: sc, stdout: raw) { failures.append(f) }
                    } else {
                        disk.attrs = attrs
                        // Real SMART data can only worsen the diskutil-derived
                        // verdict, never mask it: same wording map as makeExternalDisk.
                        switch smartSeverity(attrs: attrs) {
                        case .crit:
                            disk.severity = .crit
                            disk.status = L.reportCollectorSmartMediaErrors
                        case .warn:
                            disk.severity = .warn
                            disk.status = L.reportCollectorSmartWearHigh
                        default:
                            break   // keep the diskutil "verified" status/severity
                        }
                    }
                }
            }
            disks.append(disk)
        }

        // External physical disks.
        if let list = await CommandRunner.run("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"], timeout: 15).text {
            for dev in Parsers.externalPhysicalDisks(plist: Data(list.utf8)) {
                var title = dev
                var duStatus: String?
                if let info = await ParsedCommand.diskutilInfo.run(device: dev).text {
                    let (status, media) = Parsers.diskutilSmart(plist: Data(info.utf8))
                    duStatus = status
                    if status == nil && media == nil, let f = ParseFailure(.diskutilInfo, device: dev, stdout: info) {
                        failures.append(f)
                    }
                    if let media, !media.isEmpty { title = media }
                }
                var attrs: [(String, String)] = []
                if let sc = smartctl {
                    // sudo -n first (NOPASSWD rule) and only for a smartctl binary a
                    // non-root actor cannot swap (isSafeToRunViaSudo), then plain — both
                    // fail fast, never prompt. This is the branch external/USB/SATA disks
                    // actually need: internal NVMe answers `smartctl -A` unprivileged.
                    // Not recorded as a parse failure: ATA-shaped JSON from USB/SATA
                    // disks is a known unsupported format, not a regression (R3-FIXTURES).
                    var raw: String? = nil
                    if Self.isSafeToRunViaSudo(sc) {
                        raw = await CommandRunner.run("/usr/bin/sudo", ["-n", sc] + ParsedCommand.smartctl.arguments(device: dev), timeout: ParsedCommand.smartctl.timeout).nonEmptyText
                    }
                    if raw == nil { raw = await ParsedCommand.smartctl.run(device: dev, executable: sc).nonEmptyText }
                    if let raw { attrs = Parsers.smartctlAttrs(json: Data(raw.utf8)) }
                }
                disks.append(makeExternalDisk(device: dev, title: title, duStatus: duStatus,
                                              attrs: attrs, smartctlPresent: smartctl != nil))
            }
        }
        return (disks, failures)
    }

    private func makeDiskutilDisk(device: String, fallbackTitle: String,
                                  media: String?, status: String?, external: Bool) -> SmartDisk {
        let title = (media?.isEmpty == false) ? media! : fallbackTitle
        let s = (status ?? "").lowercased()
        let display: String
        let sev: Severity
        if s.contains("verified") { display = L.reportCollectorSmartOkVerified; sev = .good }
        else if s.contains("not supported") { display = L.reportCollectorSmartNotSupported; sev = .info }
        else if s.isEmpty { display = L.reportCollectorSmartStatusUnavailable; sev = .info }
        else { display = "SMART: \(status!)"; sev = .info }
        return SmartDisk(device: device, title: title, status: display, attrs: [], severity: sev)
    }

    private func makeExternalDisk(device: String, title: String, duStatus: String?,
                                  attrs: [(String, String)], smartctlPresent: Bool) -> SmartDisk {
        if !attrs.isEmpty {
            let sev = smartSeverity(attrs: attrs)
            let word: String
            switch sev {
            case .crit: word = L.reportCollectorSmartMediaErrors
            case .warn: word = L.reportCollectorSmartWearHigh
            default: word = "SMART: OK"
            }
            return SmartDisk(device: device, title: title, status: word, attrs: attrs, severity: sev)
        }
        let s = (duStatus ?? "").lowercased()
        if s.contains("verified") {
            return SmartDisk(device: device, title: title, status: L.reportCollectorSmartOkVerified, attrs: [], severity: .good)
        }
        if s.contains("not supported") {
            return SmartDisk(device: device, title: title, status: L.reportCollectorSmartNotSupported, attrs: [], severity: .info)
        }
        // Connected but no SMART attributes and not a plain "verified": treat as no-access
        // (box likely dropped from USB4→USB 3.x, or smartmontools absent).
        let hint = smartctlPresent ? L.reportCollectorSmartUnavailable : L.reportCollectorSmartUnavailableNoTools
        return SmartDisk(device: device, title: title, status: hint, attrs: [], severity: .warn)
    }

    private func smartSeverity(attrs: [(String, String)]) -> Severity {
        func a(_ k: String) -> String? { attrs.first { $0.0 == k }?.1 }
        func i(_ k: String) -> Int? { a(k).map { $0.filter { $0.isNumber } }.flatMap { $0.isEmpty ? nil : Int($0) } }
        let crit = a("Critical Warning")
        if (crit != nil && crit != "0x00") || (i("Media and Data Integrity Errors") ?? 0) > 0 { return .crit }
        if let pu = i("Percentage Used"), pu >= 80 { return .warn }
        return .good
    }

    static func findSmartctl() -> String? {
        firstTool(primary: ["/opt/homebrew/sbin/smartctl", "/opt/homebrew/bin/smartctl"],
                  fallback: ["/usr/local/sbin/smartctl", "/usr/local/bin/smartctl"])
    }

    /// Pure (Checks-tested). N3: may a tool found at a /usr/local FALLBACK location be run
    /// (unprivileged)? Regular file, owned by root or by the user running the app, no group/
    /// world write bit. Weaker than `sudoSafetyVerdict` on purpose: this guards an
    /// unprivileged run, and the sudo rule would reject every user-owned Homebrew install.
    /// On Apple Silicon /usr/local is root-owned; a user-owned /usr/local (Intel/Rosetta
    /// Homebrew leftovers) is the classic plant location this closes to other accounts.
    static func fallbackToolVerdict(isRegularFile: Bool, ownerUID: UInt32,
                                    currentUID: UInt32, mode: UInt16) -> Bool {
        guard isRegularFile else { return false }
        guard ownerUID == 0 || ownerUID == currentUID else { return false }
        return mode & 0o022 == 0
    }

    /// `fallbackToolVerdict` over the real file, symlinks resolved with realpath(3)
    /// (same resolution as `isSafeToRunViaSudo`). Relative or unresolvable ⇒ false.
    static func isTrustedFallbackTool(_ path: String) -> Bool {
        guard path.hasPrefix("/"), let real = realpath(path, nil) else { return false }
        defer { free(real) }
        let resolved = String(cString: real)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved),
              let uid = attrs[.ownerAccountID] as? NSNumber,
              let mode = attrs[.posixPermissions] as? NSNumber else { return false }
        return fallbackToolVerdict(isRegularFile: (attrs[.type] as? FileAttributeType) == .typeRegular,
                                   ownerUID: uid.uint32Value, currentUID: getuid(),
                                   mode: mode.uint16Value)
    }

    /// First executable primary candidate; otherwise the first executable AND trusted
    /// fallback. An untrusted fallback counts as absent. Closures injectable for Checks.
    static func firstTool(primary: [String], fallback: [String],
                          isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                          isTrusted: (String) -> Bool = { ReportCollector.isTrustedFallbackTool($0) }) -> String? {
        if let p = primary.first(where: isExecutable) { return p }
        return fallback.first { isExecutable($0) && isTrusted($0) }
    }

    /// The decision rule of `isSafeToRunViaSudo`, over facts already gathered — pure, so the
    /// two branches an unprivileged test cannot reach through the filesystem (no stock macOS
    /// file carries `schg`; a check process cannot create a root-owned file inside a
    /// group-writable directory) are still covered by MacDashboardChecks (re-review 2 [N7]).
    /// `mode` is the POSIX permission word; `ownerUID` the file's owner.
    static func sudoSafetyVerdict(isRegularFile: Bool,
                                  ownerUID: UInt32,
                                  mode: UInt16,
                                  isImmutable: Bool,
                                  ancestorsRootOwned: Bool) -> Bool {
        guard isRegularFile else { return false }           // missing/unstattable/not a file
        guard ownerUID == 0 else { return false }           // not root-owned
        guard mode & 0o022 == 0 else { return false }       // group- or world-writable
        return isImmutable || ancestorsRootOwned            // see point 2 — not equal strength
    }

    /// Whether `path` may be handed to `sudo`. Two things must hold, and the second one
    /// has two admissible proofs:
    ///
    /// 1. The binary itself (symlinks resolved) is a regular file owned by root with no
    ///    group or world write bit.
    /// 2. A non-root actor cannot REPLACE it — either every ancestor directory up to `/`
    ///    is likewise root-owned and free of group/world write bits, or the file carries
    ///    the system-immutable flag (`schg`), which blocks unlink and rename of the file
    ///    itself even inside a group-writable directory.
    ///
    ///    The two proofs are NOT of equal strength (re-review 2 [N8]). The ancestor walk closes
    ///    the whole path; `schg` closes only the FILE. Leave a group-writable ancestor in the
    ///    chain and whoever can write that directory can rename or replace the DIRECTORY —
    ///    `/opt/homebrew/bin` moved aside and recreated with their own `smartctl` inside — after
    ///    which the immutable file is simply no longer at the resolved path. `schg` removes the
    ///    trivial unlink-and-replace on a hardened file; only hardening the directory chain
    ///    closes the group-writable-ancestor attack.
    ///
    /// Why the file and not only the chain: `findSmartctl()` can only ever return a path
    /// under `/opt/homebrew/{bin,sbin}` or `/usr/local/{bin,sbin}`, and on a standard
    /// Homebrew install those are `<user>:admin drwxrwxr-x` — so an ancestor-only walk was
    /// false in every supported layout and made this whole branch unreachable dead code
    /// (V2-RELEASE re-review [M4]). Anyone in the admin group can drop their own binary
    /// there, and wherever a NOPASSWD sudoers rule for smartctl exists that is passwordless
    /// root — hence the requirement is not weakened, only moved onto the thing that can
    /// actually be hardened: `sudo chown root:wheel <path> && sudo chmod go-w <path> &&
    /// sudo chflags schg <path>`, a one-time install step (documented in SPEC.md §5).
    ///
    /// Two residual gaps. (a) TOCTOU by construction (re-review [N8]): these checks and the
    /// `sudo` exec are separate syscalls, so an attacker who can win the window between them
    /// still wins. (b) The `schg`-only proof leaves the group-writable-ancestor rename described
    /// in point 2 open. Both raise the bar; neither closes the hole.
    static func isSafeToRunViaSudo(_ path: String) -> Bool {
        // Reject a relative path before realpath(3) resolves it against the CWD.
        guard path.hasPrefix("/") else { return false }
        // realpath(3), not URL.resolvingSymlinksInPath(): the latter deliberately
        // leaves macOS's special-cased top-level symlinks (/tmp, /var, /etc ->
        // their /private/... targets) unresolved, which would let a path reached
        // through one of them be judged on the symlink node's own (safe-looking)
        // permissions instead of the real, group/world-writable target.
        guard let real = realpath(path, nil) else { return false }
        defer { free(real) }
        let resolved = String(cString: real)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved),
              let uid = attrs[.ownerAccountID] as? NSNumber,
              let mode = attrs[.posixPermissions] as? NSNumber
        else { return false }                               // missing/unstattable
        // Both proofs are evaluated eagerly rather than short-circuited: this runs at most
        // twice per report and costs a handful of lstat(2)s, and keeping the RULE in one
        // pure, testable place is worth more than those.
        return sudoSafetyVerdict(isRegularFile: (attrs[.type] as? FileAttributeType) == .typeRegular,
                                 ownerUID: uid.uint32Value,
                                 mode: mode.uint16Value,
                                 isImmutable: isSystemImmutable(resolved),
                                 ancestorsRootOwned: ancestorsAreRootOwned(of: resolved))
    }

    /// `SF_IMMUTABLE` (`chflags schg`): settable only by root, and it makes unlink/rename
    /// of the file fail regardless of the containing directory's write bits.
    private static func isSystemImmutable(_ resolvedPath: String) -> Bool {
        var st = stat()
        guard lstat(resolvedPath, &st) == 0 else { return false }
        return st.st_flags & UInt32(SF_IMMUTABLE) != 0
    }

    /// Every directory from the file's parent up to `/` is root-owned and free of group
    /// and world write bits — the original test, now one of two ways to satisfy point 2.
    /// A writable *directory* is enough to swap a file (unlink + recreate), which is why
    /// this walks the whole chain rather than stat'ing one level.
    private static func ancestorsAreRootOwned(of resolvedPath: String) -> Bool {
        var component = (resolvedPath as NSString).deletingLastPathComponent
        if component.isEmpty { component = "/" }
        while true {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: component),
                  let uid = attrs[.ownerAccountID] as? NSNumber,
                  let mode = attrs[.posixPermissions] as? NSNumber
            else { return false }
            if uid.uint32Value != 0 { return false }
            if mode.uint16Value & 0o022 != 0 { return false }
            if component == "/" { return true }
            let parent = (component as NSString).deletingLastPathComponent
            component = parent.isEmpty ? "/" : parent
        }
    }

    // MARK: - SMART tools availability (Block N8: install-smartmontools UI)

    /// Whether the SMART CLI toolchain (`smartctl`, via Homebrew) is usable, installable,
    /// or blocked on Homebrew itself not being present. Pure mapping, no I/O — callers
    /// pass in the results of `findSmartctl()`/`ReportCollector.findBrew()`.
    enum SmartToolsAvailability { case installed, installable, needsHomebrew }

    static func smartToolsAvailability(smartctl: String?, brew: String?) -> SmartToolsAvailability {
        if smartctl != nil { return .installed }
        if brew != nil { return .installable }
        return .needsHomebrew
    }

    // MARK: - energy (pmset -g custom, fallback -g)

    private func collectEnergy() async -> Outcome {
        let (energy, failure) = await energySettingsReporting()
        return Outcome(section: .energy) { $0.energy = energy; if let failure { $0.parseFailures.append(failure) } }
    }

    /// The actual pmset-custom collection logic, factored out of `collectEnergy()` so
    /// the manual energy refresh (DashboardModel, after a batched pmset apply) can call
    /// it directly without going through the `Outcome` plumbing (mirrors
    /// `collectSmartDisks()` above).
    func collectEnergySettings() async -> EnergySettings? {
        await energySettingsReporting().settings
    }

    private func energySettingsReporting() async -> (settings: EnergySettings?, failure: ParseFailure?) {
        if let custom = await ParsedCommand.pmsetCustom.run().nonEmptyText {
            let settings = Parsers.pmsetCustom(custom)
            let failure = (settings.battery.isEmpty && settings.ac.isEmpty)
                ? ParseFailure(.pmsetCustom, stdout: custom) : nil
            return (settings, failure)
        }
        let out = await CommandRunner.run("/usr/bin/pmset", ["-g"], timeout: 10).nonEmptyText
        return (out.map { Parsers.pmsetCustom($0) }, nil)
    }

    // MARK: - battery (pmset -g batt + system_profiler SPPowerDataType)

    private func collectBattery() async -> Outcome {
        var b: BatteryInfo?
        var failures: [ParseFailure] = []
        if let pm = await ParsedCommand.pmsetBatt.run().nonEmptyText {
            b = Parsers.batteryPmset(pm)
            if b == nil, let f = ParseFailure(.pmsetBatt, stdout: pm) { failures.append(f) }
        }
        if let sp = await ParsedCommand.spPower.run().text {
            let prof = Parsers.batteryPowerProfile(sp)
            if prof.cycles != nil || prof.condition != nil || prof.maxCapacity != nil {
                if b == nil { b = BatteryInfo() }
                b?.cycles = prof.cycles
                b?.condition = prof.condition
                b?.maxCapacity = prof.maxCapacity
            } else if b?.charge != nil, let f = ParseFailure(.spPower, stdout: sp) {
                // pmset reported a battery charge, so a missing profile is a parse
                // failure, not a desktop with no battery (R3-FIXTURES edge case).
                failures.append(f)
            }
        }
        // Portability: a desktop Mac's `pmset -g batt` prints only "Now drawing from
        // 'AC Power'", which batteryPmset parses into a source-only BatteryInfo. An AC
        // line is NOT evidence of a battery (desktops run on AC too), so drop anything
        // lacking real battery data — otherwise a Mac mini/Studio/Pro would show a
        // phantom Батарея tile. A laptop always has an InternalBattery line (charge/
        // state) and/or a power profile, so this never strips a real battery.
        if let batt = b,
           batt.charge == nil, batt.maxCapacity == nil,
           batt.cycles == nil, batt.condition == nil {
            b = nil
        }
        let value = b
        return Outcome(section: .battery) { $0.battery = value; $0.parseFailures += failures }
    }

    // MARK: - home dirs (slow: du)

    private func collectHomeDirs() async -> Outcome {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let out = await CommandRunner.run("/usr/bin/du", ["-xk", "-d", "1", "--", home], timeout: 120).nonEmptyText else {
            return Outcome(section: .homeDirs) { $0.homeDirs = nil; $0.homeDirsUnreadable = [] }
        }
        let all = Parsers.duKilobyteLines(out)
        // Drop the $HOME total line itself; keep children, largest first, top 20.
        let dirs = all
            .filter { $0.path != home }
            .sorted { $0.bytes > $1.bytes }
            .prefix(20)
        // The home rule: a child $HOME actually has but du never reported is either
        // on another filesystem (du -x stops at mount points — readable, nothing to
        // say) or a directory du was refused. Only the refused ones are reported.
        // Computed against the FULL du list, not the top-20 slice.
        let unreadable = DirectoryAccess
            .missingHomeChildren(home: home,
                                 duPaths: Set(all.map(\.path)),
                                 childNames: DirectoryAccess.childNames(of: home))
            .filter { DirectoryAccess.probe($0) == .denied }
        return Outcome(section: .homeDirs) { $0.homeDirs = Array(dirs); $0.homeDirsUnreadable = unreadable }
    }

    // MARK: - service dirs (slow: du -s over a fixed set)

    private func collectServiceDirs() async -> Outcome {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/Library/Caches", "\(home)/Library/Application Support",
            "\(home)/Library/Containers", "\(home)/Library/Group Containers",
            "\(home)/Library/Developer", "\(home)/.Trash",
            "/Library/Caches", "/private/var/log", "/Applications",
        ]
        var dirs: [DirSize] = []
        var results: [(index: Int, denied: Bool, path: String)] = []
        // The service rule: du produced nothing at all for THIS path. That is
        // a timeout or a cancellation as often as it is a refusal, so the path
        // is probed before anything is claimed.
        // Paths run concurrently; each keeps its own 60 s timeout; no aggregate timeout (worst case ≈ 60 s + probes, was 9 × 60 s).
        await withTaskGroup(of: (index: Int, lines: [DirSize]?, denied: Bool).self) { group in
            for (i, p) in paths.enumerated() {
                group.addTask {
                    guard FileManager.default.fileExists(atPath: p) else { return (i, nil, false) }
                    if let out = await CommandRunner.run("/usr/bin/du", ["-xsk", "--", p], timeout: 60).nonEmptyText {
                        return (i, Parsers.duKilobyteLines(out), false)
                    }
                    return (i, nil, DirectoryAccess.probe(p) == .denied)
                }
            }
            for await r in group {
                if let lines = r.lines { dirs.append(contentsOf: lines) }
                if r.denied { results.append((r.index, true, paths[r.index])) }
            }
        }
        // Completion order is arbitrary: `unreadable` keeps the order of `paths`.
        let unreadable = results.sorted { $0.index < $1.index }.map(\.path)
        let value: [DirSize]? = dirs.isEmpty ? nil : dirs.sorted { $0.bytes > $1.bytes }
        let unreadableOut = unreadable
        return Outcome(section: .serviceDirs) { $0.serviceDirs = value; $0.serviceDirsUnreadable = unreadableOut }
    }

    // MARK: - homebrew (slow)

    private func collectBrew(cached: (version: String??, outdated: [String]?)?) async -> Outcome {
        if let cached {
            // Session cache hit (Block N5): skip the ~30 s `brew outdated` re-run.
            return Outcome(section: .brew) {
                $0.brewVersion = cached.version; $0.brewOutdated = cached.outdated
            }
        }
        let info = await collectBrewInfo()
        return Outcome(section: .brew) { $0.brewVersion = info.version; $0.brewOutdated = info.outdated }
    }

    /// The actual Homebrew collection logic, factored out of `collectBrew()` so the
    /// in-app upgrade flow (DashboardModel) can re-collect a fresh snapshot after
    /// `brew upgrade` without going through the `Outcome` plumbing.
    func collectBrewInfo() async -> (version: String??, outdated: [String]?) {
        guard let brew = Self.findBrew() else {
            return (.some(nil), nil)
        }
        // brew is a Homebrew-prefix script that shells out to its own helper
        // binaries (ruby, git, curl, …) inside that prefix — unlike the rest of
        // this file's call sites (absolute-path Apple binaries), it needs its own
        // bin dir on PATH, not just `defaultEnvironment`'s bare system PATH.
        let brewEnv = CommandRunner.environment(prependingPATH: [(brew as NSString).deletingLastPathComponent])
        var version: String?
        if let v = await CommandRunner.run(brew, ["--version"], timeout: 20, environment: brewEnv).nonEmptyText {
            version = v.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces)
        }
        var outdated: [String] = []
        if let o = await CommandRunner.run(brew, ["outdated"], timeout: 60, environment: brewEnv).text {
            outdated = o.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return (.some(version), outdated)
    }

    static func findBrew() -> String? {
        firstTool(primary: ["/opt/homebrew/bin/brew"], fallback: ["/usr/local/bin/brew"])
    }

    // MARK: - macOS updates (background check, not part of the pass)

    /// Pure (Checks-tested). Labels found => labels; "no new software available" on stdout OR
    /// stderr (softwareupdate prints it to stderr) => []; anything else (timeout, launch failure,
    /// network error, unrecognised text) => nil = the check failed, never "up to date".
    static func parseSoftwareUpdate(_ o: CommandOutcome) -> [String]? {
        guard let out = o.text else { return nil }
        let labels = out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("* Label:") }
            .map { $0.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces) }
        if !labels.isEmpty { return labels }
        if (out + "\n" + o.stderrHead).lowercased().contains("no new software available") { return [] }
        return nil
    }

    /// One background macOS update check (COLLECT-FASTPATH). nil = failed; the caller keeps its cache.
    func checkUpdates() async -> UpdatesCache? {
        let clock = ContinuousClock(); let t0 = clock.now
        let outcome = await CommandRunner.run("/usr/sbin/softwareupdate", ["-l"], timeout: 120)
        guard let items = Self.parseSoftwareUpdate(outcome) else { return nil }
        return UpdatesCache(items: items, checkedAt: Date(), durationSeconds: Self.seconds(clock.now - t0))
    }
}
