// Tests/MacDashboardTests/IPSWTests.swift
// IPHONE-IPSW: parsers, merge/signed status, download policy, digests, naming, staging,
// finalize, the two sources and the model — all on recorded fixtures (Tests/APIFixtures)
// with a stubbed fetch. No network; files only inside fresh temp directories.
import CryptoKit
import Foundation
import Testing
@testable import MacDashboard

// MARK: - helpers

private func apiFixture(_ path: String) throws -> Data {
    try Data(contentsOf: apiFixturesRoot.appendingPathComponent(path))
}

private let cataloguePath = "apple/itunes-version-trimmed-2026-10-16.plist"
private let ipsw18Path = "ipswme/device-iphone18-2-2026-10-15.json"
private let ipsw10Path = "ipswme/device-iphone10-3-2026-10-15.json"
private let ipsw1Path = "ipswme/device-iphone1-1-2026-10-15.json"
private let notFoundPath = "ipswme/not-found-2026-10-15.json"

private let sha1_24A446 = "861093bf5cd647f99099733133a5c5af9b6fde5d"
private let sha256_24A446 = "b1535ded2e84bf1d7c716372e498bd10720b2b47374e7e1b4f885a6075b921eb"
private let url_24A446 = "https://updates.cdn-apple.com/2026FallFCS/3b7299da-a6a5-4bf6-82db-cd37f8c2d160/iPhone18,2_27.0.1_24A446_Restore.ipsw"

private func value<T>(_ r: Result<T, IPSWError>) -> T? {
    if case .success(let v) = r { return v }
    return nil
}

private func failure<T>(_ r: Result<T, IPSWError>) -> IPSWError? {
    if case .failure(let e) = r { return e }
    return nil
}

private func appleTarget(_ id: String, catalogue: Data? = nil) throws -> IPSWAppleTarget {
    let data = try catalogue ?? apiFixture(cataloguePath)
    return try #require(value(IPSWData.parseCatalogue(data, identifier: id)) ?? nil)
}

private func ipswList(_ path: String) throws -> IPSWThirdParty {
    try #require(value(IPSWData.parseIPSWMe(try apiFixture(path))))
}

/// The catalogue fixture re-serialized after `edit` (to build variants from real data).
private func editedCatalogue(_ edit: (inout [String: Any]) -> Void) throws -> Data {
    var root = try #require(try PropertyListSerialization.propertyList(
        from: apiFixture(cataloguePath), options: [], format: nil) as? [String: Any])
    edit(&root)
    return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
}

private func firmware(_ source: IPSWSource, build: String = "24A446", version: String = "27.0.1",
                      sha256: String? = nil, sha1: String? = nil, size: Int64? = nil,
                      url: String = url_24A446, signed: Bool? = nil) -> IPSWFirmware {
    IPSWFirmware(source: source, identifier: "iPhone18,2", version: version, buildID: build, sha256: sha256,
                 sha1: sha1, fileSize: size, url: URL(string: url)!, releaseDate: nil, signed: signed)
}

private func tempDir(_ label: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacDashboardTests-ipsw-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Records every request and answers from `respond`; `IPSWSources(fetch:)` over it.
final class IPSWStubFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let respond: @Sendable (URLRequest) throws -> (Data, Int, [String: String])

    init(_ respond: @escaping @Sendable (URLRequest) throws -> (Data, Int, [String: String])) {
        self.respond = respond
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func count(host: String) -> Int {
        requests.filter { $0.url?.host == host }.count
    }

    var sources: IPSWSources {
        IPSWSources(fetch: { [self] request in try self.handle(request) })
    }

    private func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
        let (data, status, headers) = try respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (data, response)
    }
}

/// Answers both APIs from the fixtures.
private func fixtureFetch() throws -> IPSWStubFetch {
    let catalogue = try apiFixture(cataloguePath)
    let device = try apiFixture(ipsw18Path)
    return IPSWStubFetch { request in
        switch request.url?.host {
        case "itunes.apple.com": return (catalogue, 200, [:])
        case "api.ipsw.me": return (device, 200, [:])
        default: return (Data(), 500, [:])
        }
    }
}

// MARK: - pure helpers

struct IPSWTests {

    // MARK: Apple catalogue

    @Test func catalogueTargets() throws {
        let t18 = try appleTarget("iPhone18,2")
        #expect(t18.identifier == "iPhone18,2")
        #expect(t18.firmware.source == .apple)
        #expect(t18.firmware.version == "27.0.1")
        #expect(t18.firmware.buildID == "24A446")
        #expect(t18.firmware.sha1 == sha1_24A446)
        #expect(t18.firmware.url.absoluteString == url_24A446)
        #expect(t18.firmware.signed == nil && t18.firmware.sha256 == nil && t18.firmware.fileSize == nil,
                "Apple publishes no signed flag, SHA-256 or size (F1)")

        let t10 = try appleTarget("iPhone10,3")
        #expect(t10.firmware.buildID == "20H392", "highest key wins: 17's 20H392, not 16's http 15G77")
        #expect(t10.firmware.url.scheme == "https")

        let t16 = try appleTarget("iPhone16,2")
        #expect(t16.firmware.buildID == "24A446")
        #expect(t16.firmware.sha1 == "6e9cce69b1b945d5e27062b9575bd98d59710da9")
    }

    @Test func catalogueUnknownModelIsNil() throws {
        let r = IPSWData.parseCatalogue(try apiFixture(cataloguePath), identifier: "iPhone99,9")
        #expect(r == .success(nil))
    }

    @Test func catalogueWithoutUnknownUsesSelfKeyedRestore() throws {
        let data = try editedCatalogue { root in
            var byVersion = root["MobileDeviceSoftwareVersionsByVersion"] as! [String: Any]
            var v17 = byVersion["17"] as! [String: Any]
            var versions = v17["MobileDeviceSoftwareVersions"] as! [String: Any]
            var model = versions["iPhone18,2"] as! [String: Any]
            model["Unknown"] = nil
            versions["iPhone18,2"] = model
            v17["MobileDeviceSoftwareVersions"] = versions
            byVersion["17"] = v17
            root["MobileDeviceSoftwareVersionsByVersion"] = byVersion
        }
        let t = try appleTarget("iPhone18,2", catalogue: data)
        #expect(t.firmware.buildID == "24A446")
        #expect(t.firmware.sha1 == sha1_24A446)
    }

    @Test func catalogueRejectsGarbage() throws {
        let full = try apiFixture(cataloguePath)
        let emptyArray = try PropertyListSerialization.data(fromPropertyList: [Any](), format: .xml, options: 0)
        let cases: [Data] = [
            Data("garbage".utf8),
            emptyArray,
            Data(),
            full.prefix(full.count / 2),
            Data(count: IPSWData.catalogueMaxBytes + 1),
        ]
        for data in cases {
            #expect(IPSWData.parseCatalogue(data, identifier: "iPhone18,2") == .failure(.badResponse))
        }
    }

    // MARK: ipsw.me

    @Test func ipswMe18() throws {
        let list = try ipswList(ipsw18Path)
        #expect(list.name == "iPhone 17 Pro Max")
        #expect(list.identifier == "iPhone18,2")
        #expect(list.firmwares.map(\.buildID) == ["24A446", "24A437", "23G90"], "API order kept")
        let f = list.firmwares[0]
        #expect(f.source == .ipswMe)
        #expect(f.version == "27.0.1")
        #expect(f.signed == true)
        #expect(f.fileSize == 12_708_916_186, "sizes past Int32 survive as Int64")
        #expect(f.sha256 == sha256_24A446)
        #expect(f.sha1 == sha1_24A446)
        #expect(f.url.absoluteString == url_24A446)
        #expect(f.releaseDate == ISO8601DateFormatter().date(from: "2026-09-28T18:54:15Z"))
        #expect(list.firmwares[1].signed == false)
    }

    @Test func ipswMe10EmptySha256AndHttpURLs() throws {
        let list = try ipswList(ipsw10Path)
        let b16D57 = try #require(list.firmwares.first { $0.buildID == "16D57" })
        #expect(b16D57.sha256 == nil, "an empty sha256sum is absent")
        #expect(b16D57.sha1 == "6d21d7cf9bd387d9817a194ae74b803130dbe1cd")
        #expect(list.firmwares.filter { $0.url.scheme == "http" }.map(\.buildID) == ["16D57", "15B93"])
    }

    @Test func ipswMe1NullDate() throws {
        let list = try ipswList(ipsw1Path)
        #expect(list.firmwares.count == 1)
        #expect(list.firmwares[0].releaseDate == nil)
        #expect(list.firmwares[0].buildID == "1A543a")
    }

    @Test func ipswMeRejectsAndSkips() throws {
        #expect(IPSWData.parseIPSWMe(try apiFixture(notFoundPath)) == .failure(.badResponse))
        #expect(IPSWData.parseIPSWMe(Data(count: IPSWData.ipswMeMaxBytes + 1)) == .failure(.badResponse))
        #expect(IPSWData.parseIPSWMe(Data()) == .failure(.badResponse))

        // A firmware whose filesize is a String is skipped; the others stay.
        var root = try #require(try JSONSerialization.jsonObject(with: apiFixture(ipsw18Path)) as? [String: Any])
        var firmwares = try #require(root["firmwares"] as? [[String: Any]])
        firmwares[1]["filesize"] = "12708960754"
        firmwares[2]["signed"] = 1   // a number, not a Bool
        root["firmwares"] = firmwares
        let list = try #require(value(IPSWData.parseIPSWMe(try JSONSerialization.data(withJSONObject: root))))
        #expect(list.firmwares.map(\.buildID) == ["24A446"])
    }

    // MARK: merge + installed build

    @Test func mergeAppleOnly() throws {
        let builds = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: nil)
        #expect(builds.count == 1)
        #expect(builds[0].isAppleTarget && builds[0].signed == nil && builds[0].ipswMe == nil)
        #expect(IPSWData.installedSigning(builds, build: "24A446", version: nil) == .isAppleTarget)
        #expect(IPSWData.installedSigning(builds, build: "24A437", version: nil) == .notAppleTarget)
        #expect(IPSWData.installedSigning(builds, build: nil, version: "27.0.1") == .isAppleTarget)
    }

    @Test func mergeIPSWMeOnly() throws {
        let builds = IPSWData.merge(apple: nil, ipswMe: try ipswList(ipsw18Path))
        #expect(builds.map(\.buildID) == ["24A446", "24A437", "23G90"])
        #expect(builds.allSatisfy { !$0.isAppleTarget && $0.apple == nil })
        #expect(IPSWData.installedSigning(builds, build: "24A446", version: nil) == .signed)
        #expect(IPSWData.installedSigning(builds, build: "24A437", version: nil) == .notSigned)
        #expect(IPSWData.installedSigning(builds, build: "99Z999", version: nil) == .notListed)
        #expect(IPSWData.installedSigning(builds, build: nil, version: "27.0") == .notSigned)
    }

    @Test func mergeBoth() throws {
        let builds = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: try ipswList(ipsw18Path))
        #expect(builds.map(\.buildID) == ["24A446", "24A437", "23G90"], "Apple's build merged, not duplicated")
        #expect(builds[0].isAppleTarget && builds[0].apple != nil && builds[0].ipswMe != nil)
        #expect(builds[0].signed == true)
        #expect(!builds[1].isAppleTarget && builds[1].signed == false)
        #expect(IPSWData.installedSigning(builds, build: "24A446", version: nil) == .signed)
    }

    @Test func appleTargetIsNotProofOfSigning() {
        // F1: iPhone1,1's catalogue target 7E18 is signed: false on ipsw.me.
        let a = IPSWAppleTarget(identifier: "iPhone1,1", firmware: firmware(.apple, build: "7E18", version: "3.1.3"))
        let i = IPSWThirdParty(name: "iPhone 2G", identifier: "iPhone1,1",
                               firmwares: [firmware(.ipswMe, build: "7E18", version: "3.1.3", size: 1, signed: false)])
        let builds = IPSWData.merge(apple: a, ipswMe: i)
        #expect(builds.count == 1 && builds[0].isAppleTarget && builds[0].signed == false)
        #expect(IPSWData.installedSigning(builds, build: "7E18", version: nil) == .notSigned)
    }

    @Test func installedSigningUnknown() throws {
        let twins = IPSWThirdParty(name: "x", identifier: "iPhone18,2", firmwares: [
            firmware(.ipswMe, build: "24A446", version: "27.0", size: 1, signed: true),
            firmware(.ipswMe, build: "24A447", version: "27.0", size: 1, signed: false),
        ])
        let builds = IPSWData.merge(apple: nil, ipswMe: twins)
        #expect(IPSWData.installedSigning(builds, build: nil, version: "27.0") == .unknown, "two builds share the version")
        #expect(IPSWData.installedSigning(builds, build: nil, version: nil) == .unknown)
        #expect(IPSWData.installedSigning([], build: "24A446", version: "27.0") == .unknown)
    }

    // MARK: availability (decision 5) + policy

    @Test func availability() throws {
        let apple18 = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: nil)[0]
        #expect(IPSWData.availability(apple18) == .available(URL(string: url_24A446)!))

        // The catalogue's iPhone10,3 target under key 16 (http 15G77): drop key 17.
        let only16 = try editedCatalogue { root in
            var byVersion = root["MobileDeviceSoftwareVersionsByVersion"] as! [String: Any]
            byVersion["17"] = nil
            root["MobileDeviceSoftwareVersionsByVersion"] = byVersion
        }
        let t15G77 = try appleTarget("iPhone10,3", catalogue: only16)
        #expect(t15G77.firmware.buildID == "15G77" && t15G77.firmware.url.scheme == "http")
        #expect(IPSWData.availability(IPSWData.merge(apple: t15G77, ipswMe: nil)[0]) == .noSecureAppleLink)

        for edgesuite in ["http://appldnld.apple.com.edgesuite.net/x/iPhone1,1_3.1.3_7E18_Restore.ipsw",
                          "https://appldnld.apple.com.edgesuite.net/x/iPhone1,1_3.1.3_7E18_Restore.ipsw"] {
            let a = IPSWAppleTarget(identifier: "iPhone1,1", firmware: firmware(.apple, build: "7E18", url: edgesuite))
            #expect(IPSWData.availability(IPSWData.merge(apple: a, ipswMe: nil)[0]) == .noSecureAppleLink)
        }

        // An ipsw.me-only build is never downloadable, even with an allowlisted https URL.
        let b24A437 = try #require(IPSWData.merge(apple: nil, ipswMe: try ipswList(ipsw18Path)).first { $0.buildID == "24A437" })
        #expect(IPSWData.downloadPolicy(b24A437.ipswMe!.url) == nil)
        #expect(IPSWData.availability(b24A437) == .notFromApple)
    }

    @Test func downloadPolicy() {
        for ok in ["https://updates.cdn-apple.com/2026FallFCS/a/iPhone18,2_27.0.1_24A446_Restore.ipsw",
                   "https://secure-appldnld.apple.com/iPhone/x/iPhone1,1_1.0_1A543a_Restore.ipsw",
                   "https://UPDATES.cdn-apple.com/a/b.IPSW"] {
            #expect(IPSWData.downloadPolicy(URL(string: ok)!) == nil, "allowed: \(ok)")
        }
        for bad in ["http://updates-http.cdn-apple.com/a/b.ipsw",
                    "http://appldnld.apple.com/a/b.ipsw",
                    "https://appldnld.apple.com.edgesuite.net/x.ipsw",
                    "https://updates.cdn-apple.com.evil.example/x.ipsw",
                    "https://evil.example/x.ipsw",
                    "protected://pfd.apple.com/x.ipsw",
                    "https://updates.cdn-apple.com/x.zip",
                    "https://user:pw@updates.cdn-apple.com/x.ipsw",
                    "https://updates.cdn-apple.com:8443/x.ipsw"] {
            if case .notDownloadable? = IPSWData.downloadPolicy(URL(string: bad)!) {} else {
                Issue.record("refused: \(bad)")
            }
        }
    }

    // MARK: digests + size

    @Test func expectedDigests() throws {
        let both = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: try ipswList(ipsw18Path))[0]
        let d = try #require(value(IPSWData.expectedDigests(both)))
        #expect(d == ExpectedDigests(sha256: sha256_24A446, sha1: sha1_24A446, sha1Sources: [.apple, .ipswMe]))

        var disagree = both
        disagree.ipswMe?.sha1 = "0000000000000000000000000000000000000000"
        #expect(failure(IPSWData.expectedDigests(disagree)) == .sourcesDisagree)

        var otherBuild = both
        otherBuild.ipswMe?.buildID = "24A437"
        #expect(failure(IPSWData.expectedDigests(otherBuild)) == .sourcesDisagree)

        let none = IPSWBuild(buildID: "24A446", version: "27.0.1", apple: firmware(.apple), ipswMe: nil,
                             isAppleTarget: true, signed: nil)
        #expect(failure(IPSWData.expectedDigests(none)) == .noChecksum)

        let appleOnly = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: nil)[0]
        #expect(value(IPSWData.expectedDigests(appleOnly)) == ExpectedDigests(sha256: nil, sha1: sha1_24A446, sha1Sources: [.apple]))

        let fields = Mirror(reflecting: d).children.compactMap(\.label)
        #expect(!fields.contains { $0.lowercased().contains("md5") }, "md5 is never part of the policy")
    }

    @Test func expectedSize() throws {
        let both = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: try ipswList(ipsw18Path))[0]
        #expect(IPSWData.expectedSize(both, headLength: nil) == .success(12_708_916_186))
        #expect(IPSWData.expectedSize(both, headLength: 12_708_916_186) == .success(12_708_916_186))
        #expect(IPSWData.expectedSize(both, headLength: 5) == .failure(.sourcesDisagree))
        let appleOnly = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: nil)[0]
        #expect(IPSWData.expectedSize(appleOnly, headLength: 100) == .success(100))
        #expect(IPSWData.expectedSize(appleOnly, headLength: nil) == .failure(.noSize))
        #expect(IPSWData.expectedSize(appleOnly, headLength: 0) == .failure(.noSize))
    }

    @Test func spaceCheck() {
        #expect(IPSWData.spaceCheck(needed: 10, available: 10 + IPSWData.spaceMargin) == nil)
        #expect(IPSWData.spaceCheck(needed: 10, available: 9 + IPSWData.spaceMargin)
                == .notEnoughSpace(needed: 10 + IPSWData.spaceMargin, available: 9 + IPSWData.spaceMargin))
        #expect(IPSWData.spaceCheck(needed: 10, available: nil) == nil)
    }

    // MARK: naming

    @Test func fileNames() throws {
        let encoded = IPSWAppleTarget(identifier: "iPhone10,6", firmware: firmware(
            .apple, build: "15D100", version: "11.2.6",
            url: "https://updates.cdn-apple.com/2018/ios/x/iPhone10%2C6_11.2.6_15D100_Restore.ipsw"))
        #expect(IPSWData.fileName(for: IPSWData.merge(apple: encoded, ipswMe: nil)[0]) == "iPhone10,6_11.2.6_15D100_Restore.ipsw")

        let x = IPSWData.merge(apple: try appleTarget("iPhone10,3"), ipswMe: nil)[0]
        #expect(IPSWData.fileName(for: x) == "iPhone10,3,iPhone10,6_16.7.16_20H392_Restore.ipsw")

        let odd = IPSWAppleTarget(identifier: "iPhone18,2", firmware: firmware(.apple, url: "https://updates.cdn-apple.com/download"))
        #expect(IPSWData.fileName(for: IPSWData.merge(apple: odd, ipswMe: nil)[0]) == "iPhone18,2_27.0.1_24A446_Restore.ipsw")

        let hidden = IPSWAppleTarget(identifier: "iPhone18,2", firmware: firmware(.apple, url: "https://updates.cdn-apple.com/a/.x.ipsw"))
        #expect(IPSWData.fileName(for: IPSWData.merge(apple: hidden, ipswMe: nil)[0]) == "iPhone18,2_27.0.1_24A446_Restore.ipsw")

        let n = "iPhone18,2_27.0.1_24A446_Restore.ipsw"
        #expect(IPSWData.nextName(n, attempt: 1) == n)
        #expect(IPSWData.nextName(n, attempt: 2) == "iPhone18,2_27.0.1_24A446_Restore (2).ipsw")
        #expect(IPSWData.nextName(n, attempt: 999) == "iPhone18,2_27.0.1_24A446_Restore (999).ipsw")
        let u = IPSWData.nextName(n, attempt: 1000)
        #expect(u.hasPrefix("iPhone18,2_27.0.1_24A446_Restore-") && u.hasSuffix(".ipsw"))
        #expect(u.count == n.count + 1 + 36)
    }

    @Test func identifiers() {
        #expect(IPSWData.isValidIdentifier("iPhone18,2"))
        #expect(IPSWData.isValidIdentifier("iPad13,1"))
        for bad in ["", "iPhone18", "iPhone18,", "18,2", "iPhone18,2/..", "iPhone18,2?x=1", "iPhone 18,2", "iPhone18,2\n"] {
            #expect(!IPSWData.isValidIdentifier(bad), "rejected: \(bad)")
        }
        #expect(IPSWData.ipswMeURL(identifier: "iPhone18,2")?.absoluteString == "https://api.ipsw.me/v4/device/iPhone18,2?type=ipsw")
        #expect(IPSWData.ipswMeURL(identifier: "../x") == nil)
    }

    // MARK: hashing, staging, finalize

    @Test func digestsOnePass() throws {
        let dir = try tempDir("digests")
        defer { try? FileManager.default.removeItem(at: dir) }
        var block = Data(count: Int(MIB))
        for i in 0..<block.count { block[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        var content = Data()
        for k in 0..<20 { content.append(block); content[content.count - 1] = UInt8(k) }
        let file = dir.appendingPathComponent("f.bin")
        try content.write(to: file)

        var seen: [Int64] = []
        let got = try IPSWData.digests(of: file, want: [.sha256, .sha1], progress: { seen.append($0) }, isCancelled: { false })
        #expect(got[.sha256] == IPSWData.hex(SHA256.hash(data: content)))
        #expect(got[.sha1] == IPSWData.hex(Insecure.SHA1.hash(data: content)))
        #expect(seen == seen.sorted() && Set(seen).count == seen.count, "progress is strictly increasing")
        #expect(seen.last == Int64(content.count))

        let onlySha1 = try IPSWData.digests(of: file, want: [.sha1], progress: { _ in }, isCancelled: { false })
        #expect(Array(onlySha1.keys) == [.sha1])

        var calls = 0
        #expect(throws: IPSWError.cancelled) {
            _ = try IPSWData.digests(of: file, want: [.sha256], progress: { _ in }, isCancelled: { calls += 1; return calls > 1 })
        }
    }

    @Test func removeStaleStagingOnlyOwnFiles() throws {
        let dir = try tempDir("stale")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        try Data("a".utf8).write(to: dir.appendingPathComponent("MacDashboard-ipsw-1.ipsw"))
        try fm.createDirectory(at: dir.appendingPathComponent("MacDashboard-ipsw-dir"), withIntermediateDirectories: false)
        try Data("b".utf8).write(to: dir.appendingPathComponent("keep.ipsw"))
        try Data("c".utf8).write(to: dir.appendingPathComponent("iPhone18,2_27.0.1_24A446_Restore.ipsw"))
        IPSWData.removeStaleStaging(in: dir)
        #expect(try fm.contentsOfDirectory(atPath: dir.path).sorted() == ["iPhone18,2_27.0.1_24A446_Restore.ipsw", "keep.ipsw"])
        IPSWData.removeStaleStaging(in: dir.appendingPathComponent("missing"))   // no crash on a missing dir
    }

    /// A staged file of `bytes` in `staging`, with its real digests.
    private func staged(_ bytes: Int, in staging: URL) throws -> (URL, sha256: String, sha1: String) {
        let data = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 1) })
        let url = staging.appendingPathComponent(IPSWData.stagingPrefix + UUID().uuidString + ".ipsw")
        try data.write(to: url)
        return (url, IPSWData.hex(SHA256.hash(data: data)), IPSWData.hex(Insecure.SHA1.hash(data: data)))
    }

    @Test func finalizeHappyPathAndNoOverwrite() throws {
        let root = try tempDir("finalize")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let staging = root.appendingPathComponent("staging"), downloads = root.appendingPathComponent("downloads")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: false)
        let name = "iPhone18,2_27.0.1_24A446_Restore.ipsw"

        let (f1, s256, s1) = try staged(300_000, in: staging)
        let digests = ExpectedDigests(sha256: s256, sha1: s1, sha1Sources: [.apple, .ipswMe])
        let (url, verified) = try IPSWDownloader.finalize(staged: f1, size: 300_000, digests: digests, downloadsDir: downloads,
                                                          fileName: name, progress: { _ in }, isCancelled: { false })
        #expect(url == downloads.appendingPathComponent(name))
        #expect(verified == [VerifiedDigest(algorithm: .sha256, sources: [.ipswMe]),
                             VerifiedDigest(algorithm: .sha1, sources: [.apple, .ipswMe])])
        #expect(!fm.fileExists(atPath: f1.path), "staging is gone")
        #expect(try fm.contentsOfDirectory(atPath: staging.path).isEmpty)

        // The same name again: the existing file is untouched, the new one gets " (2)".
        let before = try Data(contentsOf: url)
        let (f2, _, s1b) = try staged(300_000, in: staging)
        let (url2, verified2) = try IPSWDownloader.finalize(
            staged: f2, size: 300_000, digests: ExpectedDigests(sha256: nil, sha1: s1b, sha1Sources: [.apple]),
            downloadsDir: downloads, fileName: name, progress: { _ in }, isCancelled: { false })
        #expect(url2.lastPathComponent == "iPhone18,2_27.0.1_24A446_Restore (2).ipsw")
        #expect(try Data(contentsOf: url) == before)
        #expect(verified2 == [VerifiedDigest(algorithm: .sha1, sources: [.apple])], "SHA-1-only input → exactly that")
    }

    @Test func finalizeRefusals() throws {
        let root = try tempDir("refuse")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let staging = root.appendingPathComponent("staging"), downloads = root.appendingPathComponent("downloads")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: false)
        let name = "x.ipsw"

        // Wrong size: refused before hashing (no progress), staging deleted, destination unchanged.
        let (f1, s256, s1) = try staged(100_000, in: staging)
        var hashed = 0
        #expect(throws: IPSWError.sizeMismatch(expected: 100_001, actual: 100_000)) {
            _ = try IPSWDownloader.finalize(staged: f1, size: 100_001,
                                            digests: ExpectedDigests(sha256: s256, sha1: s1, sha1Sources: [.apple]),
                                            downloadsDir: downloads, fileName: name,
                                            progress: { _ in hashed += 1 }, isCancelled: { false })
        }
        #expect(hashed == 0)
        #expect(!fm.fileExists(atPath: f1.path))
        #expect(try fm.contentsOfDirectory(atPath: downloads.path).isEmpty)

        // Right SHA-256, wrong SHA-1: every digest is checked.
        let (f2, s256b, _) = try staged(100_000, in: staging)
        #expect(throws: IPSWError.checksumMismatch) {
            _ = try IPSWDownloader.finalize(staged: f2, size: 100_000,
                                            digests: ExpectedDigests(sha256: s256b, sha1: String(repeating: "0", count: 40),
                                                                     sha1Sources: [.apple]),
                                            downloadsDir: downloads, fileName: name, progress: { _ in }, isCancelled: { false })
        }
        #expect(!fm.fileExists(atPath: f2.path))
        #expect(try fm.contentsOfDirectory(atPath: downloads.path).isEmpty)

        // Cancelled while hashing.
        let (f3, s256c, _) = try staged(100_000, in: staging)
        #expect(throws: IPSWError.cancelled) {
            _ = try IPSWDownloader.finalize(staged: f3, size: 100_000,
                                            digests: ExpectedDigests(sha256: s256c, sha1: nil, sha1Sources: []),
                                            downloadsDir: downloads, fileName: name, progress: { _ in }, isCancelled: { true })
        }
        #expect(!fm.fileExists(atPath: f3.path))
        #expect(try fm.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @Test func stagingDirectoryIsOnTheDownloadsVolume() throws {
        let root = try tempDir("staging")
        defer { try? FileManager.default.removeItem(at: root) }
        // A "Downloads" inside the temp dir is on the temp dir's volume, so staging is the temp dir itself.
        let staging = try IPSWDownloader.stagingDirectory(for: root)
        #expect(IPSWDownloader.sameVolume(staging, root))
        #expect(staging.standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(IPSWData.hiddenStagingName).path))
    }

    // MARK: redirect policy

    @Test func redirectGuard() {
        func u(_ s: String) -> URL { URL(string: s)! }
        #expect(RedirectGuard.allows(from: u("https://api.ipsw.me/v4/device/x"), to: u("https://api.ipsw.me/v4/other")))
        #expect(!RedirectGuard.allows(from: u("https://api.ipsw.me/v4/device/x"), to: u("https://evil.example/")))
        #expect(!RedirectGuard.allows(from: u("https://itunes.apple.com/a"), to: u("http://itunes.apple.com/a")))
        #expect(!RedirectGuard.allows(from: u("https://itunes.apple.com/a"), to: u("https://updates.cdn-apple.com/a.ipsw")))
        #expect(RedirectGuard.allows(from: u("https://updates.cdn-apple.com/a.ipsw"), to: u("https://secure-appldnld.apple.com/a.ipsw")))
        #expect(!RedirectGuard.allows(from: u("https://updates.cdn-apple.com/a.ipsw"), to: u("http://updates-http.cdn-apple.com/a.ipsw")))
        #expect(!RedirectGuard.allows(from: u("https://updates.cdn-apple.com/a.ipsw"), to: u("https://appldnld.apple.com.edgesuite.net/a.ipsw")))
    }
}

// MARK: - sources (stubbed fetch)

struct IPSWSourcesTests {

    @Test func fixturesThroughSources() async throws {
        let stub = try fixtureFetch()
        let t = await stub.sources.appleTarget(identifier: "iPhone18,2")
        #expect((value(t) ?? nil)?.firmware.buildID == "24A446")
        let l = await stub.sources.ipswMe(identifier: "iPhone18,2")
        #expect(value(l)?.firmwares.count == 3)
        #expect(stub.count(host: "itunes.apple.com") == 1 && stub.count(host: "api.ipsw.me") == 1)
    }

    @Test func requestsAreExact() async throws {
        let stub = try fixtureFetch()
        _ = await stub.sources.appleTarget(identifier: "iPhone18,2")
        _ = await stub.sources.ipswMe(identifier: "iPhone18,2")
        let reqs = stub.requests
        #expect(reqs.count == 2)
        let apple = reqs[0], ipsw = reqs[1]
        #expect(apple.url == IPSWData.catalogueURL)
        #expect(apple.httpMethod == "GET")
        #expect(apple.timeoutInterval == 30)
        #expect(apple.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(ipsw.url?.absoluteString == "https://api.ipsw.me/v4/device/iPhone18,2?type=ipsw")
        #expect(ipsw.httpMethod == "GET")
        #expect(ipsw.timeoutInterval == 15)
        for r in reqs {
            #expect(r.value(forHTTPHeaderField: "User-Agent") == IPSWSources.userAgent)
            #expect(IPSWSources.userAgent.hasPrefix("MacDashboard/"))
            #expect(r.httpBody == nil && r.value(forHTTPHeaderField: "Cookie") == nil, "nothing else is sent")
        }
    }

    @Test func statusMapping() async throws {
        let notFound = try apiFixture(notFoundPath)
        let s404 = IPSWStubFetch { _ in (notFound, 404, [:]) }
        #expect(failure(await s404.sources.ipswMe(identifier: "iPhone99,9")) == .unknownDevice)
        #expect(failure(await s404.sources.appleTarget(identifier: "iPhone18,2")) == .http(404))
        let s500 = IPSWStubFetch { _ in (Data(), 500, [:]) }
        #expect(failure(await s500.sources.ipswMe(identifier: "iPhone18,2")) == .http(500))
        let s302 = IPSWStubFetch { _ in (Data(), 302, ["Location": "https://evil.example/x"]) }
        #expect(failure(await s302.sources.ipswMe(identifier: "iPhone18,2")) == .notDownloadable("evil.example"))
    }

    @Test func errorMapping() async {
        let cases: [(URLError.Code, IPSWError?)] = [
            (.notConnectedToInternet, .offline), (.networkConnectionLost, .offline), (.cannotFindHost, .offline),
            (.cannotConnectToHost, .offline), (.dnsLookupFailed, .offline), (.timedOut, .timedOut),
            (.cancelled, .cancelled), (.serverCertificateUntrusted, nil),
        ]
        for (code, want) in cases {
            let stub = IPSWStubFetch { _ in throw URLError(code) }
            let got = failure(await stub.sources.ipswMe(identifier: "iPhone18,2"))
            if let want {
                #expect(got == want, "\(code)")
            } else if case .transfer? = got {} else {
                Issue.record("\(code) → \(String(describing: got)), want .transfer")
            }
        }
    }

    @Test func badIdentifierSendsNothing() async {
        let stub = IPSWStubFetch { _ in (Data(), 200, [:]) }
        #expect(failure(await stub.sources.ipswMe(identifier: "iPhone18,2/../x")) == .badIdentifier("iPhone18,2/../x"))
        #expect(failure(await stub.sources.appleTarget(identifier: "")) == .badIdentifier(""))
        #expect(stub.requests.isEmpty)
    }

    @Test func head() async {
        let stub = IPSWStubFetch { _ in (Data(), 200, ["Content-Length": "12708916186"]) }
        #expect(failure(await stub.sources.head(URL(string: "http://updates-http.cdn-apple.com/a/b.ipsw")!)) == .notDownloadable("http"))
        #expect(failure(await stub.sources.head(URL(string: "https://evil.example/b.ipsw")!)) == .notDownloadable("evil.example"))
        #expect(stub.requests.isEmpty, "a refused URL is never requested")
        let length = value(await stub.sources.head(URL(string: url_24A446)!)) ?? nil
        #expect(length == 12_708_916_186)
        #expect(stub.requests.first?.httpMethod == "HEAD")
    }
}

// MARK: - downloader refusals before any request

@MainActor
struct IPSWDownloaderTests {

    private func firstPhase(_ b: IPSWBuild, _ sources: IPSWSources, downloadsDir: URL) async -> IPSWDownloadPhase {
        let downloader = IPSWDownloader()
        return await withCheckedContinuation { c in
            downloader.start(b, downloadsDir: downloadsDir, sources: sources) { phase in c.resume(returning: phase) }
        }
    }

    @Test func refusesBeforeAnyRequest() async throws {
        let dir = try tempDir("downloader")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stub = IPSWStubFetch { _ in (Data(), 200, ["Content-Length": "1"]) }

        let onlyIPSWMe = try #require(IPSWData.merge(apple: nil, ipswMe: try ipswList(ipsw18Path)).first)
        #expect(await firstPhase(onlyIPSWMe, stub.sources, downloadsDir: dir) == .failed(.notDownloadable("api.ipsw.me")))

        let http = IPSWAppleTarget(identifier: "iPhone5,1", firmware: firmware(
            .apple, build: "14G61", url: "http://updates-http.cdn-apple.com/2019/x/iPhone5,1_10.3.4_14G61_Restore.ipsw"))
        #expect(await firstPhase(IPSWData.merge(apple: http, ipswMe: nil)[0], stub.sources, downloadsDir: dir)
                == .failed(.notDownloadable("http")))

        var disagree = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: try ipswList(ipsw18Path))[0]
        disagree.ipswMe?.sha1 = "0000000000000000000000000000000000000000"
        #expect(await firstPhase(disagree, stub.sources, downloadsDir: dir) == .failed(.sourcesDisagree))

        #expect(stub.requests.isEmpty, "no HEAD, no GET")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func busyWhileARunIsActive() async throws {
        let dir = try tempDir("busy")
        defer { try? FileManager.default.removeItem(at: dir) }
        // The HEAD never answers until the test cancels, so the first run stays active.
        let gate = DispatchSemaphore(value: 0)
        let stub = IPSWStubFetch { _ in gate.wait(); return (Data(), 500, [:]) }
        let downloader = IPSWDownloader()
        let appleOnly = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: nil)[0]   // no size → HEAD
        var phases: [IPSWDownloadPhase] = []
        downloader.start(appleOnly, downloadsDir: dir, sources: stub.sources) { phases.append($0) }
        let second: IPSWDownloadPhase = await withCheckedContinuation { c in
            downloader.start(appleOnly, downloadsDir: dir, sources: stub.sources) { c.resume(returning: $0) }
        }
        #expect(second == .failed(.busy))
        #expect(downloader.isBusy)
        downloader.cancel()
        gate.signal()
        #expect(!downloader.isBusy)
        for _ in 0..<100 where !phases.contains(where: \.isTerminal) { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(phases.first == .preparing)
        #expect(phases.last == .failed(.cancelled))
    }

    @Test func cancelDuringPrepareLeavesNoStagingDirectory() async throws {
        let dir = try tempDir("cancel-prepare")
        defer { try? FileManager.default.removeItem(at: dir) }
        let downloader = IPSWDownloader()
        // Cancel while the HEAD is in flight, then let it succeed: prepare must stop before Downloads.
        let stub = IPSWStubFetch { _ in
            downloader.cancel()
            return (Data(), 200, ["Content-Length": "1000"])
        }
        let appleOnly = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: nil)[0]
        var phases: [IPSWDownloadPhase] = []
        downloader.start(appleOnly, downloadsDir: dir, sources: stub.sources) { phases.append($0) }
        for _ in 0..<200 where !phases.contains(where: \.isTerminal) { try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(phases.last == .failed(.cancelled))
        #expect(!downloader.isBusy)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty, "no hidden staging directory")
    }
}

// MARK: - model (stubbed sources)

@MainActor
struct IPSWModelTests {

    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 2_000_000_000) }

    @Test func eachButtonAsksOnlyItsSource() async throws {
        let stub = try fixtureFetch()
        let model = IPSWModel(sources: stub.sources, downloadsDir: { nil })

        let task = model.checkApple(productType: "iPhone18,2")
        #expect(model.apple["iPhone18,2"] == .loading)
        await task?.value
        #expect(stub.count(host: "itunes.apple.com") == 1 && stub.count(host: "api.ipsw.me") == 0)
        guard case .loaded(let target, _)? = model.apple["iPhone18,2"] else { Issue.record("apple not loaded"); return }
        #expect(target?.firmware.buildID == "24A446")
        #expect(model.installedSigning(productType: "iPhone18,2", build: "24A446", version: nil) == .isAppleTarget)

        await model.askIPSWMe(productType: "iPhone18,2")?.value
        #expect(stub.count(host: "itunes.apple.com") == 1 && stub.count(host: "api.ipsw.me") == 1)
        #expect(model.builds(productType: "iPhone18,2").map(\.buildID) == ["24A446", "24A437", "23G90"])
        #expect(model.installedSigning(productType: "iPhone18,2", build: "24A437", version: nil) == .notSigned)
        #expect(model.installedSigning(productType: "iPhone16,2", build: "24A446", version: nil) == nil, "nothing asked for 16,2")
    }

    @Test func cacheForceAndFailures() async throws {
        let stub = try fixtureFetch()
        let clock = Clock()
        let model = IPSWModel(sources: stub.sources, downloadsDir: { nil }, now: { clock.now })
        await model.checkApple(productType: "iPhone18,2")?.value
        #expect(model.checkApple(productType: "iPhone18,2") == nil, "cached within 10 minutes")
        #expect(stub.count(host: "itunes.apple.com") == 1)
        clock.now += IPSWModel.cacheLifetime + 1
        await model.checkApple(productType: "iPhone18,2")?.value
        #expect(stub.count(host: "itunes.apple.com") == 2)
        await model.checkApple(productType: "iPhone18,2", force: true)?.value
        #expect(stub.count(host: "itunes.apple.com") == 3)

        let failing = IPSWStubFetch { _ in (Data(), 500, [:]) }
        let m2 = IPSWModel(sources: failing.sources, downloadsDir: { nil })
        await m2.askIPSWMe(productType: "iPhone18,2")?.value
        #expect(m2.ipswMe["iPhone18,2"] == .failed(.http(500)))
        #expect(m2.apple["iPhone18,2"] == nil, "the other source is untouched")
    }

    @Test func noProductTypeSendsNothing() throws {
        let stub = try fixtureFetch()
        let model = IPSWModel(sources: stub.sources, downloadsDir: { nil })
        #expect(model.checkApple(productType: nil) == nil)
        #expect(model.askIPSWMe(productType: nil) == nil)
        #expect(model.apple[""] == .failed(.noIdentifier) && model.ipswMe[""] == .failed(.noIdentifier))
        #expect(stub.requests.isEmpty)
    }

    @Test func downloadWithoutDownloadsFolder() throws {
        let model = IPSWModel(sources: try fixtureFetch().sources, downloadsDir: { nil })
        let b = IPSWData.merge(apple: try appleTarget("iPhone18,2"), ipswMe: nil)[0]
        model.startDownload(b)
        #expect(model.download?.phase == .failed(.fileSystem("Downloads")))
    }
}

// MARK: - messages (language is process-wide → SerialTests)

extension SerialTests {
    struct IPSWMessageTests {
        static let allErrors: [IPSWError] = [
            .noIdentifier, .badIdentifier("x"), .unknownDevice, .http(503), .offline, .timedOut, .badResponse,
            .notDownloadable("http"), .noChecksum, .noSize, .sourcesDisagree,
            .notEnoughSpace(needed: 14_000_000_000, available: 2_000_000_000), .downloadsDenied,
            .sizeMismatch(expected: 2, actual: 1), .checksumMismatch, .transfer("boom"), .fileSystem("disk"),
            .busy, .cancelled,
        ]

        @Test func messagesInBothLanguages() {
            for lang in [AppLanguage.ru, .en] {
                L10nStore.shared.language = lang
                for e in Self.allErrors {
                    let m = IPSWData.message(for: e)
                    #expect(!m.isEmpty && !m.contains("Optional("), "\(lang) \(e): \(m)")
                }
                #expect(IPSWData.message(for: .http(503)).contains("503"))
                #expect(IPSWData.message(for: .notEnoughSpace(needed: 14_000_000_000, available: 2_000_000_000)).contains("14"))
            }
            L10nStore.shared.language = .en
            #expect(IPSWData.verifiedText([VerifiedDigest(algorithm: .sha1, sources: [.apple])]) == "Verified: SHA-1 (Apple) and size")
            #expect(IPSWData.verifiedText([VerifiedDigest(algorithm: .sha1, sources: [.ipswMe, .apple]),
                                           VerifiedDigest(algorithm: .sha256, sources: [.ipswMe])])
                    == "Verified: SHA-256 (ipsw.me), SHA-1 (Apple, ipsw.me) and size")
            #expect(StringsEN().ipswAskSends("iPhone18,2") == "Sends the model identifier iPhone18,2 to ipsw.me")
            L10nStore.shared.language = .ru
            #expect(IPSWData.verifiedText([VerifiedDigest(algorithm: .sha1, sources: [.apple])]) == "Проверено: SHA-1 (Apple) и размер")
            #expect(StringsRU().ipswAskSends("iPhone18,2") == "Отправит в ipsw.me идентификатор модели iPhone18,2")
        }
    }
}
