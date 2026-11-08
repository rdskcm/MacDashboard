// Views/SocChartHoverLayer.swift
// SOC-DETAILS Stage 3 (D9, design 7.6 / 7.9): the SoC chart hover (one rule, one marker per series, a three-line tooltip)
// as Core Animation layers over the Swift Charts image, so a pointer move never touches the chart (gpu-per-frame).
// Surface and markers are rendered once per appearance/scale by ImageRenderer; the text is drawn with Core Text once per
// sample change. Positions are instant; appear and leave are opacity only, 0.12 s (Reduce Motion plays the same fade).
// A separate file from HistoryHoverView on purpose (D24): two markers, three lines, an 80 pt box and a placement by the
// topmost marker. The pure snap (`HistoryHoverMath.nearestIndex`) and `HistoryHoverArt.render` are shared.

import SwiftUI
import AppKit
import QuartzCore

/// Overlay-space geometry of the chart, computed once per layout on the SwiftUI side (same shape as `HistoryHoverFrame`).
struct SocChartHoverFrame: Equatable {
    let plot: CGRect
    /// Absolute overlay-space x of every sample, ascending, one per `SocChartSample`.
    let xs: [CGFloat]
    /// Absolute overlay-space y of the CPU / GPU marker of every sample, nil where that series has no value.
    let cpuYs: [CGFloat?]
    let gpuYs: [CGFloat?]
}

/// Pure placement of the tooltip (unit-tested in `SocChartHoverTests`). All values are in overlay coordinates, y down.
enum SocChartHoverPlacement {
    static let boxSize = CGSize(width: 168, height: 80)
    static let gap: CGFloat = 14
    static let flipShare: CGFloat = 0.38

    /// Top-left of the tooltip box: centred on the rule at `x`, clamped to the plot horizontally; `gap` above the
    /// topmost marker, flipped `gap` below it when that marker is in the top `flipShare` of the plot (design 7.6).
    /// Without a marker the tooltip sits at the middle of the plot.
    static func tooltipOrigin(x: CGFloat, markerYs: [CGFloat], plot: CGRect, boxSize: CGSize = SocChartHoverPlacement.boxSize,
                              gap: CGFloat = SocChartHoverPlacement.gap,
                              flipShare: CGFloat = SocChartHoverPlacement.flipShare) -> CGPoint {
        let top = markerYs.min() ?? plot.midY
        let left = min(max(plot.minX, x - boxSize.width / 2), max(plot.minX, plot.maxX - boxSize.width))
        let below = plot.height > 0 && (top - plot.minY) < plot.height * flipShare
        return CGPoint(x: left, y: below ? top + gap : top - gap - boxSize.height)
    }
}

struct SocChartHoverLayer: NSViewRepresentable {
    let frame: SocChartHoverFrame?
    let samples: [SocChartSample]
    let reduceMotion: Bool
    let initialHover: Int?

    func makeNSView(context: Context) -> SocChartHoverView {
        let v = SocChartHoverView()
        v.update(frame: frame, samples: samples, reduceMotion: reduceMotion, initialHover: initialHover)
        return v
    }

    func updateNSView(_ nsView: SocChartHoverView, context: Context) {
        nsView.update(frame: frame, samples: samples, reduceMotion: reduceMotion, initialHover: initialHover)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SocChartHoverView, context: Context) -> CGSize? {
        func finite(_ v: CGFloat?) -> CGFloat {
            guard let v, v.isFinite else { return 0 }
            return v
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }
}

// MARK: - Art

/// The tooltip surface and the markers rendered to images, with appearance-resolved colours (`ImageRenderer` does not
/// resolve dynamic colours).
@MainActor
enum SocChartHoverArt {
    static let markerSize: CGFloat = 21

    /// Box 168 × 80, radius 16, `overlay` fill (no blur), rims and the pop shadow of the History tooltip; padded by the
    /// shadow's reach (`HistoryHoverArt.surfacePad`).
    static func surface(p: HistoryHoverArt.Palette, appearance: NSAppearance, width: CGFloat = SocChartHoverPlacement.boxSize.width) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let box = CGSize(width: width, height: SocChartHoverPlacement.boxSize.height)
        return Color.clear
            .frame(width: box.width, height: box.height)
            .background(shape.fill(p.overlay))
            .ds3InsetRims(shape, top: p.rimMid, ring: p.lineStrong)
            .ds3Elevation(.pop, in: shape, resolve: { Color(cgColor: ds3Resolve($0, in: appearance)) })
            .padding(HistoryHoverArt.surfacePad)
    }

    /// Smallest gap between a row's label and its value.
    nonisolated static let minLabelValueGap: CGFloat = 8

    /// Box width: 168 unless the widest row (side padding, swatch, label, 8 pt gap, value) needs more; whole points.
    nonisolated static func boxWidth(labelWidths: [CGFloat], valueWidths: [CGFloat], base: CGFloat = SocChartHoverPlacement.boxSize.width) -> CGFloat {
        let rows = zip(labelWidths, valueWidths).map { $0 + $1 }.max() ?? 0
        let need = 2 * SocChartHoverTextLayer.insetX + SocChartHoverTextLayer.swatch + SocChartHoverTextLayer.swatchGap
            + minLabelValueGap + rows
        return max(base, need.rounded(.up))
    }

    /// 9 pt dot + 2 pt overlay ring + 6 pt 22 % halo in the series colour (mockup SoC.dc.html, chart marks).
    static func marker(color: Color, overlay: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.22)).frame(width: 21, height: 21)
            Circle().fill(overlay).frame(width: 13, height: 13)
            Circle().fill(color).frame(width: 9, height: 9)
        }
        .frame(width: markerSize, height: markerSize)
    }
}

// MARK: - Text layer

/// The tooltip's three lines, drawn with Core Text once per sample change: time 12 muted, then two rows
/// "swatch, name, value" 14 with the value right-aligned. Geometry follows the mockup: box 168 × 80, padding 14, rows
/// 1.35 line height, gap 2, the stack centred vertically.
final class SocChartHoverTextLayer: CALayer {
    struct Colors {
        let muted, inkSoft, ink, cpu, gpu: CGColor
    }

    static let insetX: CGFloat = 14
    static let spacing: CGFloat = 2
    static let swatch: CGFloat = 8
    static let swatchGap: CGFloat = 7
    static let rowHeight: CGFloat = 14 * 1.35

    private var text: SocChartTooltipText?
    private var names: (cpu: String, gpu: String) = ("", "")
    private var colors: Colors?

    override init() { super.init() }

    override init(layer: Any) {
        super.init(layer: layer)
        if let o = layer as? SocChartHoverTextLayer {
            text = o.text
            names = o.names
            colors = o.colors
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the content and marks the layer for one redraw (at the next commit).
    func set(text: SocChartTooltipText, cpuName: String, gpuName: String, colors: Colors, scale: CGFloat) {
        self.text = text
        self.names = (cpuName, gpuName)
        self.colors = colors
        contentsScale = scale
        setNeedsDisplay()
    }

    static var timeFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular) }
    static var nameFont: NSFont { NSFont.systemFont(ofSize: 14, weight: .medium) }
    static var valueFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold) }

    /// Box width for this content, measured with the drawing fonts.
    static func boxWidth(text: SocChartTooltipText, cpuName: String, gpuName: String) -> CGFloat {
        func w(_ s: String, _ f: NSFont) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(line(s, font: f, color: CGColor(gray: 0, alpha: 1)), nil, nil, nil))
        }
        return SocChartHoverArt.boxWidth(
            labelWidths: [w(cpuName, nameFont), w(gpuName, nameFont)],
            valueWidths: [w(text.cpu, valueFont), w(text.gpu, valueFont)])
    }

    private static func line(_ s: String, font: NSFont, color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]))
    }

    override func draw(in ctx: CGContext) {
        let sp = PerfSignposts.begin(PerfSignposts.cpuChartTip)
        defer { sp.end() }
        guard let text, let colors else { return }
        let h = bounds.height, w = bounds.width
        let timeFont = Self.timeFont, nameFont = Self.nameFont, valueFont = Self.valueFont
        let timeBox = timeFont.ascender - timeFont.descender + timeFont.leading
        let stack = timeBox + Self.spacing + Self.rowHeight + Self.spacing + Self.rowHeight
        let top = (h - stack) / 2                                // y-down distance from the layer's top edge
        let px = max(contentsScale, 1)
        func snap(_ v: CGFloat) -> CGFloat { (v * px).rounded() / px }
        /// Baseline of a row whose text box (ascent + descent) is centred in `Self.rowHeight`, as CSS half-leading does.
        func rowBaseline(_ rowTop: CGFloat, _ f: NSFont) -> CGFloat {
            snap(rowTop + (Self.rowHeight - (f.ascender - f.descender)) / 2 + f.ascender)
        }
        let rows: [(name: String, value: String, absent: Bool, swatch: CGColor)] = [
            (names.cpu, text.cpu, text.cpuAbsent, colors.cpu),
            (names.gpu, text.gpu, text.gpuAbsent, colors.gpu),
        ]
        ctx.saveGState()
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        let yDown = ctx.ctm.d < 0
        func draw(_ ln: CTLine, x: CGFloat, baseline: CGFloat) {
            ctx.textMatrix = yDown ? CGAffineTransform(scaleX: 1, y: -1) : .identity
            ctx.textPosition = CGPoint(x: x, y: yDown ? baseline : h - baseline)
            CTLineDraw(ln, ctx)
        }
        draw(Self.line(text.time, font: timeFont, color: colors.muted), x: Self.insetX,
             baseline: snap(top + timeFont.ascender))
        var rowTop = top + timeBox + Self.spacing
        for r in rows {
            // Swatch: 8 × 8, radius 2.5, centred on the row.
            let sy = rowTop + (Self.rowHeight - Self.swatch) / 2
            let sRect = CGRect(x: Self.insetX, y: yDown ? sy : h - sy - Self.swatch, width: Self.swatch, height: Self.swatch)
            ctx.setFillColor(r.swatch)
            ctx.addPath(CGPath(roundedRect: sRect, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
            ctx.fillPath()
            draw(Self.line(r.name, font: nameFont, color: colors.inkSoft),
                 x: Self.insetX + Self.swatch + Self.swatchGap, baseline: rowBaseline(rowTop, nameFont))
            let value = Self.line(r.value, font: valueFont, color: r.absent ? colors.muted : colors.ink)
            let vw = CGFloat(CTLineGetTypographicBounds(value, nil, nil, nil))
            draw(value, x: w - Self.insetX - vw, baseline: rowBaseline(rowTop, valueFont))
            rowTop += Self.rowHeight + Self.spacing
        }
        ctx.restoreGState()
    }
}

// MARK: - View

/// Motion is the History chart's (`HistoryHoverView`): the rule and the markers appear, move and disappear at once; the
/// tooltip is a per-session container that pops in with the shared spring, slides 0.12 s ease-out to the next sample
/// with a text cross-fade, and pops out on leave. Reduce Motion: fade-only on entry and exit, no slide, text replaced at once.
final class SocChartHoverView: NSView {
    /// Copied from `HistoryHoverView.textFade`: date and values cross-fade on a sample change.
    static let textFade = true
    /// Copied from `HistoryHoverView.fade(from:to:duration:)`, `slide(to:animated:)`, `popIn`/`popOut`.
    private static let fadeDuration: CFTimeInterval = 0.12
    private static let slideDuration: CFTimeInterval = 0.12
    /// Copied from `HistoryHoverView.popSpring(_:reversed:)`: scale 0.9 -> 1 with `DS3Motion.popInSpring`, anchored at the box centre
    /// (`HistoryHoverView.popAnchor == .boxCentre`).
    private static let popScale: CGFloat = 0.9

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private let rule = CALayer()
    private let markerCPU = CALayer()
    private let markerGPU = CALayer()

    private var frameData: SocChartHoverFrame?
    private var samples: [SocChartSample] = []
    private var reduceMotion = false
    private var initialHover: Int?
    private var hovered: Int?

    /// The current session's container, its surface image layer and its current text layer.
    private var tooltip: CALayer?
    private var surfaceLayer: CALayer?
    private var textLayer: SocChartHoverTextLayer?

    private var colors: SocChartHoverTextLayer.Colors?
    private var renderedName: NSAppearance.Name?
    private var renderedScale: CGFloat?
    /// Tooltip surface images by box width (re-rendered per width once, never per frame); cleared with the appearance.
    private var surfaces: [CGFloat: CGImage] = [:]
    private var boxWidth = SocChartHoverPlacement.boxSize.width
    private var boxSize: CGSize { CGSize(width: boxWidth, height: SocChartHoverPlacement.boxSize.height) }
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
        for m in [markerCPU, markerGPU] {
            m.bounds = CGRect(x: 0, y: 0, width: SocChartHoverArt.markerSize, height: SocChartHoverArt.markerSize)
            m.contentsGravity = .resize
            m.isHidden = true
        }
        for l in [rule, markerCPU, markerGPU] { Self.silence(l); layer?.addSublayer(l) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func silence(_ l: CALayer) {
        let off = NSNull()
        let keys = ["bounds", "position", "frame", "transform", "opacity", "hidden", "contents", "backgroundColor", "sublayers"]
        l.actions = Dictionary(uniqueKeysWithValues: keys.map { ($0, off) })
    }

    // MARK: Updates from SwiftUI

    func update(frame newFrame: SocChartHoverFrame?, samples newSamples: [SocChartSample], reduceMotion newReduce: Bool,
                initialHover newInitial: Int?) {
        reduceMotion = newReduce
        let layoutChanged = newFrame != frameData || newSamples != samples
        let initialChanged = newInitial != initialHover
        frameData = newFrame
        samples = newSamples
        initialHover = newInitial
        if layoutChanged {
            relayout()
        } else if initialChanged, hovered == nil || pointerLocation() == nil {
            setHover(validIndex(newInitial), animated: false)
        }
    }

    private func validIndex(_ i: Int?) -> Int? {
        guard let i, let f = frameData, i >= 0, i < f.xs.count, f.xs.count == samples.count,
              f.cpuYs.count == samples.count, f.gpuYs.count == samples.count else { return nil }
        return i
    }

    /// Data or geometry changed (a tick, a resize): drop the tooltip session without animation and show the hover for the
    /// pointer's x in the new chart (or `initialHover` when there is no pointer), as `HistoryHoverView.relayout()`.
    private func relayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rule.bounds = CGRect(x: 0, y: 0, width: 1, height: frameData?.plot.height ?? 0)
        removeTooltipNow()
        hovered = nil
        rule.isHidden = true
        markerCPU.isHidden = true
        markerGPU.isHidden = true
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
        guard renderedName != name || renderedScale != s else { return }
        renderedName = name
        renderedScale = s
        surfaces = [:]
        let pal = HistoryHoverArt.palette(for: effectiveAppearance)
        let appearance = effectiveAppearance
        func resolved(_ c: Color) -> Color { Color(cgColor: ds3Resolve(c, in: appearance)) }
        let cpuMarker = HistoryHoverArt.render(SocChartHoverArt.marker(color: resolved(DS3.s1), overlay: pal.overlay), scale: s)
        let gpuMarker = HistoryHoverArt.render(SocChartHoverArt.marker(color: resolved(DS3.s6), overlay: pal.overlay), scale: s)
        colors = SocChartHoverTextLayer.Colors(
            muted: ds3Resolve(DS3.muted, in: appearance), inkSoft: ds3Resolve(DS3.inkSoft, in: appearance),
            ink: ds3Resolve(DS3.ink, in: appearance), cpu: ds3Resolve(DS3.s1, in: appearance),
            gpu: ds3Resolve(DS3.s6, in: appearance))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let soft = ds3Resolve(DS3.inkSoft, in: appearance)
        rule.backgroundColor = soft.copy(alpha: soft.alpha * 0.4)
        markerCPU.contents = cpuMarker
        markerGPU.contents = gpuMarker
        for l in [markerCPU, markerGPU] { l.contentsScale = s }
        surfaceLayer?.contentsScale = s
        surfaceLayer?.contents = surface(width: boxWidth)
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

    /// The surface image for a box `width`, rendered on the first use of that width.
    private func surface(width: CGFloat) -> CGImage? {
        if surfaces[width] == nil {
            let appearance = effectiveAppearance
            let pal = HistoryHoverArt.palette(for: appearance)
            surfaces[width] = HistoryHoverArt.render(SocChartHoverArt.surface(p: pal, appearance: appearance, width: width), scale: scale)
        }
        return surfaces[width]
    }

    /// One redraw of `t` for sample `i` (at the next commit).
    private func configure(_ t: SocChartHoverTextLayer, index i: Int) {
        guard let c = colors, i < samples.count else { return }
        t.set(text: SocChartModel.tooltipText(samples[i]), cpuName: L.commonCPU, gpuName: L.commonGPU, colors: c, scale: scale)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        trackingArea = a
        // D9: AppKit calls this after scrolls and layout changes; keep the rule under a resting pointer (jump, no slide, as History).
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

    /// The sample nearest to the pointer. The pointer x is clamped to the plot, so the hover stays over the margins
    /// and the axis strip while the pointer is inside the view (as History).
    private func snapIndex(at p: CGPoint) -> Int? {
        guard let f = frameData, !f.xs.isEmpty, f.xs.count == samples.count else { return nil }
        let x = min(max(p.x, f.plot.minX), f.plot.maxX)
        return HistoryHoverMath.nearestIndex(xs: f.xs, x: x)
    }

    private func hover(at p: CGPoint, animated: Bool) {
        let n = snapIndex(at: p)
        if n != hovered { setHover(n, animated: animated) }
    }

    // MARK: State

    /// Shows the hover for `requested` (re-placing and redrawing the text even for an unchanged index, because the data
    /// may have changed) or ends it. Same state machine as `HistoryHoverView.setHover`.
    private func setHover(_ requested: Int?, animated: Bool) {
        let n = validIndex(requested)
        let old = hovered
        hovered = n
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rule.isHidden = (n == nil)
        if let n {
            ensureImages()
            place(n)
        } else {
            markerCPU.isHidden = true
            markerGPU.isHidden = true
        }
        CATransaction.commit()
        switch (old, n) {
        case (nil, let n?): popIn(index: n, animated: animated)
        case (_?, nil): popOut(animated: animated)
        case (_?, let n?): slide(to: n, animated: animated)
        case (nil, nil): break
        }
    }

    /// Rule and markers never animate (History R2). A marker of a series without a value is hidden.
    private func place(_ i: Int) {
        guard let f = frameData else { return }
        rule.position = CGPoint(x: f.xs[i], y: f.plot.midY)
        for (m, y) in [(markerCPU, f.cpuYs[i]), (markerGPU, f.gpuYs[i])] {
            m.isHidden = (y == nil)
            if let y { m.position = CGPoint(x: f.xs[i], y: y) }
        }
    }

    /// Box width of sample `i` (it varies with the values, unlike History's constant width).
    private func width(of i: Int) -> CGFloat {
        SocChartHoverTextLayer.boxWidth(text: SocChartModel.tooltipText(samples[i]), cpuName: L.commonCPU, gpuName: L.commonGPU)
    }

    private func tooltipCentre(_ i: Int, box: CGSize) -> CGPoint {
        guard let f = frameData else { return .zero }
        let ys = [f.cpuYs[i], f.gpuYs[i]].compactMap { $0 }
        let o = SocChartHoverPlacement.tooltipOrigin(x: f.xs[i], markerYs: ys, plot: f.plot, boxSize: box)
        return CGPoint(x: o.x + box.width / 2, y: o.y + box.height / 2)
    }

    private func removeTooltipNow() {
        tooltip?.removeFromSuperlayer()
        tooltip = nil
        surfaceLayer = nil
        textLayer = nil
    }

    // MARK: Tooltip layers

    private func makeTextLayer(_ i: Int, box: CGSize) -> SocChartHoverTextLayer {
        let l = SocChartHoverTextLayer()
        l.bounds = CGRect(origin: .zero, size: box)
        l.position = CGPoint(x: box.width / 2, y: box.height / 2)
        Self.silence(l)
        configure(l, index: i)
        return l
    }

    private func makeTooltip(index i: Int) -> CALayer {
        ensureImages()
        boxWidth = width(of: i)
        let box = boxSize
        let half = CGPoint(x: box.width / 2, y: box.height / 2)
        let c = CALayer()
        c.bounds = CGRect(origin: .zero, size: box)
        c.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        Self.silence(c)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        c.position = tooltipCentre(i, box: box)
        let pad = HistoryHoverArt.surfacePad
        let s = CALayer()
        s.bounds = CGRect(x: 0, y: 0, width: box.width + 2 * pad, height: box.height + 2 * pad)
        s.position = half
        s.contents = surface(width: box.width)
        s.contentsScale = scale
        s.contentsGravity = .resize
        Self.silence(s)
        c.addSublayer(s)
        let t = makeTextLayer(i, box: box)
        c.addSublayer(t)
        layer?.addSublayer(c)
        CATransaction.commit()
        tooltip = c
        surfaceLayer = s
        textLayer = t
        return c
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
        let start = HistoryHoverMath.popInStart(centre: c.position, anchor: c.position, scale: Self.popScale)
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
        let scaleAnim = spring("transform.scale", Self.popScale, 1.0)
        let opacityAnim = spring("opacity", 0.0, 1.0)
        let posAnim = spring("position", NSValue(point: start), NSValue(point: .zero))
        posAnim.isAdditive = true
        return [scaleAnim, opacityAnim, posAnim]
    }

    private func popIn(index i: Int, animated: Bool) {
        let c = makeTooltip(index: i)
        guard animated else { return }
        if reduceMotion {
            c.add(fade(from: 0, to: 1, duration: Self.fadeDuration), forKey: nil)
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
        if !reduceMotion { c.setValue(Self.popScale, forKeyPath: "transform.scale") }
        if reduceMotion {
            c.add(fade(from: fromOpacity, to: 0, duration: Self.fadeDuration), forKey: nil)
        } else {
            let anims = popSpring(c, reversed: true)
            anims[0].fromValue = fromScale
            anims[1].fromValue = fromOpacity
            for a in anims { c.add(a, forKey: nil) }
        }
        CATransaction.commit()
    }

    private func slide(to i: Int, animated: Bool) {
        guard let c = tooltip, let s = surfaceLayer else { popIn(index: i, animated: animated); return }
        let from = c.position
        let newWidth = width(of: i)
        boxWidth = newWidth
        let box = boxSize
        let to = tooltipCentre(i, box: box)
        let newText = makeTextLayer(i, box: box)
        let old = textLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The box width follows the sample's values: resize the container and surface at once.
        let pad = HistoryHoverArt.surfacePad
        c.bounds = CGRect(origin: .zero, size: box)
        s.bounds = CGRect(x: 0, y: 0, width: box.width + 2 * pad, height: box.height + 2 * pad)
        s.position = CGPoint(x: box.width / 2, y: box.height / 2)
        s.contents = surface(width: newWidth)
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
            a.duration = Self.slideDuration
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            c.add(a, forKey: nil)
        }
        if animate && Self.textFade {
            newText.add(fade(from: 0, to: 1, duration: Self.fadeDuration), forKey: nil)
            CATransaction.begin()
            CATransaction.setCompletionBlock { old?.removeFromSuperlayer() }
            old?.opacity = 0
            old?.add(fade(from: 1, to: 0, duration: Self.fadeDuration), forKey: nil)
            CATransaction.commit()
        } else {
            old?.removeFromSuperlayer()
        }
    }
}
