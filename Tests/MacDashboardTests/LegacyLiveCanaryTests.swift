// Tests/MacDashboardTests/LegacyLiveCanaryTests.swift
// MOONPORT-RENAME opt-in canary: MACDASH_LIVE=1 swift test --filter liveCanary
// Prints the identity values and the old/new storage state the first-launch migration depends on, and asserts them.
// Read-only: writes nothing, moves nothing, and stats nothing under ~/Documents (that would raise a Documents prompt
// for the terminal).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    @MainActor struct LegacyLiveCanaryTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryLegacyIdentity() {
            let fm = FileManager.default
            let support = AppInfo.supportFolderURL, legacy = AppInfo.legacySupportFolderURL
            print("liveCanary bundleID = \(AppInfo.bundleID)")
            print("liveCanary supportFolder = \(support.path)")
            print("liveCanary legacy = \(legacy.path) exists=\(fm.fileExists(atPath: legacy.path))")
            let found = LegacyApp.candidateDirectories.map { dir -> String in
                let app = LegacyApp.bundleURL(in: dir)
                return "\(app.path) id=\(LegacyApp.bundleID(of: app) ?? "none")"
            }
            print("liveCanary detect: \(LegacyApp.detect().map { "\($0.url.path) id=\(AppInfo.legacyBundleID)" } ?? "none")")
            for line in found { print("liveCanary candidate \(line)") }
            let oldDomain = UserDefaults.standard.persistentDomain(forName: AppInfo.legacyBundleID)
            let newDomain = UserDefaults.standard.persistentDomain(forName: AppInfo.bundleID)
            print("liveCanary legacy defaults keys = \(oldDomain?.count ?? 0)")

            let archiveRoot = IPhoneStore.defaultArchiveRoot(), oldRoot = IPhoneStore.legacyDocumentsArchiveRoot()
            print("liveCanary archiveRoot default = \(archiveRoot.path)")
            print("liveCanary old default = \(oldRoot.path)")
            print("liveCanary archive setting new=\(newDomain?[AppSettings.iphoneArchiveFolderKey] ?? "nil") old=\(oldDomain?[AppSettings.iphoneArchiveFolderKey] ?? "nil")")
            print("liveCanary legacyArchivesMoved = \(newDomain?[LegacyArchiveMove.markerKey].map { "\($0)" } ?? "nil")")
            let recordsFile = [support, legacy].map { $0.appendingPathComponent("iphones.json") }.first { fm.fileExists(atPath: $0.path) }
            let kept = recordsFile.map { IPhoneStore(url: $0).load().filter { !$0.keptArchives.isEmpty }.count }
            print("liveCanary records with kept archives = \(kept.map(String.init) ?? "n/a (no iphones.json)")")
            let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
            let oldIPSW = caches.appendingPathComponent(AppInfo.legacyBundleID).appendingPathComponent("ipsw")
            let newIPSW = IPSWPartialStore.defaultRoot()
            print("liveCanary ipsw new=\(newIPSW.path) exists=\(fm.fileExists(atPath: newIPSW.path)) old=\(oldIPSW.path) exists=\(fm.fileExists(atPath: oldIPSW.path))")

            #expect(AppInfo.bundleID == "app.moonport")
            #expect(support.lastPathComponent == "Moonport")
            #expect(support != legacy)
            #expect(found.count == 2)
            for dir in LegacyApp.candidateDirectories {
                if let f = LegacyApp.detect(candidates: [dir], excluding: nil) {
                    #expect(LegacyApp.bundleID(of: f.url) == AppInfo.legacyBundleID)
                }
            }
            #expect(archiveRoot.path.hasSuffix("/Documents/Moonport/iPhone"))
            #expect(oldRoot.path.hasSuffix("/Documents/MacDashboard/iPhone"))
            #expect(archiveRoot.deletingLastPathComponent().deletingLastPathComponent() == oldRoot.deletingLastPathComponent().deletingLastPathComponent())
        }

        /// W3: the Full Disk Access probe the Welcome panel uses, against what the system itself says about the same
        /// paths. It shows the probe agrees with the system for the terminal's own grant, not for Moonport's.
        /// Read-only, nothing under ~/Documents.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryWelcomeFullDiskAccess() throws {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            for row in ProtectedLocations.fdaOnlyRows {
                let path = home + "/" + row
                let probe = DirectoryAccess.probe(path)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/ls")
                p.arguments = [path]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try p.run()
                p.waitUntilExit()
                print("liveCanary fda \(row) probe=\(probe) ls exit=\(p.terminationStatus)")
                let exists = FileManager.default.fileExists(atPath: path)
                if probe == .missing { #expect(!exists) }
                else { #expect(probe == .readable ? p.terminationStatus == 0 : p.terminationStatus != 0) }
            }
            print("liveCanary fda state=\(ProtectedLocations.fullDiskAccess(home: home, probe: DirectoryAccess.probe))")
        }
    }
}
