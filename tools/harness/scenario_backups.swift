// tools/harness/scenario_backups.swift
// REDESIGN-BACKUPS render scenario: the Time Machine card in its states (A–J), the Claude card in its states
// (K–O, Q–Z) and the page bar (P). English by default; BACKUPS_LANG=ru renders Russian.
// BACKUPS_VIEW selects one group of at most four sections (required; groups: narrow tm1 tm2 tm3 claude1 claude2 claude3
// claude4 claude5 bar1 bar2), per tools/harness/README.md.

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    let env = ProcessInfo.processInfo.environment
    L10nStore.shared.language = env["BACKUPS_LANG"] == "ru" ? .ru : .en

    let harnessData = FileManager.default.temporaryDirectory.appendingPathComponent("moonport-harness-backups", isDirectory: true)
    @MainActor func model(_ tweak: (AppModel) -> Void) -> AppModel {
        let m = AppModel(dataDirectory: harnessData)
        m.applyVisualFixture()
        tweak(m)
        return m
    }
    let ref = VisualFixture.referenceDate
    func dest(last: Date?, mounted: Bool, schedule: TMSchedule? = .automatic(intervalSeconds: 3600)) -> TMDestination {
        TMDestination(name: "Backup SSD", kind: "Local", mountPoint: mounted ? "/Volumes/Backup SSD" : nil,
                      quotaBytes: nil, lastBackup: last.map { Parsers.formatTMBackupDate($0) },
                      lastBackupDate: last, freeBytes: mounted ? 612_000_000_000 : nil, schedule: schedule)
    }
    @MainActor func tm(_ d: TMDestination, backup: TMBackupProgress? = nil, action: TMActionState = .idle) -> AppModel {
        model { $0.report.tmDest = .some(d); $0.timeMachine.applyFixture(updatedAt: ref, backup: backup, action: action) }
    }
    let sample = TMBackupProgress(running: true, stopping: false, phase: "Copying", percent: 0.140625,
                                  bytesDone: 1_800_000_000, bytesTotal: 12_800_000_000, secondsRemaining: 600,
                                  destinationMountPoint: "/Volumes/Backup")

    let notset = model { _ in }
    let ok = tm(dest(last: ref - 50 * 60, mounted: true))
    let okNoFDA = tm(dest(last: ref - 50 * 60, mounted: true, schedule: nil))
    let over7Off = tm(dest(last: ref - 9 * 86_400, mounted: false))
    let over30Off = tm(dest(last: ref - 34 * 86_400, mounted: false))
    let over7On = tm(dest(last: ref - 9 * 86_400, mounted: true))
    let backingDest = dest(last: ref - 86_400 - 2 * 3600, mounted: true)
    let backing = tm(backingDest, backup: sample)
    let stopping = tm(backingDest, backup: sample, action: .stopping)
    let preparing = tm(backingDest, backup: TMBackupProgress(running: true, stopping: false, phase: "PreparingSourceVolumes"))
    let findingChanges = tm(backingDest, backup: TMBackupProgress(running: true, stopping: false, phase: "FindingChanges", changedItems: 31_711, scanFraction: 0.53))
    let failed = tm(dest(last: ref - 9 * 86_400, mounted: true), action: .failed(L.bkStartDidNotBegin))
    @MainActor func claude(_ s: ClaudeBackupStatus?, attempt: ClaudeBackupAttempt? = nil, disk: Bool? = true, action: ClaudeBackupAction = .idle,
                           job: Bool = true, size: ClaudeBackupSize? = nil, progress: Double? = nil) -> AppModel {
        model { m in
            let fixtureJob = m.claudeRun.job
            m.claudeBackup = s
            m.claudeRun.applyFixture(job: job ? fixtureJob : nil, attempt: attempt, diskConnected: disk, action: action, size: size, progress: progress)
        }
    }
    let mnt = "/Volumes/Backup SSD"
    let failedAttempt = ClaudeBackupAttempt(at: ref - 3 * 3600, result: .failed(exit: 23, reason: .filesChanged), mount: mnt)

    switch env["BACKUPS_VIEW"] ?? "" {
    case "narrow":
        harnessRender(width: 904) {
            HarnessSection(label: "B: ok (narrow)") { BackupsTimeMachineCard(model: ok, narrow: true) }
            HarnessSection(label: "D: overdue 7, unmounted (narrow)") { BackupsTimeMachineCard(model: over7Off, narrow: true) }
        }
    case "tm1":
        harnessRender(width: 1094) {
            HarnessSection(label: "A: not set up") { BackupsTimeMachineCard(model: notset, narrow: false) }
            HarnessSection(label: "B: ok") { BackupsTimeMachineCard(model: ok, narrow: false) }
            HarnessSection(label: "C: ok, schedule unreadable (no FDA)") { BackupsTimeMachineCard(model: okNoFDA, narrow: false) }
            HarnessSection(label: "D: overdue 7 d, unmounted") { BackupsTimeMachineCard(model: over7Off, narrow: false) }
        }
    case "tm2":
        harnessRender(width: 1094) {
            HarnessSection(label: "E: overdue 30 d, unmounted") { BackupsTimeMachineCard(model: over30Off, narrow: false) }
            HarnessSection(label: "F: overdue 7 d, mounted") { BackupsTimeMachineCard(model: over7On, narrow: false) }
            HarnessSection(label: "G: backing up 14 %") { BackupsTimeMachineCard(model: backing, narrow: false) }
            HarnessSection(label: "H: stopping") { BackupsTimeMachineCard(model: stopping, narrow: false) }
        }
    case "tm3":
        harnessRender(width: 1094) {
            HarnessSection(label: "I: preparing (no percent)") { BackupsTimeMachineCard(model: preparing, narrow: false) }
            HarnessSection(label: "I2: looking for changes (31 711, 53 %)") { BackupsTimeMachineCard(model: findingChanges, narrow: false) }
            HarnessSection(label: "J: start failed") { BackupsTimeMachineCard(model: failed, narrow: false) }
        }
    case "claude1":
        harnessRender(width: 1094) {
            HarnessSection(label: "K: Claude ok") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), attempt: .init(at: ref - 5 * 3600, result: .ok, mount: mnt))) }
            HarnessSection(label: "L: Claude stale") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 4 * 86_400), attempt: .init(at: ref - 4 * 86_400, result: .ok, mount: mnt))) }
            HarnessSection(label: "M: Claude none") { BackupsClaudeCard(model: claude(.noSuccessFound)) }
            HarnessSection(label: "N: Claude missing") { BackupsClaudeCard(model: claude(nil)) }
        }
    case "claude2":
        harnessRender(width: 1094) {
            HarnessSection(label: "O: Claude unreadable") { BackupsClaudeCard(model: claude(.unreadable)) }
            HarnessSection(label: "Q: Claude failed, fresh snapshot") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), attempt: failedAttempt, size: ClaudeBackupSize(snapshotBytes: 28_548_000_000, addedBytes: 467_000_000, totalBytes: 38_654_000_000))) }
            HarnessSection(label: "R: Claude failed, stale") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 4 * 86_400), attempt: failedAttempt)) }
        }
    case "claude3":
        harnessRender(width: 1094) {
            HarnessSection(label: "S: Claude running") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), attempt: .init(at: ref - 7 * 60, result: .running, mount: mnt), progress: 0.62)) }
            HarnessSection(label: "S2: running, no progress data") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), attempt: .init(at: ref - 7 * 60, result: .running, mount: mnt), progress: nil)) }
            HarnessSection(label: "S3: running, finishing") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), attempt: .init(at: ref - 7 * 60, result: .running, mount: mnt), progress: 0.99)) }
            HarnessSection(label: "T: Claude interrupted") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), attempt: .init(at: ref - 4 * 3600, result: .interrupted, mount: mnt))) }
        }
    case "claude4":
        harnessRender(width: 1094) {
            HarnessSection(label: "U: click, starting") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 7 * 3600), attempt: .init(at: ref - 7 * 3600, result: .ok, mount: mnt), action: .starting)) }
            HarnessSection(label: "V: click, no disk") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 7 * 3600), attempt: .init(at: ref - 7 * 3600, result: .ok, mount: mnt), disk: false, action: .diskNotConnected)) }
            HarnessSection(label: "W: click, already running") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), attempt: .init(at: ref - 60, result: .running, mount: mnt), action: .alreadyRunning)) }
        }
    case "claude5":
        harnessRender(width: 1094) {
            HarnessSection(label: "X: click, no response") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 7 * 3600), attempt: .init(at: ref - 7 * 3600, result: .ok, mount: mnt), disk: nil, action: .noResponse)) }
            HarnessSection(label: "Y: click, launch failed") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 7 * 3600), attempt: .init(at: ref - 7 * 3600, result: .ok, mount: mnt), action: .launchFailed)) }
            HarnessSection(label: "Z: no job (a Mac without it)") { BackupsClaudeCard(model: claude(.lastSuccess(ref - 5 * 3600), job: false)) }
        }
    case "bar1":
        harnessRender(width: 1094) {
            HarnessSection(label: "P1: bar, not set up") { BackupsPageBar(model: notset) {} }
            HarnessSection(label: "P2: bar, ok") { BackupsPageBar(model: ok) {} }
            HarnessSection(label: "P3: bar, overdue 30") { BackupsPageBar(model: over30Off) {} }
        }
    case "bar2":
        harnessRender(width: 1094) {
            HarnessSection(label: "P4: bar, backing up") { BackupsPageBar(model: backing) {} }
            HarnessSection(label: "P5: bar, Claude failed") { BackupsPageBar(model: claude(.lastSuccess(ref - 5 * 3600), attempt: failedAttempt)) {} }
        }
    default:
        FileHandle.standardError.write(Data("scenario_backups: set BACKUPS_VIEW to one of: narrow tm1 tm2 tm3 claude1 claude2 claude3 claude4 claude5 bar1 bar2\n".utf8))
        exit(64)
    }
}
