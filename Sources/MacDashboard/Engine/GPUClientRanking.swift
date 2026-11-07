// Engine/GPUClientRanking.swift
// SOC-DETAILS 1.3: the pure ranking of GPU clients between two samples (decisions D10-D13). Foundation only.
// The numbers come from GPUStats.readClients(); method as in Stats Modules/GPU/reader.swift:505-548 (share of the
// elapsed time from the accumulated GPU time delta), no code copied.
import Foundation

/// One row of the "top by GPU" list.
struct GPUProcessRow: Identifiable, Equatable {
    /// Process id: the row's stable identity (live-list-identity).
    let id: Int32
    let name: String
    /// Share of the elapsed time, 0...100 with 1 decimal shown by the view; nil → "—" (implausible, above 101).
    let sharePct: Double?
}

enum GPUClientRanking {
    /// Rows shown (D11): always the first 5.
    static let rowCount = 5
    /// A single share above this is a garbage reading and shows "—" (logic 3.5).
    static let implausibleAbovePct = 101.0

    /// Pure.
    /// - Several clients of one pid are summed (D10).
    /// - A pid absent from `prev`, or whose summed counter went down, gets no row this tick (D13).
    /// - Share = Σ(cur − prev) / (dtSeconds × 1e9) × 100; nil above 101.
    /// - Order: share (unrounded) descending, then lifetime descending, then name, then pid (D10).
    /// - The first 5 rows. `names(pid)` gives the full executable name (D12), else `name16` as read.
    /// `dtSeconds <= 0` → no rows.
    static func rows(prev: [GPUClientSample], cur: [GPUClientSample], dtSeconds: Double,
                     names: (Int32) -> String?) -> [GPUProcessRow] {
        guard dtSeconds > 0 else { return [] }
        var before: [Int32: UInt64] = [:]
        for c in prev { before[c.pid, default: 0] &+= c.gpuTimeNs }
        var now: [Int32: (ns: UInt64, name16: String)] = [:]
        for c in cur {
            if let e = now[c.pid] { now[c.pid] = (e.ns &+ c.gpuTimeNs, e.name16) }
            else { now[c.pid] = (c.gpuTimeNs, c.name16) }
        }
        struct Candidate { let pid: Int32; let name: String; let share: Double; let lifetime: UInt64 }
        var candidates: [Candidate] = []
        for (pid, entry) in now {
            guard let was = before[pid], entry.ns >= was else { continue }
            let share = Double(entry.ns - was) / (dtSeconds * 1e9) * 100
            candidates.append(Candidate(pid: pid, name: names(pid) ?? entry.name16, share: share, lifetime: entry.ns))
        }
        candidates.sort {
            // An implausible reading (shown as "—") ranks after every plausible one, so it never pushes real rows out.
            let bad0 = $0.share > implausibleAbovePct, bad1 = $1.share > implausibleAbovePct
            if bad0 != bad1 { return bad1 }
            if $0.share != $1.share { return $0.share > $1.share }
            if $0.lifetime != $1.lifetime { return $0.lifetime > $1.lifetime }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.pid < $1.pid
        }
        return candidates.prefix(rowCount).map {
            GPUProcessRow(id: $0.pid, name: $0.name,
                          sharePct: $0.share > implausibleAbovePct ? nil : $0.share)
        }
    }

    /// The name the Processes card shows: the last path component of the executable path.
    static func executableName(pid: Int32) -> String? {
        guard let path = ProcessInspector.path(for: pid) else { return nil }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? nil : last
    }
}
