import Foundation
import CoreGraphics
import ApplicationServices
// tools/perf helper, compiled by gate.sh into $OUT/.bin/drv (never run from here). Marks are epoch seconds.
// usage: drv winfo <pid>            -> prints window frame
//        drv scroll x y secs dy [gap] [phase]  -> trackpad-like gesture (began/changed/ended), prints t0
//        drv move x y secs         -> sweep pointer horizontally around x,y for secs
//        drv resize <pid> <w0> <w1> <secs> [cycles] -> AX-set the first window's width w0 -> w1 -> w0 ... at 60 Hz
//                                                  (height unchanged), prints t0 / t1; exit 1 + "drv-error resize: ..." on stderr when an AX
//                                                  call fails or the final width is off by more than 2 pt
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
} else if a[1] == "resize" {
    let pid = Int32(a[2])!, w0 = Double(a[3])!, w1 = Double(a[4])!, secs = Double(a[5])!
    let cycles = a.count > 6 ? Int(a[6])! : 2
    func axFail(_ why: String) -> Never { FileHandle.standardError.write(("drv-error resize: " + why + "\n").data(using: .utf8)!); exit(1) }
    let app = AXUIElementCreateApplication(pid)
    var wins: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wins)
    guard err == .success, let win = (wins as? [AXUIElement])?.first else { axFail("no window (AXError \(err.rawValue))") }
    func readSize() -> CGSize {
        var sz: CFTypeRef?
        let e = AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sz)
        guard e == .success, let v = sz, CFGetTypeID(v) == AXValueGetTypeID() else { axFail("size not readable (AXError \(e.rawValue))") }
        var s = CGSize.zero
        // the type id is checked above, so the bit cast is a plain CF downcast (no force cast that could trap)
        guard AXValueGetValue(unsafeBitCast(v, to: AXValue.self), .cgSize, &s) else { axFail("size value is not a CGSize") }
        return s
    }
    let cur = readSize()
    let hz = 60.0, nLeg = max(1, Int(secs * hz))
    var setFailures = 0
    print("t0 \(now())"); fflush(stdout)
    for leg in 0..<(cycles * 2) {
        let (from, to) = leg % 2 == 0 ? (w0, w1) : (w1, w0)
        for i in 0...nLeg {
            var s = CGSize(width: from + (to - from) * Double(i) / Double(nLeg), height: cur.height)
            guard let v = AXValueCreate(.cgSize, &s) else { axFail("AXValueCreate failed") }
            if AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) != .success { setFailures += 1 }
            Thread.sleep(forTimeInterval: 1.0 / hz)
        }
    }
    print("t1 \(now())")
    let final = readSize()
    if setFailures > 0 { axFail("\(setFailures) of \((cycles * 2) * (nLeg + 1)) AX size sets failed") }
    if abs(final.width - w0) > 2 { axFail(String(format: "final width %.0f pt, expected %.0f", final.width, w0)) }
}
