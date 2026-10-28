// tools/harness/HarnessKit.swift
// Reusable helpers for headless UI render harnesses (see tools/harness/README.md).
// A "scenario" file composes app views with directly-injected DashboardModel state
// and calls `harnessRender(...)`; tools/harness/render.sh compiles scenario + this
// file + the full app source tree (minus MacDashboardApp.swift) and runs it.
//
// Empirically-learned gotchas baked into this setup — do not relearn them:
// - The scenario must be compiled under the literal filename `main.swift`
//   (top-level statements are only legal there); render.sh handles the copy.
// - Do NOT link `-framework Observation` — Observation is an SDK Swift module,
//   not a framework; linking it fails. AppKit + SwiftUI are enough.
// - DashboardModel and all views are @MainActor; scenarios wrap their body in
//   `MainActor.assumeIsolated { ... }` (plain main.swift top level is not
//   implicitly isolated).
// - `DashboardModel()` init is side-effect-free (loops start via `start()` —
//   never call it in a harness); inject state directly on fresh instances.
// - Pin the language first (`L10nStore.shared.language = .ru`) or an EN-first
//   system locale will render EN strings.
// - Theme is unpinned by default (follows the system). Pin it per call with
//   `appearance: .light/.dark`, or per run with render.sh's third argument
//   (`light|dark|both`, passed in as HARNESS_APPEARANCE). Explicit argument wins.

import AppKit
import SwiftUI

/// Red harness-only caption so screenshots are self-describing.
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

/// One labeled section: red caption above the content.
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

/// Theme pinned for one render. `nil` leaves it unpinned: the render uses
/// whatever the process inherits (system setting, or an
/// `NSApplication.shared.appearance` the scenario set itself).
enum HarnessAppearance: String {
    case light, dark
    var nsAppearance: NSAppearance {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)!
    }
}

/// `HARNESS_APPEARANCE` (set by render.sh's mode argument) as a theme; nil when
/// unset or empty; exits 1 on any other value so a typo cannot pass silently.
func harnessEnvironmentAppearance() -> HarnessAppearance? {
    guard let raw = ProcessInfo.processInfo.environment["HARNESS_APPEARANCE"], !raw.isEmpty else { return nil }
    guard let parsed = HarnessAppearance(rawValue: raw) else {
        FileHandle.standardError.write(Data("ERROR: HARNESS_APPEARANCE must be 'light' or 'dark', got '\(raw)'\n".utf8))
        exit(1)
    }
    return parsed
}

/// Renders `content` offscreen at fixed `width` (height = fitting size) on the
/// standard window background and writes a PNG to `path` (or to the first CLI
/// argument when `path` is nil, falling back to "harness.png"). Exits nonzero
/// with a stderr message on any failure, so render.sh surfaces errors loudly.
/// `appearance` pins the theme for this call (else HARNESS_APPEARANCE, else unpinned); the previous app appearance is restored on return.
@MainActor
func harnessRender<Content: View>(width: CGFloat = 460, appearance: HarnessAppearance? = nil,
                                  to path: String? = nil,
                                  @ViewBuilder content: () -> Content) {
    let pinned = appearance ?? harnessEnvironmentAppearance()
    var previousAppearance: NSAppearance?
    if let pinned {
        previousAppearance = NSApplication.shared.appearance
        NSApplication.shared.appearance = pinned.nsAppearance
    }
    defer { if pinned != nil { NSApplication.shared.appearance = previousAppearance } }

    let rootView = VStack(alignment: .leading, spacing: 20) { content() }
        .padding(20)
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
        .transaction { $0.disablesAnimations = true }

    // Host in a borderless window that is never ordered in (nothing shows on screen): a window-less NSHostingView reports
    // displayScale 1 and snaps frames to whole points while the capture is 2x. A window gets the main screen's backing
    // scale (nothing can force 2 on another screen), so a non-2 main screen is a hard failure. The PNG is a window-server
    // capture of this window (captureWindowPNG, SNAPSHOT-DARK-OFFSCREEN), not cacheDisplay, so blur and blend modes
    // render as in the real window.
    let hosting = NSHostingView(rootView: rootView)
    let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.hasShadow = false   // a window capture would include the shadow
    window.contentView = NSView(frame: .zero)
    window.contentView?.addSubview(hosting)
    guard window.backingScaleFactor == 2 else {
        FileHandle.standardError.write(Data("ERROR: offscreen window backing scale is \(window.backingScaleFactor), harness renders need 2\n".utf8))
        exit(1)
    }
    func place(_ fit: CGSize) {
        let frame = NSRect(x: 0, y: 0, width: max(fit.width, width), height: max(fit.height, 100))
        window.setContentSize(frame.size)
        hosting.frame = frame
        hosting.layoutSubtreeIfNeeded()
    }
    place(hosting.fittingSize)

    // Settle before capture: let a measured-thumb control (DSSlidingSegmented's
    // `onGeometryChange`) and Charts finish their layout pass before we re-measure
    // and capture — otherwise an offscreen render can catch the thumb/chart mid-layout.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
    place(hosting.fittingSize)

    // Proven capture recipe (findings C6): frame on the main display, final layout committed before the capture.
    window.setFrameOrigin(NSPoint(x: 50, y: 50))
    // System indeterminate bars animate in the presentation tree; the model state is what cacheDisplay drew.
    removeAllLayerAnimations(window.contentView!.layer!)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    let pngData: Data
    do {
        pngData = try captureWindowPNG(windowNumber: window.windowNumber,
                                       pixelWidth: Int((window.frame.width * window.backingScaleFactor).rounded()),
                                       pixelHeight: Int((window.frame.height * window.backingScaleFactor).rounded()))
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
        exit(1)
    }

    let resolved = path ?? (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "harness.png")
    let outURL = URL(fileURLWithPath: resolved)
    do {
        try pngData.write(to: outURL)
        print("Wrote \(outURL.path) — \(Int(hosting.bounds.width))x\(Int(hosting.bounds.height))")
        let isDark = hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        print("  appearance: \(isDark ? "dark" : "light") (\(pinned == nil ? "unpinned" : "pinned"))")
    } catch {
        FileHandle.standardError.write(Data("ERROR: write failed: \(error)\n".utf8))
        exit(1)
    }
}

/// Removes every CA animation from `layer` and all its descendants (SNAPSHOT-DARK-OFFSCREEN amendment 1).
/// Copy of Tests/MacDashboardTests/SnapshotSupport.swift `removeAllLayerAnimations` (the harness cannot compile test-target files); keep the two in step.
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
/// Copy of Tests/MacDashboardTests/SnapshotSupport.swift `captureWindowPNG` (the harness cannot compile test-target files); keep the two in step.
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
