// Checks/RimAngleChecks.swift — IPHONE-DESIGN: rim highlight direction.
import Foundation

func runRimAngleChecks() {
    let o = CGPoint(x: 0, y: 0)
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
    check(near(RimAngle.target(pointer: CGPoint(x: 0, y: -10), center: o), 0), "RimAngle: pointer above is 0")
    check(near(RimAngle.target(pointer: CGPoint(x: 10, y: 0), center: o), 90), "RimAngle: pointer right is 90")
    check(near(RimAngle.target(pointer: CGPoint(x: 0, y: 10), center: o), 180), "RimAngle: pointer below is 180")
    check(near(RimAngle.target(pointer: CGPoint(x: -10, y: 0), center: o), -90), "RimAngle: pointer left is -90")
    check(near(RimAngle.continuing(from: 350, to: 10), 370), "RimAngle: 350 -> 10 turns +20")
    check(near(RimAngle.continuing(from: 10, to: 350), -10), "RimAngle: 10 -> 350 turns -20")
    check(near(RimAngle.continuing(from: 315, to: 315), 315), "RimAngle: same angle stays")
    var ok = true
    for p in stride(from: 0.0, through: 720.0, by: 15.0) {
        for t in stride(from: -180.0, through: 180.0, by: 15.0) {
            let d = RimAngle.continuing(from: p, to: t) - p
            if d < -180 - 1e-9 || d >= 180 + 1e-9 { ok = false }
        }
    }
    check(ok, "RimAngle: every turn is within [-180, 180)")
}
