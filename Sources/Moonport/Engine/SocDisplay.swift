// Engine/SocDisplay.swift
// SOC-DETAILS Stage 5a: the precision the SoC page shows, and equality at that precision. The page tick writes an
// observed field only when the screen would differ (findings round 2: publishing values that change below the shown
// precision cost ~1.25 pp).
import Foundation

enum SocDisplay {
    static let shareDecimals = 1      // GPU row share, "12.3 %"
    static let ghzDecimals = 2        // group frequency, "3.95 GHz"
    static let powerDecimals = 1      // whole-Mac power, "6.8 W"
    static let splitDecimals = 1      // CPU user / system / idle, "16.0 %"

    /// The value `fmtFixed(v, decimals:)` shows, as a Double: the same `%.Nf` formatting (correct rounding of the
    /// binary value), so `rounded(a) == rounded(b)` exactly when the two texts are equal.
    static func rounded(_ v: Double, decimals: Int) -> Double {
        Double(String(format: "%.\(decimals)f", v)) ?? v
    }

    /// nil == nil; nil != a value; two values are the same when their shown texts are.
    static func sameOnScreen(_ a: Double?, _ b: Double?, decimals: Int) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return rounded(a, decimals: decimals) == rounded(b, decimals: decimals)
        default: return false
        }
    }

    /// `.mhz` is shown as GHz with `ghzDecimals`; every other case compares as itself.
    static func sameOnScreen(_ a: FrequencyState, _ b: FrequencyState) -> Bool {
        if case .mhz(let x) = a, case .mhz(let y) = b {
            return rounded(x / 1000, decimals: ghzDecimals) == rounded(y / 1000, decimals: ghzDecimals)
        }
        return a == b
    }

    /// pid, name and the shown share.
    static func sameOnScreen(_ a: GPUProcessRow, _ b: GPUProcessRow) -> Bool {
        a.id == b.id && a.name == b.name && sameOnScreen(a.sharePct, b.sharePct, decimals: shareDecimals)
    }

    /// Same case; rows: same count and pairwise the same, in order.
    static func sameOnScreen(_ a: GPURowsState, _ b: GPURowsState) -> Bool {
        switch (a, b) {
        case (.rows(let x), .rows(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { sameOnScreen($0, $1) }
        case (.rows, _), (_, .rows):
            return false
        default:
            return a == b
        }
    }

    static func sameOnScreen(_ a: CoreGroupLoad, _ b: CoreGroupLoad) -> Bool {
        a.group == b.group && a.loads == b.loads && sameOnScreen(a.frequency, b.frequency)
    }

    static func sameOnScreen(_ a: [CoreGroupLoad]?, _ b: [CoreGroupLoad]?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.count == b.count && zip(a, b).allSatisfy { sameOnScreen($0, $1) }
        default: return false
        }
    }
}
