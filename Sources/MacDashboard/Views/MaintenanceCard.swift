// Views/MaintenanceCard.swift
// Homebrew card (Обслуживание системы) — v2 restyle, Block V2-CARD-SYS.
//
// Per Spec §5.8 this card covers ONLY the Homebrew section: brew version,
// outdated packages list, and the upgrade button with live `BrewProgress`
// state. Updates and crashes sections have moved to `UpdatesCrashesCard`
// in QuietStrip.swift (block V2-QUIET, Spec §5.2).

import AppKit
import SwiftUI

struct MaintenanceCard: View {
    let model: DashboardModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var brewButtonHovering = false
    @State private var showBrewConfirm = false

    var body: some View {
        CardChrome(title: L.maintenanceTitle) {
            homebrewSection
        }
        .brewUpgradeConfirm(isPresented: $showBrewConfirm, model: model)
    }

    // MARK: - Homebrew (Spec §5.8)

    @ViewBuilder
    private var homebrewSection: some View {
        switch model.report.brewStatus {
        case .none:
            SectionStateView(done: model.report.progress["brew"] ?? false)
        case .some(.notInstalled):
            Text(L.maintenanceBrewNotInstalled)
                .font(.system(size: 13))
                .foregroundStyle(DS.muted)
        case .some(.installed(let version)):
            VStack(alignment: .leading, spacing: 6) {
                if let version {
                    Text(version)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS.inkSoft)
                } else {
                    // BREW-VERSION-FAIL: brew is present, `--version` failed — never "not installed".
                    Text(L.maintenanceBrewVersionUnknown)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS.amberInk)
                }
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
                                Text(brewStatusLine)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(DS.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                BrewStopButton(enabled: model.brewUpgradeStoppable && !model.brewStopRequested) {
                                    model.stopBrewUpgrade()
                                }
                                .fixedSize()
                            }
                        } else {
                            brewUpgradeButton
                        }
                    }
                } else {
                    // BREW-OUTDATED-FAIL: `brew outdated` failed — never claim "all fresh".
                    Text(L.maintenanceBrewOutdatedCheckFailed)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS.amberInk)
                }
                if let err = model.brewUpgradeError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
                if let notice = model.brewUpgradeNotice {
                    Text(notice).font(.system(size: 11.5)).foregroundStyle(DS.inkSoft)
                }
            }
        }
    }

    /// Progress line, or the stop phases (BREW-CANCEL) once Stop was pressed.
    private var brewStatusLine: String {
        if model.brewStopRequested {
            return model.brewUpgradeStoppable ? L.maintenanceBrewStopping : L.maintenanceBrewRechecking
        }
        return model.brewProgress.map(brewProgressText) ?? L.maintenanceBrewUpgrading
    }

    /// «Обновить пакеты» (Spec §5.8/§2.4 small capsule button, no rainbow ring —
    /// only SMART/Energy-reset/etc. capsules get the ring per §2.5's site list).
    /// Carries the `asBreathe` 5-rep breathing animation on appear (OS:559).
    private var brewUpgradeButton: some View {
        Button {
            guard model.report.brewOutdated?.isEmpty == false else { return }
            showBrewConfirm = true
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
}

/// «Остановить» (BREW-CANCEL): C3 small outline capsule (11/600, h11 v5, `line-strong` 1), the
/// neutral inline-cancel shape of AutostartCard's `OrphanCancelButton`. Always mounted while the
/// upgrade flow runs; disabled outside the brew step and after the first press.
private struct BrewStopButton: View {
    let enabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(L.maintenanceBrewStopButton)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering && enabled ? DS.ink : DS.inkSoft)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(hovering && enabled ? DS.row : Color.clear))
                .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(
            reduceMotion ? .easeOut(duration: DSMotion.reduceMotionFallback) : DSMotion.cardHover,
            value: hovering
        )
        .accessibilityLabel(L.maintenanceBrewStopA11y)
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
