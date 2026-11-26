// Tests/MoonportTests/TemperatureSensorsTests.swift
// TEMP-SENSORS-DETAIL: the validity filter, key classification, row aggregation and chip source order.
import Foundation
import Testing
@testable import Moonport

struct TemperatureSensorsTests {
    @Test func isValidRange() {
        #expect(!TemperatureSensors.isValid(10))
        #expect(TemperatureSensors.isValid(10.01))
        #expect(TemperatureSensors.isValid(150))
        #expect(!TemperatureSensors.isValid(150.01))
        #expect(!TemperatureSensors.isValid(0))
        #expect(!TemperatureSensors.isValid(-3.6))
        #expect(!TemperatureSensors.isValid(.nan))
        #expect(!TemperatureSensors.isValid(.infinity))
        #expect(!TemperatureSensors.isValid(281474976710654.53))
    }

    @Test func classification() {
        let table: [(String, SensorKind?)] = [
            ("Te04", .eCores), ("Te0P", .eCores), ("Tp1F", .pCores), ("Tg0b", .gpu), ("TG0B", nil), ("TG1B", nil),
            ("TB0T", .battery), ("TB1T", nil), ("TW0P", .wireless), ("TH0x", .ssd), ("TH0T", nil), ("TCHP", .charger),
            ("Ts0P", nil), ("TCMz", nil), ("TCMb", nil), ("Te", nil), ("Te045", nil), ("", nil)]
        for (key, kind) in table { #expect(TemperatureSensors.kind(forKey: key) == kind, "\(key)") }
    }

    @Test func readingsFromReferenceValues() {
        let values: [String: Double] = [
            "Te04": 41.870, "Te06": 52.438, "Te0P": 54.104, "Tg0C": 41.120, "Tg0D": 45.520, "Tp00": 41.030,
            "Tp0M": 58.828, "TB0T": 31.4, "TW0P": 39.221, "TH0x": 37.158, "TCHP": 38.559, "TG0B": 31.0,
            "TR1d": 281474976710654.53, "Ta04": 0, "TCMz": 57.812]
        #expect(TemperatureSensors.readings(from: values) == [
            SensorReading(kind: .eCores, celsius: 54), SensorReading(kind: .pCores, celsius: 59),
            SensorReading(kind: .gpu, celsius: 46), SensorReading(kind: .battery, celsius: 31),
            SensorReading(kind: .wireless, celsius: 39), SensorReading(kind: .ssd, celsius: 37),
            SensorReading(kind: .charger, celsius: 39)])
    }

    @Test func rowsWithKeysButNoValidValueAreNil() {
        let values: [String: Double] = [
            "Te04": 0, "Te06": -3.6, "Tg0C": 41.120, "Tg0D": 45.520, "Tp00": 41.030, "Tp0M": 58.828,
            "TW0P": 39.221, "TH0x": 37.158]
        let r = TemperatureSensors.readings(from: values)
        #expect(r.map(\.kind) == [.eCores, .pCores, .gpu, .wireless, .ssd])
        #expect(r.first?.celsius == nil)
        #expect(TemperatureSensors.readings(from: [:]).isEmpty)
    }

    @Test func idleGpuKeepsItsRowAsNil() {
        let values: [String: Double] = ["Tg0C": 0, "Tg0D": 0, "Tg1C": -2.85, "Tp00": 41.0]
        #expect(TemperatureSensors.readings(from: values)
                == [SensorReading(kind: .pCores, celsius: 41), SensorReading(kind: .gpu, celsius: nil)])
    }

    @Test func holdStep() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let nilGPU = [SensorReading(kind: .gpu, celsius: nil)]
        // A valid value refreshes `last` and passes through.
        let fresh = TemperatureSensors.holding([SensorReading(kind: .gpu, celsius: 41)], last: [:], now: t0)
        #expect(fresh.readings == [SensorReading(kind: .gpu, celsius: 41)])
        #expect(fresh.last[.gpu]?.celsius == 41 && fresh.last[.gpu]?.at == t0)
        // Held at exactly 30 s, nil just after.
        let held = TemperatureSensors.holding(nilGPU, last: fresh.last, now: t0.addingTimeInterval(30))
        #expect(held.readings == [SensorReading(kind: .gpu, celsius: 41)])
        #expect(held.last[.gpu]?.at == t0)
        let expired = TemperatureSensors.holding(nilGPU, last: fresh.last, now: t0.addingTimeInterval(30.001))
        #expect(expired.readings == nilGPU)
        // A new valid value refreshes the time.
        let refreshed = TemperatureSensors.holding([SensorReading(kind: .gpu, celsius: 43)], last: fresh.last,
                                                   now: t0.addingTimeInterval(20))
        let later = TemperatureSensors.holding(nilGPU, last: refreshed.last, now: t0.addingTimeInterval(49))
        #expect(later.readings == [SensorReading(kind: .gpu, celsius: 43)])
        // Empty `last` leaves nil.
        #expect(TemperatureSensors.holding(nilGPU, last: [:], now: t0).readings == nilGPU)
    }

    @Test func chipTemperatureSourceOrder() {
        var calls = 0
        func chip(_ values: [String: Double], fallback: Double?) -> Double? {
            TemperatureSensors.chipTemperature(values) { calls += 1; return fallback }
        }
        #expect(chip(["TCMz": 57.8, "TCMb": 49.2], fallback: 1) == 57.8)
        #expect(calls == 0)
        #expect(chip(["TCMz": 0, "TCMb": 49.2], fallback: 1) == 49.2)
        #expect(calls == 0)
        #expect(chip(["TCMb": 200], fallback: 52.0) == 52.0)
        #expect(calls == 1)
        #expect(chip([:], fallback: 5) == nil)
        #expect(chip([:], fallback: nil) == nil)
    }

    @Test func sensorsStateFromReadings() {
        #expect(SensorsState.from([]) == .unavailable)
        let r = [SensorReading(kind: .ssd, celsius: 37)]
        #expect(SensorsState.from(r) == .rows(r))
    }
}
