// Engine/IPSWModel+VisualFixture.swift
// IPHONE-IPSW: fixed firmware-card states for -visualFixture and the snapshot suite
// (`MACDASH_FIXTURE_IPSW=<state>`, default `both`). Memory only: seeding sets properties and never calls
// the downloader or the sources. All values are invented and model-level (no serial, UDID or ECID).
import Foundation

extension IPSWModel {
    static let fixtureStates = [
        "idle", "checking", "apple", "both", "legacy", "errors", "unlisted",
        "confirm", "confirm-low", "confirm-blocked",
        "preparing", "downloading", "paused", "interrupted", "verifying", "finished", "finished-gone", "cancelled", "failed",
        "relaunched", "quit-interrupted", "outdated", "rejected", "resume-nospace",
    ]

    private static let fixtureAlexType = "iPhone18,2"
    private static let fixtureSamType = "iPhone16,2"
    /// The legacy state is for a phone of this model: the page's record and snapshot must carry it (snapshot test tweak).
    static let fixtureLegacyType = "iPhone5,2"
    private static let fixtureTotal: Int64 = 9_412_345_678
    private static let fixtureStopped: Int64 = 4_100_000_000
    private static let fixtureDownloads = URL(fileURLWithPath: "/Users/fixture/Downloads", isDirectory: true)

    /// Resets the card state, then seeds `state`. Safe to call again after `IPhoneModel.applyVisualFixture()`.
    func applyVisualFixture(_ state: String) {
        let ref = VisualFixture.referenceDate
        apple = [:]
        ipswMe = [:]
        download = nil
        confirm = nil
        stoppedAt = nil
        goneFile = nil

        // Sam (remembered) always has Apple's answer, so his page shows the Apple-only wording.
        apple[Self.fixtureSamType] = .loaded(Self.fixtureSamTarget(), fetchedAt: ref)

        func loadBoth() {
            apple[Self.fixtureAlexType] = .loaded(Self.fixtureAlexTarget(), fetchedAt: ref)
            ipswMe[Self.fixtureAlexType] = .loaded(Self.fixtureAlexList(), fetchedAt: ref)
        }
        func alexBuild() -> IPSWBuild { builds(productType: Self.fixtureAlexType).first { $0.isAppleTarget }! }
        func confirmFacts(available: Int64?, blockedBySpace: Bool = false) -> IPSWConfirmState {
            let b = alexBuild()
            let size = Self.fixtureTotal
            let total: Int64 = 245_000_000_000
            let digests = (try? IPSWData.expectedDigests(b).get())
            return .ready(IPSWConfirm(
                build: b, fileName: IPSWData.fileName(for: b), host: "updates.cdn-apple.com", size: size,
                available: available, total: total, checks: digests.map(IPSWData.plannedDigests) ?? [],
                blocked: IPSWData.spaceCheck(needed: size, available: available),
                lowSpace: IPSWData.lowSpaceAfter(size: size, available: available, total: total, lowPercent: 20),
                lowPercent: 20, destination: Self.fixtureDownloads))
        }
        func paused(written: Int64, _ interruption: IPSWError?, back: TimeInterval) {
            loadBoth()
            download = (alexBuild(), .paused(written: written, total: Self.fixtureTotal, interruption: interruption))
            stoppedAt = ref.addingTimeInterval(-back)
        }

        switch state {
        case "idle": break
        case "checking":
            apple[Self.fixtureAlexType] = .loading
            ipswMe[Self.fixtureAlexType] = .loading
        case "apple":
            apple[Self.fixtureAlexType] = .loaded(Self.fixtureAlexTarget(), fetchedAt: ref)
        case "legacy":
            // A real legacy model (spec § Legacy models): the page must show an iPhone 5 (Global) on iOS 10.3.4.
            apple[Self.fixtureLegacyType] = .loaded(Self.fixtureLegacyTarget(), fetchedAt: ref)
            ipswMe[Self.fixtureLegacyType] = .loaded(Self.fixtureLegacyList(), fetchedAt: ref)
        case "errors":
            apple[Self.fixtureAlexType] = .failed(.offline)
            ipswMe[Self.fixtureAlexType] = .failed(.unknownDevice)
        case "unlisted":
            apple[Self.fixtureAlexType] = .loaded(nil, fetchedAt: ref)
        case "confirm":
            loadBoth()
            confirm = confirmFacts(available: 120_000_000_000)
        case "confirm-low":
            loadBoth()
            confirm = confirmFacts(available: 30_000_000_000)
        case "confirm-blocked":
            loadBoth()
            confirm = confirmFacts(available: 6_000_000_000)
        case "preparing":
            loadBoth()
            download = (alexBuild(), .preparing)
        case "downloading":
            loadBoth()
            download = (alexBuild(), .downloading(written: 2_100_000_000, total: Self.fixtureTotal))
        case "paused": paused(written: Self.fixtureStopped, nil, back: 600)
        case "interrupted": paused(written: Self.fixtureStopped, .offline, back: 600)
        case "verifying":
            loadBoth()
            download = (alexBuild(), .verifying(hashed: 3_200_000_000, total: Self.fixtureTotal))
        case "finished", "finished-gone":
            loadBoth()
            let b = alexBuild()
            let verified = (try? IPSWData.expectedDigests(b).get()).map(IPSWData.plannedDigests) ?? []
            let file = Self.fixtureDownloads.appendingPathComponent(IPSWData.fileName(for: b))
            download = (b, .finished(file, verified: verified))
            if state == "finished-gone" { goneFile = file }
        case "cancelled":
            loadBoth()
            download = (alexBuild(), .failed(.cancelled))
        case "failed":
            loadBoth()
            download = (alexBuild(), .failed(.checksumMismatch))
        case "relaunched":
            // Right after a launch: nothing looked up, the stopped download read from its record.
            let record = Self.fixtureRecord(buildID: "23E254", version: "26.4.1", stoppedAt: ref.addingTimeInterval(-86_400), reason: nil)
            download = (record.build, .paused(written: record.checkpoint, total: record.size, interruption: nil))
            stoppedAt = record.stoppedAt
        case "quit-interrupted":
            let record = Self.fixtureRecord(buildID: "23E254", version: "26.4.1", stoppedAt: ref.addingTimeInterval(-86_400), reason: .appQuit)
            download = (record.build, .paused(written: record.checkpoint, total: record.size, interruption: .appQuit))
            stoppedAt = record.stoppedAt
        case "outdated":
            loadBoth()
            let record = Self.fixtureRecord(buildID: "23E246", version: "26.4", stoppedAt: ref.addingTimeInterval(-86_400), reason: nil)
            download = (record.build, .paused(written: record.checkpoint, total: record.size, interruption: nil))
            stoppedAt = record.stoppedAt
        case "rejected":
            loadBoth()
            download = (alexBuild(), .failed(.resumeRejected))
        case "resume-nospace":
            paused(written: Self.fixtureStopped,
                   .notEnoughSpace(needed: 6_300_000_000, available: 4_000_000_000), back: 600)
        default: loadBoth()   // "both" and any unknown value
        }
    }

    // MARK: invented data

    private static func fixtureRecord(buildID: String, version: String, stoppedAt: Date, reason: IPSWStopReason?) -> IPSWPartialRecord {
        IPSWPartialRecord(
            version: IPSWPartialRecord.currentVersion, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            identifier: fixtureAlexType, productVersion: version, buildID: buildID,
            url: URL(string: "https://updates.cdn-apple.com/fixture/iPhone18,2_\(version)_\(buildID)_Restore.ipsw")!,
            size: fixtureTotal, sha256: String(repeating: "b", count: 64), sha1: String(repeating: "a", count: 40),
            sha1Sources: [.apple, .ipswMe], fileName: "iPhone18,2_\(version)_\(buildID)_Restore.ipsw",
            validator: "\"fixture\"", checkpoint: fixtureStopped,
            startedAt: stoppedAt.addingTimeInterval(-3_600), stoppedAt: stoppedAt, reason: reason, partInDownloads: false)
    }

    private static func fixtureAlexTarget() -> IPSWAppleTarget {
        IPSWAppleTarget(identifier: fixtureAlexType, firmware: IPSWFirmware(
            source: .apple, identifier: fixtureAlexType, version: "26.4.1", buildID: "23E254",
            sha256: nil, sha1: String(repeating: "a", count: 40), fileSize: nil,
            url: URL(string: "https://updates.cdn-apple.com/fixture/iPhone18,2_26.4.1_23E254_Restore.ipsw")!,
            releaseDate: nil, signed: nil))
    }

    /// iPhone 5 (Global): Apple's last build is served over http from a host outside the allowlist.
    private static func fixtureLegacyTarget() -> IPSWAppleTarget {
        IPSWAppleTarget(identifier: fixtureLegacyType, firmware: IPSWFirmware(
            source: .apple, identifier: fixtureLegacyType, version: "10.3.4", buildID: "14G61",
            sha256: nil, sha1: String(repeating: "d", count: 40), fileSize: nil,
            url: URL(string: "http://updates-http.cdn-apple.com/fixture/iPhone5,2_10.3.4_14G61_Restore.ipsw")!,
            releaseDate: nil, signed: nil))
    }

    /// ipsw.me for the legacy model: 10.3.4 not signed, older builds not signed.
    private static func fixtureLegacyList() -> IPSWThirdParty {
        let ref = VisualFixture.referenceDate
        func fw(_ version: String, _ build: String, daysBack: Int) -> IPSWFirmware {
            IPSWFirmware(source: .ipswMe, identifier: fixtureLegacyType, version: version, buildID: build,
                         sha256: nil, sha1: String(repeating: "d", count: 40), fileSize: 2_100_000_000,
                         url: URL(string: "https://updates.cdn-apple.com/fixture/iPhone5,2_\(version)_\(build)_Restore.ipsw")!,
                         releaseDate: ref.addingTimeInterval(-Double(daysBack) * 86_400), signed: false)
        }
        return IPSWThirdParty(name: "iPhone 5 (Global)", identifier: fixtureLegacyType, firmwares: [
            fw("10.3.4", "14G61", daysBack: 3_000), fw("10.3.3", "14G60", daysBack: 3_100),
            fw("10.3.2", "14F89", daysBack: 3_200),
        ])
    }

    private static func fixtureSamTarget() -> IPSWAppleTarget {
        IPSWAppleTarget(identifier: fixtureSamType, firmware: IPSWFirmware(
            source: .apple, identifier: fixtureSamType, version: "26.4.1", buildID: "23E254",
            sha256: nil, sha1: String(repeating: "c", count: 40), fileSize: nil,
            url: URL(string: "https://updates.cdn-apple.com/fixture/iPhone16,2_26.4.1_23E254_Restore.ipsw")!,
            releaseDate: nil, signed: nil))
    }

    /// 23E254 and 23E246 signed, 23D60 and ten older builds not signed (newest first, like ipsw.me).
    private static func fixtureAlexList() -> IPSWThirdParty {
        let ref = VisualFixture.referenceDate
        func fw(_ version: String, _ build: String, signed: Bool, size: Int64, daysBack: Int, sha: Bool) -> IPSWFirmware {
            IPSWFirmware(source: .ipswMe, identifier: fixtureAlexType, version: version, buildID: build,
                         sha256: sha ? String(repeating: "b", count: 64) : nil,
                         sha1: sha ? String(repeating: "a", count: 40) : nil, fileSize: size,
                         url: URL(string: "https://updates.cdn-apple.com/fixture/iPhone18,2_\(version)_\(build)_Restore.ipsw")!,
                         releaseDate: ref.addingTimeInterval(-Double(daysBack) * 86_400), signed: signed)
        }
        var list = [
            fw("26.4.1", "23E254", signed: true, size: fixtureTotal, daysBack: 10, sha: true),
            fw("26.4", "23E246", signed: true, size: 9_380_000_000, daysBack: 40, sha: false),
            fw("26.3.1", "23D60", signed: false, size: 9_300_000_000, daysBack: 80, sha: false),
        ]
        for i in 0..<10 {
            list.append(fw("26.\(2 - i / 4).\(i % 4)", "23C\(10 + i)", signed: false, size: 9_200_000_000 - Int64(i) * 10_000_000,
                           daysBack: 100 + i * 12, sha: false))
        }
        return IPSWThirdParty(name: "iPhone 17 Pro Max", identifier: fixtureAlexType, firmwares: list)
    }
}
