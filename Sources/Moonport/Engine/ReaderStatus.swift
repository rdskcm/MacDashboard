// Engine/ReaderStatus.swift
// READER-STATUS: the status of one hardware reader (ok, not applicable, failed) with a machine-generated reason.
// Device-neutral on purpose: Mac identifiers, order and mappings live in ReaderStatusMac.swift; the iPhone block adds
// its own file. Reason texts are technical notation, identical in every UI language (spec D3).
import Foundation

/// Stable identifier of one reader, printed verbatim in the report ("smc.power").
struct ReaderID: Hashable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// One reader's status in one report pass.
struct ReaderStatusLine: Equatable, Sendable {
    let reader: ReaderID
    let status: ReaderStatus
    /// What was read, short and machine-formatted ("PSTR 6.42 W"); nil when nothing is worth printing.
    var reading: String? = nil

    /// Pure. `lines` in the order of `order`; identifiers not in `order` follow, sorted by raw value. Stable.
    static func ordered(_ lines: [ReaderStatusLine], by order: [ReaderID]) -> [ReaderStatusLine] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return lines.enumerated().sorted { a, b in
            switch (rank[a.element.reader], rank[b.element.reader]) {
            case let (x?, y?): return x != y ? x < y : a.offset < b.offset
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                let (x, y) = (a.element.reader.rawValue, b.element.reader.rawValue)
                return x != y ? x < y : a.offset < b.offset
            }
        }.map(\.element)
    }
}

enum ReaderStatus: Equatable, Sendable {
    case ok
    case notApplicable(ReaderReason)
    case failed(ReaderReason)

    var reason: ReaderReason? {
        switch self {
        case .ok: return nil
        case .notApplicable(let r), .failed(let r): return r
        }
    }
}

/// Why a reader is not applicable or failed. Built only where the failure happened, from the values at hand.
enum ReaderReason: Error, Equatable, Sendable {
    case libraryNotLoaded(path: String, dlerror: String?)
    case symbolMissing(library: String, symbol: String)
    case serviceAbsent(className: String)
    case registryEntryAbsent(path: String)
    case registryPropertyAbsent(entry: String, property: String)
    case ioReportChannelAbsent(group: String, subgroup: String, channel: String?)
    case smcKeyAbsent(key: String, result: UInt8)
    case smcKeyUnsupported(key: String, type: String, size: Int)
    case smcResult(key: String, result: UInt8)
    case kernReturn(call: String, code: Int32)
    case errno(call: String, code: Int32)
    case nsError(call: String, domain: String, code: Int)
    case callFailed(call: String, code: Int32)
    case nullResult(call: String)
    case command(tool: String, termination: CommandOutcome.Termination)
    case emptyOutput(tool: String)
    case unparsed(tool: String)
    case executableAbsent(name: String, searched: [String])
    case empty(what: String)
    case implausible(what: String, value: String, accepted: String)
    case validationFailed(what: String, check: String)
    case prerequisiteFailed(reader: ReaderID)
    case timedOut(seconds: Int)
    case several([ReaderReason])

    /// One reason stays itself; two or more become `.several`. Callers never pass an empty list.
    static func joined(_ reasons: [ReaderReason]) -> ReaderReason {
        reasons.count == 1 ? reasons[0] : .several(reasons)
    }

    /// Pure. The report text (spec T2). Never contains a semicolon.
    var text: String {
        switch self {
        case .libraryNotLoaded(let path, let message):
            return "dlopen \(path) failed: " + (message.map { String($0.prefix(200)) } ?? "no dlerror text")
        case .symbolMissing(let library, let symbol): return "dlsym \(symbol) not found in \(library)"
        case .serviceAbsent(let name): return "IOService \(name) not found"
        case .registryEntryAbsent(let path): return "registry entry \(path) not found"
        case .registryPropertyAbsent(let entry, let property): return "registry property \(property) not found on \(entry)"
        case .ioReportChannelAbsent(let group, let subgroup, let channel):
            guard let channel else { return "IOReport group \"\(group)\" / \"\(subgroup)\" not found" }
            return "IOReport channel \(channel) not found in \"\(group)\" / \"\(subgroup)\""
        case .smcKeyAbsent(let key, let result): return "SMC key \(key) not found (result \(String(format: "0x%02X", result)))"
        case .smcKeyUnsupported(let key, let type, let size): return "SMC key \(key) has type \"\(type)\" size \(size), not decodable"
        case .smcResult(let key, let result): return "SMC key \(key) read failed (result \(String(format: "0x%02X", result)))"
        case .kernReturn(let call, let code):
            return "\(call) returned kern_return \(String(format: "0x%08X", UInt32(bitPattern: code))) (\(String(cString: mach_error_string(code))))"
        case .errno(let call, let code): return "\(call) failed: errno \(code) (\(String(cString: strerror(code))))"
        case .nsError(let call, let domain, let code): return "\(call) failed: \(domain) \(code)"
        case .callFailed(let call, let code): return "\(call) returned \(code)"
        case .nullResult(let call): return "\(call) returned NULL"
        case .command(let tool, let termination):
            switch termination {
            case .exited(let c): return "\(tool) exited with status \(c)"
            case .signaled(let s): return "\(tool) killed by signal \(s)"
            case .launchFailed(let e): return "\(tool) could not start: errno \(e) (\(String(cString: strerror(e))))"
            case .timedOut: return "\(tool) timed out"
            case .cancelled: return "\(tool) cancelled"
            }
        case .emptyOutput(let tool): return "\(tool) printed nothing"
        case .unparsed(let tool): return "\(tool) output not recognised"
        case .executableAbsent(let name, let searched): return "\(name) not found at " + searched.joined(separator: ", ")
        case .empty(let what): return "\(what): none found"
        case .implausible(let what, let value, let accepted): return "\(what) = \(value), outside \(accepted)"
        case .validationFailed(let what, let check): return "\(what) failed check: \(check)"
        case .prerequisiteFailed(let reader): return "not run because \(reader.rawValue) failed"
        case .timedOut(let seconds): return "no answer within \(seconds) s"
        case .several(let reasons): return reasons.map(\.text).joined(separator: " | ")
        }
    }
}
