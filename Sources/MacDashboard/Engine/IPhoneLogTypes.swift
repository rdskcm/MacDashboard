// Engine/IPhoneLogTypes.swift
// IPHONE-LOAD-SPEED: crash-log listing split into known / pending types, batch merge and the
// saved type cache. Foundation only (the rig compiles this file). Internal, not private
// (checks-helper-visibility).
// IPHONE-CRASHLOG-ACTIONS: the cached value is the parsed header (`IPhoneLogHeader`).

import Foundation

/// The parsed first-line header of one crash-log file (IPHONE-CRASHLOG-ACTIONS): what the type-read batches carry,
/// what `IPhoneModel.headerCache` and `IPhoneLogTypeStore` keep per "<path>|<size>|<mtime ms>" key. A header read
/// that found no JSON first line is `IPhoneLogHeader()` (all nil, category `.other`); a failed read is not cached.
/// Holds no identifier: `bugType`, the process/executable name and the report time only (identifier-mask).
struct IPhoneLogHeader: Codable, Equatable {
    var bugType: String? = nil
    var process: String? = nil
    var timestamp: Date? = nil
}

/// IPHONE-WIFI D18: why one crash-log header read failed: the AFC step ("open", "read", "limit") and the framework's
/// return code. Memory only (never stored, logged or shown); the live test prints it.
struct IPhoneHeaderReadFailure: Error, Equatable, Sendable {
    let step: String
    let code: Int32
}

/// Result of one type-read batch: cache key → parsed header (`IPhoneLogHeader()` = header has no JSON line),
/// and keys whose
/// header read failed (or could not be attempted because the job failed). Every key handed to a
/// type-read chain appears in exactly one batch, in `read` or in `failed`.
struct IPhoneLogTypeBatch: Equatable {
    var read: [String: IPhoneLogHeader] = [:]
    var failed: Set<String> = []
    /// D18: step and code of each key in `failed` that a read attempt produced.
    var failures: [String: IPhoneHeaderReadFailure] = [:]
    /// D18: keys read on the retry.
    var recovered: Set<String> = []
    var isEmpty: Bool { read.isEmpty && failed.isEmpty }
}

/// What `listLogs` posts straight after the walk.
struct IPhoneLogListing: Equatable {
    var entries: [IPhoneLogEntry]
    /// The known types of the files seen in this walk only (files gone from the phone drop out).
    var known: [String: IPhoneLogHeader]
}

enum IPhoneLogTypes {
    /// Splits a walk: directories skipped; a regular file whose `IPhoneData.logCacheKey` is in
    /// `known` gets its header fields at once (bug_type, category, process, created), any
    /// other gets `category: .pending` with `created` from the file name or mtime and goes into `pending`. `pending` is ordered
    /// newest first (nil dates last, ties by path) so the most recent logs are typed first.
    /// Entries keep the walk order; `source` is `.live`.
    static func split(_ files: [IPhoneAFCEntry], known: [String: IPhoneLogHeader])
        -> (listing: IPhoneLogListing, pending: [IPhoneAFCEntry]) {
        var entries: [IPhoneLogEntry] = []
        var seen: [String: IPhoneLogHeader] = [:]
        var pending: [IPhoneAFCEntry] = []
        for f in files where !f.isDirectory {
            let key = IPhoneData.logCacheKey(path: f.path, size: f.size, modified: f.modified)
            if let h = known[key] {
                seen[key] = h
                entries.append(IPhoneCrashLog.logEntry(path: f.path, size: f.size, modified: f.modified,
                                                       header: h, source: .live))
            } else {
                entries.append(IPhoneCrashLog.pendingEntry(path: f.path, size: f.size, modified: f.modified))
                pending.append(f)
            }
        }
        pending.sort { a, b in
            switch (a.modified, b.modified) {
            case let (x?, y?): return x != y ? x > y : a.path < b.path
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.path < b.path
            }
        }
        return (IPhoneLogListing(entries: entries, known: seen), pending)
    }

    /// Applies a batch: an entry with category `.pending` whose cache key is in `batch.read` gets
    /// that header's fields; one whose key is in
    /// `batch.failed` gets `header: nil` (category `.other`). Every other entry is returned unchanged.
    static func merge(_ entries: [IPhoneLogEntry], _ batch: IPhoneLogTypeBatch) -> [IPhoneLogEntry] {
        entries.map { e in
            guard e.category == .pending else { return e }
            let key = IPhoneData.logCacheKey(path: e.path, size: e.size, modified: e.modified)
            if let h = batch.read[key] {
                return IPhoneCrashLog.logEntry(path: e.path, size: e.size, modified: e.modified, header: h, source: e.source)
            }
            if batch.failed.contains(key) {
                return IPhoneCrashLog.logEntry(path: e.path, size: e.size, modified: e.modified, header: nil, source: e.source)
            }
            return e
        }
    }

    /// `cache` plus `batch.read`, restricted to keys of files in `entries` (a late batch from an
    /// older listing cannot re-add a file that is gone).
    static func updatedCache(_ cache: [String: IPhoneLogHeader], entries: [IPhoneLogEntry],
                             batch: IPhoneLogTypeBatch) -> [String: IPhoneLogHeader] {
        var out = cache
        let live = Set(entries.map { IPhoneData.logCacheKey(path: $0.path, size: $0.size, modified: $0.modified) })
        for (k, v) in batch.read where live.contains(k) { out[k] = v }
        return out
    }
}

/// The saved type cache (D7). Never throws on load; a missing, unreadable or other-version file
/// loads as empty and is overwritten by the next save. Version 2 (IPHONE-CRASHLOG-ACTIONS) stores the parsed
/// header per key; a version-1 file (bug-type strings) loads as empty and is rebuilt by the next listing's type
/// pass, once (D2).
final class IPhoneLogTypeStore {
    static let fileName = "iphone-log-types.json"
    static let version = 2
    private let url: URL

    private struct Envelope: Codable {
        var version: Int
        var devices: [String: [String: IPhoneLogHeader]]
    }

    init(url: URL) { self.url = url }

    /// Drops device keys not in `deviceKeys`.
    func load(keeping deviceKeys: Set<String>) -> [String: [String: IPhoneLogHeader]] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: url),
              let env = try? decoder.decode(Envelope.self, from: data),
              env.version == Self.version else { return [:] }
        return env.devices.filter { deviceKeys.contains($0.key) }
    }

    /// Writes `{"version":2,"devices":…}` (sorted keys, not pretty-printed): creates the dir 0700,
    /// atomic write, then file permissions 0600 — the same steps as `IPhoneStore.save`
    /// minus the rename-aside.
    func save(_ cache: [String: [String: IPhoneLogHeader]]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: Self.version, devices: cache))
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
