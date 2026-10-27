// Tests/MacDashboardTests/CPUPageModelTests.swift
// REDESIGN-CPU: high-load tracker, CPU page state/texts/tones, Processes card texts and widths.
import Foundation
import Testing
@testable import MacDashboard

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func cpuInput(cpu: CPUUsage? = CPUUsage(user: 18, sys: 7.7, idle: 74.3),
                      load: [Double]? = [2.1, 1.85, 1.6], chip: String? = "Apple M3", soc: Int? = 48,
                      block: BlockPhase? = nil, highSince: Date? = nil, ncpu: Int = 8) -> CPUPageModel.Input {
    CPUPageModel.Input(cpu: cpu, load: load, ncpu: ncpu, chip: chip, socTempC: soc,
                       block: block ?? .ok(at: t0), highSince: highSince, now: t0, intervalSeconds: 2)
}

private func withLanguage(_ lang: AppLanguage, _ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

extension SerialTests {
    struct CPUPageModelTests {
        // MARK: high-load tracker

        @Test func nextHighSince() {
            let now = t0
            #expect(CPULoad.nextHighSince(previous: now.addingTimeInterval(-10), previousSampleAt: now.addingTimeInterval(-2), usage: 84.9, at: now) == nil, "below 85 ends the run")
            #expect(CPULoad.nextHighSince(previous: nil, previousSampleAt: now.addingTimeInterval(-2), usage: 90, at: now) == now, "first high sample starts the run")
            let prev = now.addingTimeInterval(-120)
            #expect(CPULoad.nextHighSince(previous: prev, previousSampleAt: now.addingTimeInterval(-2), usage: 90, at: now) == prev, "continuing keeps the start")
            #expect(CPULoad.nextHighSince(previous: prev, previousSampleAt: now.addingTimeInterval(-30), usage: 90, at: now) == prev, "30 s gap still continues")
            #expect(CPULoad.nextHighSince(previous: prev, previousSampleAt: now.addingTimeInterval(-31), usage: 90, at: now) == now, "31 s gap restarts")
            #expect(CPULoad.nextHighSince(previous: prev, previousSampleAt: nil, usage: 90, at: now) == now, "no previous sample restarts")
            #expect(CPULoad.nextHighSince(previous: nil, previousSampleAt: nil, usage: 85.0, at: now) == now, "exactly 85 is high")
        }

        @Test func highMinutes() {
            #expect(CPULoad.highMinutes(since: nil, now: t0) == nil)
            #expect(CPULoad.highMinutes(since: t0.addingTimeInterval(-59), now: t0) == nil)
            #expect(CPULoad.highMinutes(since: t0.addingTimeInterval(-60), now: t0) == 1)
            #expect(CPULoad.highMinutes(since: t0.addingTimeInterval(-299), now: t0) == 4)
            #expect(CPULoad.highMinutes(since: t0.addingTimeInterval(-3600), now: t0) == 60, "counts beyond the 2-minute history")
        }

        // MARK: make

        @Test func loadingBlock() {
            withLanguage(.en) {
                let m = CPUPageModel.make(cpuInput(block: .loading(since: t0)))
                #expect(m.phase == .loading)
                #expect(m.tag == .loading)
                #expect(m.tagText == "Collecting data…")
                #expect(m.showsWait)
                #expect(m.sub.contains("collecting data…"))
                #expect(m.sub == "Apple M3 · collecting data…")
                #expect(m.hero.value == "—" && m.hero.dimmed)
                #expect(m.failureNote == nil)
            }
            withLanguage(.en) {
                let m = CPUPageModel.make(cpuInput(cpu: nil))
                #expect(m.phase == .loading, "cpu == nil in an ok block reads as loading")
            }
        }

        @Test func liveReading() {
            withLanguage(.en) {
                let m = CPUPageModel.make(cpuInput())
                #expect(m.phase == .live)
                #expect(m.tag == .ok && m.tagText == "OK")
                #expect(m.hero.value == "25.7%")
                #expect(abs(m.hero.fraction - 0.257) < 1e-9)
                #expect(m.hero.note == "load 2.10 · 1.85 · 1.60 · 8 cores")
                #expect(!m.hero.high && !m.hero.dimmed)
                #expect(m.sub == "Apple M3 · 8 cores · updates every 2 s")
                #expect(m.caption == "live snapshot")
                #expect(!m.subIsFailure && m.failureNote == nil && !m.showsWait)
                #expect(m.tiles.map(\.label) == ["User", "System", "SoC temperature"])
                #expect(m.tiles[0].value == "18.0%" && m.tiles[1].value == "7.7%")
            }
            withLanguage(.ru) {
                let m = CPUPageModel.make(cpuInput())
                #expect(m.hero.value == "25,7 %")
                #expect(m.tagText == "в норме")
                #expect(m.hero.note == "нагрузка 2,10 · 1,85 · 1,60 · 8 ядер")
                #expect(m.sub == "Apple M3 · 8 ядер · обновляется каждые 2 с")
            }
        }

        @Test func highLoad() {
            withLanguage(.en) {
                let cpu = CPUUsage(user: 71, sys: 20, idle: 9)
                var m = CPUPageModel.make(cpuInput(cpu: cpu, highSince: t0.addingTimeInterval(-4 * 60)))
                #expect(m.phase == .high && m.tag == .high && m.tagText == "High load")
                #expect(m.hero.high)
                #expect(m.hero.note == "High load for 4 min")
                m = CPUPageModel.make(cpuInput(cpu: cpu, highSince: t0.addingTimeInterval(-30)))
                #expect(m.phase == .high)
                #expect(m.hero.note == "load 2.10 · 1.85 · 1.60 · 8 cores", "below 60 s keeps the load note")
                m = CPUPageModel.make(cpuInput(cpu: CPUUsage(user: 80, sys: 5, idle: 15)))
                #expect(m.phase == .high, "exactly 85 is high")
                m = CPUPageModel.make(cpuInput(cpu: CPUUsage(user: 80, sys: 4.9, idle: 15.1)))
                #expect(m.phase == .live, "84.9 is live")
            }
            withLanguage(.ru) {
                let m = CPUPageModel.make(cpuInput(cpu: CPUUsage(user: 71, sys: 20, idle: 9), highSince: t0.addingTimeInterval(-4 * 60)))
                #expect(m.hero.note == "Высокая нагрузка уже 4 мин")
                #expect(m.tagText == "Высокая нагрузка")
            }
        }

        @Test func loadNoteFallback() {
            withLanguage(.en) {
                #expect(CPUPageModel.make(cpuInput(load: nil)).hero.note == "8 cores")
                #expect(CPUPageModel.make(cpuInput(load: [1, 2])).hero.note == "8 cores")
            }
        }

        @Test func socTile() {
            withLanguage(.en) {
                var soc = CPUPageModel.make(cpuInput(soc: 95)).tiles[2]
                #expect(soc.value == "95 °C" && soc.dot == .hot && soc.hot && soc.note == "hot · may throttle" && !soc.dimmed, "exactly 95 is hot")
                soc = CPUPageModel.make(cpuInput(soc: 94)).tiles[2]
                #expect(soc.value == "94 °C" && soc.dot == .amber && !soc.hot && soc.note == "warm" && !soc.dimmed, "94 is warm")
                soc = CPUPageModel.make(cpuInput(soc: 85)).tiles[2]
                #expect(soc.dot == .amber && !soc.hot && soc.note == "warm", "exactly 85 is warm")
                soc = CPUPageModel.make(cpuInput(soc: 84)).tiles[2]
                #expect(soc.dot == .green && !soc.hot && soc.note == "normal", "84 is normal")
                soc = CPUPageModel.make(cpuInput(soc: 48)).tiles[2]
                #expect(soc.value == "48 °C" && soc.dot == .green && !soc.hot && soc.note == "normal")
                soc = CPUPageModel.make(cpuInput(soc: nil)).tiles[2]
                #expect(soc.value == "—" && soc.dimmed && soc.dot == nil && soc.note == nil)
            }
            withLanguage(.ru) {
                #expect(CPUPageModel.make(cpuInput(soc: 48)).tiles[2].note == "норма")
                #expect(CPUPageModel.make(cpuInput(soc: 90)).tiles[2].note == "тепло")
                #expect(CPUPageModel.make(cpuInput(soc: 95)).tiles[2].note == "горячо · возможен троттлинг")
            }
        }

        @Test func socLevelBoundaries() {
            #expect(CPULoad.socLevel(84) == .normal && CPULoad.socLevel(85) == .warm)
            #expect(CPULoad.socLevel(94) == .warm && CPULoad.socLevel(95) == .hot)
        }

        @Test func failedWithLastGood() {
            withLanguage(.en) {
                let good = Date(timeIntervalSinceReferenceDate: 800_000_000 - 3600)
                let hms = CPUPageModel.hhmmss(good)
                let m = CPUPageModel.make(cpuInput(block: .failed(.timedOut, lastGoodAt: good)))
                #expect(m.phase == .failed(.timedOut, lastGoodAt: good))
                #expect(m.tag == .failed && m.tagText == "Read error" && m.subIsFailure)
                #expect(m.caption == "last data — \(hms)")
                #expect(m.sub == "Apple M3 · last data — \(hms)")
                #expect(m.failureNote == "Couldn’t read CPU counters: no response within 5 s. The app keeps trying automatically.")
                #expect(m.hero.value == "—" && m.hero.note == "No current reading" && m.hero.dimmed && !m.hero.high)
                #expect(m.tiles.map(\.value) == ["—", "—", "—"] && m.tiles.allSatisfy { $0.dimmed && $0.note == nil && $0.dot == nil })
                #expect(!m.showsWait)
            }
        }

        @Test func failedHhmmssPattern() {
            var comps = DateComponents(); comps.year = 2026; comps.month = 1; comps.day = 15
            comps.hour = 10; comps.minute = 29; comps.second = 52
            let d = Calendar.current.date(from: comps)!
            #expect(CPUPageModel.hhmmss(d) == "10:29:52")
            withLanguage(.en) {
                let m = CPUPageModel.make(cpuInput(block: .failed(.timedOut, lastGoodAt: d)))
                #expect(m.caption == "last data — 10:29:52")
                #expect(m.sub == "Apple M3 · last data — 10:29:52")
            }
        }

        @Test func failedNeverGood() {
            withLanguage(.en) {
                let m = CPUPageModel.make(cpuInput(cpu: nil, block: .failed(.noReading, lastGoodAt: nil)))
                #expect(m.phase == .failed(.noReading, lastGoodAt: nil))
                #expect(m.sub == "Apple M3 · 8 cores")
                #expect(m.caption == "live snapshot")
                #expect(m.failureNote == "Couldn’t read CPU counters: the system returned no data. The app keeps trying automatically.")
            }
            withLanguage(.ru) {
                let m = CPUPageModel.make(cpuInput(cpu: nil, block: .failed(.noReading, lastGoodAt: nil)))
                #expect(m.failureNote == "Не удалось прочитать счётчики CPU: система не вернула данных. Приложение повторяет попытки автоматически.")
            }
        }

        @Test func chipPrefix() {
            withLanguage(.en) {
                #expect(CPUPageModel.make(cpuInput(chip: nil)).sub == "8 cores · updates every 2 s")
                #expect(CPUPageModel.make(cpuInput(chip: "")).sub == "8 cores · updates every 2 s")
                #expect(CPUPageModel.make(cpuInput(chip: "  ")).sub == "8 cores · updates every 2 s")
            }
        }

        @Test func russianCorePlurals() {
            withLanguage(.ru) {
                #expect(CPUPageModel.make(cpuInput(chip: nil, ncpu: 1)).sub == "1 ядро · обновляется каждые 2 с")
                #expect(CPUPageModel.make(cpuInput(chip: nil, ncpu: 2)).sub == "2 ядра · обновляется каждые 2 с")
                #expect(CPUPageModel.make(cpuInput(chip: nil, ncpu: 5)).sub == "5 ядер · обновляется каждые 2 с")
                #expect(CPUPageModel.make(cpuInput(chip: nil, ncpu: 8)).sub == "8 ядер · обновляется каждые 2 с")
                #expect(CPUPageModel.make(cpuInput(chip: nil, ncpu: 1)).hero.note == "нагрузка 2,10 · 1,85 · 1,60 · 1 ядро")
            }
        }

        // MARK: Processes card

        @Test func procsCaption() {
            withLanguage(.en) {
                #expect(CPUPageModel.procsCaption(metric: .cpu, processCount: 412) == "top by CPU · 412 processes")
                #expect(CPUPageModel.procsCaption(metric: .mem, processCount: 1) == "top by memory · 1 process")
                #expect(CPUPageModel.procsCaption(metric: .cpu, processCount: nil) == "top by CPU")
            }
            withLanguage(.ru) {
                #expect(CPUPageModel.procsCaption(metric: .cpu, processCount: 412) == "топ по CPU · 412 процессов")
                #expect(CPUPageModel.procsCaption(metric: .mem, processCount: 1) == "топ по памяти · 1 процесс")
                #expect(CPUPageModel.procsCaption(metric: .mem, processCount: 2) == "топ по памяти · 2 процесса")
                #expect(CPUPageModel.procsCaption(metric: .mem, processCount: nil) == "топ по памяти")
            }
        }

        @Test func procBar() {
            func row(_ cpu: Double?) -> ProcEntry { ProcEntry(name: "x", cpu: cpu, memBytes: 1, pid: 5) }
            #expect(CPUPageModel.procBar(row(15.1), metric: .cpu) == .amber)
            #expect(CPUPageModel.procBar(row(15.0), metric: .cpu) == .green)
            #expect(CPUPageModel.procBar(row(8.1), metric: .cpu) == .green)
            #expect(CPUPageModel.procBar(row(8.0), metric: .cpu) == .accent)
            #expect(CPUPageModel.procBar(row(nil), metric: .cpu) == .accent)
            #expect(CPUPageModel.procBar(row(50), metric: .mem) == .series)
            #expect(CPUPageModel.procBarOpacity(.cpu) == 0.20)
            #expect(CPUPageModel.procBarOpacity(.mem) == 0.18)
        }

        @Test func procTexts() {
            withLanguage(.en) {
                let r = ProcEntry(name: "Xcode", cpu: 18.44, memBytes: 3 * 1024 * 1024 * 1024, pid: 103)
                let cpuMode = CPUPageModel.procTexts(r, metric: .cpu)
                #expect(cpuMode.value == "18.4%" && cpuMode.secondary == fmtBytes(r.memBytes))
                let memMode = CPUPageModel.procTexts(r, metric: .mem)
                #expect(memMode.value == fmtBytes(r.memBytes) && memMode.secondary == "18.4%")
                let none = ProcEntry(name: "y", cpu: nil, memBytes: nil, pid: nil)
                #expect(CPUPageModel.procTexts(none, metric: .cpu).value == "—")
                #expect(CPUPageModel.procTexts(none, metric: .cpu).secondary == "—")
                #expect(CPUPageModel.procTexts(none, metric: .mem).value == "—")
                #expect(CPUPageModel.procTexts(none, metric: .mem).secondary == "—")
            }
            withLanguage(.ru) {
                let r = ProcEntry(name: "Xcode", cpu: 18.44, memBytes: 1024, pid: 103)
                #expect(CPUPageModel.procTexts(r, metric: .cpu).value == "18,4 %")
            }
        }

        @Test func showsActions() {
            #expect(!CPUPageModel.showsActions(pid: nil))
            #expect(!CPUPageModel.showsActions(pid: 0))
            #expect(!CPUPageModel.showsActions(pid: 1))
            #expect(CPUPageModel.showsActions(pid: 2))
        }

        @Test func heroWidths() {
            let a = CPUPageModel.heroWidths(total: 900)
            #expect(abs(a.hero - 254.857142857) < 0.001 && abs(a.tiles - 637.142857143) < 0.001)
            let b = CPUPageModel.heroWidths(total: 500)
            #expect(b.hero == 200 && b.tiles == 292)
            let c = CPUPageModel.heroWidths(total: 4)
            #expect(c.hero == 0 && c.tiles == 0)
            let d = CPUPageModel.heroWidths(total: 100)
            #expect(d.hero == 92 && d.tiles == 0, "hero clamps to total − 8")
        }
    }
}
