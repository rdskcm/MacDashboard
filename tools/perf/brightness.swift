// tools/perf/brightness.swift — main-display brightness for tools/perf/night.sh (compiled by it; never run from here).
// usage: brightness get | set <0..1> | kbd-get | kbd-set <0..1> | brightness kbd-get | brightness kbd-set <0..1>
// Method 1: DisplayServices (private framework, dlopen; the method of the open-source `brightness` CLI,
//           github.com/nriley/brightness, on Apple Silicon). Method 2: IOKit IODisplayGet/SetFloatParameter with
//           kIODisplayBrightnessKey (public, deprecated; Intel-era built-in panels).
// Keyboard backlight: CoreBrightness KeyboardBrightnessClient (private framework, dlopen + ObjC runtime; the route of the open-source mac-brightnessctl). No Apple CLI or public API sets the keyboard backlight.
// Every set is verified by reading back. Exit 0 ok ("<value> <method>"), 2 not readable/settable here, 64 usage.
import Foundation
import CoreGraphics
import IOKit
import IOKit.graphics

typealias DSGet = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
typealias DSSet = @convention(c) (UInt32, Float) -> Int32
let display = CGMainDisplayID()
let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

func dsGet() -> Float? {
    guard let ds, let s = dlsym(ds, "DisplayServicesGetBrightness") else { return nil }
    var v: Float = -1
    return unsafeBitCast(s, to: DSGet.self)(display, &v) == 0 && v >= 0 ? v : nil
}
func dsSet(_ v: Float) -> Bool {
    guard let ds, let s = dlsym(ds, "DisplayServicesSetBrightness") else { return false }
    return unsafeBitCast(s, to: DSSet.self)(display, v) == 0
}
func ioService() -> io_service_t? {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    let s = IOIteratorNext(it)
    return s == 0 ? nil : s
}
func ioGet() -> Float? {
    guard let s = ioService() else { return nil }
    defer { IOObjectRelease(s) }
    var v: Float = 0
    return IODisplayGetFloatParameter(s, 0, kIODisplayBrightnessKey as CFString, &v) == kIOReturnSuccess ? v : nil
}
func ioSet(_ v: Float) -> Bool {
    guard let s = ioService() else { return false }
    defer { IOObjectRelease(s) }
    return IODisplaySetFloatParameter(s, 0, kIODisplayBrightnessKey as CFString, v) == kIOReturnSuccess
}
typealias KBGet = @convention(c) (AnyObject, Selector, UInt64) -> Float
typealias KBSet = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
func kbClient() -> (NSObject, UInt64)? {
    guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
          let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
    let c = cls.init()
    var id: UInt64 = 1                                   // built-in keyboard when the ID list is unavailable
    let ids = NSSelectorFromString("copyKeyboardBacklightIDs")
    if c.responds(to: ids), let arr = c.perform(ids)?.takeRetainedValue() as? [NSNumber], let first = arr.first { id = first.uint64Value }
    return (c, id)
}
func kbGet() -> Float? {
    guard let k = kbClient() else { return nil }
    let sel = NSSelectorFromString("brightnessForKeyboard:")
    guard k.0.responds(to: sel) else { return nil }
    let v = unsafeBitCast(k.0.method(for: sel), to: KBGet.self)(k.0, sel, k.1)
    return v >= 0 && v <= 1 ? v : nil
}
func kbSet(_ v: Float) -> Bool {
    guard let k = kbClient() else { return false }
    let sel = NSSelectorFromString("setBrightness:forKeyboard:")
    guard k.0.responds(to: sel) else { return false }
    return unsafeBitCast(k.0.method(for: sel), to: KBSet.self)(k.0, sel, v, k.1)
}
func fail(_ msg: String, _ code: Int32) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(code) }
func ok(_ v: Float, _ m: String) -> Never { print(String(format: "%.3f", v) + " " + m); exit(0) }

let a = CommandLine.arguments
guard a.count >= 2 else { fail("usage: brightness get | set <0..1> | kbd-get | kbd-set <0..1>", 64) }
switch a[1] {
case "get":
    if let v = dsGet() { ok(v, "displayservices") }
    if let v = ioGet() { ok(v, "iokit") }
    fail("brightness: not readable on main display \(display)", 2)
case "set":
    guard a.count == 3, let t = Float(a[2]), (0...1).contains(t) else { fail("usage: brightness set <0..1>", 64) }
    let methods: [(String, () -> Float?, (Float) -> Bool)] = [("displayservices", dsGet, dsSet), ("iokit", ioGet, ioSet)]
    for (name, get, set) in methods where get() != nil {
        guard set(t) else { fail("brightness: \(name) set failed", 2) }
        usleep(300_000)
        guard let rb = get(), abs(rb - t) <= 0.02 else { fail("brightness: \(name) read back \(get() ?? -1) after set \(t)", 2) }
        ok(rb, name)
    }
    fail("brightness: not settable on main display \(display)", 2)
case "kbd-get":
    if let v = kbGet() { ok(v, "corebrightness") }
    fail("brightness: keyboard backlight not readable (CoreBrightness KeyboardBrightnessClient unavailable)", 2)
case "kbd-set":
    guard a.count == 3, let t = Float(a[2]), (0...1).contains(t) else { fail("usage: brightness kbd-set <0..1>", 64) }
    guard kbGet() != nil else { fail("brightness: keyboard backlight not settable (CoreBrightness KeyboardBrightnessClient unavailable)", 2) }
    guard kbSet(t) else { fail("brightness: corebrightness keyboard set failed", 2) }
    for _ in 0..<10 { usleep(200_000); if let rb = kbGet(), abs(rb - t) <= 0.02 { ok(rb, "corebrightness") } }
    fail("brightness: corebrightness keyboard read back \(kbGet() ?? -1) after set \(t)", 2)
default:
    fail("usage: brightness get | set <0..1> | kbd-get | kbd-set <0..1>", 64)
}
