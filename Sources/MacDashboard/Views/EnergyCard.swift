// Views/EnergyCard.swift
// Настройки энергии (pmset) card — collapsed by default via DisclosureGroup.
//
// SPEC Block K: editable toggles/sleep timers with a pending-changes model, applied
// in one batched `pmset` call via PrivilegedRunner (Touch ID / admin password), plus
// a click-toggled ℹ️ explanation per parameter.

import SwiftUI

// MARK: - Настройки энергии (pmset) — collapsed by default

private var energyKeyOrder: [(key: String, label: String)] {
    [
        ("displaysleep", L.energyParamDisplaySleep), ("sleep", L.energyParamSleep),
        ("disksleep", L.energyParamDiskSleep), ("powernap", "Power Nap"),
        ("lowpowermode", L.energyParamLowPowerMode), ("standby", "Standby"),
        ("hibernatemode", L.energyParamHibernateMode), ("womp", L.energyParamWoMP)
    ]
}
private let energyBinaryKeys: Set<String> = ["powernap", "lowpowermode", "standby", "womp"]
private let energySleepKeys: Set<String> = ["displaysleep", "sleep", "disksleep"]

/// macOS laptop defaults (Apple Silicon portables) for the editable keys, as
/// (battery, AC). Best-effort documented values — `pmset restoredefaults` is
/// deliberately not used because it also resets non-editable keys like
/// hibernatemode. hibernatemode is intentionally absent (read-only in the UI).
private let energyDefaults: [String: (battery: String, ac: String)] = [
    "displaysleep": ("2", "10"),
    "sleep": ("1", "1"),
    "disksleep": ("10", "10"),
    "powernap": ("0", "1"),
    "lowpowermode": ("0", "0"),
    "standby": ("1", "1"),
    "womp": ("0", "1")
]

/// Explanation text shown under a parameter row when its ℹ️ is clicked. Only keys in
/// `energyKeyOrder` get one — extra/unknown pmset keys stay plain read-only rows.
private var energyInfoText: [String: String] {
    [
        "displaysleep": L.energyInfoDisplaySleep,
        "sleep": L.energyInfoSleep,
        "disksleep": L.energyInfoDiskSleep,
        "powernap": L.energyInfoPowerNap,
        "lowpowermode": L.energyInfoLowPowerMode,
        "standby": L.energyInfoStandby,
        "hibernatemode": L.energyInfoHibernateMode,
        "womp": L.energyInfoWoMP
    ]
}

private func energyValue(_ key: String, _ bucket: [(String, String)]) -> String {
    guard let raw = bucket.first(where: { $0.0 == key })?.1 else { return "—" }
    if energyBinaryKeys.contains(key) { return raw == "1" ? L.energyValueOn : L.energyValueOff }
    if energySleepKeys.contains(key), raw == "0" { return L.energyValueNever }
    return raw
}

/// Which pmset power source a pending change targets — `-b` (battery) or `-c` (AC).
enum EnergyBucket: Equatable {
    case battery
    case ac
}

/// One not-yet-applied edit: a validated integer string for `key` in `bucket`.
struct EnergyChange: Equatable {
    let bucket: EnergyBucket
    let key: String
    let value: String
}

struct EnergyCard: View {
    let model: DashboardModel

    @State private var pending: [EnergyChange] = []
    @State private var applying = false
    @State private var applyError: String? = nil
    @State private var infoKey: String? = nil

    var body: some View {
        if let energy = model.report.energy, !(energy.battery.isEmpty && energy.ac.isEmpty) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if !pending.isEmpty || resetAvailable(energy) {
                        applyBar(energy)
                    }
                    energyTable(energy)
                        .disabled(applying)
                }
                .padding(.top, 10)
            } label: {
                Text(L.energyCardTitle).font(.headline)
            }
            .cardBackground()
        } else {
            CardChrome(title: L.energyCardTitle) {
                SectionStateView(done: model.report.progress["energy"] ?? false)
            }
        }
    }

    // MARK: - Pending-changes bar

    private func applyBar(_ energy: EnergySettings) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if !pending.isEmpty {
                    Button(L.energyApply(pending.count)) { applyPending() }
                        .buttonStyle(.borderedProminent)
                    Button(L.energyCancel) {
                        pending = []
                        applyError = nil
                    }
                }
                if resetAvailable(energy) {
                    Button(L.energyResetToDefaults) { stageReset(energy) }
                        .help(L.energyResetHelp)
                }
                if applying {
                    ProgressView().controlSize(.small)
                }
            }
            .controlSize(.small)
            .disabled(applying)

            if let applyError {
                Text(applyError).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    /// Defensive whitelist: the key must be a plain-letters token, or one of the
    /// known `energyKeyOrder` keys — this is the only spot where non-constant
    /// text reaches a root shell via `PrivilegedRunner`.
    private func isValidPmsetKey(_ key: String) -> Bool {
        if key.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil { return true }
        return energyKeyOrder.contains { $0.key == key }
    }

    private func applyPending() {
        guard !applying else { return }
        let batteryArgs = pending.filter { $0.bucket == .battery && Int($0.value) != nil && isValidPmsetKey($0.key) }
            .map { "\($0.key) \($0.value)" }
        let acArgs = pending.filter { $0.bucket == .ac && Int($0.value) != nil && isValidPmsetKey($0.key) }
            .map { "\($0.key) \($0.value)" }

        var commands: [String] = []
        if !batteryArgs.isEmpty { commands.append("/usr/bin/pmset -b \(batteryArgs.joined(separator: " "))") }
        if !acArgs.isEmpty { commands.append("/usr/bin/pmset -c \(acArgs.joined(separator: " "))") }
        guard !commands.isEmpty else { return }
        let command = commands.joined(separator: " && ")

        applying = true
        applyError = nil

        Task {
            let outcome = await Task.detached { PrivilegedRunner.run(command) }.value
            applying = false
            switch outcome {
            case .success:
                pending = []
                applyError = nil
                await model.refreshEnergyNow()
            case .cancelled:
                applyError = L.energyApplyCancelled
            case .failed(let msg):
                applyError = L.energyApplyFailed(msg)
            }
        }
    }

    // MARK: - Table

    private func energyTable(_ energy: EnergySettings) -> some View {
        let knownKeys = energyKeyOrder.filter { k in
            energy.battery.contains { $0.0 == k.key } || energy.ac.contains { $0.0 == k.key }
        }
        let knownSet = Set(knownKeys.map(\.key))
        let extraKeys = (energy.battery.map(\.0) + energy.ac.map(\.0))
            .filter { !knownSet.contains($0) }
            .reduce(into: [String]()) { acc, k in if !acc.contains(k) { acc.append(k) } }

        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text(L.energyColParam).font(.caption).foregroundStyle(.secondary)
                Text(L.energyColBattery).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
                Text(L.energyColAC).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
            Divider()
            ForEach(knownKeys, id: \.key) { k in
                GridRow {
                    HStack(spacing: 4) {
                        Text(k.label).font(.callout)
                        Button {
                            infoKey = (infoKey == k.key) ? nil : k.key
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    controlView(bucket: .battery, key: k.key, energy: energy)
                        .frame(width: 110, alignment: .trailing)
                    controlView(bucket: .ac, key: k.key, energy: energy)
                        .frame(width: 110, alignment: .trailing)
                }
                if infoKey == k.key, let text = energyInfoText[k.key] {
                    GridRow {
                        Text(text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                            .gridCellColumns(3)
                    }
                }
            }
            ForEach(extraKeys, id: \.self) { key in
                GridRow {
                    Text(key).font(.callout)
                    Text(energyValue(key, energy.battery)).font(.callout).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    Text(energyValue(key, energy.ac)).font(.callout).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Per-cell controls

    @ViewBuilder
    private func controlView(bucket: EnergyBucket, key: String, energy: EnergySettings) -> some View {
        if rawValue(bucket, key, energy: energy) == nil {
            Text("—").font(.callout).foregroundStyle(.secondary)
        } else if energyBinaryKeys.contains(key) {
            let dirty = pending.contains { $0.bucket == bucket && $0.key == key }
            Toggle("", isOn: toggleBinding(bucket, key, energy: energy))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(dirty ? .orange : nil)
                // tint is invisible in the OFF state — outline marks a pending change either way
                .overlay {
                    if dirty {
                        Capsule().strokeBorder(Color.orange, lineWidth: 1.5).padding(-2)
                    }
                }
        } else if energySleepKeys.contains(key) {
            let dirty = pending.contains { $0.bucket == bucket && $0.key == key }
            EnergySleepField(
                value: effectiveValue(bucket, key, energy: energy) ?? "0",
                isDirty: dirty,
                onCommit: { newValue in
                    updatePending(bucket, key, value: newValue, original: rawValue(bucket, key, energy: energy))
                }
            )
        } else {
            // hibernatemode and any other known-but-non-editable key: read-only, as before.
            Text(energyValue(key, bucket == .battery ? energy.battery : energy.ac))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pending-changes helpers

    private func rawValue(_ bucket: EnergyBucket, _ key: String, energy: EnergySettings) -> String? {
        let source = bucket == .battery ? energy.battery : energy.ac
        return source.first(where: { $0.0 == key })?.1
    }

    private func effectiveValue(_ bucket: EnergyBucket, _ key: String, energy: EnergySettings) -> String? {
        if let p = pending.first(where: { $0.bucket == bucket && $0.key == key }) { return p.value }
        return rawValue(bucket, key, energy: energy)
    }

    private func toggleBinding(_ bucket: EnergyBucket, _ key: String, energy: EnergySettings) -> Binding<Bool> {
        Binding(
            get: { effectiveValue(bucket, key, energy: energy) == "1" },
            set: { newValue in
                updatePending(bucket, key, value: newValue ? "1" : "0",
                              original: rawValue(bucket, key, energy: energy))
            }
        )
    }

    /// Adds/replaces a pending entry, or removes it when `value` matches the
    /// currently-applied (`original`) value — i.e. editing back to the applied
    /// value clears the dirty state instead of leaving a no-op pending entry.
    private func updatePending(_ bucket: EnergyBucket, _ key: String, value: String, original: String?) {
        if value == original {
            pending.removeAll { $0.bucket == bucket && $0.key == key }
        } else if let idx = pending.firstIndex(where: { $0.bucket == bucket && $0.key == key }) {
            pending[idx] = EnergyChange(bucket: bucket, key: key, value: value)
        } else {
            pending.append(EnergyChange(bucket: bucket, key: key, value: value))
        }
    }

    // MARK: - Reset-to-defaults

    private func defaultValue(_ bucket: EnergyBucket, _ key: String) -> String? {
        guard let pair = energyDefaults[key] else { return nil }
        return bucket == .battery ? pair.battery : pair.ac
    }

    /// True if any editable key/bucket pair present in the report has an effective
    /// value (applied + pending overlay) that differs from the macOS default.
    private func resetAvailable(_ energy: EnergySettings) -> Bool {
        for key in energyDefaults.keys {
            for bucket in [EnergyBucket.battery, .ac] {
                guard rawValue(bucket, key, energy: energy) != nil else { continue }
                if effectiveValue(bucket, key, energy: energy) != defaultValue(bucket, key) {
                    return true
                }
            }
        }
        return false
    }

    /// Stages every editable key/bucket pair present in the report to its macOS
    /// default value. Keys already at default are naturally cleared from `pending`
    /// by `updatePending`; only real diffs remain staged for review/apply.
    private func stageReset(_ energy: EnergySettings) {
        for k in energyKeyOrder where energyDefaults[k.key] != nil {
            for bucket in [EnergyBucket.battery, .ac] {
                guard let original = rawValue(bucket, k.key, energy: energy),
                      let def = defaultValue(bucket, k.key) else { continue }
                updatePending(bucket, k.key, value: def, original: original)
            }
        }
        applyError = nil
    }
}

// MARK: - Sleep-timer numeric field

/// Small numeric field for a sleep-timer key (displaysleep/sleep/disksleep): digits
/// only, clamped to 0…9999, committed on Enter or on losing focus (not on every
/// keystroke, so a value mid-edit like "1" isn't sent to `pmset` prematurely).
private struct EnergySleepField: View {
    let value: String
    let isDirty: Bool
    let onCommit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(width: 52)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isDirty ? Color.orange : Color.clear, lineWidth: 1.5)
            )
            .onChange(of: text) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue { text = digits }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in
                if !focused { text = newValue }
            }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        let clamped = min(max(Int(digits) ?? 0, 0), 9999)
        text = String(clamped)
        onCommit(text)
    }
}
