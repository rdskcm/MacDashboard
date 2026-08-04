// Views/MaintenanceCard.swift
// Homebrew card (Обслуживание системы) — v2 restyle, Block V2-CARD-SYS.
//
// Per Spec §5.8 this card now covers ONLY the Homebrew section: brew version,
// outdated packages list, and the upgrade button with live `BrewProgress`
// state. The macOS-updates and crashes sections previously merged into this
// same card (see the old block comment this replaces) move out to a future
// "quiet strip" block (§5.2, V2-QUIET) that doesn't exist yet — kept rendered
// exactly as before under the `v2-quiet-pending` marker below so nothing
// disappears from the UI before that block lands. Their logic/state is
// untouched; only the Homebrew section above the marker got the v2 restyle.

import AppKit
import SwiftUI

struct MaintenanceCard: View {
    let model: DashboardModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var brewButtonHovering = false

    var body: some View {
        CardChrome(title: L.maintenanceTitle) {
            VStack(alignment: .leading, spacing: 14) {
                homebrewSection

                // v2-quiet-pending — moves to V2-QUIET (Spec §5.2); rendering
                // and logic below are exactly as before the v2 restyle.
                Divider()

                maintenanceSection(L.maintenanceUpdatesSection) {
                    if let updates = model.report.updates {
                        if updates.isEmpty {
                            Text(L.maintenanceUpdatesAllUpdated).font(.callout).foregroundStyle(DS.greenInk)
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
                            Text(L.maintenanceCrashesNone).font(.callout).foregroundStyle(DS.greenInk)
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

    // MARK: - Homebrew (Spec §5.8)

    @ViewBuilder
    private var homebrewSection: some View {
        switch model.report.brewVersion {
        case .none:
            SectionStateView(done: model.report.progress["brew"] ?? false)
        case .some(.none):
            Text(L.maintenanceBrewNotInstalled)
                .font(.system(size: 13))
                .foregroundStyle(DS.muted)
        case .some(.some(let version)):
            VStack(alignment: .leading, spacing: 6) {
                Text(version)
                    .font(.system(size: 13.5))
                    .foregroundStyle(DS.inkSoft)
                if let outdated = model.report.brewOutdated {
                    if outdated.isEmpty {
                        Text(L.maintenanceBrewAllFresh)
                            .font(.system(size: 13.5))
                            .foregroundStyle(DS.greenInk)
                    } else {
                        Text(L.maintenanceBrewOutdatedCount(outdated.count))
                            .font(.system(size: 13.5))
                            .foregroundStyle(DS.inkSoft)
                        Text(outdated.prefix(5).joined(separator: ", "))
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.muted)
                            .lineLimit(2)
                        if model.brewUpgrading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(model.brewProgress.map(brewProgressText) ?? L.maintenanceBrewUpgrading)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(DS.muted)
                            }
                        } else {
                            brewUpgradeButton
                        }
                    }
                    if let err = model.brewUpgradeError {
                        Text(err).font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    /// «Обновить пакеты» (Spec §5.8/§2.4 small capsule button, no rainbow ring —
    /// only SMART/Energy-reset/etc. capsules get the ring per §2.5's site list).
    /// Carries the `asBreathe` 5-rep breathing animation on appear (OS:559).
    private var brewUpgradeButton: some View {
        Button {
            model.upgradeBrewNow()
        } label: {
            Text(L.maintenanceBrewUpgradeButton)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(brewButtonHovering ? DS.ink : DS.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(DS.glass3))
                .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { brewButtonHovering = $0 }
        .animation(
            reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
            value: brewButtonHovering
        )
        .asBreathe()
        .accessibilityLabel(L.maintenanceBrewUpgradeButton)
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

// MARK: - `asBreathe` (Spec §5.8, OS:559)

/// Amber border/glow breathing animation, played once on appear — Spec §5.8's
/// prototype `asBreathe` keyframe (`animation: asBreathe 2s ease-in-out 5
/// alternate forwards`, unconditional, not gated on any state). `DSMotion
/// .breathing` (DesignSystem.swift) is the exact same easeInOut/2s/5-rep/
/// autoreverses curve already used for this identical keyframe on
/// `AutostartCard`'s "check for outdated" capsule — that button's own
/// `BreathingWarnBackground` modifier additionally gates on
/// `DashboardModel.isPaused` (re-breathing on window return) and is `private`
/// to its file, so it can't be imported here; this is the same technique
/// (amber strokeBorder + amber glow shadow, Reduce-Motion-safe) minus that
/// pause-gating, since the Homebrew button has no equivalent concept and the
/// spec only calls for "on appear".
private struct AsBreatheBorder: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content.background(
                Capsule()
                    .strokeBorder(DS.amber, lineWidth: 1)
                    .shadow(color: DS.amber.opacity(0.6), radius: 6)
            )
        } else {
            content
                .background(
                    Capsule()
                        .strokeBorder(DS.amber.opacity(isAnimating ? 1.0 : 0.5), lineWidth: 1)
                        .shadow(color: DS.amber.opacity(isAnimating ? 0.6 : 0.25), radius: 6)
                )
                .onAppear {
                    withAnimation(DSMotion.breathing) { isAnimating = true }
                }
        }
    }
}

private extension View {
    func asBreathe() -> some View { modifier(AsBreatheBorder()) }
}
