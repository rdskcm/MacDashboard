// make_icon.swift — renders the app icon (dark squircle + pulse line + live dot,
// same palette as the legacy make_dashboard_app.py) and packs it into an .icns.
// Run: swift tools/make_icon.swift <output.icns>   (needs only CLT + /usr/bin/iconutil)
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else { FileHandle.standardError.write("usage: make_icon.swift out.icns\n".data(using: .utf8)!); exit(2) }
let outURL = URL(fileURLWithPath: args[1])

let bg = NSColor(srgbRed: 26/255, green: 26/255, blue: 25/255, alpha: 1)      // #1a1a19
let lineStart = NSColor(srgbRed: 57/255, green: 135/255, blue: 229/255, alpha: 1)  // #3987e5
let lineEnd = NSColor(srgbRed: 27/255, green: 175/255, blue: 122/255, alpha: 1)    // #1baf7a (matches live dot)
let dot = NSColor(srgbRed: 27/255, green: 175/255, blue: 122/255, alpha: 1)   // #1baf7a

/// Draws the icon at `size` px. `pulseColors` is the left→right gradient stop
/// list for the pulse polyline (default: blue → green, matching the live dot);
/// the live dot itself is always solid `dot` regardless of `pulseColors`.
func drawIcon(_ size: Int, pulseColors: [NSColor] = [lineStart, lineEnd]) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Squircle background (macOS masks its own shape since Big Sur; inset ~10%)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    bg.setFill(); path.fill()

    // Pulse line: flat — spike up — flat — dip — flat
    let lw = max(1, s * 0.045)
    let midY = s * 0.5
    let pts: [(CGFloat, CGFloat)] = [
        (0.16, 0.50), (0.34, 0.50), (0.42, 0.68), (0.50, 0.36), (0.56, 0.55),
        (0.62, 0.50), (0.78, 0.50),
    ]
    let pulsePath = CGMutablePath()
    pulsePath.move(to: CGPoint(x: pts[0].0 * s, y: midY))
    for p in pts { pulsePath.addLine(to: CGPoint(x: p.0 * s, y: p.1 * s)) }
    // Stroke-as-outline, then fill the outline with a left→right gradient —
    // AppKit/CoreGraphics has no native gradient-stroke primitive.
    let stroked = pulsePath.copy(strokingWithWidth: lw, lineCap: .round, lineJoin: .round, miterLimit: 10)

    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        ctx.addPath(stroked)
        ctx.clip()
        if let gradient = NSGradient(colors: pulseColors) {
            gradient.draw(from: NSPoint(x: 0.16 * s, y: midY), to: NSPoint(x: 0.78 * s, y: midY),
                          options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        }
        ctx.restoreGState()
    }

    // Live dot at the end of the line (always solid, never gradient)
    let r = s * 0.045
    let dotRect = NSRect(x: 0.78 * s - r, y: 0.5 * s - r, width: 2 * r, height: 2 * r)
    dot.setFill(); NSBezierPath(ovalIn: dotRect).fill()
    return rep
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
