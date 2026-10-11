// Engine/SysdiagnoseImporter.swift
// App-only (temp dirs, file moves; not in Checks; tar runs in SysdiagnoseExtractor). Imports one sysdiagnose
// `.tar.gz`: copies it from the phone (read-only AFC, through the transport) or uses the
// Mac file the user picked, extracts only the members the import parses (D13) into a
// fresh temp dir, parses them, optionally keeps the archive under App Support, and ALWAYS
// removes the temp dir. Nothing outside the temp dir is ever deleted, and a Mac-picked
// file is never moved or deleted.

import Foundation

/// What a successful run hands back: the summary plus the parsed data the model merges.
struct ImportOutput {
    var archiveName: String
    var summary: ImportSummary
    var points: [BatteryPoint]
    var logs: [IPhoneLogEntry]
}

struct SysdiagnoseImporter {
    enum Source {
        case phone(handle: IPhoneHandle, remotePath: String, size: Int64)
        case mac(URL)
    }

    let transport: MobileDeviceTransport

    @MainActor
    init(transport: MobileDeviceTransport = .shared) {
        self.transport = transport
    }

    func run(source: Source, deviceKey: String, keep: Bool,
             keepRoot: URL = IPhoneStore.defaultURL().deletingLastPathComponent(),
             onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> Result<ImportOutput, ImportError> {
        let fm = FileManager.default
        // 1. Fresh temp root, removed on every exit (success, failure, cancel).
        let root = fm.temporaryDirectory.appendingPathComponent("MacDashboard-sysdiag-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(.copyFailed)
        }
        defer { try? fm.removeItem(at: root) }

        // 2. The archive file.
        let archiveURL: URL
        let archiveName: String
        let isPhoneCopy: Bool
        switch source {
        case .phone(let handle, let remotePath, let size):
            archiveName = (remotePath as NSString).lastPathComponent
            archiveURL = root.appendingPathComponent(archiveName)
            isPhoneCopy = true
            let ok: Bool = await withCheckedContinuation { cont in
                Task { @MainActor in
                    transport.copyFile(handle, remotePath: remotePath, size: size, to: archiveURL,
                                       progress: { onProgress(.copying(done: Int64($0), total: size)) },
                                       completion: { cont.resume(returning: $0) })
                }
            }
            guard ok else { return .failure(.copyFailed) }
            let copied = (try? fm.attributesOfItem(atPath: archiveURL.path)[.size] as? NSNumber)?.int64Value
            guard copied == size else { return .failure(.sizeMismatch) }
        case .mac(let url):
            archiveName = url.lastPathComponent
            archiveURL = url
            isPhoneCopy = false
        }
        if Task.isCancelled { return .failure(.cancelled) }

        // 3. Extract only the needed members (SysdiagnoseExtractor: list, select, extract).
        await onProgress(.extracting)
        let extractDir = root.appendingPathComponent("x", isDirectory: true)
        do {
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(.tarFailed(.workFiles))
        }
        let extracted = await SysdiagnoseExtractor.extract(archive: archiveURL, into: extractDir,
                                                           memberList: root.appendingPathComponent("members.txt"))
        if case .failure(let e) = extracted { return .failure(e) }

        // 4. Parse.
        await onProgress(.parsing)
        var (csvFiles, ipsFiles) = Self.extractedFiles(in: extractDir)
        csvFiles.sort { $0.lastPathComponent < $1.lastPathComponent }
        var days: [String: BatteryPoint] = [:]
        var skipped = 0
        for u in csvFiles {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let parsed = IPhoneData.parseBDCDaily(text)
            skipped += parsed.skipped
            for p in parsed.points { days[p.day] = p }   // later file wins for a shared day
        }
        let points = days.values.sorted { $0.day < $1.day }

        let prefix = extractDir.standardizedFileURL.path
        var logs: [IPhoneLogEntry] = []
        for u in ipsFiles.sorted(by: { $0.path < $1.path }) {
            let rel = u.standardizedFileURL.path.hasPrefix(prefix)
                ? String(u.standardizedFileURL.path.dropFirst(prefix.count)) : u.lastPathComponent
            let attrs = try? fm.attributesOfItem(atPath: u.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let modified = attrs?[.modificationDate] as? Date
            var head = Self.readPrefix(u, limit: 4096)
            if let d = head, size > 4096, !d.contains(0x0A) { head = Self.readPrefix(u, limit: 65536) }
            let bug = head.flatMap { IPhoneData.bugType(fromHeader: $0) }
            logs.append(IPhoneLogEntry(path: rel, size: size, modified: modified, bugType: bug,
                                       category: IPhoneData.category(bugType: bug),
                                       source: .archive(name: archiveName)))
        }

        // 5. Keep.
        var keptURL: URL?
        if keep {
            guard let dest = Self.keepArchive(from: archiveURL, move: isPhoneCopy, deviceKey: deviceKey, keepRoot: keepRoot) else {
                return .failure(.keepFailed)
            }
            keptURL = dest
        }
        return .success(ImportOutput(archiveName: archiveName,
                                     summary: ImportSummary(batteryPoints: points.count, skippedRows: skipped,
                                                            logFiles: logs.count, keptPath: keptURL),
                                     points: points, logs: logs))
    }

    /// BDC_Daily CSVs and `.ips` files under `dir`. Synchronous: FileManager.enumerator
    /// iteration is not allowed in an async context.
    private static func extractedFiles(in dir: URL) -> (csv: [URL], ips: [URL]) {
        var csv: [URL] = [], ips: [URL] = []
        if let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let u as URL in en {
                guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let name = u.lastPathComponent
                if name.hasPrefix("BDC_Daily_"), name.hasSuffix(".csv") { csv.append(u) }
                else if name.hasSuffix(".ips") { ips.append(u) }
            }
        }
        return (csv, ips)
    }

    private static func readPrefix(_ url: URL, limit: Int) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        return try? h.read(upToCount: limit)
    }

    /// Moves (phone copy) or copies (Mac file) the archive to
    /// `<keepRoot>/iphones/<deviceKey>/sysdiagnose/<name>`; dirs 0700, file 0600; on a name
    /// clash " (2)", " (3)"… is inserted before `.tar.gz`; never overwrites.
    static func keepArchive(from src: URL, move: Bool, deviceKey: String, keepRoot: URL) -> URL? {
        let fm = FileManager.default
        var dir = keepRoot
        for part in ["iphones", deviceKey, "sysdiagnose"] {
            dir.appendPathComponent(part, isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])) != nil else { return nil }
            }
        }
        let name = src.lastPathComponent
        let suffix = name.hasSuffix(".tar.gz") ? ".tar.gz" : (name as NSString).pathExtension.isEmpty ? "" : "." + (name as NSString).pathExtension
        let stem = String(name.dropLast(suffix.count))
        var dest = dir.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(stem) (\(n))\(suffix)")
            n += 1
        }
        do {
            if move { try fm.moveItem(at: src, to: dest) } else { try fm.copyItem(at: src, to: dest) }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        } catch {
            try? fm.removeItem(at: dest)   // dest is the free name chosen above, never an existing file
            return nil
        }
        return dest
    }
}
