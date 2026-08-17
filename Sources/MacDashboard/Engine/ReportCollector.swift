// Engine/ReportCollector.swift
// Full read-only system report. Each section is an independent step with its own
// timeout; a section that fails leaves its field nil and still marks progress done,
// so a denied permission or absent tool never blocks the rest. Quick sections run
// concurrently; the du-heavy and update-check sections run afterwards, also
// concurrently as a second group (they are mutually independent).
// SPEC §5.2. Nothing here modifies the system.
//
// Blocking subprocess waits are dispatched to the global queue (via runOffPool) so
// they never starve Swift's cooperative thread pool when many run at once.

import Foundation

enum ReportSection: String, CaseIterable {
    case system, snapshots, homeDirs, serviceDirs, security, tmDest, spotlight
    case crashes, brew, updates, autostart, smart, energy, battery
}

final class ReportCollector {

    /// One scope per collector instance: DashboardModel creates a fresh
    /// ReportCollector per collect()/manual-refresh call, so cancelling this scope
    /// kills exactly this instance's live subprocesses and no one else's.
    let cancelScope = CommandCancellationScope()

    /// A section's result: which section, and how to fold it into the report.
    private struct Outcome {
        let section: ReportSection
        let mutate: (inout FullReport) -> Void
    }

    /// Freshness window for the session brew-outdated cache (Block N5): `brew
    /// outdated` costs ~30 s and its result only changes via brew operations, so
    /// repeat manual refreshes within this window reuse the previous result.
    static let brewCacheWindow: TimeInterval = 600

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

    /// Pure (Checks-tested): one entry per report FILE NAME, first occurrence wins.
    /// The collector concatenates two directories (see `crashReportDirectories`) and
    /// the same report could plausibly be listed by both; without this it would be
    /// counted twice and inflate a process's crash count. Input order IS the priority
    /// order, so the per-user copy wins over the system one.
    static func crashDedup(files: [(name: String, mtime: Date)]) -> [(name: String, mtime: Date)] {
        var seen = Set<String>()
        return files.filter { seen.insert($0.name).inserted }
    }

    /// Pure (Checks-tested): the whole crash pipeline except the directory read —
    /// drop reports listed by more than one directory, drop files outside the window,
    /// collapse repeats per process, mark a group as a panic group if ANY of its
    /// reports is a `.panic`, order by count (desc) then name (asc, so ties are
    /// deterministic), cap the group count — keeping panic/own-app groups first so the
    /// cap can never discard them (V2-CRASH-DETECT).
    static func crashGroups(files: [(name: String, mtime: Date)], now: Date,
                            window: TimeInterval = crashAgeWindow,
                            maxGroups: Int = crashMaxGroups) -> [CrashGroup] {
        var acc: [String: (count: Int, isPanic: Bool)] = [:]
        for f in crashDedup(files: files) where isCrashRecent(mtime: f.mtime, now: now, window: window) {
            let name = crashProcessName(from: f.name)
            let prev = acc[name] ?? (count: 0, isPanic: false)
            acc[name] = (count: prev.count + 1,
                         isPanic: prev.isPanic || crashIsPanic(from: f.name))
        }
        let sorted = acc
            .map { CrashGroup(process: $0.key, count: $0.value.count, isPanic: $0.value.isPanic) }
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
        // Bridge structured-concurrency cancellation to the live subprocesses:
        // cancelling the awaiting Task SIGKILLs whatever this instance has spawned
        // (and short-circuits every subsequent CommandRunner.run in this pass), so
        // the remaining sections fall through fast with nil results and the caller's
        // own `guard !Task.isCancelled` discards the returned report.
        await withTaskCancellationHandler {
            await collectBody(skipSlow: skipSlow, cachedBrew: cachedBrew, onSection: onSection)
        } onCancel: { [scope = cancelScope] in
            scope.cancel()
        }
    }

    private func collectBody(skipSlow: Bool,
                             cachedBrew: (version: String??, outdated: [String]?)?,
                             onSection: @escaping @MainActor (FullReport) -> Void) async -> FullReport {
        var report = FullReport()
        report.createdAt = Date()
        let initial = report
        await MainActor.run { onSection(initial) }

        // Quick sections — concurrent. for-await serializes the merges on this task.
        let quick: [() async -> Outcome] = [
            { await self.off { self.collectSystem() } },
            { await self.off { self.collectSnapshots() } },
            { await self.off { self.collectSecurity() } },
            { await self.off { self.collectTMDest() } },
            { await self.off { self.collectSpotlight() } },
            { await self.off { self.collectCrashes() } },
            { await self.off { self.collectAutostart() } },
            { await self.off { self.collectSmart() } },
            { await self.off { self.collectEnergy() } },
            { await self.off { self.collectBattery() } },
        ]
        await withTaskGroup(of: Outcome.self) { group in
            for job in quick { group.addTask { await job() } }
            for await outcome in group {
                outcome.mutate(&report)
                report.progress[outcome.section.rawValue] = true
                let snap = report
                await MainActor.run { onSection(snap) }
            }
        }

        // Slow sections — concurrent, after the quick ones (du/softwareupdate are heavy
        // but mutually independent: different binaries, disjoint FullReport fields).
        // for-await serializes the merges on this task, same as the quick group.
        let slow: [() async -> Outcome] = skipSlow ? [] : [
            { await self.off { self.collectHomeDirs() } },
            { await self.off { self.collectServiceDirs() } },
            { await self.off { self.collectBrew(cached: cachedBrew) } },
            { await self.off { self.collectUpdates() } },
        ]
        await withTaskGroup(of: Outcome.self) { group in
            for job in slow { group.addTask { await job() } }
            for await outcome in group {
                outcome.mutate(&report)
                report.progress[outcome.section.rawValue] = true
                let snap = report
                await MainActor.run { onSection(snap) }
            }
        }
        return report
    }

    /// Runs blocking work off the cooperative pool so concurrent sections don't
    /// deadlock waiting on subprocesses.
    private func off(_ work: @escaping () -> Outcome) async -> Outcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: work()) }
        }
    }

    // MARK: - system

    private func collectSystem() -> Outcome {
        var info = SystemInfo()
        if let sv = CommandRunner.run("/usr/bin/sw_vers", [], timeout: 10, scope: cancelScope) {
            let parsed = Parsers.swVers(sv)
            info.osName = parsed.osName; info.osVersion = parsed.osVersion; info.osBuild = parsed.osBuild
        }
        if let hw = CommandRunner.run("/usr/sbin/system_profiler", ["SPHardwareDataType"], timeout: 25, scope: cancelScope) {
            let h = Parsers.hardwareProfile(hw)
            info.modelName = h.modelName; info.modelId = h.modelId; info.chip = h.chip
            info.cores = h.cores; info.memBytes = h.memBytes
        }
        if info.chip == nil, let brand = CommandRunner.run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"], timeout: 5, scope: cancelScope) {
            let s = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { info.chip = s }
        }
        if let up = CommandRunner.run("/usr/bin/uptime", [], timeout: 10, scope: cancelScope) {
            info.uptime = Parsers.uptimeHuman(up)
        }
        info.hostName = ProcessInfo.processInfo.hostName
        let has = info.osName != nil || info.modelName != nil || info.chip != nil
        return Outcome(section: .system) { $0.system = has ? info : nil }
    }

    // MARK: - Time Machine local snapshots

    private func collectSnapshots() -> Outcome {
        let out = CommandRunner.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 15, scope: cancelScope)
        let names: [String]? = out.map { text in
            text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("com.apple.TimeMachine.") }
        }
        return Outcome(section: .snapshots) { $0.snapshots = names }
    }

    // MARK: - security

    private func collectSecurity() -> Outcome {
        let s = collectSecurityInfo()
        return Outcome(section: .security) { $0.security = s }
    }

    /// The actual security-state collection logic, factored out of `collectSecurity()`
    /// so a manual re-check (DashboardModel's `enableFirewallNow()`, AR wave 2) can call
    /// it directly without going through the `Outcome` plumbing, mirroring
    /// `collectSmartDisks()`/`collectBrewInfo()` above.
    func collectSecurityInfo() -> SecurityState {
        var s = SecurityState()
        if let t = CommandRunner.run("/usr/bin/fdesetup", ["status"], timeout: 10, scope: cancelScope) { s.fileVault = Parsers.fileVaultStatus(t) }
        if let t = CommandRunner.run("/usr/sbin/spctl", ["--status"], timeout: 10, scope: cancelScope) { s.gatekeeper = Parsers.gatekeeperStatus(t) }
        if let t = CommandRunner.run("/usr/bin/csrutil", ["status"], timeout: 10, scope: cancelScope) { s.sip = Parsers.sipStatus(t) }
        if let t = CommandRunner.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], timeout: 10, scope: cancelScope) {
            s.firewall = Parsers.firewallStatus(t)
        } else if let t = CommandRunner.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.alf", "globalstate"], timeout: 10, scope: cancelScope) {
            s.firewall = Parsers.firewallStatus(t)
        }
        return s
    }

    // MARK: - Time Machine destination

    private func collectTMDest() -> Outcome {
        guard let value = collectTMDestInfo() else {
            return Outcome(section: .tmDest) { _ in }   // leave .none
        }
        return Outcome(section: .tmDest) { $0.tmDest = .some(value) }
    }

    /// The actual Time Machine destination collection logic, factored out of
    /// `collectTMDest()` so the live SMART refresh loop (DashboardModel) can call it
    /// directly without going through the `Outcome` plumbing (which mutates a
    /// `FullReport` rather than returning a value), mirroring `collectSmartDisks()` above.
    ///
    /// Double optional: outer `nil` = command failed / not checked (leave `report.tmDest`
    /// untouched); `.some(nil)` = checked, no destination configured; `.some(x)` = configured.
    func collectTMDestInfo() -> TMDestination?? {
        guard let out = CommandRunner.run("/usr/bin/tmutil", ["destinationinfo"], timeout: 15, scope: cancelScope) else {
            return nil
        }
        var dest = Parsers.tmDestination(out)
        if dest != nil { applyLastBackup(to: &dest!) }
        let value: TMDestination? = dest
        return .some(value)
    }

    /// Fills in `dest.lastBackup` via a fallback chain, since `tmutil latestbackup`
    /// silently yields empty stdout (⇒ `CommandRunner.run` returns nil, indistinguishable
    /// here from a launch failure — both mean "try the next source") without Full Disk
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
    private func applyLastBackup(to dest: inout TMDestination) {
        if let last = CommandRunner.run("/usr/bin/tmutil", ["latestbackup"], timeout: 15, scope: cancelScope) {
            let s = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.lowercased().contains("no backup") {
                dest.lastBackupUnavailableReason = L.reportCollectorNoBackupsYet
                return
            }
            if !s.isEmpty, let date = Parsers.tmLatestBackupDate(fromPath: s) {
                dest.lastBackup = Parsers.formatTMBackupDate(date)
                return
            }
        }
        var diskutilFoundZeroBackups = false
        if let mount = dest.mountPoint,
           let out = CommandRunner.run("/usr/sbin/diskutil", ["apfs", "listSnapshots", mount], timeout: 15, scope: cancelScope) {
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
            dest.lastBackupUnavailableReason = L.reportCollectorDiskNotConnected
        } else if diskutilFoundZeroBackups {
            dest.lastBackupUnavailableReason = L.reportCollectorNoCompletedBackups
        } else {
            dest.lastBackupUnavailableReason = L.reportCollectorDateUnavailableNoFDA
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

    private func collectSpotlight() -> Outcome {
        let out = CommandRunner.run("/usr/bin/mdutil", ["-s", "/"], timeout: 10, scope: cancelScope)
        let text: String? = out.map { raw in
            if raw.lowercased().contains("indexing enabled") { return L.reportCollectorSpotlightEnabled }
            if raw.lowercased().contains("indexing disabled") { return L.reportCollectorSpotlightDisabled }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Outcome(section: .spotlight) { $0.spotlight = text }
    }

    // MARK: - crashes (FileManager, no shell)

    private func collectCrashes() -> Outcome {
        let files = Self.crashReportDirectories.flatMap { Self.crashFiles(in: $0) }
        let groups = Self.crashGroups(files: files, now: Date())
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

    private func collectAutostart() -> Outcome {
        var a = AutostartInfo()
        if let li = CommandRunner.run("/usr/bin/osascript",
            ["-e", "tell application \"System Events\" to get the name of every login item"], timeout: 15, scope: cancelScope) {
            a.loginItems = Parsers.loginItems(li)
        } else {
            a.loginItems = nil
        }
        let lang = L10nStore.shared.language
        a.userAgents = inspectDir(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"), language: lang)
        a.systemAgents = inspectDir(URL(fileURLWithPath: "/Library/LaunchAgents"), language: lang)
        a.systemDaemons = inspectDir(URL(fileURLWithPath: "/Library/LaunchDaemons"), language: lang)
        if let ll = CommandRunner.run("/bin/launchctl", ["list"], timeout: 15, scope: cancelScope) {
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

    private func collectSmart() -> Outcome {
        let disks = collectSmartDisks()
        let smartctlPresent = Self.findSmartctl() != nil
        return Outcome(section: .smart) { $0.smart = disks; $0.smartctlPresent = smartctlPresent }
    }

    /// The actual SMART/disks collection logic, factored out of `collectSmart()` so the
    /// live SMART refresh loop (DashboardModel) can call it directly without going through
    /// the `Outcome` plumbing (which mutates a `FullReport` rather than returning a value).
    func collectSmartDisks() -> [SmartDisk] {
        var disks: [SmartDisk] = []
        let smartctl = Self.findSmartctl()

        // Internal boot disk.
        if let info = CommandRunner.run("/usr/sbin/diskutil", ["info", "disk0"], timeout: 15, scope: cancelScope) {
            let (status, media) = Parsers.diskutilSmart(info)
            var disk = makeDiskutilDisk(device: "internal",
                                        fallbackTitle: L.reportCollectorInternalDiskFallbackTitle,
                                        media: media, status: status, external: false)
            // Block N7: NVMe SMART/Health attrs for the internal disk (temperature,
            // wear, etc.). MUST be -A (attributes-only): -a returns a benign nonzero
            // exit on this controller (Error Information Log fetch fails) — and exit
            // codes are ignored anyway (CommandRunner returns stdout regardless).
            // sudo -n first (whitelisted NOPASSWD rule), then plain — both fail
            // fast, never prompt (same chain as the external path below).
            if let sc = smartctl {
                let raw = CommandRunner.run("/usr/bin/sudo", ["-n", sc, "-A", "disk0"], timeout: 15, scope: cancelScope)
                    ?? CommandRunner.run(sc, ["-A", "disk0"], timeout: 15, scope: cancelScope)
                if let raw {
                    let attrs = Parsers.smartctlAttrs(raw)
                    if !attrs.isEmpty {
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
        if let list = CommandRunner.run("/usr/sbin/diskutil", ["list"], timeout: 15, scope: cancelScope) {
            for dev in externalPhysicalDisks(list) {
                var title = dev
                var duStatus: String?
                if let info = CommandRunner.run("/usr/sbin/diskutil", ["info", dev], timeout: 15, scope: cancelScope) {
                    let (status, media) = Parsers.diskutilSmart(info)
                    duStatus = status
                    if let media, !media.isEmpty { title = media }
                }
                var attrs: [(String, String)] = []
                if let sc = smartctl {
                    // sudo -n first (NOPASSWD rule), then plain — both fail fast, never prompt.
                    let raw = CommandRunner.run("/usr/bin/sudo", ["-n", sc, "-A", dev], timeout: 15, scope: cancelScope)
                        ?? CommandRunner.run(sc, ["-A", dev], timeout: 15, scope: cancelScope)
                    if let raw { attrs = Parsers.smartctlAttrs(raw) }
                }
                disks.append(makeExternalDisk(device: dev, title: title, duStatus: duStatus,
                                              attrs: attrs, smartctlPresent: smartctl != nil))
            }
        }
        return disks
    }

    private func externalPhysicalDisks(_ diskutilList: String) -> [String] {
        var devices: [String] = []
        for line in diskutilList.components(separatedBy: "\n") {
            guard line.contains("external, physical") else { continue }
            // "/dev/disk4 (external, physical):"
            if let slash = line.range(of: "/dev/") {
                let rest = line[slash.lowerBound...]
                let dev = rest.prefix { !$0.isWhitespace && $0 != "(" }
                let name = String(dev).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                if !name.isEmpty { devices.append(name) }
            }
        }
        return devices
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
        for p in ["/opt/homebrew/sbin/smartctl", "/opt/homebrew/bin/smartctl",
                  "/usr/local/sbin/smartctl", "/usr/local/bin/smartctl"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
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

    private func collectEnergy() -> Outcome {
        let energy = collectEnergySettings()
        return Outcome(section: .energy) { $0.energy = energy }
    }

    /// The actual pmset-custom collection logic, factored out of `collectEnergy()` so
    /// the manual energy refresh (DashboardModel, after a batched pmset apply) can call
    /// it directly without going through the `Outcome` plumbing (mirrors
    /// `collectSmartDisks()` above).
    func collectEnergySettings() -> EnergySettings? {
        let out = CommandRunner.run("/usr/bin/pmset", ["-g", "custom"], timeout: 10, scope: cancelScope)
            ?? CommandRunner.run("/usr/bin/pmset", ["-g"], timeout: 10, scope: cancelScope)
        return out.map { Parsers.pmsetCustom($0) }
    }

    // MARK: - battery (pmset -g batt + system_profiler SPPowerDataType)

    private func collectBattery() -> Outcome {
        var b: BatteryInfo?
        if let pm = CommandRunner.run("/usr/bin/pmset", ["-g", "batt"], timeout: 10, scope: cancelScope) {
            b = Parsers.batteryPmset(pm)
        }
        if let sp = CommandRunner.run("/usr/sbin/system_profiler", ["SPPowerDataType"], timeout: 25, scope: cancelScope) {
            let prof = Parsers.batteryPowerProfile(sp)
            if prof.cycles != nil || prof.condition != nil || prof.maxCapacity != nil {
                if b == nil { b = BatteryInfo() }
                b?.cycles = prof.cycles
                b?.condition = prof.condition
                b?.maxCapacity = prof.maxCapacity
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
        return Outcome(section: .battery) { $0.battery = value }
    }

    // MARK: - home dirs (slow: du)

    private func collectHomeDirs() -> Outcome {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let out = CommandRunner.run("/usr/bin/du", ["-xk", "-d", "1", home], timeout: 120, scope: cancelScope) else {
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

    private func collectServiceDirs() -> Outcome {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/Library/Caches", "\(home)/Library/Application Support",
            "\(home)/Library/Containers", "\(home)/Library/Group Containers",
            "\(home)/Library/Developer", "\(home)/.Trash",
            "/Library/Caches", "/private/var/log", "/Applications",
        ]
        var dirs: [DirSize] = []
        var unreadable: [String] = []
        for p in paths {
            guard FileManager.default.fileExists(atPath: p) else { continue }
            if let out = CommandRunner.run("/usr/bin/du", ["-xsk", p], timeout: 60, scope: cancelScope) {
                dirs.append(contentsOf: Parsers.duKilobyteLines(out))
            } else if DirectoryAccess.probe(p) == .denied {
                // The service rule: du produced nothing at all for THIS path. That is
                // a timeout or a cancellation as often as it is a refusal, so the path
                // is probed before anything is claimed.
                unreadable.append(p)
            }
        }
        let value: [DirSize]? = dirs.isEmpty ? nil : dirs.sorted { $0.bytes > $1.bytes }
        let unreadableOut = unreadable
        return Outcome(section: .serviceDirs) { $0.serviceDirs = value; $0.serviceDirsUnreadable = unreadableOut }
    }

    // MARK: - homebrew (slow)

    private func collectBrew(cached: (version: String??, outdated: [String]?)?) -> Outcome {
        if let cached {
            // Session cache hit (Block N5): skip the ~30 s `brew outdated` re-run.
            return Outcome(section: .brew) {
                $0.brewVersion = cached.version; $0.brewOutdated = cached.outdated
            }
        }
        let info = collectBrewInfo()
        return Outcome(section: .brew) { $0.brewVersion = info.version; $0.brewOutdated = info.outdated }
    }

    /// The actual Homebrew collection logic, factored out of `collectBrew()` so the
    /// in-app upgrade flow (DashboardModel) can re-collect a fresh snapshot after
    /// `brew upgrade` without going through the `Outcome` plumbing.
    func collectBrewInfo() -> (version: String??, outdated: [String]?) {
        guard let brew = Self.findBrew() else {
            return (.some(nil), nil)
        }
        // brew is a Homebrew-prefix script that shells out to its own helper
        // binaries (ruby, git, curl, …) inside that prefix — unlike the rest of
        // this file's call sites (absolute-path Apple binaries), it needs its own
        // bin dir on PATH, not just `defaultEnvironment`'s bare system PATH.
        let brewEnv = CommandRunner.environment(prependingPATH: [(brew as NSString).deletingLastPathComponent])
        var version: String?
        if let v = CommandRunner.run(brew, ["--version"], timeout: 20, environment: brewEnv, scope: cancelScope) {
            version = v.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces)
        }
        var outdated: [String] = []
        if let o = CommandRunner.run(brew, ["outdated"], timeout: 60, environment: brewEnv, scope: cancelScope) {
            outdated = o.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return (.some(version), outdated)
    }

    static func findBrew() -> String? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // MARK: - macOS updates (slow)

    private func collectUpdates() -> Outcome {
        guard let out = CommandRunner.run("/usr/sbin/softwareupdate", ["-l"], timeout: 120, scope: cancelScope) else {
            return Outcome(section: .updates) { $0.updates = nil }   // nil = not checked (timed out)
        }
        if out.lowercased().contains("no new software available") {
            return Outcome(section: .updates) { $0.updates = [] }
        }
        var items: [String] = []
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            // softwareupdate marks actionable items with a leading "* Label:".
            if t.hasPrefix("* Label:") {
                items.append(t.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces))
            }
        }
        let value = items
        return Outcome(section: .updates) { $0.updates = value }
    }
}
