// Engine/CStringBuffer.swift
// SWIFT6-MODE: replaces the deprecated `String(cString: [CChar])` at the sysctl / proc_pidpath /
// IORegistry buffer sites.
import Foundation

extension String {
    /// Decodes a NUL-terminated C character buffer filled by a C API (sysctl, proc_pidpath, IORegistry).
    /// Stops at the first NUL, or at the end of the buffer if it has none — never reads past it.
    /// Invalid UTF-8 is repaired with U+FFFD, as `String(cString:)` did.
    init(nulTerminated buffer: [CChar]) {
        self = buffer.withUnsafeBytes { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
