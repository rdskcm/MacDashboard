// Engine/IPSWPartialStore.swift
// IPHONE-IPSW (Decision 8): the persisted half of a stopped download. A partial firmware and a
// small JSON record live under ~/Library/Caches/<bundle id>/ipsw/ (never App Support, which
// holds the user's history), so a quit, crash or force-quit keeps the downloaded part and the
// next launch can show it as stopped. Reading and cleaning this folder never touches the
// network and never touches ~/Downloads (network-stance: nothing happens on its own at launch).

import Foundation

/// Why a download stopped without the user pressing Stop. Persisted in the record.
enum IPSWStopReason: Codable, Equatable, Sendable {
    case offline, timedOut, transfer(String), appQuit

    init?(_ e: IPSWError) {
        switch e {
        case .offline: self = .offline
        case .timedOut: self = .timedOut
        case .transfer(let detail): self = .transfer(detail)
        default: return nil
        }
    }

    var error: IPSWError {
        switch self {
        case .offline: return .offline
        case .timedOut: return .timedOut
        case .transfer(let detail): return .transfer(detail)
        case .appQuit: return .appQuit
        }
    }
}

/// Everything needed to show, resume, verify and clean up one download without the network.
struct IPSWPartialRecord: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var id: UUID
    /// ProductType, e.g. `iPhone18,2`.
    var identifier: String
    var productVersion: String
    var buildID: String
    /// Apple's `FirmwareURL`; must pass `IPSWData.downloadPolicy` again before a resume.
    var url: URL
    var size: Int64
    var sha256: String?
    var sha1: String?
    var sha1Sources: [IPSWSource]
    var fileName: String
    /// The first 200 response's `ETag`, else its `Last-Modified`; sent back as `If-Range`.
    var validator: String?
    /// Bytes known to be flushed to disk. A resume truncates the partial to this length.
    var checkpoint: Int64
    var startedAt: Date
    /// nil while running: a record found like that at launch is a crash.
    var stoppedAt: Date?
    /// nil = the user pressed Stop.
    var reason: IPSWStopReason?
    /// The partial sits in the hidden staging directory inside Downloads (D20), not next to the record.
    var partInDownloads: Bool

    var digests: ExpectedDigests {
        ExpectedDigests(sha256: sha256, sha1: sha1, sha1Sources: Set(sha1Sources))
    }

    /// The merged build this record was started from, for display and «Start over». The ipsw.me
    /// firmware only carries the digests and the size; its URL is never downloaded (decision 5).
    var build: IPSWBuild {
        let apple = IPSWFirmware(source: .apple, identifier: identifier, version: productVersion, buildID: buildID,
                                 sha256: nil, sha1: sha1Sources.contains(.apple) ? sha1 : nil, fileSize: nil,
                                 url: url, releaseDate: nil, signed: nil)
        let ipswMe = IPSWFirmware(source: .ipswMe, identifier: identifier, version: productVersion, buildID: buildID,
                                  sha256: sha256, sha1: sha1Sources.contains(.ipswMe) ? sha1 : nil, fileSize: size,
                                  url: url, releaseDate: nil, signed: nil)
        return IPSWBuild(buildID: buildID, version: productVersion, apple: apple, ipswMe: ipswMe,
                         isAppleTarget: true, signed: nil)
    }
}

enum IPSWPartialStore {
    /// The partial is flushed and the record's `checkpoint` rewritten every this many bytes (D21).
    static let checkpointBytes: Int64 = 64 << 20
    static let maxAge: TimeInterval = 7 * 86_400

    /// `~/Library/Caches/<bundle id>/ipsw/` (`MacDashboard` when there is no bundle id, as under `swift test`).
    static func defaultRoot() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MacDashboard", isDirectory: true)
            .appendingPathComponent("ipsw", isDirectory: true)
    }

    static func partURL(_ id: UUID, in dir: URL) -> URL {
        dir.appendingPathComponent(IPSWData.stagingPrefix + id.uuidString + ".part", isDirectory: false)
    }

    static func recordURL(_ id: UUID, in root: URL) -> URL {
        root.appendingPathComponent(IPSWData.stagingPrefix + id.uuidString + ".json", isDirectory: false)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func write(_ r: IPSWPartialRecord, root: URL) throws {
        try encoder().encode(r).write(to: recordURL(r.id, in: root), options: .atomic)
    }

    static func read(_ url: URL) -> IPSWPartialRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(IPSWPartialRecord.self, from: data)
    }

    /// Deletes the record and, when it sits in `root`, its partial.
    static func delete(_ r: IPSWPartialRecord, root: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: recordURL(r.id, in: root))
        try? fm.removeItem(at: partURL(r.id, in: root))
    }

    /// Launch and download-start cleanup, inside `root` only (see the cases in the spec, R18).
    /// For a `partInDownloads` record only the `.json` goes here: its partial lives in Downloads,
    /// which launch never touches (the next download start sweeps the hidden directory).
    /// Returns the one surviving record with its partial's URL, nil when nothing is left.
    @discardableResult
    static func cleanup(root: URL, knownIdentifiers: Set<String>?, now: Date) -> (record: IPSWPartialRecord, part: URL)? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
        func remove(_ name: String) { try? fm.removeItem(at: root.appendingPathComponent(name, isDirectory: false)) }
        func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }
        func ext(_ name: String) -> String { (name as NSString).pathExtension }

        let mine = names.filter { $0.hasPrefix(IPSWData.stagingPrefix) }
        let jsonStems = Set(mine.filter { ext($0) == "json" }.map(stem))
        for name in mine {
            switch ext(name) {
            case "ipsw": remove(name)                                   // staged file of the shipped engine
            case "part" where !jsonStems.contains(stem(name)): remove(name)
            default: break
            }
        }

        var alive: [IPSWPartialRecord] = []
        for name in mine where ext(name) == "json" {
            let partName = stem(name) + ".part"
            let url = root.appendingPathComponent(name, isDirectory: false)
            guard let r = read(url), r.version == IPSWPartialRecord.currentVersion else {
                remove(name); remove(partName)
                continue
            }
            let partPresent = fm.fileExists(atPath: root.appendingPathComponent(partName).path)
            let expired = (r.stoppedAt ?? r.startedAt) < now.addingTimeInterval(-maxAge)
            let unknownModel = knownIdentifiers.map { !$0.contains(r.identifier) } ?? false
            if (!r.partInDownloads && !partPresent) || expired || unknownModel {
                remove(name); remove(partName)
                continue
            }
            alive.append(r)
        }

        // One download at a time: the newest start wins.
        alive.sort { $0.startedAt > $1.startedAt }
        for extra in alive.dropFirst() { delete(extra, root: root) }
        guard let keep = alive.first else { return nil }
        return (keep, partURL(keep.id, in: root))
    }
}
