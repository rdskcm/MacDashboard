// Engine/SysdiagnoseExtractor.swift
// IPHONE-IMPORT-IOS27: extracts only the sysdiagnose members the import parses (D13) and
// does not fail when one kind of member is absent. Two tar passes: list the archive, pick
// the members in Swift, extract exactly those through a member-list file. Foundation +
// CommandRunner only, so the file is symlinked into the Checks target; everything is
// internal, not private (checks-helper-visibility).

import Foundation

enum SysdiagnoseExtractor {
    static let tarPath = "/usr/bin/tar"
    static let timeout: TimeInterval = 300

    static func listArguments(archive: String) -> [String] { ["-tzf", archive] }

    static func extractArguments(archive: String, into dir: String, memberList: String) -> [String] {
        ["-xzf", archive, "-C", dir, "-T", memberList]
    }

    /// True for a member the import parses, judged by the path components of one `tar -t`
    /// line: `…/logs/BatteryBDC/BDC_Daily_*.csv`, `…/logs/BatteryBDC/BDC_Once_*.csv`, `…/crashes_and_spins/*.ips`,
    /// `…/crashes_and_spins/Retired/*.ips`. Any number of leading components (none included);
    /// `.` components are ignored; a line ending in `/` is a directory.
    static func isWanted(_ line: String) -> Bool {
        guard !line.hasSuffix("/") else { return false }
        let parts = line.split(separator: "/").map(String.init).filter { $0 != "." }
        guard let name = parts.last else { return false }
        let dirs = Array(parts.dropLast())
        if (name.hasPrefix("BDC_Daily_") || name.hasPrefix("BDC_Once_")) && name.hasSuffix(".csv") {
            return Array(dirs.suffix(2)) == ["logs", "BatteryBDC"]
        }
        guard name.hasSuffix(".ips") else { return false }
        return dirs.last == "crashes_and_spins" || Array(dirs.suffix(2)) == ["crashes_and_spins", "Retired"]
    }

    /// The tar pattern for one listed member. Works on UTF-8 bytes: [A-Za-z0-9/._-] is copied;
    /// each listing escape (`\` + 3 octal digits, or `\` + one character: one archive byte)
    /// and every other byte becomes `?`, tar's one-byte wildcard. So no name can inject a
    /// wildcard, and the pattern matches whether tar printed a byte raw or escaped.
    /// A `-` as the first byte also becomes `?`, so no line of the member list can read as a tar option.
    static func pattern(forListed line: String) -> String {
        let b = Array(line.utf8)
        var out: [UInt8] = []
        var i = 0
        while i < b.count {
            let c = b[i]
            if c == UInt8(ascii: "\\") {
                let octal = i + 3 < b.count && b[(i + 1)...(i + 3)].allSatisfy { (0x30...0x37).contains($0) }
                i += octal ? 4 : 2
                out.append(UInt8(ascii: "?"))
                continue
            }
            let safe = (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
                || c == UInt8(ascii: "/") || c == UInt8(ascii: ".") || c == UInt8(ascii: "_") || c == UInt8(ascii: "-")
            out.append(safe && !(c == UInt8(ascii: "-") && i == 0) ? c : UInt8(ascii: "?"))
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Patterns for every wanted member of a `tar -t` listing, in listing order, deduplicated.
    static func memberPatterns(listing: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in listing.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) where isWanted(String(line)) {
            let p = pattern(forListed: String(line))
            if seen.insert(p).inserted { out.append(p) }
        }
        return out
    }

    /// nil for a clean exit; `.cancelled`; otherwise `.tarFailed` with the reason (D8).
    static func importError(for o: CommandOutcome) -> ImportError? {
        let line = o.stderrHead.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { ExtractFailure.message(String($0.prefix(200))) }
        switch o.termination {
        case .exited(0): return nil
        case .cancelled: return .cancelled
        case .launchFailed(let code): return .tarFailed(.launchFailed(code))
        case .timedOut: return .tarFailed(.timedOut)
        case .exited(let n): return .tarFailed(line ?? .exitCode(n))
        case .signaled(let s): return .tarFailed(line ?? .signal(s))
        }
    }

    /// Lists `archive`, extracts its wanted members into `dir` (which must exist), and returns
    /// how many member patterns were used. Nothing wanted → `.success(0)`, `memberList` is not
    /// written and the extraction tar is not run (an empty list would extract everything).
    static func extract(archive: URL, into dir: URL, memberList: URL) async -> Result<Int, ImportError> {
        let listing = await CommandRunner.run(tarPath, listArguments(archive: archive.path), timeout: timeout)
        if let e = importError(for: listing) { return .failure(e) }
        if listing.stdoutTruncated { return .failure(.tarFailed(.listingTooLong)) }
        let patterns = memberPatterns(listing: listing.stdout)
        guard !patterns.isEmpty else { return .success(0) }
        do {
            try Data((patterns.joined(separator: "\n") + "\n").utf8).write(to: memberList, options: .withoutOverwriting)
        } catch {
            return .failure(.tarFailed(.workFiles))
        }
        let out = await CommandRunner.run(tarPath, extractArguments(archive: archive.path, into: dir.path,
                                                                    memberList: memberList.path),
                                          timeout: timeout)
        if let e = importError(for: out) { return .failure(e) }
        return .success(patterns.count)
    }
}
