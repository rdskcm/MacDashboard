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

/// Renders `content` offscreen at fixed `width` (height = fitting size) on the
/// standard window background and writes a PNG to `path` (or to the first CLI
/// argument when `path` is nil, falling back to "harness.png"). Exits nonzero
/// with a stderr message on any failure, so render.sh surfaces errors loudly.
@MainActor
func harnessRender<Content: View>(width: CGFloat = 460, to path: String? = nil,
                                  @ViewBuilder content: () -> Content) {
    let rootView = VStack(alignment: .leading, spacing: 20) { content() }
        .padding(20)
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))

    let hosting = NSHostingView(rootView: rootView)
    let fitting = hosting.fittingSize
    hosting.frame = NSRect(x: 0, y: 0, width: max(fitting.width, width), height: max(fitting.height, 100))
    hosting.layoutSubtreeIfNeeded()

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        FileHandle.standardError.write(Data("ERROR: bitmapImageRepForCachingDisplay returned nil\n".utf8))
        exit(1)
    }
    rep.size = hosting.bounds.size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("ERROR: PNG conversion failed\n".utf8))
        exit(1)
    }

    let resolved = path ?? (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "harness.png")
    let outURL = URL(fileURLWithPath: resolved)
    do {
        try pngData.write(to: outURL)
        print("Wrote \(outURL.path) — \(Int(hosting.bounds.width))x\(Int(hosting.bounds.height))")
    } catch {
        FileHandle.standardError.write(Data("ERROR: write failed: \(error)\n".utf8))
        exit(1)
    }
}
