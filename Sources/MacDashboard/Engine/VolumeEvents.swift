// Engine/VolumeEvents.swift
// DISK-MOUNT-LIVE: which mount notifications count, and the timing of the re-read they cause. Foundation only.
import Foundation

enum VolumeEvents {
    /// Trailing debounce: one disk can mount several volumes in a row (not measured; `followUp` corrects a short value).
    static let debounce: Duration = .milliseconds(1500)
    /// The second read after the first lands: destinationinfo may lag a mount, a whole disk may leave `diskutil`
    /// after its last unmount, and a sampler read started before the event may have overwritten the first read.
    static let followUp: Duration = .seconds(8)

    /// True only for `/Volumes/<name>`. Time Machine's snapshot mounts live deeper
    /// (`/Volumes/.timemachine/<UUID>/…`, `/Volumes/com.apple.TimeMachine.localsnapshots/…`) and cause no read.
    /// A missing path counts: a missed event costs up to 300 s, an extra read about a second.
    static func isRelevant(path: String?) -> Bool {
        guard let path else { return true }
        let parts = path.split(separator: "/")
        guard parts.count == 2, parts[0] == "Volumes" else { return false }
        return !parts[1].hasPrefix(".") && !parts[1].hasPrefix("com.apple.TimeMachine")
    }
}
