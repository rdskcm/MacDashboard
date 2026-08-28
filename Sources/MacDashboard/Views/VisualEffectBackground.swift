// Views/VisualEffectBackground.swift
// Real translucent blur backing for the Settings window (V2-SETTINGS-CHROME).
// There is no existing blur/vibrancy plumbing anywhere else in the app to copy
// (the battery popover's frosted look is free NSPopover vibrancy, no view code
// at all) — this file is the first hand-written NSVisualEffectView wrapper.
import AppKit
import SwiftUI

/// Wraps an `NSVisualEffectView` (`material = .popover`, `blendingMode =
/// .behindWindow`, `state = .active`, matching the spec's Change 1) and, the
/// moment it lands on its `NSWindow`, also configures that window: opaque =
/// false / background = .clear (Change 3) so the material can show the desktop
/// through it.
///
/// The Settings window KEEPS its system titlebar (user decision at acceptance,
/// 2026-08-11): hiding it via `.fullSizeContentView` grew the window's content
/// area by the titlebar height while the SwiftUI root stays pinned to a fixed
/// 680×420, which left an uncovered transparent strip along the bottom edge
/// (unblurred desktop, since the window background is `.clear`) and pushed the
/// top card under the window's top edge. Only the translucency is wanted here —
/// so this view configures window transparency and nothing else.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowConfiguringVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Subclass exists only to hook `viewDidMoveToWindow` — the first point at
/// which the backing `NSWindow` is available to configure. Deliberately
/// unguarded: re-parenting re-applies the same two values, which is idempotent.
private final class WindowConfiguringVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
