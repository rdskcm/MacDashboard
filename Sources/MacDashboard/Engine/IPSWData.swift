// Engine/IPSWData.swift
// IPHONE-IPSW: the pure half of "which iOS builds can this phone be restored to, and
// download one into ~/Downloads". Models, the two parsers (Apple's version catalogue and
// ipsw.me), the merge into the list the UI shows, the download URL / checksum / size
// policy, file naming, one-pass hashing and staging cleanup. No networking here (that is
// IPSWSources / IPSWDownloader). Foundation + CryptoKit only — covered by Tests/MacDashboardTests.
//
// Two facts from the live research (specs/IPHONE-IPSW.md) shape every type below:
// - Apple's catalogue names ONE restore build per model and carries no "signed" flag;
//   it is not proof of signing (finding F1: iPhone1,1's target is not signed). So
//   `signed` comes from ipsw.me only and stays nil until that source was asked.
// - Download URLs come from Apple's catalogue only (decision 5); ipsw.me's `url` is
//   never downloaded, and every URL must pass `downloadPolicy` (network-stance).

import Foundation
import CryptoKit

enum IPSWSource: String, Equatable, Hashable, Sendable { case apple, ipswMe }

/// One build as ONE source describes it.
struct IPSWFirmware: Equatable, Identifiable, Sendable {
    var source: IPSWSource
    var identifier: String
    var version: String
    var buildID: String
    var sha256: String?
    var sha1: String?
    var fileSize: Int64?
    var url: URL
    var releaseDate: Date?
    /// ipsw.me's per-build flag. Always nil for `.apple` (F1); size and date are nil there too.
    var signed: Bool?
    var id: String { "\(source.rawValue):\(buildID)" }
}

/// Apple's current restore build for one model.
struct IPSWAppleTarget: Equatable, Sendable {
    var identifier: String
    var firmware: IPSWFirmware
}

/// ipsw.me's answer for one model, builds in API order (newest first).
struct IPSWThirdParty: Equatable, Sendable {
    var name: String
    var identifier: String
    var firmwares: [IPSWFirmware]
}

/// The merged view the UI shows: one row per build ID.
struct IPSWBuild: Equatable, Identifiable, Sendable {
    var buildID: String
    var version: String
    var apple: IPSWFirmware?
    var ipswMe: IPSWFirmware?
    /// Apple's catalogue names this build as the model's current restore build.
    var isAppleTarget: Bool
    /// From ipsw.me only (F1); nil when ipsw.me was not asked or does not list the build.
    var signed: Bool?
    var id: String { buildID }
}

/// Status of the build installed on the phone, with its provenance in the case name.
enum InstalledSigning: Equatable {
    case signed, notSigned, notListed          // per ipsw.me
    case isAppleTarget, notAppleTarget         // Apple only (ipsw.me not asked)
    case unknown
}

enum DigestAlgorithm: Equatable, Hashable, Sendable { case sha256, sha1 }

/// Whether a build can be downloaded here (decision 5).
enum DownloadAvailability: Equatable, Sendable {
    case available(URL)        // Apple lists it and its URL passes downloadPolicy
    case noSecureAppleLink     // Apple lists it, but its URL fails downloadPolicy (http, edgesuite, protected://, …)
    case notFromApple          // only ipsw.me lists it; its URL is never used
}

/// The checksums a download must match. `sha256` is only ever ipsw.me's.
struct ExpectedDigests: Equatable, Sendable {
    var sha256: String?
    var sha1: String?
    var sha1Sources: Set<IPSWSource>
}

/// One digest the finished file was verified against, and who published it (decision 3).
struct VerifiedDigest: Equatable, Hashable, Sendable {
    var algorithm: DigestAlgorithm
    var sources: Set<IPSWSource>
}

enum IPSWError: Error, Equatable {
    case noIdentifier, badIdentifier(String), unknownDevice, http(Int), offline, timedOut, badResponse
    case notDownloadable(String), noChecksum, noSize, sourcesDisagree
    case notEnoughSpace(needed: Int64, available: Int64), downloadsDenied
    case sizeMismatch(expected: Int64, actual: Int64), checksumMismatch
    case transfer(String), fileSystem(String), busy, cancelled
}

enum IPSWData {
    /// Apple's device-software catalogue (the one Finder and Configurator read). Fixed URL;
    /// the request carries nothing device-specific.
    static let catalogueURL = URL(string:
        "https://itunes.apple.com/WebObjects/MZStore.woa/wa/com.apple.jingle.appserver.client.MZITunesClientCheck/version")!
    static let ipswMeBase = URL(string: "https://api.ipsw.me/v4/")!
    static let catalogueMaxBytes = 16 * 1024 * 1024    // observed 6.3 MB
    static let ipswMeMaxBytes = 2 * 1024 * 1024        // observed ≤ 51 KB
    /// The download allowlist (network-stance): exact hosts, https only. Widening it is a user decision.
    static let firmwareHosts: Set<String> = ["updates.cdn-apple.com", "secure-appldnld.apple.com"]
    /// Free space required beyond the file itself.
    static let spaceMargin: Int64 = 1 << 30
    /// Every staged file and nothing else starts with this, so stale staging can be swept safely.
    static let stagingPrefix = "MacDashboard-ipsw-"
    /// The hidden staging directory inside ~/Downloads, used only when the temp dir is on another volume.
    static let hiddenStagingName = ".MacDashboard-ipsw-staging"
    static let hashChunkSize = 8 * 1024 * 1024

    // MARK: identifiers

    /// `iPhone18,2`-shaped: letters, digits, a comma, digits. Anything else is never sent anywhere.
    static func isValidIdentifier(_ s: String) -> Bool {
        s.count <= 32 && s.range(of: "^[A-Za-z]+[0-9]+,[0-9]+$", options: .regularExpression) != nil
    }

    static func ipswMeURL(identifier: String) -> URL? {
        guard isValidIdentifier(identifier) else { return nil }
        return URL(string: ipswMeBase.absoluteString + "device/" + identifier + "?type=ipsw")
    }

    // MARK: parsers

    /// Apple's catalogue: the model's entry under the HIGHEST numeric key that has it, then
    /// `Unknown.Universal.Restore`, else the first `Restore` filed under its own build.
    /// `.success(nil)` = Apple does not list the model; `.badResponse` = not the catalogue.
    static func parseCatalogue(_ data: Data, identifier: String) -> Result<IPSWAppleTarget?, IPSWError> {
        guard !data.isEmpty, data.count <= catalogueMaxBytes,
              let root = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let byVersion = root["MobileDeviceSoftwareVersionsByVersion"] as? [String: Any]
        else { return .failure(.badResponse) }

        var best: (key: Int, model: [String: Any])?
        for (key, value) in byVersion {
            guard let n = Int(key),
                  let versions = (value as? [String: Any])?["MobileDeviceSoftwareVersions"] as? [String: Any],
                  let model = versions[identifier] as? [String: Any] else { continue }
            if best == nil || n > best!.key { best = (n, model) }
        }
        guard let model = best?.model else { return .success(nil) }

        var restore: [String: Any]?
        if let universal = (model["Unknown"] as? [String: Any])?["Universal"] as? [String: Any] {
            restore = universal["Restore"] as? [String: Any]
        }
        if restore == nil {
            // Sorted so the choice does not depend on dictionary order. `SameAs` entries have no Restore.
            for key in model.keys.sorted() {
                if let r = (model[key] as? [String: Any])?["Restore"] as? [String: Any],
                   r["BuildVersion"] as? String == key {
                    restore = r
                    break
                }
            }
        }
        guard let r = restore else { return .success(nil) }
        guard let build = r["BuildVersion"] as? String, !build.isEmpty,
              let version = r["ProductVersion"] as? String, !version.isEmpty,
              let urlString = r["FirmwareURL"] as? String, let url = URL(string: urlString)
        else { return .failure(.badResponse) }

        let firmware = IPSWFirmware(source: .apple, identifier: identifier, version: version, buildID: build,
                                    sha256: nil, sha1: hexDigest(r["FirmwareSHA1"], length: 40), fileSize: nil,
                                    url: url, releaseDate: nil, signed: nil)
        return .success(IPSWAppleTarget(identifier: identifier, firmware: firmware))
    }

    /// ipsw.me `/v4/device/<id>?type=ipsw`. A firmware with a missing or mistyped required
    /// field is skipped; md5 is never read.
    static func parseIPSWMe(_ data: Data) -> Result<IPSWThirdParty, IPSWError> {
        guard !data.isEmpty, data.count <= ipswMeMaxBytes,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = root["name"] as? String,
              let identifier = root["identifier"] as? String,
              let list = root["firmwares"] as? [Any]
        else { return .failure(.badResponse) }

        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime]
        var firmwares: [IPSWFirmware] = []
        for item in list {
            guard let f = item as? [String: Any],
                  let version = f["version"] as? String, !version.isEmpty,
                  let build = f["buildid"] as? String, !build.isEmpty,
                  let urlString = f["url"] as? String, let url = URL(string: urlString),
                  let size = (f["filesize"] as? NSNumber).flatMap({ integerValue($0) }), size > 0,
                  let signed = (f["signed"] as? NSNumber).flatMap({ boolValue($0) })
            else { continue }
            let date = (f["releasedate"] as? String).flatMap { dates.date(from: $0) }
            firmwares.append(IPSWFirmware(source: .ipswMe, identifier: (f["identifier"] as? String) ?? identifier,
                                          version: version, buildID: build,
                                          sha256: hexDigest(f["sha256sum"], length: 64),
                                          sha1: hexDigest(f["sha1sum"], length: 40),
                                          fileSize: size, url: url, releaseDate: date, signed: signed))
        }
        return .success(IPSWThirdParty(name: name, identifier: identifier, firmwares: firmwares))
    }

    /// A JSON integer (not a Bool, not a fraction) as Int64.
    static func integerValue(_ n: NSNumber) -> Int64? {
        guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.int64Value
        return NSNumber(value: v) == n ? v : nil
    }

    /// A JSON Bool (not a number) as Bool.
    static func boolValue(_ n: NSNumber) -> Bool? {
        CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : nil
    }

    /// Lowercased hex of exactly `length` characters, else nil (empty and malformed = absent).
    static func hexDigest(_ value: Any?, length: Int) -> String? {
        guard let s = (value as? String)?.lowercased(), s.count == length,
              s.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return s
    }

    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: merge + signed status

    /// One build per build ID: Apple's target first, then ipsw.me's builds in API order.
    static func merge(apple: IPSWAppleTarget?, ipswMe: IPSWThirdParty?) -> [IPSWBuild] {
        var out: [IPSWBuild] = []
        var index: [String: Int] = [:]
        if let a = apple?.firmware {
            index[a.buildID] = 0
            out.append(IPSWBuild(buildID: a.buildID, version: a.version, apple: a, ipswMe: nil,
                                 isAppleTarget: true, signed: nil))
        }
        for f in ipswMe?.firmwares ?? [] {
            if let i = index[f.buildID] {
                if out[i].ipswMe == nil {
                    out[i].ipswMe = f
                    out[i].signed = f.signed
                }
                continue
            }
            index[f.buildID] = out.count
            out.append(IPSWBuild(buildID: f.buildID, version: f.version, apple: nil, ipswMe: f,
                                 isAppleTarget: false, signed: f.signed))
        }
        return out
    }

    /// The installed build's status. Matched by build when the phone reported one (never
    /// falling back to the version then: one version can have several builds), else by
    /// version when exactly one build has it.
    static func installedSigning(_ builds: [IPSWBuild], build: String?, version: String?) -> InstalledSigning {
        let askedIPSWMe = builds.contains { $0.ipswMe != nil }
        let askedApple = builds.contains { $0.apple != nil }
        guard askedIPSWMe || askedApple else { return .unknown }

        let match: IPSWBuild?
        if let b = build, !b.isEmpty {
            match = builds.first { $0.buildID == b }
        } else if let v = version, !v.isEmpty {
            let hits = builds.filter { $0.version == v }
            guard hits.count <= 1 else { return .unknown }
            match = hits.first
        } else {
            return .unknown
        }

        if askedIPSWMe {
            guard let signed = match?.ipswMe?.signed else { return .notListed }
            return signed ? .signed : .notSigned
        }
        return match?.isAppleTarget == true ? .isAppleTarget : .notAppleTarget
    }

    // MARK: download policy (specs/IPHONE-IPSW.md § Download security, network-stance)

    /// Rules 1-2: https, an EXACT allowlisted host (no suffix matching), default port, no
    /// credentials, a `.ipsw` path. nil = allowed.
    static func downloadPolicy(_ url: URL) -> IPSWError? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" else { return .notDownloadable(scheme) }
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        guard firmwareHosts.contains(host), url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else { return .notDownloadable(host) }
        guard url.pathExtension.lowercased() == "ipsw" else { return .notDownloadable(url.lastPathComponent) }
        return nil
    }

    /// Decision 5: only Apple's URL is ever downloaded.
    static func availability(_ b: IPSWBuild) -> DownloadAvailability {
        guard let a = b.apple else { return .notFromApple }
        return downloadPolicy(a.url) == nil ? .available(a.url) : .noSecureAppleLink
    }

    /// Rules 3-4: every digest any source published, cross-checked before a byte is fetched.
    static func expectedDigests(_ b: IPSWBuild) -> Result<ExpectedDigests, IPSWError> {
        let a = b.apple, i = b.ipswMe
        for f in [a, i].compactMap({ $0 }) where f.buildID != b.buildID {
            return .failure(.sourcesDisagree)
        }
        if let s1 = a?.sha1, let s2 = i?.sha1, s1 != s2 { return .failure(.sourcesDisagree) }
        var sources = Set<IPSWSource>()
        if a?.sha1 != nil { sources.insert(.apple) }
        if i?.sha1 != nil { sources.insert(.ipswMe) }
        let digests = ExpectedDigests(sha256: i?.sha256, sha1: a?.sha1 ?? i?.sha1, sha1Sources: sources)
        guard digests.sha256 != nil || digests.sha1 != nil else { return .failure(.noChecksum) }
        return .success(digests)
    }

    /// Rule 5: ipsw.me's `filesize`, else the HEAD `Content-Length`; both present and different = refuse.
    static func expectedSize(_ b: IPSWBuild, headLength: Int64?) -> Result<Int64, IPSWError> {
        let listed = b.ipswMe?.fileSize.flatMap { $0 > 0 ? $0 : nil }
        let head = headLength.flatMap { $0 > 0 ? $0 : nil }
        switch (listed, head) {
        case let (x?, y?): return x == y ? .success(x) : .failure(.sourcesDisagree)
        case let (x?, nil): return .success(x)
        case let (nil, y?): return .success(y)
        case (nil, nil): return .failure(.noSize)
        }
    }

    /// Rule 6: nil = enough room.
    static func spaceCheck(needed size: Int64, available: Int64?) -> IPSWError? {
        guard let available else { return nil }   // the volume did not say; the transfer fails later if it fills
        let needed = size + spaceMargin
        return available >= needed ? nil : .notEnoughSpace(needed: needed, available: available)
    }

    // MARK: naming

    /// The URL's last path component (percent-decoded), or a built name when that is unusable.
    static func fileName(for b: IPSWBuild) -> String {
        let f = b.apple ?? b.ipswMe
        let candidate = f?.url.lastPathComponent ?? ""
        let usable = !candidate.isEmpty && !candidate.hasPrefix(".") && !candidate.contains("/")
            && !candidate.contains(":") && candidate.lowercased().hasSuffix(".ipsw")
        if usable { return candidate }
        let raw = "\(f?.identifier ?? "iPhone")_\(b.version)_\(b.buildID)_Restore.ipsw"
        return raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    }

    /// Rule 9: attempt 1 = the name itself, 2…999 = `<stem> (n).ipsw`, then a UUID suffix.
    static func nextName(_ name: String, attempt: Int) -> String {
        let hasExt = name.lowercased().hasSuffix(".ipsw")
        let stem = hasExt ? String(name.dropLast(5)) : name
        let ext = hasExt ? String(name.suffix(5)) : ".ipsw"
        if attempt <= 1 { return stem + ext }
        if attempt > 999 { return "\(stem)-\(UUID().uuidString)\(ext)" }
        return "\(stem) (\(attempt))\(ext)"
    }

    // MARK: hashing + staging

    /// SHA-256 and/or SHA-1 of `file` in ONE pass, 8 MiB at a time. Throws only IPSWError.
    static func digests(of file: URL, want: Set<DigestAlgorithm>,
                        progress: (Int64) -> Void, isCancelled: () -> Bool) throws -> [DigestAlgorithm: String] {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: file) } catch { throw IPSWError.fileSystem(error.localizedDescription) }
        defer { try? handle.close() }
        var sha256: SHA256? = want.contains(.sha256) ? SHA256() : nil
        var sha1: Insecure.SHA1? = want.contains(.sha1) ? Insecure.SHA1() : nil
        var done: Int64 = 0
        while true {
            if isCancelled() { throw IPSWError.cancelled }
            let chunk: Data?
            do {
                chunk = try autoreleasepool { try handle.read(upToCount: hashChunkSize) }
            } catch {
                throw IPSWError.fileSystem(error.localizedDescription)
            }
            guard let data = chunk, !data.isEmpty else { break }
            sha256?.update(data: data)
            sha1?.update(data: data)
            done += Int64(data.count)
            progress(done)
        }
        var out: [DigestAlgorithm: String] = [:]
        if let h = sha256 { out[.sha256] = hex(h.finalize()) }
        if let h = sha1 { out[.sha1] = hex(h.finalize()) }
        return out
    }

    /// Rule 10: deletes `MacDashboard-ipsw-*` entries directly inside `dir` — nothing else.
    static func removeStaleStaging(in dir: URL, fileManager: FileManager = .default) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasPrefix(stagingPrefix) {
            try? fileManager.removeItem(at: dir.appendingPathComponent(name, isDirectory: false))
        }
    }

    // MARK: messages

    static func message(for e: IPSWError) -> String {
        switch e {
        case .noIdentifier, .badIdentifier: return L.ipswErrNoIdentifier
        case .unknownDevice: return L.ipswErrUnknownDevice
        case .http(let code): return L.ipswErrHTTP(code)
        case .offline: return L.ipswErrOffline
        case .timedOut: return L.ipswErrTimedOut
        case .badResponse: return L.ipswErrBadResponse
        case .notDownloadable: return L.ipswErrNotDownloadable
        case .noChecksum: return L.ipswErrNoChecksum
        case .noSize: return L.ipswErrNoSize
        case .sourcesDisagree: return L.ipswErrSourcesDisagree
        case .notEnoughSpace(let needed, let available):
            return L.ipswErrNotEnoughSpace(fmtCapacity(needed), fmtCapacity(available))
        case .downloadsDenied: return L.ipswErrDownloadsDenied
        case .sizeMismatch: return L.ipswErrSizeMismatch
        case .checksumMismatch: return L.ipswErrChecksumMismatch
        case .transfer(let detail): return L.ipswErrTransfer(detail)
        case .fileSystem(let detail): return L.ipswErrFileSystem(detail)
        case .busy: return L.ipswBusy
        case .cancelled: return L.ipswCancelled
        }
    }

    /// Decision 3: the exact verified set as one line, e.g.
    /// "Verified: SHA-256 (ipsw.me), SHA-1 (Apple, ipsw.me) and size".
    static func verifiedText(_ verified: Set<VerifiedDigest>) -> String {
        func name(_ s: IPSWSource) -> String { s == .apple ? "Apple" : "ipsw.me" }
        let order: [DigestAlgorithm] = [.sha256, .sha1]
        let parts = order.compactMap { alg -> String? in
            guard let v = verified.first(where: { $0.algorithm == alg }) else { return nil }
            let label = alg == .sha256 ? "SHA-256" : "SHA-1"
            let who = [IPSWSource.apple, .ipswMe].filter { v.sources.contains($0) }.map(name).joined(separator: ", ")
            return who.isEmpty ? label : "\(label) (\(who))"
        }
        return L.ipswVerified(parts.joined(separator: ", ") + " " + L.ipswVerifiedSizeOnly)
    }
}
