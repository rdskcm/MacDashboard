// Engine/DirectoryAccess.swift
// Per-directory readability probe: tells "the app was refused this folder" apart
// from "this folder isn't there". macOS exposes no supported API for asking
// whether the app holds Full Disk Access (and TCC.db is itself FDA-gated), so the
// app never asks — it probes the exact directories it needs and reports the ones
// that exist but refuse to open. Pure + Foundation-only — compiled into Checks.

import Foundation

/// What a directory probe found. `.missing` is the "say nothing" outcome: the path
/// is absent, is not a directory, or failed to open for a reason that is not a
/// permission denial — none of those is something to report to the user.
enum DirAccess: String, Equatable { case readable, denied, missing }

/// What the open attempt reported, as three facts the pure decision table can be
/// fed from a check without performing any syscall.
enum DirOpenOutcome: Equatable { case opened, permissionDenied, otherFailure }

enum DirectoryAccess {

    // MARK: - pure decision (Checks-covered, no syscalls)

    /// The whole decision, in one table. Order matters: a path that is absent or is
    /// not a directory is `.missing` whatever the open attempt said.
    static func classify(exists: Bool, isDirectory: Bool, open: DirOpenOutcome) -> DirAccess {
        guard exists, isDirectory else { return .missing }
        switch open {
        case .opened: return .readable
        case .permissionDenied: return .denied
        case .otherFailure: return .missing
        }
    }

    /// Immediate children of `home` that `du -d 1` did NOT report, as absolute
    /// paths, sorted. Pure set math: `duPaths` is what the du output listed,
    /// `childNames` is what the directory actually contains. Trailing slashes are
    /// normalized on both sides so "/Users/x/Documents/" counts as reported.
    static func missingHomeChildren(home: String, duPaths: Set<String>, childNames: [String]) -> [String] {
        let base = normalized(home)
        let reported = Set(duPaths.map(normalized))
        return childNames
            .map { base + "/" + $0 }
            .filter { !reported.contains(normalized($0)) }
            .sorted()
    }

    private static func normalized(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    // MARK: - syscalls (thin, no decisions)

    /// Non-throwing probe of one absolute path. `stat` first (via FileManager),
    /// then `opendir` — `stat` succeeds on a TCC-protected directory and so does
    /// `access(R_OK)` (the POSIX mode bits are fine); only actually opening the
    /// directory is refused, which is why the open attempt IS the probe. The
    /// handle is closed immediately, so no descriptor is held.
    static func probe(_ path: String) -> DirAccess {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        guard exists, isDir.boolValue else {
            return classify(exists: exists, isDirectory: isDir.boolValue, open: .otherFailure)
        }
        if let handle = opendir(path) {
            closedir(handle)
            return classify(exists: true, isDirectory: true, open: .opened)
        }
        // errno is read immediately after the failing call — nothing runs in between.
        let denied = (errno == EPERM || errno == EACCES)
        return classify(exists: true, isDirectory: true, open: denied ? .permissionDenied : .otherFailure)
    }

    /// Immediate child NAMES of `dir` (hidden entries included, "." and ".."
    /// excluded). Empty when `dir` itself cannot be listed — the app then makes no
    /// claim about what is hidden rather than guessing.
    static func childNames(of dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    }
}
