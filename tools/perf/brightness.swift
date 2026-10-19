// tools/perf/brightness.swift — main-display brightness for tools/perf/night.sh (compiled by it; never run from here).
// usage: brightness get | brightness set <0..1>
// Method 1: DisplayServices (private framework, dlopen; the method of the open-source `brightness` CLI,
//           github.com/nriley/brightness, on Apple Silicon). Method 2: IOKit IODisplayGet/SetFloatParameter with
//           kIODisplayBrightnessKey (public, deprecated; Intel-era built-in panels).
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
func fail(_ msg: String, _ code: Int32) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(code) }
func ok(_ v: Float, _ m: String) -> Never { print(String(format: "%.3f", v) + " " + m); exit(0) }

let a = CommandLine.arguments
guard a.count >= 2 else { fail("usage: brightness get | brightness set <0..1>", 64) }
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
default:
    fail("usage: brightness get | brightness set <0..1>", 64)
}
