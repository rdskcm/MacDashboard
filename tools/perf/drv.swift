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
//        drv probe <pid> <x> <y> [inner]  -> real scroll range of the AXScrollArea under (x,y) (position change / bar change at rest),
//                                                  points per event and coast; one line "range=.. ppe=.. coast=.. x=.. y=.. inner=0|1 short=0|1"
//                                                  (exit 3 + reason on stdout when the area or its movement is not readable). No trace is attached.
//        drv goto <pid> <x> <y> start  -> move the page to the lower turn point; env as for wave
//        drv wave <pid> <x,y,events,gap>...  -> triangle wave of wheel events inside the range (env SCROLL_RANGE_PT, SCROLL_PPE,
//                                                  SCROLL_COAST_PT, SCROLL_POSLOG; optional SCROLL_POS_HZ, SCROLL_INNER, SCROLL_END_FRAC);
//                                                  prints t0 after its AX lookup and t1 at the end, logs the bar value at 10 Hz
let a = CommandLine.arguments
func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

// ---- SCROLL-BENCH-EDGES: probe / goto / wave (AX reads of the scroll bar; the range is never taken from child frame extents) ----
let gestureDy = 6.0, marginExtra = 15.0, minSpan = 60.0
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}
func role(_ e: AXUIElement) -> String { (attr(e, kAXRoleAttribute) as? String) ?? "" }
func roots(_ pid: Int32) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    let ws = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    var main: AXUIElement?
    if let m = attr(app, kAXMainWindowAttribute) { main = (m as! AXUIElement) } else { main = ws.first }
    guard let w = main else { return [] }
    var sheets = children(w).filter { role($0) == "AXSheet" }
    if let mf = frame(w) {
        for o in ws where !CFEqual(o, w) && !sheets.contains(where: { CFEqual($0, o) }) {
            if let f = frame(o), mf.insetBy(dx: -2, dy: -2).contains(f) { sheets.append(o) }
        }
    }
    return sheets + [w]
}
func firstDescendant(_ root: AXUIElement, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    var stack = Array(children(root).reversed())
    var seen = 0
    while let e = stack.popLast(), seen < 20000 {
        seen += 1
        if match(e) { return e }
        stack.append(contentsOf: children(e).reversed())
    }
    return nil
}
func findArea(_ pid: Int32, _ x: Double, _ y: Double) -> AXUIElement? {
    let pt = CGPoint(x: x, y: y)
    for r in roots(pid) {
        if let sa = firstDescendant(r, { role($0) == "AXScrollArea" && (frame($0)?.contains(pt) ?? false) }) { return sa }
    }
    return nil
}
func vbar(_ area: AXUIElement) -> AXUIElement? {
    children(area).first { role($0) == "AXScrollBar" && (attr($0, kAXOrientationAttribute) as? String) == "AXVerticalOrientation" }
}
func innerArea(_ area: AXUIElement) -> AXUIElement? {
    firstDescendant(area, { role($0) == "AXScrollArea" && vbar($0) != nil })
}
func barValue(_ bar: AXUIElement) -> Double? { (attr(bar, kAXValueAttribute) as? NSNumber)?.doubleValue }
func rest(_ bar: AXUIElement) -> Double? {
    var reads: [Double] = []
    var last: Double?
    let end = Date().addingTimeInterval(2)
    while Date() < end {
        if let v = barValue(bar) {
            last = v
            reads.append(v)
            if reads.count >= 3 {
                let t = reads.suffix(3)
                if t.max()! - t.min()! <= 0.0001 { return v }
            }
        } else { reads.removeAll() }
        Thread.sleep(forTimeInterval: 0.06)
    }
    return last
}
func contentPos(_ area: AXUIElement) -> Double? {
    guard let af = frame(area) else { return nil }
    var lo = Double.infinity
    for k in children(area) where role(k) != "AXScrollBar" { if let r = frame(k) { lo = min(lo, Double(r.minY)) } }
    return lo.isFinite ? Double(af.minY) - lo : nil
}
func post(_ x: Double, _ y: Double, wheel: Int32, phase: Int64) {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: wheel, wheel2: 0, wheel3: 0)!
    e.location = CGPoint(x: x, y: y)
    e.setIntegerValueField(CGEventField(rawValue: 99)!, value: phase)   // scrollPhase began/changed/ended
    e.setIntegerValueField(CGEventField(rawValue: 137)!, value: 1)      // isContinuous
    e.post(tap: .cghidEventTap)
}
func leg(_ x: Double, _ y: Double, _ dy: Double, _ n: Int, _ dir: Int) {   // dir +1 = down = negative wheel value
    for i in 0..<n {
        post(x, y, wheel: Int32(-Double(dir) * dy), phase: i == 0 ? 1 : 2)
        Thread.sleep(forTimeInterval: 1.0 / 60)
    }
    post(x, y, wheel: 0, phase: 4)
}
func warp(_ x: Double, _ y: Double) {
    CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
    CGAssociateMouseAndMouseCursorPosition(1)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.3)
}
func gotoPos(_ target: Double, _ x: Double, _ y: Double, _ bar: AXUIElement, _ R: Double, _ ppe: Double, _ coast: Double) {
    for _ in 0..<5 {
        guard let b = rest(bar) else { return }
        let d = target - b * R
        if abs(d) <= 15 { return }
        let n = Int((abs(d) - coast) / ppe)
        let dir = d > 0 ? 1 : -1
        if n >= 1 { leg(x, y, gestureDy, n, dir) } else { leg(x, y, 2, max(1, Int(abs(d) / 4)), dir) }
    }
}
func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
func fail(_ s: String, _ code: Int32 = 3) -> Never { print(s); fflush(stdout); exit(code) }
func waveFail(_ why: String) -> Never { FileHandle.standardError.write(("drv-error wave: " + why + "\n").data(using: .utf8)!); exit(3) }
func envD(_ k: String) -> Double? { ProcessInfo.processInfo.environment[k].flatMap { Double($0) } }
func timed(_ bar: AXUIElement) { AXUIElementSetMessagingTimeout(bar, 0.5) }
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
} else if a[1] == "probe" {
    let pid = Int32(a[2])!, x0 = Double(a[3])!, y0 = Double(a[4])!
    let wantInner = a.count > 5 && a[5] == "inner"
    guard let area = findArea(pid, x0, y0), let bar = vbar(area) else { fail("nobar") }
    timed(bar)
    var innerEl: AXUIElement? = nil, innerBar: AXUIElement? = nil
    if wantInner {
        guard let ia = innerArea(area), let ib = vbar(ia) else { fail("noinner") }
        timed(ib); innerEl = ia; innerBar = ib
    }
    warp(x0, y0)
    guard let b0 = rest(bar), let p0 = contentPos(area) else { fail("noread") }
    let first = b0 <= 0.5 ? 1 : -1
    leg(x0, y0, gestureDy, 12, first)
    guard let b1 = rest(bar), let p1 = contentPos(area) else { fail("noread") }
    if abs(b1 - b0) < 0.0005 || abs(p1 - p0) < 2 { fail("nomove") }
    let R = abs(p1 - p0) / abs(b1 - b0)
    if R < 100 { fail(String(format: "range=%.1f short=1", R), 0) }
    leg(x0, y0, gestureDy, 8, -first)
    guard var cur = rest(bar) else { fail("noread") }
    let n2 = min(max(Int(0.45 * R / 6), 12), 60), n1 = max(4, n2 / 3)
    leg(x0, y0, gestureDy, n2, first)
    guard let c2 = rest(bar) else { fail("noread") }
    let d2 = abs(c2 - cur) * R; cur = c2
    leg(x0, y0, gestureDy, n1, -first)
    guard let c1 = rest(bar) else { fail("noread") }
    let d1 = abs(c1 - cur) * R
    let ppe = (d2 - d1) / Double(n2 - n1)
    let coast = clamp(d1 - Double(n1) * ppe, 0, 100)
    if ppe <= 0 || ppe > 18 { fail(String(format: "badcal ppe=%.3f", ppe)) }
    let m = coast + marginExtra, lo = m, hi = R - m
    if hi - lo < minSpan { fail(String(format: "range=%.1f short=1", R), 0) }
    gotoPos(lo, x0, y0, bar, R, ppe, coast)
    guard let ia = innerEl, let ib = innerBar else {
        print(String(format: "range=%.1f ppe=%.3f coast=%.1f x=%.0f y=%.0f inner=0 short=0", R, ppe, coast, x0, y0))
        exit(0)
    }
    guard let af = frame(area), let pb = rest(bar), let inf = frame(ia) else { fail("noread") }
    let pPage = clamp(pb * R + Double(inf.minY) - (Double(af.minY) + 40), lo, hi)
    gotoPos(pPage, x0, y0, bar, R, ppe, coast)
    guard let inf2 = frame(ia) else { fail("noread") }
    let x = Double(inf2.midX), y = min(Double(inf2.midY), Double(af.maxY) - 20)
    warp(x, y)
    guard let b0i = rest(ib) else { fail("noread") }
    leg(x, y, gestureDy, 60, 1)
    guard let b1i = rest(ib) else { fail("noread") }
    if b1i - b0i < 0.0005 { fail("nomove inner") }
    let Ri = (60 * ppe + coast) / (b1i - b0i)
    if Ri - 2 * m < minSpan { fail(String(format: "range=%.1f short=1", Ri), 0) }
    print(String(format: "range=%.1f ppe=%.3f coast=%.1f x=%.0f y=%.0f inner=1 short=0", Ri, ppe, coast, x, y))
} else if a[1] == "goto" || a[1] == "wave" {
    let isWave = a[1] == "wave"
    let env = ProcessInfo.processInfo.environment
    func bad(_ why: String) -> Never { isWave ? waveFail(why) : fail("drv-error goto: " + why) }
    let pid = Int32(a[2])!
    struct Seg { var x: Double; var y: Double; var events: Int; var gap: Double }
    var segs: [Seg] = []
    if isWave {
        for s in a[3...] {
            let f = s.split(separator: ",").compactMap { Double(String($0)) }
            guard f.count == 4 else { bad("bad segment \(s)") }
            segs.append(Seg(x: f[0], y: f[1], events: Int(f[2]), gap: f[3]))
        }
        guard !segs.isEmpty else { bad("no segment") }
    } else {
        guard a.count > 5, let gx = Double(a[3]), let gy = Double(a[4]) else { bad("usage: goto <pid> <x> <y> start") }
        segs = [Seg(x: gx, y: gy, events: 0, gap: 0)]
    }
    guard let R = envD("SCROLL_RANGE_PT"), let ppe = envD("SCROLL_PPE"), let coast = envD("SCROLL_COAST_PT"), R > 0, ppe > 0 else { bad("SCROLL_RANGE_PT / SCROLL_PPE / SCROLL_COAST_PT missing") }
    let hz = envD("SCROLL_POS_HZ") ?? 10
    guard hz > 0 else { bad("bad SCROLL_POS_HZ") }
    guard let page = findArea(pid, segs[0].x, segs[0].y) else { bad("no scroll area under \(segs[0].x),\(segs[0].y)") }
    var area = page
    if env["SCROLL_INNER"] == "1" { guard let ia = innerArea(page) else { bad("no inner scroll area") }; area = ia }
    guard let bar = vbar(area) else { bad("no vertical scroll bar") }
    timed(bar)
    let m = coast + marginExtra, lo = m, hi = R - m
    if !isWave {
        warp(segs[0].x, segs[0].y)
        gotoPos(lo, segs[0].x, segs[0].y, bar, R, ppe, coast)
        exit(0)
    }
    guard let logPath = env["SCROLL_POSLOG"], !logPath.isEmpty else { bad("SCROLL_POSLOG missing") }
    guard FileManager.default.createFile(atPath: logPath, contents: nil), let h = FileHandle(forWritingAtPath: logPath) else { bad("cannot open \(logPath)") }
    let lock = NSLock()
    final class Flags: @unchecked Sendable { var active = false, stop = false, closed = false }   // guarded by lock
    let fl = Flags()
    func wr(_ s: String) { lock.lock(); if !fl.closed { h.write(s.data(using: .utf8)!) }; lock.unlock() }
    func epoch() -> Double { Date().timeIntervalSince1970 }
    wr(String(format: "# range=%.1f ppe=%.3f coast=%.1f hz=%g lo=%.1f hi=%.1f\n", R, ppe, coast, hz, lo, hi))
    let th = Thread {
        while true {
            lock.lock(); let s = fl.stop, act = fl.active; lock.unlock()
            if s { return }
            if act {
                if let v = barValue(bar) { wr(String(format: "P %.3f %.5f\n", epoch(), v)) }
                Thread.sleep(forTimeInterval: 1.0 / hz)
            } else { Thread.sleep(forTimeInterval: 0.05) }
        }
    }
    th.start()
    print("t0 \(now())"); fflush(stdout)
    var dir = 0
    var p = 0.0
    for (si, sg) in segs.enumerated() {
        warp(sg.x, sg.y)
        if let b = barValue(bar) { p = b * R }
        if si == 0 { dir = p < R / 2 ? 1 : -1 }
        wr(String(format: "S %.3f\n", epoch()))
        lock.lock(); fl.active = true; lock.unlock()
        for i in 0..<sg.events {
            if dir > 0 && p + ppe > hi { dir = -1 }
            if dir < 0 && p - ppe < lo { dir = 1 }
            post(sg.x, sg.y, wheel: Int32(-Double(dir) * gestureDy), phase: i == 0 ? 1 : 2)
            p += Double(dir) * ppe
            Thread.sleep(forTimeInterval: 1.0 / 60)
        }
        post(sg.x, sg.y, wheel: 0, phase: 4)
        lock.lock(); fl.active = false; lock.unlock()
        wr(String(format: "E %.3f\n", epoch()))
        p += Double(dir) * coast
        Thread.sleep(forTimeInterval: sg.gap)
    }
    if let fr = envD("SCROLL_END_FRAC") {
        let last = segs[segs.count - 1]
        gotoPos(clamp(fr * R, lo, hi), last.x, last.y, bar, R, ppe, coast)
    }
    lock.lock(); fl.stop = true; lock.unlock()
    Thread.sleep(forTimeInterval: 0.01)
    lock.lock(); fl.closed = true; h.closeFile(); lock.unlock()
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
