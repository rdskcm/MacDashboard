// Views/LegacyNoticeOverlay.swift
// MOONPORT-RENAME D7, amendment 3 (design §1, §2, §5): the Moonport Welcome panel as a centred in-window modal.
// Mounted by `MainDashboardView` only while a notice exists, and unmounted once the exit animation ends
// (`no-unseen-work`). It owns the veil over the whole window (the app header included), the placement, the motion and
// the focus; the panel draws its own surface (`LegacyNoticeSheet`). Only opacity, scale and offset animate: the material is
// static and its container fades (`gpu-per-frame`, `effects-near-zero-cost`). Reduce Motion: 0.12 s opacity fades only.
import SwiftUI

@MainActor struct LegacyNoticeOverlay: View {
    let notice: LegacyNotice
    let settings: AppSettings
    let actions: WelcomeActions
    /// Called after the exit animation: the owner sets its notice to nil, which unmounts this view.
    let onFinished: () -> Void

    private enum Phase { case hidden, shown, leaving }
    @State private var phase = Phase.hidden
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(GlassSettings.self) private var glass: GlassSettings?

    private static let exitDuration = 0.25
    private static let reducedDuration = 0.12

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backdrop
                panel(windowHeight: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("legacy-notice-overlay")
        .onAppear {
            phase = .shown
            focused = true
        }
    }

    // MARK: Layers

    /// Design §2: `veil` tint over a thin material (static, only the container's opacity changes). Reduce Transparency:
    /// `ground` at 72 % with no material (D-W15). It takes every click (no dismiss on click) and ignores the safe area,
    /// so it also covers the title-bar strip and the header pills.
    private var backdrop: some View {
        ZStack {
            if (glass?.fill ?? .standard).usesMaterial {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(DS3.veil)
            } else {
                Rectangle().fill(DS3.ground.opacity(0.72))
            }
        }
        .ignoresSafeArea()
        .opacity(phase == .shown ? 1 : 0)
        .animation(backdropAnimation, value: phase)
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
    }

    private func panel(windowHeight: CGFloat) -> some View {
        LegacyNoticeSheet(notice: notice, settings: settings, onDone: dismiss, actions: actions,
                          maxPanelHeight: max(200, windowHeight - 48))
            .environment(\.noticeEntered, phase != .hidden)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L.legacyNoticeTitle)
            .accessibilityAddTraits(.isModal)
            .opacity(phase == .shown ? 1 : 0)
            .scaleEffect(phaseScale)
            .offset(y: phase == .hidden && !reduceMotion ? 10 : 0)
            .animation(panelAnimation, value: phase)
            .allowsHitTesting(phase == .shown)
    }

    private var phaseScale: CGFloat {
        if reduceMotion { return 1 }
        switch phase {
        case .hidden: return 0.975
        case .shown: return 1
        case .leaving: return 0.97
        }
    }

    // MARK: Motion (design §5)

    private var backdropAnimation: Animation {
        if reduceMotion { return .easeOut(duration: Self.reducedDuration) }
        return phase == .leaving ? .easeIn(duration: Self.exitDuration) : .timingCurve(0.4, 0, 0.2, 1, duration: 0.9)
    }

    private var panelAnimation: Animation {
        if reduceMotion { return .easeOut(duration: Self.reducedDuration) }
        return phase == .leaving ? .timingCurve(0.4, 0, 1, 1, duration: Self.exitDuration)
                                 : .timingCurve(0.16, 1, 0.3, 1, duration: 1.2).delay(0.1)
    }

    private func dismiss() {
        guard phase != .leaving else { return }
        phase = .leaving
        let seconds = reduceMotion ? Self.reducedDuration : Self.exitDuration
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            onFinished()
        }
    }
}
