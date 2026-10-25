// Engine/ArchiveMigration.swift
// REDESIGN-IPHONE: moves kept sysdiagnose archives between folders. Never deletes a source before its copy is
// verified; each move is independent; running twice is a no-op. Foundation only — covered by
// Tests/MacDashboardTests/ArchiveMigrationTests.swift on temp dirs.
import Foundation

struct ArchiveMove: Equatable, Sendable {
    let source: URL
    let destination: URL
}

enum ArchiveMigration {
    struct Outcome: Equatable, Sendable {
        var moved: [ArchiveMove] = []     // destination holds the file, source is gone (or was a verified duplicate)
        var skipped: [ArchiveMove] = []   // destination exists with different content; both files kept
        var failed: [ArchiveMove] = []    // nothing changed for this file
        var clean: Bool { skipped.isEmpty && failed.isEmpty }
    }

    // MARK: Planning

    /// Legacy layout → current layout: `<legacyRoot>/<dir>/sysdiagnose/<file>` → `<archiveRoot>/<dir>/<file>`.
    static func planLegacy(legacyRoot: URL, archiveRoot: URL) -> [ArchiveMove] {
        var moves: [ArchiveMove] = []
        for dir in subdirectories(of: legacyRoot) {
            let inner = dir.appendingPathComponent("sysdiagnose", isDirectory: true)
            for file in regularFiles(in: inner) {
                moves.append(ArchiveMove(source: file,
                                         destination: archiveRoot.appendingPathComponent(dir.lastPathComponent, isDirectory: true)
                                            .appendingPathComponent(file.lastPathComponent)))
            }
        }
        return moves.sorted { $0.source.path < $1.source.path }
    }

    /// Current layout, folder change: `<from>/<dir>/<file>` → `<to>/<dir>/<file>`.
    static func plan(from: URL, to: URL) -> [ArchiveMove] {
        var moves: [ArchiveMove] = []
        for dir in subdirectories(of: from) {
            for file in regularFiles(in: dir) {
                moves.append(ArchiveMove(source: file,
                                         destination: to.appendingPathComponent(dir.lastPathComponent, isDirectory: true)
                                            .appendingPathComponent(file.lastPathComponent)))
            }
        }
        return moves.sorted { $0.source.path < $1.source.path }
    }

    private static func children(of dir: URL) -> [(url: URL, isDir: Bool, isRegular: Bool)] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { u in
            guard !u.lastPathComponent.hasPrefix("."),
                  let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.isDirectory == true, v.isRegularFile == true)
        }
    }
    private static func subdirectories(of dir: URL) -> [URL] { children(of: dir).filter(\.isDir).map(\.url) }
    private static func regularFiles(in dir: URL) -> [URL] { children(of: dir).filter(\.isRegular).map(\.url) }

    // MARK: Execution

    /// Executes the moves in order. `forceCopy` takes the copy-verify-remove path even on one volume (tests).
    static func execute(_ moves: [ArchiveMove], forceCopy: Bool = false) -> Outcome {
        let fm = FileManager.default
        var out = Outcome()
        for m in moves {
            // 1. Destination already there: a verified duplicate is an earlier interrupted run, anything else is a conflict.
            if fm.fileExists(atPath: m.destination.path) {
                // Source and destination can be one file (symlinked or case-differing folder); removing the "duplicate" would delete the only copy.
                if isSameFile(m.source, m.destination) {
                    out.moved.append(m)
                } else if sameContent(m.source, m.destination) {
                    try? fm.removeItem(at: m.source)   // a failed removal leaves a duplicate; the data is safe twice
                    out.moved.append(m)
                } else {
                    out.skipped.append(m)
                }
                continue
            }
            // 2. Destination directory.
            let destDir = m.destination.deletingLastPathComponent()
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            } catch { out.failed.append(m); continue }
            // 3. Same volume: atomic rename.
            if !forceCopy, let a = volume(of: m.source), let b = volume(of: destDir), a.isEqual(b) {
                if (try? fm.moveItem(at: m.source, to: m.destination)) != nil {
                    restrict(m.destination); out.moved.append(m)
                } else { out.failed.append(m) }
                continue
            }
            // 4. Copy, verify, rename into place, remove the source.
            let part = destDir.appendingPathComponent("." + m.destination.lastPathComponent + ".part")
            try? fm.removeItem(at: part)
            do {
                try fm.copyItem(at: m.source, to: part)
                guard sameContent(m.source, part) else { throw CocoaError(.fileReadCorruptFile) }
                try fm.moveItem(at: part, to: m.destination)
            } catch {
                try? fm.removeItem(at: part)
                out.failed.append(m); continue
            }
            try? fm.removeItem(at: m.source)   // a failure here leaves a duplicate; the next run's step 1 removes it
            restrict(m.destination)
            out.moved.append(m)
        }
        return out
    }

    /// The reverse moves of `outcome.moved`, for a rollback.
    static func reversed(_ outcome: Outcome) -> [ArchiveMove] {
        outcome.moved.reversed().map { ArchiveMove(source: $0.destination, destination: $0.source) }
    }

    private static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let x = (try? a.resourceValues(forKeys: key))?.fileResourceIdentifier,
           let y = (try? b.resourceValues(forKeys: key))?.fileResourceIdentifier {
            return x.isEqual(y)
        }
        return a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
    }

    private static func restrict(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func volume(of url: URL) -> NSObjectProtocol? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
    }

    // MARK: Cleanup

    /// Removes each directory only while it is completely empty (a `.DS_Store` keeps it), deepest first;
    /// never removes `stopAt` or anything outside it.
    static func removeEmptyDirectories(_ dirs: [URL], stopAt: URL) {
        let fm = FileManager.default
        let stop = stopAt.standardizedFileURL.path
        let eligible = dirs.map(\.standardizedFileURL).filter { $0.path.hasPrefix(stop + "/") }
        for d in eligible.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            guard let items = try? fm.contentsOfDirectory(atPath: d.path), items.isEmpty else { continue }
            try? fm.removeItem(at: d)
        }
    }

    // MARK: Comparison

    /// Equal size and equal bytes (1 MiB chunks). False on any read error.
    static func sameContent(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        guard let sa = (try? fm.attributesOfItem(atPath: a.path))?[.size] as? NSNumber,
              let sb = (try? fm.attributesOfItem(atPath: b.path))?[.size] as? NSNumber,
              sa == sb,
              let ha = try? FileHandle(forReadingFrom: a),
              let hb = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? ha.close(); try? hb.close() }
        let chunk = 1 << 20
        do {
            while true {
                // `read(upToCount:)` returns nil (or empty) at end of file; the sizes match, so both end together.
                let da = try ha.read(upToCount: chunk) ?? Data()
                let db = try hb.read(upToCount: chunk) ?? Data()
                if da != db { return false }
                if da.isEmpty { return true }
            }
        } catch { return false }
    }
}
