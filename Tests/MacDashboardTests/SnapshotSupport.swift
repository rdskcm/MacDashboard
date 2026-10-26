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

/// Layout and settle exactly as tools/harness/HarnessKit.swift `harnessRender`, but into an explicit 2x bitmap (D4).
/// The view is hosted in a borderless window that is never ordered front: a window-less `NSHostingView` reports
/// `displayScale` 1 and snaps frames to whole points while the bitmap is 2x, so hairlines would render as a 1x picture
/// scaled up. A window gets the main screen's backing scale (nothing can force 2 on another screen), so a non-2 main
/// screen fails the render instead of producing a reference that no Retina window shows.
@MainActor
func renderSnapshotPNG<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> Data? {
    let rootView = VStack(alignment: .leading, spacing: 20) { content() }
        .padding(20)
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
        .transaction { $0.disablesAnimations = true }
    let hosting = NSHostingView(rootView: rootView)
    let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSView(frame: .zero)
    window.contentView?.addSubview(hosting)
    guard window.backingScaleFactor == 2 else {
        Issue.record("offscreen window backing scale is \(window.backingScaleFactor), snapshots need 2")
        return nil
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
    let size = hosting.bounds.size
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int((size.width * 2).rounded()), pixelsHigh: Int((size.height * 2).rounded()),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}

/// One snapshot run: renders each state to <out>/current/<state>.png and, in `finish()`, writes <out>/rendered.tsv
/// (state, ok | RENDER-FAILED) and <out>/timing.txt. The comparison with the references is done by
/// `vbtool snap-compare` (built with -O by tools/visual/snapshots.sh): the unoptimised test build is ~50x slower per pixel.
@MainActor
final class SnapshotRun {
    let out: URL
    private var rows: [String] = []
    private var renderSeconds = 0.0

    init(out: URL) throws {
        self.out = out
        try FileManager.default.createDirectory(at: out.appendingPathComponent("current"), withIntermediateDirectories: true)
    }

    func snap<Content: View>(_ base: String, _ mode: String, width: CGFloat, @ViewBuilder content: () -> Content) {
        let state = "\(base)-\(mode)"
        let previous = NSApplication.shared.appearance
        NSApplication.shared.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        defer { NSApplication.shared.appearance = previous }
        let cur = out.appendingPathComponent("current/\(state).png")
        let t0 = Date()
        let rendered = renderSnapshotPNG(width: width, content: content)
        renderSeconds += Date().timeIntervalSince(t0)
        guard let png = rendered, (try? png.write(to: cur)) != nil else {
            Issue.record("\(state): render or write failed"); rows.append("\(state)\tRENDER-FAILED"); return
        }
        rows.append("\(state)\tok")
    }

    func finish() throws {
        let body = (rows + ["# complete \(rows.count) states"]).joined(separator: "\n") + "\n"
        try body.write(to: out.appendingPathComponent("rendered.tsv"), atomically: true, encoding: .utf8)
        let timing = String(format: "render_seconds: %.1f\n", renderSeconds)
        try timing.write(to: out.appendingPathComponent("timing.txt"), atomically: true, encoding: .utf8)
    }
}
