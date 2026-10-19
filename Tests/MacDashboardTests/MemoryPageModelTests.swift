// Tests/MacDashboardTests/MemoryPageModelTests.swift
// REDESIGN-MEMORY: swap-high rule, pressure mapping, Memory page state/texts/tones, Processes card texts.
import Foundation
import Testing
@testable import MacDashboard

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let GiB: Int64 = 1 << 30

private func gib(_ x: Double) -> Int64 { Int64(x * Double(GiB)) }

private func memSnap(total: Int64 = 16 * GiB, active: Double = 6, wired: Double = 2.5, inactive: Double = 4.5,
                     speculative: Double = 0.3, free: Double = 1.2, compressor: Double = 1.0,
                     purgeable: Double = 0.2, fileBacked: Double = 3.0) -> MemSnapshot {
    MemSnapshot(total: total, pageSize: 16384, free: gib(free), active: gib(active), inactive: gib(inactive),
                speculative: gib(speculative), wired: gib(wired), compressor: gib(compressor),
                purgeable: gib(purgeable), fileBacked: gib(fileBacked))
}

private func memInput(mem: MemSnapshot? = memSnap(),
                      swap: SwapInfo? = SwapInfo(total: 2 * GiB, used: 512 << 20, free: 2 * GiB - (512 << 20)),
                      pressure: MemoryPressureLevel? = .normal, installed: Int64? = 16 * GiB,
                      block: BlockPhase? = nil, narrow: Bool = false) -> MemoryPageModel.Input {
    MemoryPageModel.Input(mem: mem, swap: swap, pressure: pressure, installedBytes: installed,
                          block: block ?? .ok(at: t0), intervalSeconds: 2, narrow: narrow)
}

private func withLanguage(_ lang: AppLanguage, _ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

extension SerialTests {
    struct MemoryPageModelTests {
        @Test func swapHigh() {
            #expect(!MemoryLoad.isSwapHigh(nil))
            #expect(!MemoryLoad.isSwapHigh(SwapInfo(total: 0, used: 0, free: 0)))
            #expect(!MemoryLoad.isSwapHigh(SwapInfo(total: 2 * GiB, used: GiB, free: GiB)))
            #expect(MemoryLoad.isSwapHigh(SwapInfo(total: 2 * GiB, used: GiB + 1, free: GiB - 1)))
            #expect(MemoryLoad.isSwapHigh(SwapInfo(total: 8 * GiB, used: gib(5.2), free: 8 * GiB - gib(5.2))))
        }

        @Test func pressureTone() {
            #expect(MemoryLoad.pressureTone(.normal) == .low)
            #expect(MemoryLoad.pressureTone(.warn) == .medium)
            #expect(MemoryLoad.pressureTone(.critical) == .high)
            #expect(MemoryLoad.pressureTone(nil) == nil)
        }

        @Test func otherBytes() {
            let m = MemoryPageModel.make(memInput())
            #expect(abs(m.segments[2].bytes - gib(1.5)) <= 1)
            let over = memSnap(total: 8 * GiB)   // six fields sum to 15.5 GiB > 8
            #expect(over.otherBytes == over.compressor)
        }

        @Test func live() {
            withLanguage(.en) {
                let m = MemoryPageModel.make(memInput())
                #expect(m.tag == .low)
                #expect(m.tagText == "Pressure: low")
                #expect(m.sub == "16 GB · updates every 2 s")
                #expect(m.usageCaption == "16 GB total · live snapshot")
                #expect(m.compCaption == "16 GB · by page type")
                #expect(m.heroValue == "9.5 GB")
                #expect(m.heroNote == "of 16 GB · 59%")
                #expect(m.heroTone == .accent)
                #expect(m.tiles.map(\.value) == ["1 GB", "204.8 MB", "512 MB", "3 GB"])
                #expect(m.tiles[2].note == "25% of 2 GB")
                #expect(m.tiles[2].amber == false)
                #expect(m.segments.map(\.value) == ["6 GB", "2.5 GB", "1.5 GB", "4.5 GB", "307.2 MB", "1.2 GB"])
                #expect(m.segments[0].share == "38%")
                #expect(m.segments[0].listFraction == 1)
                #expect(!m.showsWait)
                #expect(m.failureNote == nil)
            }
        }

        @Test func pressureLevels() {
            withLanguage(.en) {
                let w = MemoryPageModel.make(memInput(pressure: .warn))
                #expect(w.tag == .medium && w.heroTone == .amber)
                let c = MemoryPageModel.make(memInput(pressure: .critical))
                #expect(c.tag == .high && c.heroTone == .hot)
                let n = MemoryPageModel.make(memInput(pressure: nil))
                #expect(n.tag == .unknown && n.tagText == "Pressure: unknown" && n.heroTone == .accent)
            }
        }

        @Test func swapHighTile() {
            withLanguage(.en) {
                let s = SwapInfo(total: 8 * GiB, used: gib(5.2), free: 8 * GiB - gib(5.2))
                let t = MemoryPageModel.make(memInput(swap: s)).tiles[2]
                #expect(t.value == "5.2 GB")
                #expect(t.note == "65% of 8 GB")
                #expect(t.amber)
            }
        }

        @Test func swapEdge() {
            withLanguage(.en) {
                let none = MemoryPageModel.make(memInput(swap: nil)).tiles[2]
                #expect(none.value == "—" && none.dimmed)
                let zero = MemoryPageModel.make(memInput(swap: SwapInfo(total: 0, used: 0, free: 0))).tiles[2]
                #expect(zero.value == "0 B" && zero.note == nil)
            }
        }

        @Test func loading() {
            withLanguage(.en) {
                let m = MemoryPageModel.make(memInput(block: .loading(since: t0)))
                #expect(m.showsWait && m.tag == .loading)
                #expect(m.tagText == "Collecting data…")
                #expect(m.sub == "16 GB · collecting data…")
                let n = MemoryPageModel.make(memInput(mem: nil))
                #expect(n.showsWait && n.tag == .loading)
            }
        }

        @Test func failed() {
            withLanguage(.en) {
                let stale = L.commonLastData(CPUPageModel.hhmmss(t0))
                let m = MemoryPageModel.make(memInput(block: .failed(.timedOut, lastGoodAt: t0)))
                #expect(m.tag == .failed && m.tagText == "Read failed" && m.subIsFailure)
                #expect(m.sub == "16 GB · last data — " + CPUPageModel.hhmmss(t0))
                #expect(m.usageCaption == stale && m.compCaption == stale)
                #expect(m.failureNote == "Couldn’t read memory statistics: no response within 5 s.")
                #expect(m.heroValue == "—" && m.heroNote == "No current reading" && m.heroTone == .neutral)
                #expect(m.tiles.allSatisfy { $0.value == "—" && $0.dimmed })
                #expect(m.segments.allSatisfy { $0.value == "—" && $0.share == "" && $0.barFraction == 0 && $0.listFraction == 0 })
                let n = MemoryPageModel.make(memInput(block: .failed(.noReading, lastGoodAt: nil)))
                #expect(n.failureNote == "Couldn’t read memory statistics: the system returned no data.")
                #expect(n.sub == "16 GB")
                #expect(n.usageCaption == "16 GB total · live snapshot" && n.compCaption == "16 GB · by page type")
                for text in [m.failureNote, n.failureNote, m.sub, n.sub] { #expect(!(text ?? "").contains("vm_stat")) }
            }
        }

        @Test func narrowLabel() {
            withLanguage(.en) {
                #expect(MemoryPageModel.make(memInput(narrow: true)).segments[2].label == "Other")
                #expect(MemoryPageModel.make(memInput(narrow: false)).segments[2].label == "Other (incl. compressed)")
            }
        }

        @Test func russian() {
            withLanguage(.ru) {
                let m = MemoryPageModel.make(memInput())
                #expect(m.sub == "16 ГБ · обновляется каждые 2 с")
                #expect(m.heroNote == "из 16 ГБ · 59 %")
                #expect(m.segments[1].value == "2,5 ГБ")
                #expect(m.tagText == "Давление: низкое")
                #expect(m.tiles[2].note == "25 % из 2 ГБ")
                #expect(MemoryPageModel.procsCaption(processCount: 412) == "топ-8 · 412 процессов")
            }
        }

        @Test func procs() {
            withLanguage(.en) {
                #expect(MemoryPageModel.procsCaption(processCount: 412) == "top 8 · 412 processes")
                #expect(MemoryPageModel.procsCaption(processCount: 1) == "top 8 · 1 process")
                #expect(MemoryPageModel.procsCaption(processCount: nil) == "top 8")
                #expect(MemoryPageModel.procSecondary(ProcEntry(name: "x", cpu: 7.5, memBytes: 1, pid: 5)) == "7.5% CPU")
                #expect(MemoryPageModel.procSecondary(ProcEntry(name: "x", cpu: nil, memBytes: 1, pid: 5)) == "—")
            }
        }
    }
}
