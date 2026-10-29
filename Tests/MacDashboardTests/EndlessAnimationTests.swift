// EndlessAnimationTests.swift
// PULSE-COST (R6, rule no-unseen-work): the «All good» line runs no endless animation, and collapsed process rows
// mount no spinner. Each check has a known-positive control (a lone DS3Spinner), so a walker that sees nothing fails.

import SwiftUI
import AppKit
import QuartzCore
import Testing
@testable import MacDashboard

@MainActor
private final class Host {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    init<V: View>(_ view: V) {
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.frame(width: 900, height: 700))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        window.contentView = hosting
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        window.contentView?.layoutSubtreeIfNeeded()
    }
    private var views: [NSView] {
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        return window.contentView.map(all) ?? []
    }
    /// Animations that repeat forever, on every layer under the hosting view (each layer counted once).
    var endlessAnimations: Int {
        var seen = Set<ObjectIdentifier>()
        var n = 0
        func walk(_ l: CALayer) {
            guard seen.insert(ObjectIdentifier(l)).inserted else { return }
            for k in l.animationKeys() ?? [] {
                if let a = l.animation(forKey: k), a.repeatCount >= 1e6 || a.repeatDuration >= 1e6 { n += 1 }
            }
            for s in l.sublayers ?? [] { walk(s) }
        }
        for v in views { if let l = v.layer { walk(l) } }
        return n
    }
    var spinners: Int { views.filter { $0 is DS3SpinnerView }.count }
    func close() { window.contentView = nil; window.close(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
}

extension SerialTests {
    @Suite struct EndlessAnimationTests {
        @MainActor @Test func allGoodLineRunsNoEndlessAnimation() throws {
            VisualFixture.forced = false
            #expect(!DS3Motion.isFrozen, "the check needs live motion; a frozen run creates no animations at all")
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-endless-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let m = AppModel(dataDirectory: dir)

            let control = Host(DS3Spinner(role: .track, size: 13))
            #expect(control.endlessAnimations == 1, "control: a lone spinner in a window runs one endless animation")
            control.close()

            let h = Host(HomeAllGoodLine(model: m))
            #expect(h.endlessAnimations == 0, "the «All good» line is static (PULSE-COST R1)")
            h.close()
        }

        @MainActor @Test func collapsedProcessRowsMountNoSpinner() throws {
            VisualFixture.forced = true
            defer { VisualFixture.forced = false }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-endless-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let m = AppModel(dataDirectory: dir)
            m.applyVisualFixture()
            #expect(!m.topCPU.isEmpty, "control: the fixture has process rows")

            let control = Host(DS3Spinner(role: .track, size: 13))
            #expect(control.spinners == 1, "control: a mounted spinner is found")
            control.close()

            let h = Host(ProcessListCard(model: m))
            #expect(h.spinners == 0, "no row is open, so no row mounts a spinner (PULSE-COST R3)")
            h.close()
        }
    }
}
