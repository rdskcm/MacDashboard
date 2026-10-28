// Tests/MacDashboardTests/SnapshotSupport.swift
// HARNESS-REDESIGN-RETARGET: offscreen snapshot rendering and comparison for ContentSnapshotTests.
// Enabled only when MACDASH_SNAPSHOTS=<absolute output dir> is set (tools/visual/snapshots.sh sets it);
// references live in <package>/Tests/Snapshots/<state>.png, change only through `snapshots.sh --bless`, and are compared by vbtool.
import AppKit
import SwiftUI
import Testing
@testable import MacDashboard

enum SnapshotEnv {
    static var outDir: URL? {
        guard let p = ProcessInfo.processInfo.environment["MACDASH_SNAPSHOTS"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }
}

/// Red caption above a section (copy of tools/harness/HarnessKit.swift `HarnessLabel`/`HarnessSection`).
struct HarnessLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.red)
    }
}
struct HarnessSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HarnessLabel(text: label)
            content
        }
    }
}

/// Layout and settle exactly as tools/harness/HarnessKit.swift `harnessRender`, captured at 2x (D4).
/// The view is hosted in a borderless window that is never ordered in (nothing shows on screen): a window-less
/// `NSHostingView` reports `displayScale` 1 and snaps frames to whole points while the capture is 2x, so hairlines would
/// render as a 1x picture scaled up. A window gets the main screen's backing scale (nothing can force 2 on another
/// screen), so a non-2 main screen fails the render instead of producing a reference that no Retina window shows.
/// SNAPSHOT-DARK-OFFSCREEN: the PNG is a window-server capture of that window (`captureWindowPNG`), not `cacheDisplay`.
/// `cacheDisplay` draws the layer tree on the CPU, which turns ds3Elevation's `.destinationOut` punch inside a
/// `compositingGroup` white and drops `.blur`; the window server composites both as the real window does.
@MainActor
func renderSnapshotPNG<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) throws -> Data {
    let rootView = VStack(alignment: .leading, spacing: 20) { content() }
        .padding(20)
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
        .transaction { $0.disablesAnimations = true }
    let hosting = NSHostingView(rootView: rootView)
    let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.hasShadow = false   // a window capture would include the shadow
    window.contentView = NSView(frame: .zero)
    window.contentView?.addSubview(hosting)
    guard window.backingScaleFactor == 2 else {
        throw WindowCaptureError(description: "offscreen window backing scale is \(window.backingScaleFactor), snapshots need 2")
    }
    func place(_ fit: CGSize) {
        let frame = NSRect(x: 0, y: 0, width: max(fit.width, width), height: max(fit.height, 100))
        window.setContentSize(frame.size)
        hosting.frame = frame
        hosting.layoutSubtreeIfNeeded()
    }
    place(hosting.fittingSize)
    // Same 1.0 s settle as the harness (DSSlidingSegmented thumb, Charts layout).
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
    place(hosting.fittingSize)
    // Proven capture recipe (findings C6): frame on the main display, final layout committed before the capture.
    window.setFrameOrigin(NSPoint(x: 50, y: 50))
    // System indeterminate bars animate in the presentation tree; the model state is what cacheDisplay drew.
    removeAllLayerAnimations(window.contentView!.layer!)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    return try captureWindowPNG(windowNumber: window.windowNumber,
                                pixelWidth: Int((window.frame.width * window.backingScaleFactor).rounded()),
                                pixelHeight: Int((window.frame.height * window.backingScaleFactor).rounded()))
}

/// Removes every CA animation from `layer` and all its descendants (SNAPSHOT-DARK-OFFSCREEN amendment 1).
/// Copy in tools/harness/HarnessKit.swift (the harness cannot compile test-target files); keep the two in step.
fileprivate func removeAllLayerAnimations(_ layer: CALayer) {
    layer.removeAllAnimations()
    for sub in layer.sublayers ?? [] { removeAllLayerAnimations(sub) }
}

/// A window capture that produced no usable image (SNAPSHOT-DARK-OFFSCREEN R4/R5).
struct WindowCaptureError: Error, CustomStringConvertible {
    let description: String
}

/// PNG bytes of a window captured by the window server: `/usr/sbin/screencapture -x -l <windowNumber>`
/// (SNAPSHOT-DARK-OFFSCREEN, findings C6). It renders a window that was never ordered in exactly like the real
/// on-screen window and shows nothing on screen. Throws instead of returning a blank, partial or wrong-size image.
/// Copy in tools/harness/HarnessKit.swift (the harness cannot compile test-target files); keep the two in step.
func captureWindowPNG(windowNumber: Int, pixelWidth: Int, pixelHeight: Int) throws -> Data {
    guard CGPreflightScreenCaptureAccess() else {
        throw WindowCaptureError(description: "Screen Recording permission is missing for the app that started this run "
            + "(Terminal, iTerm, Xcode, ...). Turn it on in System Settings > Privacy & Security > "
            + "Screen & System Audio Recording, quit and reopen that app, then run again.")
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("md-wincap-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-x", "-l", String(windowNumber), tmp.path]
    let output = Pipe()
    proc.standardOutput = output
    proc.standardError = output
    do { try proc.run() } catch {
        throw WindowCaptureError(description: "cannot launch /usr/sbin/screencapture: \(error)")
    }
    proc.waitUntilExit()
    let toolText = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard proc.terminationStatus == 0 else {
        throw WindowCaptureError(description: "screencapture -l \(windowNumber) exited \(proc.terminationStatus): \(toolText)")
    }
    guard let png = try? Data(contentsOf: tmp), let image = NSBitmapImageRep(data: png)?.cgImage else {
        throw WindowCaptureError(description: "screencapture -l \(windowNumber) wrote no readable image")
    }
    guard abs(image.width - pixelWidth) <= 1, abs(image.height - pixelHeight) <= 1 else {
        throw WindowCaptureError(description: "capture of window \(windowNumber) is \(image.width)x\(image.height) px, "
            + "the window is \(pixelWidth)x\(pixelHeight) px")
    }
    guard !cgImageIsUniform(image) else {
        throw WindowCaptureError(description: "capture of window \(windowNumber) is one flat colour (blank)")
    }
    return png
}

/// True when every pixel of `image` has the same RGBA value, i.e. a blank capture. A real state differs within its
/// first rows (text after 20 pt padding), so the scan stops early; only a blank image is scanned whole.
func cgImageIsUniform(_ image: CGImage) -> Bool {
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return true }
    var pixels = [UInt32](repeating: 0, count: w * h)
    let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drawn else { return true }
    let first = pixels[0]
    return !pixels.contains { $0 != first }
}

/// One snapshot run: renders each state to <out>/current/<state>.png and, in `finish()`, writes <out>/rendered.tsv
/// (state, ok | RENDER-FAILED) and <out>/timing.txt. The comparison with the references is done by
/// `vbtool snap-compare` (built with -O by tools/visual/snapshots.sh): the unoptimised test build is ~50x slower per pixel.
@MainActor
final class SnapshotRun {
    let out: URL
    private var rows: [String] = []
    private var renderSeconds = 0.0
    /// First render or write failure of this run (D5): later states are skipped and `finish()` throws, so no
    /// rendered.tsv is written and snapshots.sh stops with exit 70 instead of comparing a broken run.
    private var stopReason: String?

    init(out: URL) throws {
        self.out = out
        try FileManager.default.createDirectory(at: out.appendingPathComponent("current"), withIntermediateDirectories: true)
    }

    func snap<Content: View>(_ base: String, _ mode: String, width: CGFloat, @ViewBuilder content: () -> Content) {
        let state = "\(base)-\(mode)"
        guard stopReason == nil else { return }
        let previous = NSApplication.shared.appearance
        NSApplication.shared.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        defer { NSApplication.shared.appearance = previous }
        let cur = out.appendingPathComponent("current/\(state).png")
        let t0 = Date()
        do {
            let png = try renderSnapshotPNG(width: width, content: content)
            renderSeconds += Date().timeIntervalSince(t0)
            try png.write(to: cur, options: .atomic)
        } catch {
            stopReason = "\(state): \(error)"
            Issue.record("\(state): snapshot failed, run stopped: \(error)")
            return
        }
        rows.append("\(state)\tok")
    }

    func finish() throws {
        if let stopReason {
            throw WindowCaptureError(description: "snapshot run stopped at \(stopReason); rendered.tsv not written")
        }
        let body = (rows + ["# complete \(rows.count) states"]).joined(separator: "\n") + "\n"
        try body.write(to: out.appendingPathComponent("rendered.tsv"), atomically: true, encoding: .utf8)
        let timing = String(format: "render_seconds: %.1f\n", renderSeconds)
        try timing.write(to: out.appendingPathComponent("timing.txt"), atomically: true, encoding: .utf8)
    }
}

// SNAPSHOT-DARK-OFFSCREEN R9: failure paths of the window capture. In the gated suite (D9): they need a window server.
extension SerialTests.SnapshotTests {
    @Test func captureOfMissingWindowThrows() {
        #expect(throws: WindowCaptureError.self) {
            try captureWindowPNG(windowNumber: Int(Int32.max), pixelWidth: 10, pixelHeight: 10)
        }
    }

    @Test func flatImageCountsAsBlank() throws {
        func image(twoColours: Bool) throws -> CGImage {
            let ctx = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            if twoColours {
                ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                ctx.fill(CGRect(x: 3, y: 3, width: 1, height: 1))
            }
            return try #require(ctx.makeImage())
        }
        #expect(cgImageIsUniform(try image(twoColours: false)))
        #expect(!cgImageIsUniform(try image(twoColours: true)))
    }
}
