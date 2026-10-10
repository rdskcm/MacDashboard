// Tests/MacDashboardTests/ParsersTests.swift
// CI-SWIFT-TESTING: swift-testing port of the Parsers.parseSize / swapUsage checks
// (Checks/main.swift). Runs via `swift test` locally and in CI; the primary gate is still `swift run MacDashboardChecks`.
import Testing
@testable import MacDashboard

@Test(arguments: [
    ("62G", 62 << 30),
    ("228Gi", 228 << 30),
    ("4.0K", 4096),
    ("0B", 0),
    ("545M+", 545 << 20),
    ("3808K-", 3808 * 1024),
] as [(String, Int64)])
func parseSizeAcceptsHumanSizes(token: String, bytes: Int64) {
    #expect(Parsers.parseSize(token) == bytes)
}

@Test(arguments: ["abc", ""])
func parseSizeRejectsNonSizes(token: String) {
    #expect(Parsers.parseSize(token) == nil)
}

@Test func swapUsageParsesSysctlLine() throws {
    let line = "vm.swapusage: total = 2048.00M  used = 430.44M  free = 1617.56M  (encrypted)"
    let swap = try #require(Parsers.swapUsage(line: line))
    let mib = 1024.0 * 1024.0
    #expect(swap.total == Int64(2048.00 * mib))
    #expect(swap.used == Int64(430.44 * mib))
    #expect(swap.free == Int64(1617.56 * mib))
    #expect(Parsers.swapUsage(line: "vm.swapusage: nothing relevant here") == nil)
}
