// Engine/AIRedaction.swift
// Deterministic PII-style redaction for text sent to the AI assistant (Block AI,
// Wave 1). Pure Foundation only — this file is symlinked into the Checks target
// (see Checks/README.md), so no SwiftUI / App-only globals here.

import Foundation

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
struct RedactionContext: Equatable {
    var usernames: [String] = []
    var hostNames: [String] = []
    var serials: [String] = []
    var ssids: [String] = []
}

struct RedactionOptions: Equatable {
    var redactSerials = true
    var redactUsername = true
    var redactHostname = true
    var redactSSID = true
}

enum Redactor {
    static let userPlaceholder   = "[REDACTED-USER]"
    static let hostPlaceholder   = "[REDACTED-HOST]"
    static let serialPlaceholder = "[REDACTED-SERIAL]"
    static let ssidPlaceholder   = "[REDACTED-SSID]"

    /// Replaces every case-insensitive, word-boundary-guarded occurrence of each
    /// known secret value with its placeholder. Longest values are substituted
    /// first so overlapping candidates (e.g. a full hostname vs. its short form)
    /// never get partially matched by a shorter value processed earlier.
    static func redact(_ text: String, context: RedactionContext, options: RedactionOptions) -> String {
        var pairs: [(value: String, placeholder: String)] = []
        if options.redactUsername { pairs.append(contentsOf: context.usernames.map { ($0, userPlaceholder) }) }
        if options.redactHostname { pairs.append(contentsOf: context.hostNames.map { ($0, hostPlaceholder) }) }
        if options.redactSerials { pairs.append(contentsOf: context.serials.map { ($0, serialPlaceholder) }) }
        if options.redactSSID { pairs.append(contentsOf: context.ssids.map { ($0, ssidPlaceholder) }) }

        // Drop too-short values, then dedupe (keep first placeholder assignment).
        var seen = Set<String>()
        var filtered: [(value: String, placeholder: String)] = []
        for pair in pairs where pair.value.count >= 2 {
            if seen.contains(pair.value) { continue }
            seen.insert(pair.value)
            filtered.append(pair)
        }

        // Longest value first.
        filtered.sort { $0.value.count > $1.value.count }

        var result = text
        for pair in filtered {
            let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: pair.value) + "(?![A-Za-z0-9])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: NSRegularExpression.escapedTemplate(for: pair.placeholder))
        }
        return result
    }
}
#endif
