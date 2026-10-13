import Foundation
import CoreGraphics
// tools/perf helper, compiled by gate.sh into $OUT/.bin/hold. Marks are epoch seconds.
// usage: hold x y secs  -> park the pointer at x,y with +-2pt jitter at 60 Hz for secs; prints t0/t1
let a = CommandLine.arguments
let x = Double(a[1])!, y = Double(a[2])!, secs = Double(a[3])!
func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }
print("t0 \(now())"); fflush(stdout)
let n = Int(secs * 60)
for i in 0..<n {
    let px = x + 2 * sin(Double(i) / 9.0)
    CGWarpMouseCursorPosition(CGPoint(x: px, y: y))
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: px, y: y), mouseButton: .left)!.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 1.0 / 60)
}
print("t1 \(now())")
