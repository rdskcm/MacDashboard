// make_icon.swift — renders the app icon exactly as design_handoff variant 1a:
// handoff squircle path, gPlateA plate gradient, gCoolFlat pulse, live dot,
// hairline rim. No drop shadow, no sheen — the OS supplies those.
// Run: swift tools/make_icon.swift <output.icns>   (needs only CLT + /usr/bin/iconutil)
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else { FileHandle.standardError.write("usage: make_icon.swift out.icns\n".data(using: .utf8)!); exit(2) }
let outURL = URL(fileURLWithPath: args[1])

// Handoff squircle outline, 201 M/L nodes in a 0–100 coordinate space, from
// the project's design handoff (design_handoff variant 1a, sq.txt). Kept
// exact — not rounded, resampled, or replaced with a computed superellipse.
let squirclePoints: [(Double, Double)] = [
    (100.0,50.0), (99.99,62.53), (99.96,66.52), (99.91,69.43), (99.84,71.79), (99.75,73.81),
    (99.64,75.59), (99.51,77.19), (99.37,78.66), (99.2,80.01), (99.01,81.26), (98.8,82.43),
    (98.56,83.52), (98.31,84.56), (98.04,85.53), (97.74,86.46), (97.43,87.33), (97.09,88.17),
    (96.73,88.96), (96.34,89.71), (95.94,90.43), (95.5,91.11), (95.05,91.76), (94.57,92.38),
    (94.06,92.97), (93.53,93.53), (92.97,94.06), (92.38,94.57), (91.76,95.05), (91.11,95.5),
    (90.43,95.94), (89.71,96.34), (88.96,96.73), (88.17,97.09), (87.33,97.43), (86.46,97.74),
    (85.53,98.04), (84.56,98.31), (83.52,98.56), (82.43,98.8), (81.26,99.01), (80.01,99.2),
    (78.66,99.37), (77.19,99.51), (75.59,99.64), (73.81,99.75), (71.79,99.84), (69.43,99.91),
    (66.52,99.96), (62.53,99.99), (50.0,100.0), (37.47,99.99), (33.48,99.96), (30.57,99.91),
    (28.21,99.84), (26.19,99.75), (24.41,99.64), (22.81,99.51), (21.34,99.37), (19.99,99.2),
    (18.74,99.01), (17.57,98.8), (16.48,98.56), (15.44,98.31), (14.47,98.04), (13.54,97.74),
    (12.67,97.43), (11.83,97.09), (11.04,96.73), (10.29,96.34), (9.57,95.94), (8.89,95.5),
    (8.24,95.05), (7.62,94.57), (7.03,94.06), (6.47,93.53), (5.94,92.97), (5.43,92.38),
    (4.95,91.76), (4.5,91.11), (4.06,90.43), (3.66,89.71), (3.27,88.96), (2.91,88.17),
    (2.57,87.33), (2.26,86.46), (1.96,85.53), (1.69,84.56), (1.44,83.52), (1.2,82.43),
    (0.99,81.26), (0.8,80.01), (0.63,78.66), (0.49,77.19), (0.36,75.59), (0.25,73.81),
    (0.16,71.79), (0.09,69.43), (0.04,66.52), (0.01,62.53), (0.0,50.0), (0.01,37.47),
    (0.04,33.48), (0.09,30.57), (0.16,28.21), (0.25,26.19), (0.36,24.41), (0.49,22.81),
    (0.63,21.34), (0.8,19.99), (0.99,18.74), (1.2,17.57), (1.44,16.48), (1.69,15.44),
    (1.96,14.47), (2.26,13.54), (2.57,12.67), (2.91,11.83), (3.27,11.04), (3.66,10.29),
    (4.06,9.57), (4.5,8.89), (4.95,8.24), (5.43,7.62), (5.94,7.03), (6.47,6.47),
    (7.03,5.94), (7.62,5.43), (8.24,4.95), (8.89,4.5), (9.57,4.06), (10.29,3.66),
    (11.04,3.27), (11.83,2.91), (12.67,2.57), (13.54,2.26), (14.47,1.96), (15.44,1.69),
    (16.48,1.44), (17.57,1.2), (18.74,0.99), (19.99,0.8), (21.34,0.63), (22.81,0.49),
    (24.41,0.36), (26.19,0.25), (28.21,0.16), (30.57,0.09), (33.48,0.04), (37.47,0.01),
    (50.0,0.0), (62.53,0.01), (66.52,0.04), (69.43,0.09), (71.79,0.16), (73.81,0.25),
    (75.59,0.36), (77.19,0.49), (78.66,0.63), (80.01,0.8), (81.26,0.99), (82.43,1.2),
    (83.52,1.44), (84.56,1.69), (85.53,1.96), (86.46,2.26), (87.33,2.57), (88.17,2.91),
    (88.96,3.27), (89.71,3.66), (90.43,4.06), (91.11,4.5), (91.76,4.95), (92.38,5.43),
    (92.97,5.94), (93.53,6.47), (94.06,7.03), (94.57,7.62), (95.05,8.24), (95.5,8.89),
    (95.94,9.57), (96.34,10.29), (96.73,11.04), (97.09,11.83), (97.43,12.67), (97.74,13.54),
    (98.04,14.47), (98.31,15.44), (98.56,16.48), (98.8,17.57), (99.01,18.74), (99.2,19.99),
    (99.37,21.34), (99.51,22.81), (99.64,24.41), (99.75,26.19), (99.84,28.21), (99.91,30.57),
    (99.96,33.48), (99.99,37.47), (100.0,50.0),
]

// Trace preset (points, stroke width, dot centre/radius, all in the 0–100
// space) selected by the rendered pixel size, so thin strokes survive at
// small sizes. Pulse gradient start/end x follow the preset's own first and
// last point, not a hard-coded 18/78.
struct TracePreset {
    let pts: [(CGFloat, CGFloat)]
    let lineWidth: CGFloat
    let dotCx: CGFloat
    let dotR: CGFloat
}
func tracePreset(for size: Int) -> TracePreset {
    if size == 16 {
        return TracePreset(pts: [(20,50),(38,50),(45,33),(53,67),(59,46),(64,50),(76,50)],
                           lineWidth: 8, dotCx: 76, dotR: 6)
    } else if size == 32 {
        return TracePreset(pts: [(18,50),(36,50),(43,31),(51,69),(57,44),(62,50),(77,50)],
                           lineWidth: 6, dotCx: 77, dotR: 5.2)
    } else {
        return TracePreset(pts: [(18,50),(36,50),(43,31),(51,69),(57,44),(62,50),(78,50)],
                           lineWidth: 5, dotCx: 78, dotR: 4.6)
    }
}

let cs = CGColorSpaceCreateDeviceRGB()
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xff)/255,
                                         CGFloat((hex >> 8) & 0xff)/255,
                                         CGFloat(hex & 0xff)/255, a])!
}

/// Draws the icon at `size` px, selecting the trace preset by pixel size.
func drawIcon(_ size: Int) -> NSBitmapImageRep {
    // Handoff coordinates are a 0–100 space. The plate is inset so the icon
    // carries the standard macOS margin the .icns shape would otherwise leave
    // to the system.
    let S = CGFloat(size)
    let inset: CGFloat = 0.08
    let span = S * (1 - 2 * inset)
    func px(_ v: CGFloat) -> CGFloat { S * inset + v / 100 * span }
    func py(_ v: CGFloat) -> CGFloat { S - (S * inset + v / 100 * span) }   // SVG y grows down

    let squircle = CGMutablePath()
    for (i, p) in squirclePoints.enumerated() {
        let x = px(CGFloat(p.0)), y = py(CGFloat(p.1))
        if i == 0 { squircle.move(to: CGPoint(x: x, y: y)) } else { squircle.addLine(to: CGPoint(x: x, y: y)) }
    }
    squircle.closeSubpath()

    let preset = tracePreset(for: size)

    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Plate: gPlateA, #1e2226 → #0c0e10, running (0.1,0) → (0.9,1) of the plate box.
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let plate = CGGradient(colorsSpace: cs, colors: [c(0x1e2226), c(0x0c0e10)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(plate, start: CGPoint(x: px(10), y: py(0)), end: CGPoint(x: px(90), y: py(100)),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Pulse: gCoolFlat, #4a9ae8 → #2ec4a0, horizontal across the trace.
    let trace = CGMutablePath()
    trace.addLines(between: preset.pts.map { CGPoint(x: px($0.0), y: py($0.1)) })
    ctx.saveGState()
    ctx.addPath(trace)
    ctx.setLineWidth(preset.lineWidth / 100 * span)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let cool = CGGradient(colorsSpace: cs, colors: [c(0x4a9ae8), c(0x2ec4a0)] as CFArray, locations: [0, 1])!
    let firstX = preset.pts.first!.0, lastX = preset.pts.last!.0
    ctx.drawLinearGradient(cool, start: CGPoint(x: px(firstX), y: py(50)), end: CGPoint(x: px(lastX), y: py(50)),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Live dot — solid #2ec4a0, thickening the trace's right end.
    let r = preset.dotR / 100 * span
    ctx.setFillColor(c(0x2ec4a0))
    ctx.fillEllipse(in: CGRect(x: px(preset.dotCx) - r, y: py(50) - r, width: 2*r, height: 2*r))

    // Hairline rim, rgba(255,255,255,0.11), stroke-width 1 in the 0–100 space.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [1, 1, 1, 0.11])!)
    ctx.setLineWidth(1.0 / 100 * span)
    ctx.strokePath()
    ctx.restoreGState()

    guard let img = ctx.makeImage() else { exit(1) }
    return NSBitmapImageRep(cgImage: img)
}

let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("dashicon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = drawIcon(px)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: tmp.appendingPathComponent(name))
    }
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", outURL.path]
try p.run(); p.waitUntilExit()
exit(p.terminationStatus)
