// Views/HistoryHoverLayer.swift
// HISTORY-HOVER-COST: the History chart hover (rule, point, tooltip) as Core Animation layers. Surface and marker are rendered once per appearance/scale by ImageRenderer; the date and value are drawn with Core Text into a CALayer once per sample change; motion is layer animation on the render server (gpu-per-frame).

import SwiftUI
import AppKit
import QuartzCore

/// Overlay-space geometry of the chart, computed once per layout on the SwiftUI side.
struct HistoryHoverFrame: Equatable {
    let plot: CGRect
    /// Absolute overlay-space x / y of every sample (`xs` ascending, same count as the points).
    let xs: [CGFloat]
    let ys: [CGFloat]
}

/// Pure helpers (unit-tested in `HistoryHoverTests`).
enum HistoryHoverMath {
    /// Index of the `xs` entry nearest to `x`; ties go to the lower index. `xs` must be ascending.
    static func nearestIndex(xs: [CGFloat], x: CGFloat) -> Int? {
        guard !xs.isEmpty else { return nil }
        var lo = 0, hi = xs.count      // first index with xs[i] >= x
        while lo < hi {
            let mid = (lo + hi) / 2
            if xs[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return 0 }
        if lo == xs.count { return xs.count - 1 }
        return (x - xs[lo - 1]) <= (xs[lo] - x) ? lo - 1 : lo
    }

    /// Where a box centred at `p` starts a pop-in that scales by `s` about the overlay point `a`: `p + (1 - s)(a - p)`
    /// as an offset from `p` (D7).
    static func popInStart(centre p: CGPoint, anchor a: CGPoint, scale s: CGFloat = 0.9) -> CGPoint {
        CGPoint(x: (1 - s) * (a.x - p.x), y: (1 - s) * (a.y - p.y))
    }
}

struct HistoryHoverLayer: NSViewRepresentable {
    let frame: HistoryHoverFrame?
    let points: [HistoryChartPoint]
    let metric: HistoryMetric
    let reduceMotion: Bool
    let initialHover: Int?

    func makeNSView(context: Context) -> HistoryHoverView {
        let v = HistoryHoverView()
        v.update(frame: frame, points: points, metric: metric, reduceMotion: reduceMotion, initialHover: initialHover)
        return v
    }

    func updateNSView(_ nsView: HistoryHoverView, context: Context) {
        nsView.update(frame: frame, points: points, metric: metric, reduceMotion: reduceMotion, initialHover: initialHover)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HistoryHoverView, context: Context) -> CGSize? {
        func finite(_ v: CGFloat?) -> CGFloat {
            guard let v, v.isFinite else { return 0 }
            return v
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }
}

// MARK: - Art

/// The SwiftUI views rendered to images, with appearance-resolved colours (`ImageRenderer` does not resolve dynamic colours, D5).
@MainActor
enum HistoryHoverArt {
    struct Palette {
        let accent, overlay, ink, muted, rimMid, lineStrong: Color
    }

    static func palette(for appearance: NSAppearance) -> Palette {
        func c(_ t: Color) -> Color { Color(cgColor: ds3Resolve(t, in: appearance)) }
        return Palette(accent: c(DS3.accent), overlay: c(DS3.overlay), ink: c(DS3.ink), muted: c(DS3.muted),
                       rimMid: c(DS3.rimMid), lineStrong: c(DS3.lineStrong))
    }

    /// The box height is fixed; the width is per data set (`HistoryHoverView.boxWidth`), at most `maxBoxWidth`.
    static let boxHeight: CGFloat = 62
    static let maxBoxWidth: CGFloat = 168
    static let gap: CGFloat = 14
    /// The `.pop` shadow (inset 12, offset 18, blur 20) reaches <= 66 pt below the box; 72 keeps the whole blur.
    static let surfacePad: CGFloat = 72
    static let markerSize: CGFloat = 21

    static func surface(p: Palette, appearance: NSAppearance, width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Color.clear
            .frame(width: width, height: boxHeight)
            .background(shape.fill(p.overlay))
            .ds3InsetRims(shape, top: p.rimMid, ring: p.lineStrong)
            .ds3Elevation(.pop, in: shape, resolve: { Color(cgColor: ds3Resolve($0, in: appearance)) })
            .padding(surfacePad)
    }

    /// 9 pt point + 2 pt overlay ring + 6 pt accent .22 halo (History.dc.html:97)
    static func marker(p: Palette) -> some View {
        ZStack {
            Circle().fill(p.accent.opacity(0.22)).frame(width: 21, height: 21)
            Circle().fill(p.overlay).frame(width: 13, height: 13)
            Circle().fill(p.accent).frame(width: 9, height: 9)
        }
        .frame(width: markerSize, height: markerSize)
    }

    static func render<V: View>(_ v: V, scale: CGFloat) -> CGImage? {
        let r = ImageRenderer(content: v)
        r.scale = scale
        r.isOpaque = false
        return r.cgImage
    }
}

// MARK: - Text layer

/// The tooltip's date and value, drawn with Core Text once per sample change (ITERATION 2: the `ImageRenderer` text render
/// was 29 % of main-thread time in the G4 trace). Geometry is today's `tooltip(_:)`: a leading-aligned 2 pt-spaced stack
/// of a 12 pt monospaced-digit regular line and a 17 pt monospaced-digit bold line (kern -0.17), padded 9 / 14, vertically
/// centred in the box (62 pt high, at most 168 pt wide; the width is fitted to the data set).
final class HistoryHoverTextLayer: CALayer {
    static let dateSize: CGFloat = 12
    static let valueSize: CGFloat = 17
    static let valueKern: CGFloat = -0.17
    static let spacing: CGFloat = 2
    static let insetX: CGFloat = 14

    private var date = ""
    private var value = ""
    private var dateColor: CGColor?
    private var valueColor: CGColor?

    override init() { super.init() }

    override init(layer: Any) {
        super.init(layer: layer)
        if let o = layer as? HistoryHoverTextLayer {
            date = o.date
            value = o.value
            dateColor = o.dateColor
            valueColor = o.valueColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the content and marks the layer for one redraw (at the next commit).
    func set(date: String, value: String, dateColor: CGColor, valueColor: CGColor, scale: CGFloat) {
        self.date = date
        self.value = value
        self.dateColor = dateColor
        self.valueColor = valueColor
        contentsScale = scale
        setNeedsDisplay()
    }

    static var dateFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: dateSize, weight: .regular) }
    static var valueFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: valueSize, weight: .bold) }

    /// The one place that builds the attributed strings: drawing and `fittedWidth` both go through it.
    private static func attributed(_ text: String, font: NSFont, color: CGColor, kern: CGFloat) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        if kern != 0 { attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = kern }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func dateString(_ text: String, color: CGColor) -> NSAttributedString {
        attributed(text, font: dateFont, color: color, kern: 0)
    }

    private static func valueString(_ text: String, color: CGColor) -> NSAttributedString {
        attributed(text, font: valueFont, color: color, kern: valueKern)
    }

    /// `lineLimit(1)` truncation: a line wider than `maxWidth` ends in "…".
    private static func line(_ s: NSAttributedString, maxWidth: CGFloat) -> CTLine {
        let ln = CTLineCreateWithAttributedString(s)
        guard CTLineGetTypographicBounds(ln, nil, nil, nil) > Double(maxWidth), s.length > 0 else { return ln }
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: s.attributes(at: 0, effectiveRange: nil)))
        return CTLineCreateTruncatedLine(ln, Double(maxWidth), .end, token) ?? ln
    }

    /// Box width for these lines: inset + the wider line + inset, never above `HistoryHoverArt.maxBoxWidth`.
    @MainActor static func fittedWidth(date: String, value: String) -> CGFloat {
        let clear = CGColor(gray: 0, alpha: 1)
        let d = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(dateString(date, color: clear)), nil, nil, nil)
        let v = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(valueString(value, color: clear)), nil, nil, nil)
        return min(HistoryHoverArt.maxBoxWidth, 2 * insetX + CGFloat(max(d, v)).rounded(.up))
    }

    override func draw(in ctx: CGContext) {
        guard let dateColor, let valueColor else { return }
        let h = bounds.height
        let dateFont = Self.dateFont, valueFont = Self.valueFont
        let textWidth = bounds.width - 2 * Self.insetX
        let dl = Self.line(Self.dateString(date, color: dateColor), maxWidth: textWidth)
        let vl = Self.line(Self.valueString(value, color: valueColor), maxWidth: textWidth)
        // Line boxes as SwiftUI `Text` lays them out: ascent + descent + leading of the line's font.
        let dBox = dateFont.ascender - dateFont.descender + dateFont.leading
        let vBox = valueFont.ascender - valueFont.descender + valueFont.leading
        let top = (h - (dBox + Self.spacing + vBox)) / 2           // y-down distance from the layer's top edge
        // SwiftUI puts every baseline on the device pixel grid; Core Text would otherwise round a fractional one up.
        let px = max(contentsScale, 1)
        let dateBaseline = ((top + dateFont.ascender) * px).rounded() / px
        let valueBaseline = ((top + dBox + Self.spacing + valueFont.ascender) * px).rounded() / px
        ctx.saveGState()
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        // The layer sits under a flipped view, so CA hands over a y-down context (ctm.d < 0) and the glyphs need a
        // flipped text matrix; in a y-up context the baseline is measured from the bottom edge instead.
        let yDown = ctx.ctm.d < 0
        for (ln, baseline) in [(dl, dateBaseline), (vl, valueBaseline)] {
            ctx.textMatrix = yDown ? CGAffineTransform(scaleX: 1, y: -1) : .identity
            ctx.textPosition = CGPoint(x: Self.insetX, y: yDown ? baseline : h - baseline)
            CTLineDraw(ln, ctx)
        }
        ctx.restoreGState()
    }
}

// MARK: - View

final class HistoryHoverView: NSView {
    enum PopAnchor { case overlayFrame, boxCentre }
    /// `.overlayFrame` = SwiftUI's `.scale` transition scales about the centre of the tooltip's layout frame (at most 168x62, at the
    /// overlay's top-left), so near the right edge the box travels sideways as it pops; `.boxCentre` = it grows and shrinks
    /// in place at every edge. User 2026-10-24 A/B: preferred the in-place pop seen near the left edge on main.
    static let popAnchor: PopAnchor = .boxCentre
    /// First check 2 decides: `true` = date and value cross-fade on a sample change; `false` = replaced at once.
    static let textFade = true

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private let rule = CALayer()
    private let marker = CALayer()

    private var frameData: HistoryHoverFrame?
    private var points: [HistoryChartPoint] = []
    private var metric: HistoryMetric = .disk
    private var reduceMotion = false
    private var initialHover: Int?
    private var hovered: Int?

    /// The current session's container, its surface image layer and its current text image layer.
    private var tooltip: CALayer?
    private var surfaceLayer: CALayer?
    private var textLayer: HistoryHoverTextLayer?

    private var palette: HistoryHoverArt.Palette?
    private var surfaceImage: CGImage?
    private var markerImage: CGImage?
    private var renderedName: NSAppearance.Name?
    private var renderedScale: CGFloat?
    private var renderedWidth: CGFloat?
    /// The box width for the current data set (set in `relayout()`); constant during a sweep.
    private var boxWidth: CGFloat = HistoryHoverArt.maxBoxWidth
    private var boxSize: CGSize { CGSize(width: boxWidth, height: HistoryHoverArt.boxHeight) }
    private var textColors: (date: CGColor, value: CGColor)?
    private var trackingArea: NSTrackingArea?

    /// Offscreen snapshots have no window and render at 2x (`SnapshotSupport.swift`).
    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
        rule.allowsEdgeAntialiasing = true
        rule.isHidden = true
        marker.isHidden = true
        marker.contentsGravity = .resize
        Self.silence(rule)
        Self.silence(marker)
        layer?.addSublayer(rule)
        layer?.addSublayer(marker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func silence(_ l: CALayer) {
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "transform", "opacity", "hidden", "contents", "backgroundColor", "sublayers"]
        l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
    }

    // MARK: Updates from SwiftUI

    func update(frame newFrame: HistoryHoverFrame?, points newPoints: [HistoryChartPoint], metric newMetric: HistoryMetric,
                reduceMotion newReduce: Bool, initialHover newInitial: Int?) {
        reduceMotion = newReduce
        let layoutChanged = newFrame != frameData || newPoints != points || newMetric != metric
        let initialChanged = newInitial != initialHover
        frameData = newFrame
        points = newPoints
        metric = newMetric
        initialHover = newInitial
        if layoutChanged {
            relayout()
        } else if initialChanged, hovered == nil || pointerLocation() == nil {
            setHover(validIndex(newInitial), animated: false)
        }
    }

    private func validIndex(_ i: Int?) -> Int? {
        guard let i, let f = frameData, i >= 0, i < f.xs.count, i < points.count else { return nil }
        return i
    }

    /// Data or geometry changed: drop the tooltip session without animation and show the hover for the pointer's x in the
    /// new chart (or `initialHover` when there is no pointer).
    private func relayout() {
        boxWidth = points.isEmpty ? HistoryHoverArt.maxBoxWidth : points.reduce(0) { w, pt in
            max(w, HistoryHoverTextLayer.fittedWidth(date: HistoryPageModel.tooltipDate(pt.date, calendar: .current),
                                                     value: HistoryPageModel.tooltipValue(pt.value, metric: metric)))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rule.bounds = CGRect(x: 0, y: 0, width: 1, height: frameData?.plot.height ?? 0)
        marker.bounds = CGRect(x: 0, y: 0, width: HistoryHoverArt.markerSize, height: HistoryHoverArt.markerSize)
        removeTooltipNow()
        hovered = nil
        rule.isHidden = true
        marker.isHidden = true
        CATransaction.commit()
        if let p = pointerLocation() {
            hover(at: p, animated: false)
        } else {
            setHover(validIndex(initialHover), animated: false)
        }
    }

    // MARK: Images

    private func ensureImages() {
        let name = effectiveAppearance.name
        let s = scale
        guard renderedName != name || renderedScale != s || renderedWidth != boxWidth else { return }
        renderedName = name
        renderedScale = s
        renderedWidth = boxWidth
        let pal = HistoryHoverArt.palette(for: effectiveAppearance)
        palette = pal
        surfaceImage = HistoryHoverArt.render(HistoryHoverArt.surface(p: pal, appearance: effectiveAppearance, width: boxWidth), scale: s)
        markerImage = HistoryHoverArt.render(HistoryHoverArt.marker(p: pal), scale: s)
        textColors = (ds3Resolve(DS3.muted, in: effectiveAppearance), ds3Resolve(DS3.ink, in: effectiveAppearance))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let accent = ds3Resolve(DS3.accent, in: effectiveAppearance)
        rule.backgroundColor = accent.copy(alpha: accent.alpha * 0.45)
        marker.contents = markerImage
        marker.contentsScale = s
        surfaceLayer?.contents = surfaceImage
        surfaceLayer?.contentsScale = s
        if let i = hovered, let t = textLayer { configure(t, index: i) }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if renderedName != nil || hovered != nil { ensureImages() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if renderedName != nil || hovered != nil { ensureImages() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if renderedName != nil || hovered != nil { ensureImages() }
    }

    /// One redraw of `t` for sample `i` (at the next commit).
    private func configure(_ t: HistoryHoverTextLayer, index i: Int) {
        guard let c = textColors, i < points.count else { return }
        t.set(date: HistoryPageModel.tooltipDate(points[i].date, calendar: .current),
              value: HistoryPageModel.tooltipValue(points[i].value, metric: metric),
              dateColor: c.date, valueColor: c.value, scale: scale)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        trackingArea = a
        // D9: AppKit calls this after scrolls and layout changes; keep the rule on the day under a resting pointer.
        if let p = pointerLocation() {
            hover(at: p, animated: false)
        } else if hovered != nil && initialHover == nil {
            setHover(nil, animated: false)
        }
    }

    override func mouseEntered(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil), animated: true) }
    override func mouseMoved(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil), animated: true) }
    override func mouseExited(with event: NSEvent) { setHover(nil, animated: true) }

    /// The pointer in view coordinates when it is over the visible part of this view in the active app.
    private func pointerLocation() -> CGPoint? {
        guard let w = window, NSApp.isActive else { return nil }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        return visibleRect.contains(p) ? p : nil
    }

    private func hover(at p: CGPoint, animated: Bool) {
        guard let f = frameData, !f.xs.isEmpty else { setHover(nil, animated: animated); return }
        let x = min(max(p.x, f.plot.minX), f.plot.maxX)
        let n = HistoryHoverMath.nearestIndex(xs: f.xs, x: x)
        if n != hovered { setHover(n, animated: animated) }
    }

    // MARK: State

    private func setHover(_ requested: Int?, animated: Bool) {
        let n = validIndex(requested)
        let old = hovered
        hovered = n
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rule.isHidden = (n == nil)
        marker.isHidden = (n == nil)
        if let n { ensureImages(); place(n) }
        CATransaction.commit()
        switch (old, n) {
        case (nil, let n?): popIn(index: n, animated: animated)
        case (_?, nil): popOut(animated: animated)
        case (_?, let n?): slide(to: n, animated: animated)
        case (nil, nil): break
        }
    }

    /// Rule and point never animate (R2).
    private func place(_ i: Int) {
        guard let f = frameData else { return }
        rule.position = CGPoint(x: f.xs[i], y: f.plot.midY)
        marker.position = CGPoint(x: f.xs[i], y: f.ys[i])
    }

    private func tooltipCentre(_ i: Int) -> CGPoint {
        guard let f = frameData else { return .zero }
        let o = IPhoneData.tooltipOrigin(point: CGPoint(x: f.xs[i] - f.plot.minX, y: f.ys[i] - f.plot.minY), plot: f.plot.size,
                                         size: boxSize, gap: HistoryHoverArt.gap)
        return CGPoint(x: f.plot.minX + o.x + boxSize.width / 2, y: f.plot.minY + o.y + boxSize.height / 2)
    }

    private func removeTooltipNow() {
        tooltip?.removeFromSuperlayer()
        tooltip = nil
        surfaceLayer = nil
        textLayer = nil
    }

    // MARK: Tooltip layers

    private func makeTextLayer(_ i: Int) -> HistoryHoverTextLayer {
        let l = HistoryHoverTextLayer()
        l.bounds = CGRect(origin: .zero, size: boxSize)
        l.position = CGPoint(x: boxSize.width / 2, y: boxSize.height / 2)
        Self.silence(l)
        configure(l, index: i)
        return l
    }

    private func makeTooltip(index i: Int) -> CALayer {
        ensureImages()
        let box = boxSize
        let half = CGPoint(x: box.width / 2, y: box.height / 2)
        let c = CALayer()
        c.bounds = CGRect(origin: .zero, size: box)
        c.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        Self.silence(c)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        c.position = tooltipCentre(i)
        let side = box.width + 2 * HistoryHoverArt.surfacePad, high = box.height + 2 * HistoryHoverArt.surfacePad
        let s = CALayer()
        s.bounds = CGRect(x: 0, y: 0, width: side, height: high)
        s.position = half
        s.contents = surfaceImage
        s.contentsScale = scale
        s.contentsGravity = .resize
        Self.silence(s)
        c.addSublayer(s)
        let t = makeTextLayer(i)
        c.addSublayer(t)
        layer?.addSublayer(c)
        CATransaction.commit()
        tooltip = c
        surfaceLayer = s
        textLayer = t
        return c
    }

    private func popAnchorPoint(_ c: CALayer) -> CGPoint {
        Self.popAnchor == .overlayFrame
            ? CGPoint(x: boxSize.width / 2, y: boxSize.height / 2)
            : c.position
    }

    private func fade(from: Float, to: Float, duration: CFTimeInterval) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return a
    }

    /// The pop spring on scale, opacity and an additive position: `reversed` runs it 1 -> 0.9 / 1 -> 0 / 0 -> start.
    private func popSpring(_ c: CALayer, reversed: Bool) -> [CABasicAnimation] {
        let s = DS3Motion.popInSpring
        let start = HistoryHoverMath.popInStart(centre: c.position, anchor: popAnchorPoint(c))
        func spring(_ keyPath: String, _ from: Any, _ to: Any) -> CASpringAnimation {
            let a = CASpringAnimation(keyPath: keyPath)
            a.fromValue = reversed ? to : from
            a.toValue = reversed ? from : to
            a.mass = CGFloat(s.mass)
            a.stiffness = CGFloat(s.stiffness)
            a.damping = CGFloat(s.damping)
            a.duration = a.settlingDuration
            return a
        }
        let scaleAnim = spring("transform.scale", 0.9, 1.0)
        let opacityAnim = spring("opacity", 0.0, 1.0)
        let posAnim = spring("position", NSValue(point: start), NSValue(point: .zero))
        posAnim.isAdditive = true
        return [scaleAnim, opacityAnim, posAnim]
    }

    private func popIn(index i: Int, animated: Bool) {
        let c = makeTooltip(index: i)
        guard animated else { return }
        if reduceMotion {
            c.add(fade(from: 0, to: 1, duration: 0.12), forKey: nil)
        } else {
            for a in popSpring(c, reversed: false) { c.add(a, forKey: nil) }
        }
    }

    private func popOut(animated: Bool) {
        guard let c = tooltip else { return }
        tooltip = nil
        surfaceLayer = nil
        textLayer = nil
        guard animated else { c.removeFromSuperlayer(); return }
        // An exit during an in-flight pop-in reverses from where the box is on screen, not from the model's 1/1.
        let shown = c.presentation()
        let fromOpacity = shown?.opacity ?? c.opacity
        let fromScale = (shown?.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        CATransaction.begin()
        CATransaction.setCompletionBlock { c.removeFromSuperlayer() }
        c.opacity = 0
        if !reduceMotion { c.setValue(0.9, forKeyPath: "transform.scale") }
        if reduceMotion {
            c.add(fade(from: fromOpacity, to: 0, duration: 0.12), forKey: nil)
        } else {
            let anims = popSpring(c, reversed: true)
            anims[0].fromValue = fromScale
            anims[1].fromValue = fromOpacity
            for a in anims { c.add(a, forKey: nil) }
        }
        CATransaction.commit()
    }

    private func slide(to i: Int, animated: Bool) {
        guard let c = tooltip else { popIn(index: i, animated: animated); return }
        let from = c.position
        let to = tooltipCentre(i)
        let newText = makeTextLayer(i)
        let old = textLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        c.position = to
        c.addSublayer(newText)
        CATransaction.commit()
        textLayer = newText
        let animate = animated && !reduceMotion
        if animate {
            let a = CABasicAnimation(keyPath: "position")
            a.isAdditive = true
            a.fromValue = NSValue(point: CGPoint(x: from.x - to.x, y: from.y - to.y))
            a.toValue = NSValue(point: .zero)
            a.duration = 0.12
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            c.add(a, forKey: nil)
        }
        if animate && Self.textFade {
            newText.add(fade(from: 0, to: 1, duration: 0.12), forKey: nil)
            CATransaction.begin()
            CATransaction.setCompletionBlock { old?.removeFromSuperlayer() }
            old?.opacity = 0
            old?.add(fade(from: 1, to: 0, duration: 0.12), forKey: nil)
            CATransaction.commit()
        } else {
            old?.removeFromSuperlayer()
        }
    }
}
