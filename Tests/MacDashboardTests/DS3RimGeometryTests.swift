// DS3RimGeometryTests.swift
// APPEAR-CA-ENTRANCE R6: the rim converts the tracker's window-space pointer into its own coordinates, with and
// without a nested `DS3EntranceHost` (where `DS3.windowSpace` is not resolvable).

import Testing
import SwiftUI
import AppKit
@testable import MacDashboard

@MainActor
private final class RHost {
    let tracker = DS3PointerTracker()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
    init<V: View>(_ view: V) {
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.frame(width: 600, height: 500, alignment: .topLeading).ds3PointerTracking(tracker))
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        window.contentView = hosting
        settle()
    }
    func settle(_ s: TimeInterval = 0.3) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: s))
        window.contentView?.layoutSubtreeIfNeeded()
    }
    func rim() -> DS3RimView? {
        func walk(_ v: NSView) -> DS3RimView? {
            if let r = v as? DS3RimView { return r }
            for s in v.subviews { if let r = walk(s) { return r } }
            return nil
        }
        return window.contentView.flatMap(walk)
    }
    func close() { window.contentView = nil; window.close(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
}

private struct RimCard: View {
    var body: some View {
        Color.clear.frame(width: 300, height: 200).overlay(DS3Rim(cornerRadius: 20))
    }
}

extension SerialTests {
    @Suite struct DS3RimGeometryTests {
        @MainActor private func check(_ view: some View, _ label: String) {
            let h = RHost(view)
            h.tracker.pointer(CGPoint(x: 150, y: 80))
            h.settle(0.1)
            let a = h.rim()?.lastAim
            #expect(a != nil, "\(label): the rim was aimed")
            #expect(abs((a?.x ?? -999) - 50) < 0.5 && abs((a?.y ?? -999) - 30) < 0.5, "\(label): got \(String(describing: a))")
            h.tracker.pointer(nil)
            h.settle(0.1)
            #expect(h.rim()?.lastAim == nil, "\(label): pointer outside clears the aim")
            h.close()
        }

        @MainActor @Test func rimConvertsWindowSpaceItself() {
            VisualFixture.forced = false
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                print("skipped: Reduce Motion is on (rims are static and record nothing)")
                return
            }
            check(ZStack(alignment: .topLeading) { RimCard().offset(x: 100, y: 50) }, "plain")
            check(ZStack(alignment: .topLeading) {
                DS3EntranceHost(delay: 0, offsetY: 0, scale: 1, slideX: 0) { RimCard() }.frame(width: 300).offset(x: 100, y: 50)
            }, "hosted")
        }
    }
}
