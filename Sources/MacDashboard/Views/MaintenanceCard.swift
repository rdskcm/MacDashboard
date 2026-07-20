// Views/MaintenanceCard.swift
// Обслуживание системы card (merged Homebrew / Обновления macOS / Недавние краши).
//
// Previously three separate compact cards (Homebrew, Обновления macOS,
// Недавние краши) that were often half-empty and scattered in the grid.
// Merged into one card with three clearly-labeled sub-sections, each keeping
// its original nil/empty-state handling untouched.

import AppKit
import SwiftUI

struct MaintenanceCard: View {
    let model: DashboardModel

    var body: some View {
        CardChrome(title: L.maintenanceTitle) {
            VStack(alignment: .leading, spacing: 14) {
                maintenanceSection("Homebrew") {
                    switch model.report.brewVersion {
                    case .none:
                        SectionStateView(done: model.report.progress["brew"] ?? false)
                    case .some(.none):
                        Text(L.maintenanceBrewNotInstalled).font(.callout).foregroundStyle(.secondary)
                    case .some(.some(let version)):
                        VStack(alignment: .leading, spacing: 6) {
                            Text(version).font(.callout)
                            if let outdated = model.report.brewOutdated {
                                if outdated.isEmpty {
                                    Text(L.maintenanceBrewAllFresh).font(.callout).foregroundStyle(Severity.good.color)
                                } else {
                                    Text(L.maintenanceBrewOutdatedCount(outdated.count)).font(.callout)
                                    Text(outdated.prefix(5).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    if model.brewUpgrading {
                                        HStack(spacing: 6) {
                                            ProgressView().controlSize(.small)
                                            Text(model.brewProgress.map(brewProgressText) ?? L.maintenanceBrewUpgrading).font(.caption).foregroundStyle(.secondary)
                                        }
                                    } else {
                                        RainbowCapsuleButton(title: L.maintenanceBrewUpgradeButton) { model.upgradeBrewNow() }
                                    }
                                }
                                if let err = model.brewUpgradeError {
                                    Text(err).font(.caption2).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                Divider()

                maintenanceSection(L.maintenanceUpdatesSection) {
                    if let updates = model.report.updates {
                        if updates.isEmpty {
                            Text(L.maintenanceUpdatesAllUpdated).font(.callout).foregroundStyle(Severity.good.color)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(updates.prefix(5).enumerated()), id: \.offset) { _, u in
                                    Text(u).font(.callout)
                                }
                                if updates.count > 5 {
                                    Text(L.maintenanceAndMore(updates.count - 5)).font(.caption).foregroundStyle(.secondary)
                                }
                                RainbowCapsuleButton(title: L.maintenanceOpenSoftwareUpdate) {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
                                }
                            }
                        }
                    } else {
                        SectionStateView(done: model.report.progress["updates"] ?? false)
                    }
                }

                Divider()

                maintenanceSection(L.maintenanceCrashesSection) {
                    if let crashes = model.report.crashes {
                        if crashes.isEmpty {
                            Text(L.maintenanceCrashesNone).font(.callout).foregroundStyle(Severity.good.color)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(crashes.prefix(5).enumerated()), id: \.offset) { _, c in
                                    Text(c).font(.callout).lineLimit(1).truncationMode(.middle)
                                }
                                if crashes.count > 5 {
                                    Text(L.maintenanceAndMore(crashes.count - 5)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        SectionStateView(done: model.report.progress["crashes"] ?? false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func maintenanceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
