// Views/DS3EntranceHost.swift
// APPEAR-CA-ENTRANCE: a card (or page bar) in its own hosting view whose entrance is a Core Animation spring on the
// host's layer. The card's SwiftUI tree is not evaluated while it moves (gpu-per-frame). Replaces `.ds3Appear` at
// page/card level; `DS3Appear` stays for inner entrances.
// Amendment 2: the hosted root carries no width; sizeThatFits measures, never reassigns (no per-pass rebuild).

import SwiftUI
import AppKit
import QuartzCore

extension View {
    /// Hosted entrance (APPEAR-CA-ENTRANCE). `slideX` is the page slide every page-level element shares (bar and cards);
    /// `delay`, `offsetY`, `scale` are the card's own staggered entrance (0 / 0 / 1 for the bar).
    func ds3HostedEntrance(delay: Double = 0, offsetY: CGFloat = DS3Motion.appearOffsetY, scale: CGFloat = DS3Motion.appearScale,
                           slideX: CGFloat = DS3Motion.pageOffsetX) -> some View {
        DS3EntranceHost(delay: delay, offsetY: offsetY, scale: scale, slideX: slideX) { self }
    }
}

/// The entrance parameters, in points; `slideX` is the page slide (no delay, `DS3Motion.page` spring), the rest the
/// card's own staggered entrance (`DS3Motion.appear` spring).
struct DS3EntranceSpec: Equatable {
    var delay: Double
    var offsetY: CGFloat
    var scale: CGFloat
    var slideX: CGFloat
}

/// Amendment 2: an `NSHostingController` per card. The hosted root carries no width — the hosting view lays the card
/// out at its own bounds — and `sizeThatFits` answers each proposal by measuring the card at that width. The window
/// probes its min size at the 900-pt minimum width on every layout pass (827-pt cards beside the real 927); a
/// measurement answers that probe without touching the hosted graph, where re-pinning the width rebuilt the card twice
/// per pass (HUNT-TABLE-2026-10-30: scroll ×1.23 with the rebuild, ×0.99 without).
struct DS3EntranceHost<Content: View>: NSViewControllerRepresentable {
    let delay: Double
    let offsetY: CGFloat
    let scale: CGFloat
    let slideX: CGFloat
    @ViewBuilder let content: () -> Content

    /// Called at mount and on an outer update only (R14); never from `sizeThatFits`.
    private func root(_ context: Context) -> AnyView {
        DS3EntranceHostTestHooks.rootAssignments += 1
        return AnyView(
            content()
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.self, context.environment)
        )
    }

    func makeNSViewController(context: Context) -> DS3EntranceHostController {
        let c = DS3EntranceHostController(rootView: root(context))
        c.sizingOptions = [.intrinsicContentSize]
        c.view.identifier = DS3EntranceHostTestHooks.viewID
        DS3Appear.entranceStarts += 1
        if !(context.environment.accessibilityReduceMotion || DS3Motion.isFrozen) {
            c.pending = DS3EntranceSpec(delay: delay, offsetY: offsetY, scale: scale, slideX: slideX)
        }
        return c
    }

    func updateNSViewController(_ c: DS3EntranceHostController, context: Context) {
        c.rootView = root(context)
    }

    /// A measurement, never a write: the card's size at the proposed width. Nil / infinite width (the window's ideal
    /// and max probes) → the width the host is placed at; before the first placement → SwiftUI's default (ideal size).
    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController c: DS3EntranceHostController, context: Context) -> CGSize? {
        let width: CGFloat
        if let w = proposal.width, w.isFinite {
            width = max(w, 0)
        } else if c.view.bounds.width > 0 {
            width = c.view.bounds.width
        } else {
            return nil
        }
        return c.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    static func dismantleNSViewController(_ c: DS3EntranceHostController, coordinator: Coordinator) {
        c.pending = nil
        c.view.layer?.removeAllAnimations()
        c.rootView = AnyView(EmptyView())
    }
}

/// The hosting controller whose view's layer carries the entrance. `pending` is consumed on the first `viewDidLayout()`
/// with non-empty bounds (the centred scale needs the size: AppKit backing layers keep `anchorPoint` at (0,0)).
final class DS3EntranceHostController: NSHostingController<AnyView> {
    var pending: DS3EntranceSpec?

    override func viewDidLayout() {
        super.viewDidLayout()
        let b = view.bounds
        guard let spec = pending, b.width > 0, b.height > 0, let layer = view.layer else { return }
        pending = nil
        DS3EntranceAnimation.add(to: layer, size: b.size, spec: spec)
    }
}

/// Test hooks (DS3EntranceHostTests, APPEAR-CA-ENTRANCE Amendment 2). `rootAssignments`: hosted roots built,
/// process-wide (mount 1, outer update 1, layout pass / size probe 0). `viewID`: the hosted view's identifier.
enum DS3EntranceHostTestHooks {
    @MainActor static var rootAssignments = 0
    @MainActor static let viewID = NSUserInterfaceItemIdentifier("ds3.entranceHost")
}

/// The entrance as render-server animations. Model values are at the final state; each animation runs from the
/// start value with `fillMode = .backwards`, so the layer holds the start value during `delay` and is at the final
/// state when the animation is removed. Spring form = SwiftUI's `.spring(response:dampingFraction:)` with mass 1:
/// stiffness = (2π/response)², damping = 4π·dampingFraction/response.
enum DS3EntranceAnimation {
    static func spring(_ keyPath: String, from: Any, to: Any, response: Double, dampingFraction: Double,
                       delay: Double, additive: Bool) -> CASpringAnimation {
        let a = CASpringAnimation(keyPath: keyPath)
        a.mass = 1
        a.stiffness = pow(2 * .pi / response, 2)
        a.damping = 4 * .pi * dampingFraction / response
        a.initialVelocity = 0
        a.fromValue = from
        a.toValue = to
        a.isAdditive = additive
        a.duration = a.settlingDuration
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .backwards
        a.isRemovedOnCompletion = true
        return a
    }

    // Literal pairs mirroring `DS3Motion.appear` = .spring(response: 0.6, dampingFraction: 0.7) and
    // `DS3Motion.page` = .spring(response: 0.5, dampingFraction: 0.75): `Animation` is opaque, so they cannot be read.

    /// Centred scale + rise as one non-additive `transform` animation; the page slide as an additive
    /// `transform.translation.x` on top of it (CA applies additive animations after the non-additive value).
    static func add(to layer: CALayer, size: CGSize, spec: DS3EntranceSpec) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        if spec.slideX != 0 {
            layer.add(spring("transform.translation.x", from: spec.slideX, to: 0, response: 0.5, dampingFraction: 0.75,
                             delay: 0, additive: true), forKey: "ds3.slideX")
        }
        layer.add(spring("opacity", from: Float(0), to: Float(1), response: 0.6, dampingFraction: 0.7,
                         delay: spec.delay, additive: false), forKey: "ds3.opacity")
        if spec.scale != 1 || spec.offsetY != 0 {
            var t = CATransform3DMakeTranslation(size.width / 2, size.height / 2 + spec.offsetY, 0)
            t = CATransform3DScale(t, spec.scale, spec.scale, 1)
            t = CATransform3DTranslate(t, -size.width / 2, -size.height / 2, 0)
            layer.add(spring("transform", from: NSValue(caTransform3D: t), to: NSValue(caTransform3D: CATransform3DIdentity),
                             response: 0.6, dampingFraction: 0.7, delay: spec.delay, additive: false), forKey: "ds3.enter")
        }
        CATransaction.commit()
    }
}
