// Engine/RimAngle.swift
// IPHONE-DESIGN: direction of the DS3 rim highlight. Pure, covered by Tests/MacDashboardTests.
import Foundation

/// Degrees in the CSS convention: 0 = up, clockwise.
enum RimAngle {
    static let resting: Double = 315

    static func target(pointer: CGPoint, center: CGPoint) -> Double {
        atan2(Double(pointer.x - center.x), Double(-(pointer.y - center.y))) * 180 / .pi
    }

    /// `previous` advanced by the shortest signed turn to `target`; the result may leave 0..<360.
    static func continuing(from previous: Double, to target: Double) -> Double {
        let d = ((target - previous).truncatingRemainder(dividingBy: 360) + 540)
            .truncatingRemainder(dividingBy: 360) - 180
        return previous + d
    }
}
