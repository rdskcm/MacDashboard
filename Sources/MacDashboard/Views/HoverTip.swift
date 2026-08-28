// Views/HoverTip.swift
// Custom hover tooltip (1s delay; the system `.help()` delay is fixed and too long).
//
// The bubble is rendered as a floating, borderless NSPanel rather than an in-tree
// SwiftUI `.overlay`. zIndex only orders siblings within the same SwiftUI container —
// it does NOT lift a view above unrelated sibling views or the enclosing ScrollView's
// clip region, so an in-tree overlay gets painted over / clipped by neighboring cards.
// A separate floating window has no such sibling and always paints on top.

import SwiftUI
import AppKit

/// Tiny invisible NSView whose only job is to give us a stable AppKit anchor for the
/// hovered SwiftUI content: once it's inserted into the hierarchy (via `.background`)
/// it shares the exact frame of `content`, so we can later ask it for its window and
/// convert its bounds to screen coordinates.
private struct AnchorFinder: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-resolve on every update too: the view can be reparented into a new
        // window (e.g. moved between hierarchies) without makeNSView firing again.
        DispatchQueue.main.async { onResolve(nsView) }
    }
}

// MARK: - Attention-style variant (Block V2-SUMMARY, additive)
//
// `.hoverTip(_:)` / `show(text:anchor:)` / `position(_:near:in:)` above are the
// shared path — its positioning (centred under the anchor, flipping above when
// it would fall off screen) is untouched, but its bubble content now renders
// `AttentionTipBubble` too (V2-UI-POLISH), the same look `.attentionTip(_:)`
// below uses. `.attentionTip(_:)` is a sibling entry point (recommendation-
// capsule explanations) with its own positioning math (left-aligned to the
// anchor, above by default, clamps instead of flipping); it happens to reuse
// `TipPanelController`'s single lazily-created `panel` for lifecycle economy,
// but a given controller instance only ever serves one style (style is a
// `let` on the owning `HoverTipModifier`), so the two paths never collide.

/// Where the bubble appears relative to its anchor. Threaded through
/// `HoverTipModifier` with `.below` as the default so every existing
/// `.hoverTip(_:)` call keeps running the untouched `show()`/`position()` path
/// above verbatim; `.above` is new, consumed only by `.attentionTip(_:)`.
enum TipPlacement { case below, above }

/// `.standard` (default) means centred below the anchor, flips when it would
/// go off screen. `.attention` means left-aligned to the anchor, above by
/// default, clamps instead of flipping. Both now render the same
/// `AttentionTipBubble` look via the shared `showAttention()`/`show()` paths
/// below — different positioning, same fill/border/shadow/corner-radius/padding
/// and fade+rise entrance.
enum TipStyle { case standard, attention }

private let attnTipHorizontalPadding: CGFloat = 11
private let attnTipVerticalPadding: CGFloat = 9
private let attnTipContentMaxWidth: CGFloat = 340
private let attnTipCornerRadius: CGFloat = 9
/// The single bubble margin, sized for this bubble's shadow (radius 12, y 8):
/// `.shadow()` draws outside the view's reported size and doesn't participate
/// in layout, but the panel is sized to `fittingSize` and the compositor
/// hard-clips anything outside the window frame. Without transparent margin
/// around the bubble, the soft shadow would be cut off at the (invisible)
/// panel edge — reintroducing a hard-edge look. This margin gives the shadow
/// room; `position(_:near:in:)` subtracts it back out so the *visible*
/// rounded-rect still sits `gap` points from the anchor.
private let attnTipBubbleMargin: CGFloat = 26
private let attnTipGap: CGFloat = 9
/// Rise distance for the fade+rise entrance (spec: "3 pt rise"). Deliberately
/// its own constant, not `DSMotion.tooltipRiseY` (-7 pt) — that constant is
/// unused elsewhere and tuned for a different, not-yet-built tooltip; reusing
/// it here would silently change this bubble's motion if it's ever wired up
/// for that other purpose later.
private let attnTipRiseY: CGFloat = 3
/// Entrance duration (spec: "0.14 s ease"); Reduce Motion falls back to the
/// shared `DSMotion.reduceMotionFallback` (0.12 s), fade-only (no rise).
private let attnTipEnterDuration: Double = 0.14

/// The recommendation-capsule tooltip bubble: 12 pt text at a ~1.4 line-height
/// (`lineSpacing` approximates CSS `line-height: 1.4` as `fontSize * 0.4` extra
/// leading — SwiftUI has no direct line-height multiplier), `DS.inkSoft`,
/// `DS.ground2` fill, `DS.lineStrong` border, a fade+rise entrance that drops
/// the rise (fade only) under Reduce Motion. Non-interactive.
///
/// `NSHostingView.fittingSize` asks the view for its size at an *unspecified*
/// (ideal) proposed width. A `.frame(maxWidth:)` responds to an unspecified
/// incoming width by reporting `min(child's unconstrained single-line width, maxWidth)`
/// for its own size, but that unconstrained-width query is what it also hands to the
/// child — so the child `Text` never actually re-flows at the max width, and the
/// reported height is always the single-line height, regardless of how many lines
/// the text wraps to once really laid out at that width. That's the sizing bug: the
/// panel (and its rounded-rect background) ends up sized for one line while the text
/// itself wraps to several and spills past the edges.
///
/// The fix: make the bubble's width *fixed*, not a max. A `.frame(width:)` reports
/// (and hands its child) that exact width regardless of the proposal it receives —
/// including the unspecified-width query `fittingSize` uses — so `Text` is forced to
/// really wrap at that width during the very same measurement pass that computes the
/// height. `contentWidth` below is that fixed width, precomputed once per `show()` as
/// `min(natural single-line width, attnTipContentMaxWidth)` so short texts still hug
/// their content instead of always rendering a full max-width bubble.
private struct AttentionTipBubble: View {
    let text: String
    let contentWidth: CGFloat
    let reduceMotion: Bool

    @State private var appeared = false

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(12 * 0.4)
            .foregroundStyle(DS.inkSoft)
            .padding(.horizontal, attnTipHorizontalPadding).padding(.vertical, attnTipVerticalPadding)
            .frame(width: contentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: attnTipCornerRadius).fill(DS.ground2))
            .overlay(RoundedRectangle(cornerRadius: attnTipCornerRadius).strokeBorder(DS.lineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
            .allowsHitTesting(false)
            .padding(attnTipBubbleMargin) // transparent — see comment on attnTipBubbleMargin
            .opacity(appeared ? 1 : 0)
            // Under Reduce Motion the rise is dropped entirely (not just
            // animated faster) — the offset is pinned to 0 regardless of
            // `appeared`, so animating `appeared` only ever moves opacity.
            .offset(y: (appeared || reduceMotion) ? 0 : attnTipRiseY)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? DSMotion.reduceMotionFallback : attnTipEnterDuration)) {
                    appeared = true
                }
            }
    }
}

/// The natural (unwrapped, single-line) width of `text` at the bubble's font/padding,
/// clamped to `attnTipContentMaxWidth`. Feeding this in as `AttentionTipBubble.contentWidth`
/// is what makes short texts hug their content instead of always spanning the full max
/// width — see the doc comment on `AttentionTipBubble` for why a *measured fixed* width
/// is required at all.
private func attnTipContentWidth(for text: String) -> CGFloat {
    let probe = NSHostingView(rootView:
        Text(text)
            .font(.system(size: 12))
            .padding(.horizontal, attnTipHorizontalPadding).padding(.vertical, attnTipVerticalPadding)
            .fixedSize()
    )
    return min(probe.fittingSize.width, attnTipContentMaxWidth)
}

/// Owns the floating NSPanel and its lifecycle. Created once per HoverTipModifier
/// instance via @State, so it survives body re-evaluations; must be explicitly torn
/// down (onDisappear) rather than left to accumulate hidden panels.
private final class TipPanelController: NSObject {
    private var panel: NSPanel?
    private weak var anchorView: NSView?
    private var moveObserver: NSObjectProtocol?
    private var boundsObserver: NSObjectProtocol?

    /// Whether the bubble is currently on screen. Consulted by `.onChange(of: text)`
    /// in HoverTipModifier to decide whether a text change should live-update the
    /// visible bubble (vs. being a no-op while hidden/pending).
    private(set) var isVisible = false

    /// Most recently known text, kept up to date on every `text` change regardless
    /// of visibility. The delayed show-work-item reads this instead of the text it
    /// captured at scheduling time, so it never fires with a stale copy: if `text`
    /// changes while the 1s delay is still pending, the bubble shows the latest
    /// value once it appears rather than whatever was current when hover began.
    var latestText: String = ""

    func show(text: String, anchor: NSView) {
        guard !text.isEmpty, let window = anchor.window else { return }
        anchorView = anchor

        let contentWidth = attnTipContentWidth(for: text)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let hosting = NSHostingView(rootView: AttentionTipBubble(text: text, contentWidth: contentWidth, reduceMotion: reduceMotion))
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fitting)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(contentRect: NSRect(origin: .zero, size: fitting),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false // the bubble draws its own soft shadow via SwiftUI
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            self.panel = panel
            observeGeometryChanges(of: window)
        }

        panel.appearance = anchor.effectiveAppearance
        panel.contentView = hosting
        panel.setContentSize(fitting)
        position(panel, near: anchor, in: window)

        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        isVisible = true
    }

    /// Order the panel out without releasing it, so it can be shown again cheaply
    /// on the next hover cycle (matches "hide immediately on hover exit").
    func hide() {
        isVisible = false
        guard let panel else { return }
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
    }

    /// Full teardown: remove observers, close and release the panel. Called when
    /// the hovered view disappears, so we never leak an NSPanel referencing a
    /// deallocated anchor.
    func teardown() {
        hide()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        moveObserver = nil
        boundsObserver = nil
        panel?.close()
        panel = nil
        anchorView = nil
    }

    private func position(_ panel: NSPanel, near anchor: NSView, in window: NSWindow) {
        let anchorFrameInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorScreenRect = window.convertToScreen(anchorFrameInWindow)
        let bubbleSize = panel.frame.size
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchorScreenRect.midX - bubbleSize.width / 2
        // Clamp the VISIBLE bubble to the screen, not the panel frame: `panel.frame`
        // carries `attnTipBubbleMargin` of transparent shadow room per side, so a bare
        // panel clamp left the bubble visually inset by that margin instead of the 10 pt
        // it used to be (V2-RELEASE re-review [N5]). Same correction the vertical math
        // below and BOTH of `positionAttention`'s clamps apply — its horizontal one only
        // since re-review 2 [M3], which caught it still using the old panel-frame form.
        x = max(visible.minX - attnTipBubbleMargin,
                min(x, visible.maxX + attnTipBubbleMargin - bubbleSize.width))

        // AppKit screen coordinates have a bottom-left origin, so "above the anchor"
        // means a larger Y. Flip below if that would push the bubble off the top edge.
        // `panel.frame` includes `attnTipBubbleMargin` of transparent shadow room on
        // every side (see AttentionTipBubble), so the *visible* rounded-rect sits
        // `attnTipBubbleMargin` inside the panel edge — offset the gap by that margin
        // so the visible bubble, not the invisible panel frame, ends up `gap` points
        // from the anchor.
        let gap: CGFloat = 8
        var y = anchorScreenRect.maxY + gap - attnTipBubbleMargin
        if y + bubbleSize.height > visible.maxY + attnTipBubbleMargin {
            y = anchorScreenRect.minY - gap + attnTipBubbleMargin - bubbleSize.height // flip below
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Attention-style sibling of `show(text:anchor:)` above — same panel
    /// lifecycle (create-once, reposition-and-reshow on every call), different
    /// content view and positioning. Left separate rather than parameterizing
    /// `show()` itself so that method, and every existing `.hoverTip(_:)` call
    /// site it serves, stays byte-identical.
    func showAttention(text: String, anchor: NSView, placement: TipPlacement) {
        guard !text.isEmpty, let window = anchor.window else { return }
        anchorView = anchor

        let contentWidth = attnTipContentWidth(for: text)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let hosting = NSHostingView(rootView: AttentionTipBubble(text: text, contentWidth: contentWidth, reduceMotion: reduceMotion))
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fitting)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(contentRect: NSRect(origin: .zero, size: fitting),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false // the bubble draws its own soft shadow via SwiftUI
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            self.panel = panel
            observeGeometryChanges(of: window)
        }

        panel.appearance = anchor.effectiveAppearance
        panel.contentView = hosting
        panel.setContentSize(fitting)
        positionAttention(panel, near: anchor, in: window, placement: placement)

        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        isVisible = true
    }

    /// Left-aligned to `anchor`'s leading edge, `attnTipGap` above (or below)
    /// it per `placement`. It does not flip, but it does clamp both axes to the
    /// screen's visible frame (V2-POLISH B3) — a tip too tall for the space above
    /// its anchor slides down over the card rather than being clipped by the menu bar.
    private func positionAttention(_ panel: NSPanel, near anchor: NSView, in window: NSWindow, placement: TipPlacement) {
        let anchorFrameInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorScreenRect = window.convertToScreen(anchorFrameInWindow)
        let bubbleSize = panel.frame.size
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Left-aligned: the *visible* bubble's leading edge lines up with the
        // anchor's leading edge (the panel origin sits `attnTipBubbleMargin`
        // further left, inside the transparent shadow margin — same idea as
        // the horizontal centering in `position(_:near:in:)`, just left- not
        // center-aligned).
        var x = anchorScreenRect.minX - attnTipBubbleMargin
        // Clamp the VISIBLE bubble, not the panel frame: `panel.frame` carries
        // `attnTipBubbleMargin` of transparent shadow room per side, so a bare panel
        // clamp left the bubble visually inset by that margin (V2-RELEASE re-review
        // [N5] fixed this in `position(_:near:in:)`; re-review 2 [M3] found this
        // second positioner still had the old form). Same expression as :254-255.
        x = max(visible.minX - attnTipBubbleMargin,
                min(x, visible.maxX + attnTipBubbleMargin - bubbleSize.width))

        var y: CGFloat
        switch placement {
        case .above:
            y = anchorScreenRect.maxY + attnTipGap - attnTipBubbleMargin
        case .below:
            y = anchorScreenRect.minY - attnTipGap + attnTipBubbleMargin - bubbleSize.height
        }
        // Vertical clamp, the counterpart of the horizontal one above (V2-POLISH B3):
        // this positioner never flips, and attention cards sit at the very top of the
        // window, so a long `.above` tip used to run under the menu bar and get its top
        // clipped. `visibleFrame` already excludes the menu bar and the Dock. The
        // ±attnTipBubbleMargin terms are there because `panel.frame` carries that much
        // transparent shadow room on every side, so it is the VISIBLE bubble that ends
        // up inside `visible` — same margin bookkeeping as `position(_:near:in:)`'s flip
        // test. Clamped low-then-high on purpose: for a bubble taller than the visible
        // frame the top, where the text starts, is what must stay on screen.
        y = min(visible.maxY + attnTipBubbleMargin - bubbleSize.height,
                max(visible.minY - attnTipBubbleMargin, y))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func observeGeometryChanges(of window: NSWindow) {
        // The bubble's screen position is computed once, at show time, from the
        // anchor's frame. If the window moves or its content scrolls afterwards,
        // that position goes stale. onHover(false) usually catches pointer-relative
        // movement, but two-finger trackpad scrolling can move the anchor view out
        // from under a perfectly stationary cursor — NSTrackingArea hit-testing is
        // driven by mouse-moved events, not by scrolling, so onHover may not fire at
        // all in that case. Close proactively instead of relying on it:
        //  - NSWindow.didMoveNotification for the window being dragged/moved.
        //  - NSView.boundsDidChangeNotification, which NSScrollView's NSClipView
        //    posts on every live-scroll tick (it enables postsBoundsChangedNotifications
        //    on its content view automatically), for scrolling content underneath.
        let center = NotificationCenter.default
        moveObserver = center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            self?.hide()
        }
        boundsObserver = center.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let changedView = note.object as? NSView, changedView.window === window else { return }
            self.hide()
        }
    }
}

struct HoverTipModifier: ViewModifier {
    let text: String
    /// Both default to the values every existing `.hoverTip(_:)` call site
    /// gets, so those call sites are unaffected by this initializer growing
    /// two new parameters (Block V2-SUMMARY, additive).
    var style: TipStyle = .standard
    var placement: TipPlacement = .below
    @State private var pending: DispatchWorkItem?
    @State private var anchorView: NSView?
    @State private var controller = TipPanelController()

    func body(content: Content) -> some View {
        content
            .background(AnchorFinder { view in
                if anchorView !== view { anchorView = view }
            })
            .onHover { hovering in
                pending?.cancel()
                if hovering && !text.isEmpty {
                    controller.latestText = text
                    let item = DispatchWorkItem {
                        // Read `controller.latestText` rather than the `text` this
                        // closure captured at scheduling time: if `text` changes
                        // during the 1s delay, `.onChange` below keeps latestText
                        // current, so the bubble appears with the current value
                        // instead of whatever was hovered a second ago.
                        if let anchorView { show(text: controller.latestText, anchor: anchorView) }
                    }
                    pending = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
                } else {
                    controller.hide()
                }
            }
            .onChange(of: text) { _, newValue in
                // Keep the controller's notion of "current text" fresh regardless of
                // visibility (consumed by the pending work item above). If the tip
                // is already showing, update it live; if it isn't, do nothing else —
                // don't show it early and don't touch the pending delay.
                controller.latestText = newValue
                guard controller.isVisible else { return }
                if newValue.isEmpty {
                    controller.hide()
                } else if let anchorView {
                    show(text: newValue, anchor: anchorView)
                }
            }
            .onDisappear {
                pending?.cancel()
                controller.teardown()
            }
    }

    /// The only place `style` is consulted: dispatches to the standard
    /// (centred below, flips near a screen edge) path or the attention
    /// (left-aligned above, clamps) path — both render `AttentionTipBubble`.
    private func show(text: String, anchor: NSView) {
        switch style {
        case .standard: controller.show(text: text, anchor: anchor)
        case .attention: controller.showAttention(text: text, anchor: anchor, placement: placement)
        }
    }
}
extension View {
    func hoverTip(_ text: String) -> some View { modifier(HoverTipModifier(text: text)) }

    /// Above-anchor, left-aligned attention-style tooltip (Block V2-SUMMARY) —
    /// recommendation-capsule explanations, see `AttentionTipBubble`.
    func attentionTip(_ text: String) -> some View {
        modifier(HoverTipModifier(text: text, style: .attention, placement: .above))
    }
}
