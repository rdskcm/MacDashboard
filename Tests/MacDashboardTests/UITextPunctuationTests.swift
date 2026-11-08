// Tests/MacDashboardTests/UITextPunctuationTests.swift
// UI-SEMICOLON-SWEEP: user-visible text has no semicolons (user rule 2026-11-05: two short sentences instead).
// Source scan of the string tables in Engine/Strings/ — no process-wide state, so this suite stays outside
// `SerialTests`. Paths come from `#filePath`, so the test runs from any cwd. Pattern: EngineBoundaryTests.swift.
import Foundation
import Testing

/// `<package>/Sources/MacDashboard/Engine/Strings`.
private let stringTablesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/MacDashboardTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // package root
    .appendingPathComponent("Sources/MacDashboard/Engine/Strings", isDirectory: true)

/// The text of every one-line string literal on `line`, literals nested inside `\( … )` included (a nested literal
/// comes before the literal that contains it). A `//` comment outside a literal ends the line.
private func stringLiteralTexts(_ line: Substring) -> [String] {
    let c = Array(line)
    var i = 0
    var out: [String] = []
    scanLiteralCode(c, &i, &out, interpolation: false)
    return out
}

/// Code outside literals: collects literals; stops at a `//` comment or (interpolation) at the `)` closing the `\(`.
private func scanLiteralCode(_ c: [Character], _ i: inout Int, _ out: inout [String], interpolation: Bool) {
    var depth = 0
    while i < c.count {
        let ch = c[i]
        if ch == "/", i + 1 < c.count, c[i + 1] == "/" { i = c.count; return }
        if ch == "\"" { i += 1; out.append(scanLiteralText(c, &i, &out)); continue }
        if interpolation {
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                if depth == 0 { i += 1; return }
                depth -= 1
            }
        }
        i += 1
    }
}

/// Consumes a literal after its opening quote; returns its text without the interpolations.
private func scanLiteralText(_ c: [Character], _ i: inout Int, _ out: inout [String]) -> String {
    var text = ""
    while i < c.count {
        let ch = c[i]
        if ch == "\\" {
            if i + 1 < c.count, c[i + 1] == "(" {
                i += 2
                scanLiteralCode(c, &i, &out, interpolation: true)
            } else {
                if i + 1 < c.count { text.append(c[i + 1]) }
                i += 2
            }
            continue
        }
        i += 1
        if ch == "\"" { return text }
        text.append(ch)
    }
    return text
}

struct UITextPunctuationTests {
    @Test func scannerReadsLiteralsOnly() {
        #expect(stringLiteralTexts(#"var a: String { "one; two" } // x; "y" z"#) == ["one; two"])
        #expect(stringLiteralTexts(#"return "\(head): \(e.joined(separator: "; "))." + x"#) == ["; ", ": ."])
        #expect(stringLiteralTexts(#"let s = "a \"b\" c"; let t = 1"#) == ["a \"b\" c"])
    }

    @Test func stringTablesHaveNoSemicolons() throws {
        let files = try FileManager.default.contentsOfDirectory(at: stringTablesRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty, "no string tables found at \(stringTablesRoot.path)")
        var hits: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("\"\"\""),
                    "\(file.lastPathComponent): multi-line string literal. Extend stringLiteralTexts before using one.")
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for literal in stringLiteralTexts(line) where literal.contains(";") || literal.contains("；") {
                    hits.append("\(file.lastPathComponent):\(n + 1): \"\(literal)\"")
                }
            }
        }
        #expect(hits.isEmpty, "User-visible text must not contain a semicolon (use two short sentences):\n\(hits.joined(separator: "\n"))")
    }
}
