import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
// tools/perf helper, compiled by gate.sh into $OUT/.bin/ax (never run from here). Native AX by pid
// (AXUIElementCreateApplication) for every gate UI action. It replaces the old AppleScript helper, whose process lookup
// `first process whose unix id is <pid>` returned another MacDashboard process's window contents when two ran
// (GATE-AX-MISS, 2026-10-30), so the gate pressed buttons in the wrong app.
// usage: ax <pid> <kind> [value]          (trusted and focused ignore pid; pass 0)
//   id <AXIdentifier>[|alt...]       press (AXPress) the first AXButton / AXRadioButton of window 1 whose AXIdentifier is a value
//   title <text>[|alt...]            press the first AXButton / AXRadioButton whose AXTitle or AXDescription is a value
//                                    (pass both languages: "Таблица|Table")
//   frame <AXIdentifier>[|alt...]    "x y w h" (integers, global top-left points) of the first element with that identifier
//   exists <AXIdentifier>[|alt...]   "present" | "absent"
//   enabled <AXIdentifier>[|alt...]  "enabled" | "disabled" for the first element with that identifier, else "absent"
//   vscroll <x>,<y>                  first AXScrollArea of window 1 whose frame contains the global point: "bar" when it has
//                                    a vertical AXScrollBar child (its content overflows), else "nobar"
//   pin                              window 1 to (0, 29) 1000x733, then the verify check: "pinned" | "MISMATCH ..." | "no window"
//   verify [cgpid]                   "match x y w h" when window 1's AX frame equals (within 2 pt) a layer-0 on-screen CG
//                                    window of cgpid (default: pid), else "MISMATCH ax=... cg=..." | "no window"
//   front                            set AXFrontmost and activate the app; "front" once pid is the focused application (<= 1 s), else "NOT FRONT (...)"
//   focused                          pid of the focused application (NSWorkspace frontmost application), or "none"
//   trusted                          "trusted" | "untrusted": AXIsProcessTrusted() (the grant of the terminal app running the gate)
//   dump                             "windows: <n>", "window 1 @ x,y wxh", then "<id> <AXRole> @ x,y wxh" per element of window 1
//                                    with a non-empty AXIdentifier
// Window 1 = the app's main window (mainWindow()): the AXWindows element whose AXMain is true, else the first AXStandardWindow,
// else the largest by AX frame area (tooltips and overlays are extra, small AXWindows entries). Elements are searched depth-first in AXChildren order (as
// AppleScript's `entire contents`), at most 20000. "NOT FOUND" when nothing matches or the app has no window.
// Prints one result and exits 0; a usage error exits 64.

func usage() -> Never {
    FileHandle.standardError.write("usage: ax <pid> <kind> [value]\n".data(using: .utf8)!)
    exit(64)
}
func out(_ s: String) -> Never { print(s); exit(0) }

let a = CommandLine.arguments
guard a.count >= 3, let pid = Int32(a[1]) else { usage() }
let kind = a[2]
let value = a.count > 3 ? a[3] : ""
let alts = value.split(separator: "|").map(String.init)
let app = AXUIElementCreateApplication(pid)

func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ n: String) -> String { (attr(e, n) as? String) ?? "" }
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}
func n(_ v: CGFloat) -> Int { Int(v.rounded()) }
func geo(_ f: CGRect?) -> String {   // "x,y wxh"
    guard let f = f else { return "?" }
    return "\(n(f.minX)),\(n(f.minY)) \(n(f.width))x\(n(f.height))"
}
func near(_ p: CGRect, _ q: CGRect) -> Bool {
    abs(p.minX - q.minX) <= 2 && abs(p.minY - q.minY) <= 2 && abs(p.width - q.width) <= 2 && abs(p.height - q.height) <= 2
}
func windows() -> [AXUIElement] { (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
func mainWindow() -> AXUIElement? {
    let ws = windows()
    if let m = ws.first(where: { (attr($0, kAXMainAttribute) as? Bool) == true }) { return m }
    if let s = ws.first(where: { str($0, kAXSubroleAttribute) == "AXStandardWindow" }) { return s }
    func area(_ w: AXUIElement) -> CGFloat { frame(w).map { $0.width * $0.height } ?? 0 }
    return ws.max(by: { area($0) < area($1) })
}
// Depth-first, pre-order (AXChildren order); the first element for which match is true.
func find(_ root: AXUIElement, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    var stack = Array(children(root).reversed())
    var seen = 0
    while let e = stack.popLast(), seen < 20000 {
        seen += 1
        if match(e) { return e }
        stack.append(contentsOf: children(e).reversed())
    }
    return nil
}
func hasID(_ e: AXUIElement) -> Bool { let id = str(e, "AXIdentifier"); return !id.isEmpty && alts.contains(id) }
func cgFrames(_ p: Int32) -> [CGRect] {
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    return list.compactMap { w -> CGRect? in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == p, (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: b as CFDictionary)
    }
}
func verify(_ w: AXUIElement, against p: Int32) -> String {
    guard let f = frame(w) else { return "no window" }
    let cg = cgFrames(p)
    if let m = cg.first(where: { near($0, f) }) { return "match \(n(m.minX)) \(n(m.minY)) \(n(m.width)) \(n(m.height))" }
    return "MISMATCH ax=\(geo(f)) cg=\(cg.isEmpty ? "none" : cg.map { geo($0) }.joined(separator: ";")) (cg pid \(p))"
}
func focusedPid() -> Int32? {
    NSWorkspace.shared.frontmostApplication?.processIdentifier
}

switch kind {
case "trusted":
    out(AXIsProcessTrusted() ? "trusted" : "untrusted")
case "focused":
    out(focusedPid().map { String($0) } ?? "none")
case "front":
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    NSRunningApplication(processIdentifier: pid)?.activate()
    for _ in 0..<10 {
        if focusedPid() == pid { out("front") }
        Thread.sleep(forTimeInterval: 0.1)
    }
    out("NOT FRONT (focused pid \(focusedPid().map { String($0) } ?? "none"))")
case "pin":
    guard let w = mainWindow() else { out("no window") }
    var p = CGPoint(x: 0, y: 29), s = CGSize(width: 1000, height: 733)
    let target = CGRect(origin: p, size: s)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    // The window server applies the frame asynchronously: poll up to 2 s for AX frame = target = an on-screen CG frame.
    var last = ""
    for _ in 0..<20 {
        last = verify(w, against: pid)
        if last.hasPrefix("match"), let f = frame(w), near(f, target) { out("pinned") }
        Thread.sleep(forTimeInterval: 0.1)
    }
    // AX and CG agree but not at the target: "pinned", and gate.sh's CG frame check reports the wrong frame (exit 70).
    out(last.hasPrefix("match") ? "pinned" : last)
case "verify":
    guard let w = mainWindow() else { out("no window") }
    var p = pid
    if !value.isEmpty { guard let v = Int32(value) else { usage() }; p = v }
    out(verify(w, against: p))
case "vscroll":
    let xy = value.split(separator: ",").compactMap { Double(String($0)) }
    guard xy.count == 2 else { usage() }
    guard let w = mainWindow() else { out("NOT FOUND") }
    let pt = CGPoint(x: xy[0], y: xy[1])
    guard let sa = find(w, { str($0, kAXRoleAttribute) == "AXScrollArea" && (frame($0)?.contains(pt) ?? false) }) else { out("NOT FOUND") }
    let vertical = children(sa).contains {
        str($0, kAXRoleAttribute) == "AXScrollBar" && str($0, kAXOrientationAttribute) == "AXVerticalOrientation"
    }
    out(vertical ? "bar" : "nobar")
case "frame", "exists", "enabled":
    guard !alts.isEmpty else { usage() }
    let miss = kind == "frame" ? "NOT FOUND" : "absent"
    guard let w = mainWindow(), let e = find(w, hasID) else { out(miss) }
    if kind == "exists" { out("present") }
    if kind == "enabled" { out((attr(e, kAXEnabledAttribute) as? Bool) == true ? "enabled" : "disabled") }
    guard let f = frame(e) else { out("NOT FOUND") }
    out("\(n(f.minX)) \(n(f.minY)) \(n(f.width)) \(n(f.height))")
case "id", "title":
    guard !alts.isEmpty else { usage() }
    guard let w = mainWindow() else { out("NOT FOUND") }
    let hit = find(w) { e in
        let role = str(e, kAXRoleAttribute)
        guard role == "AXButton" || role == "AXRadioButton" else { return false }
        if kind == "id" { return hasID(e) }
        let t = str(e, kAXTitleAttribute), d = str(e, kAXDescriptionAttribute)
        return (!t.isEmpty && alts.contains(t)) || (!d.isEmpty && alts.contains(d))
    }
    guard let e = hit else { out("NOT FOUND") }
    let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
    out(err == .success ? "pressed" : "PRESS FAILED (AXError \(err.rawValue))")
case "dump":
    let ws = windows()
    var lines = ["windows: \(ws.count)"]
    if let w = mainWindow() {
        lines.append("window 1 @ \(geo(frame(w)))")
        _ = find(w) { e in
            let id = str(e, "AXIdentifier")
            if !id.isEmpty { lines.append("\(id) \(str(e, kAXRoleAttribute)) @ \(geo(frame(e)))") }
            return false
        }
    }
    out(lines.joined(separator: "\n"))
default:
    usage()
}
