import Foundation
import CoreGraphics
// tools/perf helper, compiled by gate.sh into $OUT/.bin/drv (never run from here). Marks are epoch seconds.
// usage: drv winfo <pid>            -> prints window frame
//        drv scroll x y secs dy [gap] [phase]  -> trackpad-like gesture (began/changed/ended), prints t0
//        drv move x y secs         -> sweep pointer horizontally around x,y for secs
let a = CommandLine.arguments
func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }
if a[1] == "winfo" {
    let pid = Int32(a[2])!
    let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    for w in l where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
        print(w[kCGWindowBounds as String]!, w[kCGWindowLayer as String]!, w[kCGWindowName as String] ?? "")
    }
} else if a[1] == "scroll" {
    let x = Double(a[2])!, y = Double(a[3])!, secs = Double(a[4])!, dy = Double(a[5])!
    let hz = 60.0
    CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
    CGAssociateMouseAndMouseCursorPosition(1)
    let mv = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    mv.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.3)
    print("t0 \(now())"); fflush(stdout)
    let n = Int(secs * hz)
    for i in 0..<n {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(a.count > 6 ? Int(a[6])! : 0), wheel3: 0)!
        e.location = CGPoint(x: x, y: y)
        e.setIntegerValueField(CGEventField(rawValue: 99)!, value: i == 0 ? 1 : 2)   // scrollPhase began/changed
        e.setIntegerValueField(CGEventField(rawValue: 137)!, value: 1)  // isContinuous
        e.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 1.0 / hz)
    }
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0)!
    e.setIntegerValueField(CGEventField(rawValue: 99)!, value: 4)
    e.setIntegerValueField(CGEventField(rawValue: 137)!, value: 1)
    e.post(tap: .cghidEventTap)
    print("t1 \(now())")
} else if a[1] == "move" {
    let x = Double(a[2])!, y = Double(a[3])!, secs = Double(a[4])!
    print("t0 \(now())"); fflush(stdout)
    let n = Int(secs * 60)
    for i in 0..<n {
        let px = x + 150 * sin(Double(i) / 30.0)
        CGWarpMouseCursorPosition(CGPoint(x: px, y: y))
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: px, y: y), mouseButton: .left)!.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 1.0 / 60)
    }
    print("t1 \(now())")
}
