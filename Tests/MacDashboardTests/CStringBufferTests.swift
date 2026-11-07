// Tests/MacDashboardTests/CStringBufferTests.swift
// SWIFT6-MODE: String(nulTerminated:) replaces the deprecated String(cString: [CChar]).
import Testing
@testable import MacDashboard

struct CStringBufferTests {
    @Test func stopsAtFirstNul() { #expect(String(nulTerminated: [104, 105, 0, 120]) == "hi") }
    @Test func withoutNulUsesWholeBuffer() { #expect(String(nulTerminated: [104, 105]) == "hi") }
    @Test func leadingNulIsEmpty() { #expect(String(nulTerminated: [0, 104]) == "") }
    @Test func emptyBufferIsEmpty() { #expect(String(nulTerminated: []) == "") }
    @Test func signedBytesDecodeAsUTF8() { #expect(String(nulTerminated: [-61, -87, 0]) == "é") }
}
