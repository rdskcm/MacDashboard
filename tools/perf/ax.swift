import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
// tools/perf helper, compiled by gate.sh and tools/visual/smoke.sh into their $OUT/.bin/ax (never run from here). Native AX by pid
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
//   place <x>,<y>,<w>,<h>            window 1 to that frame (global top-left points), same poll as pin: "placed" | "off x y w h"
//                                    (AX and CG agree on another frame) | "MISMATCH ..." | "no window"
//   main                             "x y w h" of the AXWindows element whose AXMain is true | "notmain" | "no window"
//   appmenu <prefix>[|alt...]        press the first item of the application menu (menu bar item index 1) whose AXTitle
//                                    starts with a value: "pressed" | "NOT FOUND: <titles|...>" | "PRESS FAILED (...)"
//   closewin <x>,<y>,<w>,<h>         press the AXCloseButton (direct child AXButton) of the AXWindows element whose frame is
//                                    within 2 pt of that frame: "pressed" | "no window" | "NOT FOUND" | "PRESS FAILED (...)"
//   verify [cgpid]                   "match x y w h" when window 1's AX frame equals (within 2 pt) a layer-0 on-screen CG
//                                    window of cgpid (default: pid), else "MISMATCH ax=... cg=..." | "no window"
//   front                            set AXFrontmost and activate the app; "front" once pid is the focused application (<= 1 s), else "NOT FRONT (...)"
//   focused                          pid of the focused application (NSWorkspace frontmost application), or "none"
//   trusted                          "trusted" | "untrusted": AXIsProcessTrusted() (the grant of the terminal app running the gate)
//   dump                             "windows: <n>", "window 1 @ x,y wxh", then "<id> <AXRole> @ x,y wxh" per element of window 1
//                                    with a non-empty AXIdentifier
//   text <x>,<y>,<w>,<h>             visible strings of the AXWindows element whose frame is within 2 pt of that frame (plus
//                                    its sheets), one per line in reading order (SMOKE-TEXT-NOISE D4-D7) | "NO TEXT" | "no window"
//                                    An element only partly inside the clip contributes just its visible part of AXValue: AXStringForRange of
//                                    AXVisibleCharacterRange, else the \n-lines whose AXBoundsForRange meets the clip, else the whole value
//                                    plus "PARTIAL-CLIP <role>" on stderr (SMOKE-TEXT-NOISE R11); an AXValue equal to a descendant's is read
//                                    from the deepest element only (Amendment 1a)
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
// Sets w's frame, then polls up to 2 s (the window server applies it asynchronously) for AX frame = target = an
// on-screen CG frame of pid. nil when settled at the target, else the last verify() answer.
func setFrame(_ w: AXUIElement, _ target: CGRect) -> String? {
    var p = target.origin, s = target.size
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    var last = ""
    for _ in 0..<20 {
        last = verify(w, against: pid)
        if last.hasPrefix("match"), let f = frame(w), near(f, target) { return nil }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return last
}
func rect(_ v: String) -> CGRect {   // "x,y,w,h" -> CGRect, else usage
    let xs = v.split(separator: ",").compactMap { Double(String($0)) }
    guard xs.count == 4 else { usage() }
    return CGRect(x: xs[0], y: xs[1], width: xs[2], height: xs[3])
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
    guard let last = setFrame(w, CGRect(x: 0, y: 29, width: 1000, height: 733)) else { out("pinned") }
    // AX and CG agree but not at the target: "pinned", and gate.sh's CG frame check reports the wrong frame (exit 70).
    out(last.hasPrefix("match") ? "pinned" : last)
case "place":
    let target = rect(value)
    guard let w = mainWindow() else { out("no window") }
    guard let last = setFrame(w, target) else { out("placed") }
    out(last.hasPrefix("match ") ? "off " + String(last.dropFirst(6)) : last)
case "main":
    let ws = windows()
    guard !ws.isEmpty else { out("no window") }
    guard let m = ws.first(where: { (attr($0, kAXMainAttribute) as? Bool) == true }), let f = frame(m) else { out("notmain") }
    out("\(n(f.minX)) \(n(f.minY)) \(n(f.width)) \(n(f.height))")
case "appmenu":
    guard !alts.isEmpty else { usage() }
    guard let barRef = attr(app, kAXMenuBarAttribute), CFGetTypeID(barRef) == AXUIElementGetTypeID() else { out("NOT FOUND: no menu bar") }
    let barItems = children(barRef as! AXUIElement)
    guard barItems.count > 1, let menu = children(barItems[1]).first else { out("NOT FOUND: no application menu") }
    let entries = children(menu)
    let titles = entries.map { str($0, kAXTitleAttribute) }
    guard let i = titles.firstIndex(where: { t in !t.isEmpty && alts.contains { t.hasPrefix($0) } }) else {
        out("NOT FOUND: " + titles.joined(separator: "|"))
    }
    let err = AXUIElementPerformAction(entries[i], kAXPressAction as CFString)
    out(err == .success ? "pressed" : "PRESS FAILED (AXError \(err.rawValue))")
case "closewin":
    let target = rect(value)
    guard let w = windows().first(where: { win in frame(win).map { near($0, target) } ?? false }) else { out("no window") }
    guard let b = children(w).first(where: {
        str($0, kAXRoleAttribute) == "AXButton" && str($0, kAXSubroleAttribute) == "AXCloseButton"
    }) else { out("NOT FOUND") }
    let err = AXUIElementPerformAction(b, kAXPressAction as CFString)
    out(err == .success ? "pressed" : "PRESS FAILED (AXError \(err.rawValue))")
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
case "text":
    // SMOKE-TEXT-NOISE: the visible text of the captured window for smoke's text check. Visible (D4): a frame with
    // positive area that intersects the window frame and every AXScrollArea ancestor's frame, no AXHidden on the path,
    // and (outside a sheet) not lying entirely inside a sheet's frame. Strings (D5): distinct non-empty AXValue (String
    // only), AXTitle, AXDescription, whitespace runs folded to one space. Order (D7): minY, minX, depth-first index.
    // R11: an element whose frame is not entirely inside the clip (one multi-line text box in a scroll view) gives only its
    // visible part of AXValue, see visibleValue.
    let target = rect(value)
    let ws = windows()
    guard let root = ws.first(where: { w in frame(w).map { near($0, target) } ?? false }),
          let rootFrame = frame(root) else { out("no window") }
    var sheets = children(root).filter { str($0, kAXRoleAttribute) == "AXSheet" }
    for w in ws where !CFEqual(w, root) && !sheets.contains(where: { CFEqual($0, w) }) {
        if let f = frame(w), target.insetBy(dx: -2, dy: -2).contains(f) { sheets.append(w) }
    }
    let sheetFrames = sheets.compactMap { frame($0) }
    var items: [(y: Int, x: Int, i: Int, s: String)] = []
    var visited = 0
    func fold(_ s: String) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    // SwiftUI Text + .textSelection exposes two nested AXStaticText with one AXValue; only the deepest is read (R11 / Amendment 1a).
    func descendantHasValue(_ e: AXUIElement, _ value: String) -> Bool {
        var budget = 200
        func scan(_ x: AXUIElement) -> Bool {
            for c in children(x) {
                guard budget > 0 else { return false }
                budget -= 1
                if (attr(c, "AXHidden") as? Bool) == true { continue }
                if (attr(c, kAXValueAttribute) as? String) == value || scan(c) { return true }
            }
            return false
        }
        return scan(e)
    }
    func axRange(_ r: CFRange) -> AXValue? { var r = r; return AXValueCreate(.cfRange, &r) }
    func visibleValue(_ e: AXUIElement, _ full: String, clip: CGRect) -> String {
        var names: CFArray?
        _ = AXUIElementCopyAttributeNames(e, &names)
        let attrNames = (names as? [String]) ?? []
        names = nil
        _ = AXUIElementCopyParameterizedAttributeNames(e, &names)
        let paramNames = (names as? [String]) ?? []
        func param(_ name: String, _ r: CFRange) -> AnyObject? {
            guard let p = axRange(r) else { return nil }
            var v: CFTypeRef?
            return AXUIElementCopyParameterizedAttributeValue(e, name as CFString, p, &v) == .success ? v : nil
        }
        if attrNames.contains("AXVisibleCharacterRange"), paramNames.contains("AXStringForRange"),
           let rv = attr(e, "AXVisibleCharacterRange"), CFGetTypeID(rv) == AXValueGetTypeID() {
            var r = CFRange()
            // SwiftUI reports the whole string as the visible range even inside a scroll view: such a range carries no clip.
            if AXValueGetValue(rv as! AXValue, .cfRange, &r), r.length > 0, r.length < (full as NSString).length,
               let s = param("AXStringForRange", r) as? String { return s }
        }
        if paramNames.contains("AXBoundsForRange") {
            let ns = full as NSString
            var kept: [String] = []
            var start = 0
            for line in full.components(separatedBy: "\n") {
                let len = (line as NSString).length
                defer { start += len + 1 }
                if fold(line).isEmpty { continue }
                guard let bv = param("AXBoundsForRange", CFRange(location: start, length: len)),
                      CFGetTypeID(bv) == AXValueGetTypeID() else { continue }
                var b = CGRect.zero
                if AXValueGetValue(bv as! AXValue, .cgRect, &b), b.width > 0, b.height > 0 {
                    let i = b.intersection(clip)
                    if !i.isNull && i.width > 0 && i.height > 0 { kept.append(ns.substring(with: NSRange(location: start, length: len))) }
                }
            }
            return kept.joined(separator: "\n")
        }
        FileHandle.standardError.write("PARTIAL-CLIP \(str(e, kAXRoleAttribute))\n".data(using: .utf8)!)
        return full
    }
    func walk(_ e: AXUIElement, clip: CGRect, inSheet: Bool) {
        guard visited < 20000 else { return }
        visited += 1
        if (attr(e, "AXHidden") as? Bool) == true { return }
        if !inSheet && sheets.contains(where: { CFEqual($0, e) }) { return }   // walked as its own root below
        let f = frame(e)
        if !inSheet, let f = f, sheetFrames.contains(where: { $0.contains(f) }) { return }   // covered by the sheet
        var inner = clip
        if str(e, kAXRoleAttribute) == "AXScrollArea", let f = f { inner = clip.intersection(f) }
        if let f = f, f.width > 0, f.height > 0 {
            let v = f.intersection(clip)
            if !v.isNull && v.width > 0 && v.height > 0 {
                var got: [String] = []
                var value = (attr(e, kAXValueAttribute) as? String) ?? ""
                if !value.isEmpty && descendantHasValue(e, value) { value = "" }   // the deepest element carrying the string wins
                if !value.isEmpty && v != f { value = visibleValue(e, value, clip: clip) }
                for s in [value, str(e, kAXTitleAttribute), str(e, kAXDescriptionAttribute)] {
                    let t = fold(s)
                    if !t.isEmpty && !got.contains(t) { got.append(t) }
                }
                for t in got { items.append((y: n(f.minY), x: n(f.minX), i: items.count, s: t)) }
            }
        }
        for c in children(e) { walk(c, clip: inner, inSheet: inSheet) }
    }
    for c in children(root) { walk(c, clip: rootFrame, inSheet: false) }
    for s in sheets {
        guard let sf = frame(s) else { continue }
        for c in children(s) { walk(c, clip: sf.intersection(rootFrame), inSheet: true) }
    }
    guard !items.isEmpty else { out("NO TEXT") }
    items.sort { ($0.y, $0.x, $0.i) < ($1.y, $1.x, $1.i) }
    out(items.map { $0.s }.joined(separator: "\n"))
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
