// Engine/IPhoneLogTypes.swift
// IPHONE-LOAD-SPEED: crash-log listing split into known / pending types, batch merge and the
// saved type cache. Foundation only (the rig compiles this file). Internal, not private
// (checks-helper-visibility).

import Foundation

/// Result of one type-read batch: cache key → bug_type ("" = header has none), and keys whose
/// header read failed (or could not be attempted because the job failed). Every key handed to a
/// type-read chain appears in exactly one batch, in `read` or in `failed`.
struct IPhoneLogTypeBatch: Equatable {
    var read: [String: String] = [:]
    var failed: Set<String> = []
    var isEmpty: Bool { read.isEmpty && failed.isEmpty }
}

/// What `listLogs` posts straight after the walk.
struct IPhoneLogListing: Equatable {
    var entries: [IPhoneLogEntry]
    /// The known types of the files seen in this walk only (files gone from the phone drop out).
    var known: [String: String]
}

enum IPhoneLogTypes {
    /// Splits a walk: directories skipped; a regular file whose `IPhoneData.logCacheKey` is in
    /// `known` gets its bug_type/category at once (bugType nil when the cached value is ""), any
    /// other gets `bugType: nil, category: .pending` and goes into `pending`. `pending` is ordered
    /// newest first (nil dates last, ties by path) so the most recent logs are typed first.
    /// Entries keep the walk order; `source` is `.live`.
    static func split(_ files: [IPhoneAFCEntry], known: [String: String])
        -> (listing: IPhoneLogListing, pending: [IPhoneAFCEntry]) {
        var entries: [IPhoneLogEntry] = []
        var seen: [String: String] = [:]
        var pending: [IPhoneAFCEntry] = []
        for f in files where !f.isDirectory {
            let key = IPhoneData.logCacheKey(path: f.path, size: f.size, modified: f.modified)
            if let t = known[key] {
                seen[key] = t
                let bt: String? = t.isEmpty ? nil : t
                entries.append(IPhoneLogEntry(path: f.path, size: f.size, modified: f.modified, bugType: bt,
                                              category: IPhoneData.category(bugType: bt), source: .live))
            } else {
                entries.append(IPhoneLogEntry(path: f.path, size: f.size, modified: f.modified, bugType: nil,
                                              category: .pending, source: .live))
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
    /// that bug_type ("" → nil) and `IPhoneData.category(bugType:)`; one whose key is in
    /// `batch.failed` gets `bugType: nil, category: .other`. Every other entry is returned unchanged.
    static func merge(_ entries: [IPhoneLogEntry], _ batch: IPhoneLogTypeBatch) -> [IPhoneLogEntry] {
        entries.map { e in
            guard e.category == .pending else { return e }
            let key = IPhoneData.logCacheKey(path: e.path, size: e.size, modified: e.modified)
            var out = e
            if let t = batch.read[key] {
                out.bugType = t.isEmpty ? nil : t
                out.category = IPhoneData.category(bugType: out.bugType)
            } else if batch.failed.contains(key) {
                out.bugType = nil
                out.category = .other
            }
            return out
        }
    }

    /// `cache` plus `batch.read`, restricted to keys of files in `entries` (a late batch from an
    /// older listing cannot re-add a file that is gone).
    static func updatedCache(_ cache: [String: String], entries: [IPhoneLogEntry],
                             batch: IPhoneLogTypeBatch) -> [String: String] {
        var out = cache
        let live = Set(entries.map { IPhoneData.logCacheKey(path: $0.path, size: $0.size, modified: $0.modified) })
        for (k, v) in batch.read where live.contains(k) { out[k] = v }
        return out
    }
}

/// The saved type cache (D7). Never throws on load; a missing, unreadable or other-version file
/// loads as empty and is overwritten by the next save.
final class IPhoneLogTypeStore {
    static let fileName = "iphone-log-types.json"
    static let version = 1
    private let url: URL

    private struct Envelope: Codable {
        var version: Int
        var devices: [String: [String: String]]
    }

    init(url: URL) { self.url = url }

    /// Drops device keys not in `deviceKeys`.
    func load(keeping deviceKeys: Set<String>) -> [String: [String: String]] {
        guard let data = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.version == Self.version else { return [:] }
        return env.devices.filter { deviceKeys.contains($0.key) }
    }

    /// Writes `{"version":1,"devices":…}` (sorted keys, not pretty-printed): creates the dir 0700,
    /// atomic write, then file permissions 0600 — the same steps as `IPhoneStore.save`
    /// minus the rename-aside.
    func save(_ cache: [String: [String: String]]) throws {
        let encoder = JSONEncoder()
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
