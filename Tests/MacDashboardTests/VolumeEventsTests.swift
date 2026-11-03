// Tests/MacDashboardTests/VolumeEventsTests.swift
// DISK-MOUNT-LIVE: the mount-event filter over the paths seen on the real machine, and an opt-in live canary.
import Foundation
import Testing
@testable import MacDashboard

struct VolumeEventsTests {
    @Test func realVolumesAreRelevant() {
        for p in ["/Volumes/Backup SSD Time Machine", "/Volumes/Backup SSD Data",
                  "/Volumes/MDLIVETEST", "/Volumes/Backup/"] {
            #expect(VolumeEvents.isRelevant(path: p), "\(p)")
        }
        #expect(VolumeEvents.isRelevant(path: nil), "a missing URL counts")
    }

    @Test func snapshotAndSystemMountsAreNot() {
        for p in ["/Volumes/.timemachine/00000000-0000-4000-8000-000000000000/2026-01-01-120000.backup",
                  "/Volumes/com.apple.TimeMachine.localsnapshots/Backups.backupdb/Test Mac/2026-01-01-120000/Macintosh HD - Data",
                  "/Volumes/com.apple.TimeMachine.localsnapshots", "/Volumes/.timemachine",
                  "/", "/Volumes", "/System/Volumes/Data", "/private/tmp/x"] {
            #expect(!VolumeEvents.isRelevant(path: p), "\(p)")
        }
    }
}

extension SerialTests {
    @MainActor struct VolumeEventsLiveCanaryTests {
        // Opt-in: MACDASH_LIVE=1 swift test --filter liveCanaryVolumeEvents. Reads only: mount, tmutil status, tmutil destinationinfo.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryVolumeEvents() async throws {
            // The filter against the real mount table.
            let table = await CommandRunner.run("/sbin/mount", [], timeout: 10).text ?? ""
            let paths = table.split(separator: "\n").compactMap { line -> String? in
                guard let on = line.range(of: " on "), let paren = line.range(of: " (", options: .backwards) else { return nil }
                return String(line[on.upperBound..<paren.lowerBound])
            }
            for p in paths { print("liveCanary mount \(p) relevant=\(VolumeEvents.isRelevant(path: p))") }
            #expect(!paths.isEmpty)
            #expect(!VolumeEvents.isRelevant(path: "/"))
            for p in paths where p.contains("/.timemachine") || p.contains("com.apple.TimeMachine") || p.hasPrefix("/System/Volumes") {
                #expect(!VolumeEvents.isRelevant(path: p), "\(p)")
            }

            // The destination read against tmutil's plain-text form, and the mount table.
            let dest = await ReportCollector().collectTMDestInfo()
            let plainDest = await CommandRunner.run("/usr/bin/tmutil", ["destinationinfo"], timeout: 15).text ?? ""
            let plainMount = plainDest.split(separator: "\n")
                .first { $0.hasPrefix("Mount Point") }
                .flatMap { line in line.range(of: ": ").map { String(line[$0.upperBound...]) } }
            var parsedMount: String? = nil
            var parsedFree: Int64? = nil
            if case .some(.some(let d)) = dest { parsedMount = d.mountPoint; parsedFree = d.freeBytes }
            print("liveCanary destination parsed=\(parsedMount ?? "-") plain=\(plainMount ?? "-") free=\(String(describing: parsedFree))")
            #expect(dest != nil)
            #expect(parsedMount == plainMount)
            if let parsedMount {
                #expect(paths.contains(parsedMount))
                #expect(VolumeEvents.isRelevant(path: parsedMount))
            }

            // The status read in both output forms.
            let xmlOutcome = await ParsedCommand.tmutilStatus.run()
            let plainOutcome = await CommandRunner.run("/usr/bin/tmutil", ["status"], timeout: 10)
            let xml = try #require(xmlOutcome.nonEmptyText.flatMap { TimeMachineStatus.parse(text: $0) })
            let plain = try #require(plainOutcome.text.flatMap { TimeMachineStatus.parse(text: $0) })
            for (form, s) in [("xml", xml), ("plain", plain)] {
                print("liveCanary status \(form) running=\(s.running) phase=\(s.phase ?? "-") percent=\(String(describing: s.percent)) fractionDone=\(String(describing: s.scanFraction)) barShare=\(String(describing: s.barShare)) overall=\(String(describing: TimeMachineStatus.overallFraction(s))) bytes=\(String(describing: s.bytesDone))/\(String(describing: s.bytesTotal)) mount=\(s.destinationMountPoint ?? "-")")
            }
            #expect(xml.running == plain.running)   // a backup starting or ending between the two reads can fail this: rerun once
            guard xml.running else {
                print("liveCanary no backup running: the progress and precedence assertions did not run")
                return
            }
            if xml.phase == "FindingChanges" { #expect(abs((xml.barShare ?? -1) - 0.1) < 1e-6) }
            if xml.phase == "Copying" { #expect(abs((xml.barShare ?? -1) - 0.9) < 1e-6) }
            if let overall = TimeMachineStatus.overallFraction(xml) { #expect((0...1).contains(overall)) }
            if let mount = xml.destinationMountPoint {
                #expect(FileManager.default.fileExists(atPath: mount))
                #expect(paths.contains(mount))
            }
        }
    }
}
