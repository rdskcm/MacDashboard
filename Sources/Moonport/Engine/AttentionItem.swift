// Engine/AttentionItem.swift
// The attention data model: compact chip-sized items (AttentionItem) that Assess.assess() builds.
// Pure and Foundation-only — covered by Tests/MoonportTests.

import Foundation

/// The 17 attention kinds (the design's 16 keys plus `timeMachineOverdue`; `diskFull`/`diskFullSoon` are both key `disk`),
/// in the fixed order the spec assigns them (also the order `Assess.assess` evaluates their branches).
enum AttentionKind: String, CaseIterable {
    case diskFull, diskFullSoon,
         swapHigh, // memory pressure (name kept for id stability)
         batteryCapacity, batteryCondition, fileVaultOff,
         gatekeeperOff, sipOff, firewallOff, updates, crashes, timeMachine, timeMachineOverdue, claudeBackup, smartErrors, smartWear,
         wakeHolders
}

/// A single attention chip: compact label + detail
/// plus the full sentence for tooltip/list display.
struct AttentionItem: Identifiable, Equatable {
    var kind: AttentionKind
    var sev: Severity
    var label: String       // short chip form, e.g. "Disk"
    var detail: String      // e.g. "92 % full"
    var fullText: String    // the existing assessment sentence (tooltip / list body)
    var action: AdviceAction? = nil
    /// `.wakeHolders` only: the holders this item names, in its order — the targets of the
    /// plate's per-app "Don’t warn" menu (SLEEP-IGNORE-APP). Empty for every other kind.
    var wakeHolderKeys: [WakeHolderKey] = []
    /// TRIAGE-THRESHOLDS-REVIEW: one or two plain sentences on why this matters to the user; every kind built by
    /// `Assess.assess` sets it. Optional only so existing memberwise calls compile. Not part of `id`.
    var why: String? = nil
    /// The tooltip / notification body: `fullText`, then `why` when present.
    var fullTextWithWhy: String { why.map { fullText + " " + $0 } ?? fullText }
    var id: String { "\(kind.rawValue)|\(label)|\(detail)" }
}
