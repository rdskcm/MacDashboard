// Engine/BrewProgress.swift
// Live-progress model + pure line-reducer for `brew upgrade`, fed by
// `CommandRunner.runStreaming`'s per-line callback. Foundation-only (this file is
// symlinked into the Checks target — no AppKit/SwiftUI/L10n here).
//
// Parsing rules are empirically grounded against non-TTY `brew upgrade` output on
// current Homebrew (concurrent DownloadQueue): see BrewProgressParser.consume for
// the exact line shapes recognized.

import Foundation

/// One live snapshot of `brew upgrade` progress, derived from its non-TTY output.
struct BrewProgress: Equatable {
    enum Phase: Equatable {
        case downloading   // global up-front fetch phase
        case upgrading     // per-formula install phase
    }
    var phase: Phase
    var formula: String?     // current formula (upgrading) / last finished download item (downloading)
    var completed: Int       // number of `==> Upgrading <name>` markers seen so far (may exceed total when dependents get pulled in)
    var total: Int           // outdated count known before launch; 0 = unknown
    var downloadsDone: Int   // finished downloads (stderr ✔︎ lines)
}

/// Pure line-reducer. Feed every output line; read `progress` after each change.
struct BrewProgressParser {
    let total: Int
    private(set) var progress: BrewProgress?   // nil until the first recognized marker

    init(total: Int) {
        self.total = total
    }

    /// Recognized "type" prefixes on a finished-download `✔︎ ` line, longest first so
    /// e.g. "Bottle Manifest " is tried before the shorter "Bottle " it would
    /// otherwise also match.
    private static let downloadTypePrefixes = [
        "Bottle Manifest ", "Bottle ", "Formula ", "Resource ", "Patch ", "Cask "
    ]

    /// Returns true when `progress` changed.
    mutating func consume(line: String, isStderr: Bool) -> Bool {
        if isStderr {
            return consumeStderr(line)
        }
        return consumeStdout(line)
    }

    private mutating func consumeStdout(_ line: String) -> Bool {
        if line.hasPrefix("==> Fetching downloads for:") {
            if progress == nil {
                progress = BrewProgress(phase: .downloading, formula: nil, completed: 0,
                                         total: total, downloadsDone: 0)
            } else {
                progress?.phase = .downloading
            }
            return true
        }

        if line.hasPrefix("==> Upgrading ") {
            let remainder = String(line.dropFirst("==> Upgrading ".count))
            // Excludes Homebrew's "==> Upgrading N dependents of upgraded formulae:"
            // header — formula names never contain spaces, and that header ends
            // with ":".
            guard !remainder.contains(" "), !remainder.hasSuffix(":") else { return false }
            if progress == nil {
                progress = BrewProgress(phase: .upgrading, formula: nil, completed: 0,
                                         total: total, downloadsDone: 0)
            }
            progress?.phase = .upgrading
            progress?.completed += 1
            progress?.formula = remainder
            return true
        }

        if line.hasPrefix("==> Installing "), let range = line.range(of: " dependency: ") {
            let dep = String(line[range.upperBound...])
            if progress == nil {
                progress = BrewProgress(phase: .upgrading, formula: nil, completed: 0,
                                         total: total, downloadsDone: 0)
            }
            progress?.phase = .upgrading
            progress?.formula = dep
            return true
        }

        return false
    }

    private mutating func consumeStderr(_ line: String) -> Bool {
        guard line.hasPrefix("✔︎ ") else { return false }

        if progress == nil {
            progress = BrewProgress(phase: .downloading, formula: nil, completed: 0,
                                     total: total, downloadsDone: 0)
        }
        progress?.downloadsDone += 1
        if progress?.phase == .downloading {
            progress?.formula = Self.parsedDownloadName(from: line)
        }
        return true
    }

    /// Drops the leading "✔︎ ", then the first matching download-type prefix, then
    /// one trailing parenthesized suffix (" (…)") if present.
    private static func parsedDownloadName(from line: String) -> String {
        var remainder = String(line.dropFirst("✔︎ ".count))
        for prefix in downloadTypePrefixes where remainder.hasPrefix(prefix) {
            remainder = String(remainder.dropFirst(prefix.count))
            break
        }
        if remainder.hasSuffix(")"), let openParen = remainder.range(of: " (", options: .backwards) {
            remainder = String(remainder[remainder.startIndex..<openParen.lowerBound])
        }
        return remainder
    }
}
