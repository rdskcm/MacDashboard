// Engine/InFlightReads.swift
// IPHONE-LOGS-REATTACH: per-device bookkeeping of the one current in-flight read (crash-log
// listing, identity read). Bound to a request id and handle, not to the device, so a read
// from a detached connection can neither block nor clear a newer one. Pure; symlinked into
// Checks. Internal, not private (checks-helper-visibility).

struct InFlightReads<Handle: Hashable> {
    private var current: [String: (id: Int, handle: Handle)] = [:]
    private var lastID = 0

    /// True while a read of `key` is in flight.
    func contains(_ key: String) -> Bool { current[key] != nil }

    /// Starts a read of `key` over `handle`: returns its request id, or nil when a read over
    /// the same handle is already in flight. A read over another handle is superseded.
    mutating func begin(_ key: String, handle: Handle) -> Int? {
        if current[key]?.handle == handle { return nil }
        lastID += 1
        current[key] = (lastID, handle)
        return lastID
    }

    /// Ends request `id`. True iff it is still current (its result may be applied); a
    /// superseded or detached request returns false and leaves the current entry alone.
    mutating func finish(_ key: String, id: Int) -> Bool {
        guard current[key]?.id == id else { return false }
        current[key] = nil
        return true
    }

    /// `handle` detached: no read over it counts as in flight any more.
    mutating func detach(_ handle: Handle) {
        current = current.filter { $0.value.handle != handle }
    }
}
