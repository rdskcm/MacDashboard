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

/// `.shadow()` draws outside the view's reported size and doesn't participate in
/// layout, but the panel is sized to `fittingSize` and the compositor hard-clips
/// anything outside the window frame. Without transparent margin around the bubble,
/// the soft shadow would be cut off at the (invisible) panel edge — reintroducing a
/// hard-edge look. This margin gives the shadow room; `position(_:near:in:)` below
/// subtracts it back out so the *visible* rounded-rect still sits `gap` points from
/// the anchor.
private let tipBubbleMargin: CGFloat = 10

/// Maximum width of the bubble's *content* (the padded text box, before the
/// transparent shadow margin), matching the previous `.frame(maxWidth: 280)`.
private let tipContentMaxWidth: CGFloat = 320

private let tipHorizontalPadding: CGFloat = 8
private let tipVerticalPadding: CGFloat = 7

/// `NSHostingView.fittingSize` asks the view for its size at an *unspecified*
/// (ideal) proposed width. A `.frame(maxWidth:)` responds to an unspecified
/// incoming width by reporting `min(child's unconstrained single-line width, maxWidth)`
/// for its own size, but that unconstrained-width query is what it also hands to the
/// child — so the child `Text` never actually re-flows at 280pt, and the reported
/// height is always the single-line height, regardless of how many lines the text
/// wraps to once really laid out in a 280pt-wide window. That's the sizing bug: the
/// panel (and its rounded-rect background) ends up sized for one line while the text
/// itself wraps to several and spills past the edges.
///
/// The fix: make the bubble's width *fixed*, not a max. A `.frame(width:)` reports
/// (and hands its child) that exact width regardless of the proposal it receives —
/// including the unspecified-width query `fittingSize` uses — so `Text` is forced to
/// really wrap at that width during the very same measurement pass that computes the
/// height. `contentWidth` below is that fixed width, precomputed once per `show()` as
/// `min(natural single-line width, tipContentMaxWidth)` so short texts still hug their
/// content instead of always rendering a full 280pt-wide bubble.
private struct TipBubble: View {
    let text: String
    let contentWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, tipHorizontalPadding).padding(.vertical, tipVerticalPadding)
            .frame(width: contentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(light: Color(hex: 0xECECEC), dark: Color(hex: 0x2D2D2D))))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            .allowsHitTesting(false)
            .padding(tipBubbleMargin) // transparent — see comment on tipBubbleMargin
    }
}

/// The natural (unwrapped, single-line) width of `text` at the bubble's font/padding,
/// clamped to `tipContentMaxWidth`. Feeding this in as `TipBubble.contentWidth` is what
/// makes short texts hug their content instead of always spanning the full max width —
/// see the comment on `TipBubble` for why a *measured fixed* width is required at all.
private func tipContentWidth(for text: String) -> CGFloat {
    let probe = NSHostingView(rootView:
        Text(text)
            .font(.caption)
            .padding(.horizontal, tipHorizontalPadding).padding(.vertical, tipVerticalPadding)
            .fixedSize()
    )
    return min(probe.fittingSize.width, tipContentMaxWidth)
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

        let contentWidth = tipContentWidth(for: text)
        let hosting = NSHostingView(rootView: TipBubble(text: text, contentWidth: contentWidth))
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
        x = max(visible.minX, min(x, visible.maxX - bubbleSize.width))

        // AppKit screen coordinates have a bottom-left origin, so "above the anchor"
        // means a larger Y. Flip below if that would push the bubble off the top edge.
        // `panel.frame` includes `tipBubbleMargin` of transparent shadow room on every
        // side (see TipBubble), so the *visible* rounded-rect sits `tipBubbleMargin`
        // inside the panel edge — offset the gap by that margin so the visible bubble,
        // not the invisible panel frame, ends up `gap` points from the anchor.
        let gap: CGFloat = 8
        var y = anchorScreenRect.maxY + gap - tipBubbleMargin
        if y + bubbleSize.height > visible.maxY + tipBubbleMargin {
            y = anchorScreenRect.minY - gap + tipBubbleMargin - bubbleSize.height // flip below
        }
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
                        if let anchorView { controller.show(text: controller.latestText, anchor: anchorView) }
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
                    controller.show(text: newValue, anchor: anchorView)
                }
            }
            .onDisappear {
                pending?.cancel()
                controller.teardown()
            }
    }
}
extension View {
    func hoverTip(_ text: String) -> some View { modifier(HoverTipModifier(text: text)) }
}
