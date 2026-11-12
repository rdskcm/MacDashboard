// Engine/IPhoneCrashLog.swift
// IPHONE-CRASHLOG-ACTIONS: the pure half of the crash-log row
// actions — header fields, created time, process fallback, Console eligibility, the temp copy folder and the
// save write. Foundation only; covered by Tests/MoonportTests/IPhoneCrashLogTests.swift. Internal, not
// private (checks-helper-visibility).

import Foundation

/// Why a row action stopped (shown under the buttons, `L.iphoneLogsActionError`).
enum IPhoneLogActionError: Equatable, CaseIterable {
    case disconnected, copyFailed, noSpace, gone, consoleFailed, saveFailed
}

enum IPhoneCrashLog {
    /// Decision 2: Console is offered for `.ips` files up to this size. Assumption: 18× the largest `.ips`
    /// seen on the reference phone (stackshot, 1 744 640 B, IPHONE-SPIKE Q5).
    static let consoleMaxBytes: Int64 = 32 << 20

    /// Name prefix of each per-file copy folder in the temp directory (Decision 3, D5). Brand-neutral; `md-` is
    /// the tag the test fixtures already use for their temp roots. The import roots keep `IPhoneData.importTempPrefix`.
    static let tempPrefix = "md-crashlog-"

    /// Decision 4: how long «✓ Saved» stays on the button.
    static let savedConfirmSeconds: Double = 1.5

    /// A copy whose progress line is shown under the buttons (smaller copies finish in well under a second).
    static let progressLineMinBytes: Int64 = 8 << 20

    /// Header fields from the first-line JSON object (F5, F7), ONE JSON parse per file. `process`: `name`, else `app_name` (trimmed, non-empty).
    /// `timestamp`: `ipsTimestamp`. No other key is read (identifier-mask: `incident_id`, `slice_uuid` and any
    /// device field never leave this function). No JSON first line → `IPhoneLogHeader()` (all nil).
    static func logHeader(fromHeader data: Data) -> IPhoneLogHeader {
        guard let obj = IPhoneData.headerObject(data) else { return IPhoneLogHeader() }
        func str(_ k: String) -> String? {
            guard let s = obj[k] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return IPhoneLogHeader(bugType: IPhoneData.bugType(in: obj),
                               process: str("name") ?? str("app_name"),
                               timestamp: str("timestamp").flatMap(ipsTimestamp))
    }

    /// `timestamp` of an `.ips` header. Shape confirmed on the phone: "<date> +0300" (IPHONE-SPIKE Q5). Accepted
    /// formats (assumption from Apple-written reports seen in training data, not from Apple documentation, which
    /// does not specify it): "yyyy-MM-dd HH:mm:ss.SS Z" and "yyyy-MM-dd HH:mm:ss Z". Anything else → nil.
    private static let ipsTimestampFormatters: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z"].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    static func ipsTimestamp(_ s: String) -> Date? {
        for f in ipsTimestampFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// The `-YYYY-MM-DD-HHMMSS` stamp in a report file name (e.g. `ServiceExtension-2026-10-12-044145.ips`),
    /// read as wall-clock time in `timeZone`. nil when absent or not a valid date.
    static func fileNameTimestamp(_ name: String, timeZone: TimeZone = .current) -> Date? {
        guard let r = name.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { return nil }
        let digits = name[r].filter(\.isNumber).map { Int(String($0))! }
        func num(_ a: Int, _ n: Int) -> Int { digits[a..<(a + n)].reduce(0) { $0 * 10 + $1 } }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = DateComponents(year: num(0, 4), month: num(4, 2), day: num(6, 2),
                               hour: num(8, 2), minute: num(10, 2), second: num(12, 2))
        guard c.isValidDate(in: cal) else { return nil }
        return cal.date(from: c)
    }

    /// Process name from the file name, only for the categories whose file name starts with the process
    /// (mockup rule, IPHONE-SPIKE Q5 name patterns): strip `ExcUserFault_`, cut at `.diskwrites_resource` /
    /// `.cpu_resource`, cut at the `-YYYY-MM-DD` stamp, drop a trailing `.ips`. nil for every other category
    /// (`JetsamEvent-…`, `stacks-…`, analytics names are report kinds, not processes — F6).
    static func processFromFileName(_ name: String, category: LogCategory) -> String? {
        guard [.appCrash, .exceptionFault, .diskWrites, .cpuResource].contains(category) else { return nil }
        var s = Substring(name)
        if s.hasPrefix("ExcUserFault_") { s = s.dropFirst("ExcUserFault_".count) }
        for marker in [".diskwrites_resource", ".cpu_resource"] {
            if let r = s.range(of: marker) { s = s[..<r.lowerBound] }
        }
        if let r = s.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) { s = s[..<r.lowerBound] }
        if s.hasSuffix(".ips") { s = s.dropLast(4) }
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// One listing / import entry with the derived fields. `header` nil = the header read failed (category
    /// `.other`, as `IPhoneLogTypes.merge` does today for a failed key). created = header timestamp → file-name
    /// stamp → AFC/file mtime. Called by `IPhoneLogTypes.split` (known keys), `IPhoneLogTypes.merge` (read and
    /// failed keys) and `SysdiagnoseImporter.run` (archive rows); the fixture builds its own entries.
    static func logEntry(path: String, size: Int64, modified: Date?, header: IPhoneLogHeader?,
                         source: IPhoneLogEntry.Source, timeZone: TimeZone = .current) -> IPhoneLogEntry {
        let name = (path as NSString).lastPathComponent
        let bug = header?.bugType
        let category = IPhoneData.category(bugType: bug)
        return IPhoneLogEntry(path: path, size: size, modified: modified, bugType: bug, category: category,
                              source: source,
                              process: header?.process ?? processFromFileName(name, category: category),
                              created: header?.timestamp ?? fileNameTimestamp(name, timeZone: timeZone) ?? modified)
    }

    /// A listing entry whose header is not read yet (`IPhoneLogTypes.split`, IPHONE-LOAD-SPEED): type `.pending`,
    /// no process (the category is unknown, so the file-name rule cannot apply), created from the file name or mtime.
    static func pendingEntry(path: String, size: Int64, modified: Date?, timeZone: TimeZone = .current) -> IPhoneLogEntry {
        let name = (path as NSString).lastPathComponent
        return IPhoneLogEntry(path: path, size: size, modified: modified, bugType: nil, category: .pending,
                              source: .live, created: fileNameTimestamp(name, timeZone: timeZone) ?? modified)
    }

    /// Decision 2.
    static func canOpenInConsole(name: String, size: Int64) -> Bool {
        name.hasSuffix(".ips") && size > 0 && size <= consoleMaxBytes
    }

    /// Free space before a copy: `available` nil (unknown) → allowed, the copy itself then fails cleanly.
    /// Margin = `IPSWData.spaceMargin` (1 GiB), the app's existing free-space margin.
    static func hasRoom(available: Int64?, size: Int64) -> Bool {
        guard let available else { return true }
        return available >= size + IPSWData.spaceMargin
    }

    /// Available bytes on the volume of `url` (same keys as IPSWDownloader's check).
    static func availableBytes(at url: URL) -> Int64? {
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let n = v?.volumeAvailableCapacityForImportantUsage, n > 0 { return n }
        return v?.volumeAvailableCapacity.map { Int64($0) }
    }

    /// A fresh `<dir>/md-crashlog-<UUID>/` (0700). nil when it cannot be created.
    static func makeCopyDir(in dir: URL) -> URL? {
        let u = dir.appendingPathComponent(tempPrefix + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            return u
        } catch { return nil }
    }

    /// Size of a local file, nil when it is missing.
    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// Writes the local copy to the place the user chose in the save panel (the panel already asked about
    /// replacing). An existing file is replaced atomically (`replaceItemAt` via a staging copy), so a failed
    /// write leaves it as it was. Never deletes anything else. false on any error.
    static func writeSaved(from src: URL, to dest: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path) {
            // Stage beside the destination, then move into place: a failed copy never leaves a partial file at dest.
            let staged = dest.deletingLastPathComponent()
                .appendingPathComponent(".\(dest.lastPathComponent).\(UUID().uuidString).part")
            defer { try? fm.removeItem(at: staged) }
            guard (try? fm.copyItem(at: src, to: staged)) != nil else { return false }
            return (try? fm.moveItem(at: staged, to: dest)) != nil
        }
        guard let stageDir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                         appropriateFor: dest, create: true) else { return false }
        defer { try? fm.removeItem(at: stageDir) }
        let staged = stageDir.appendingPathComponent(dest.lastPathComponent)
        guard (try? fm.copyItem(at: src, to: staged)) != nil else { return false }
        return (try? fm.replaceItemAt(dest, withItemAt: staged)) != nil
    }
}
