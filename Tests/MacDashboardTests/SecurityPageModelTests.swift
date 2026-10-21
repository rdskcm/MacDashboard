// Tests/MacDashboardTests/SecurityPageModelTests.swift
// REDESIGN-SECURITY: Security page tag priority, tiles, banners, updates and crashes texts (EN + RU).
import Foundation
import Testing
@testable import MacDashboard

private let now: Date = {
    var c = DateComponents(); c.year = 2026; c.month = 1; c.day = 15; c.hour = 12; c.minute = 0
    return Calendar.current.date(from: c)!
}()
private func at(_ month: Int, _ day: Int, _ h: Int, _ min: Int) -> Date {
    var c = DateComponents(); c.year = 2026; c.month = month; c.day = day; c.hour = h; c.minute = min
    return Calendar.current.date(from: c)!
}

private let allOn = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: true)

private func upd(_ title: String, size: Int64? = nil, restart: Bool = false) -> SoftwareUpdate {
    SoftwareUpdate(label: title, title: title, version: nil, sizeBytes: size, restartRequired: restart)
}

private func input(security: SecurityState? = allOn, action: SecurityActionState = .idle, fvOpened: Bool = false,
                   updates: [SoftwareUpdate]? = [], checkedAt: Date? = nil, checking: Bool = false,
                   crashes: [CrashGroup]? = [], opened: String? = nil) -> SecurityPageModel.Input {
    SecurityPageModel.Input(security: security, action: action, fileVaultOpened: fvOpened, updates: updates,
                            updatesCheckedAt: checkedAt, checkingUpdates: checking, crashes: crashes,
                            openedReportPath: opened, now: now)
}
private func make(_ i: SecurityPageModel.Input) -> SecurityPageModel { SecurityPageModel.make(i) }

private func crash(_ name: String, _ count: Int = 1, panic: Bool = false, last: Date? = nil, path: String? = nil) -> CrashGroup {
    CrashGroup(process: name, count: count, isPanic: panic, directory: "/d", lastReportAt: last, newestReportPath: path)
}

private func withLanguage(_ lang: AppLanguage, _ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

extension SerialTests {
    struct SecurityPageModelTests {
        @Test func allOnIsGreen() {
            withLanguage(.en) {
                let m = make(input())
                #expect(m.tag == .green && m.tagText == "All on")
                #expect(m.protectionCaption == "4 of 4 on")
                #expect(m.tiles.count == 4)
                #expect(m.tiles.allSatisfy { $0.value == "on" && $0.dot == .green && $0.button == nil && !$0.error })
                #expect(m.tiles.map(\.label) == ["FileVault", "Gatekeeper", "SIP", "Firewall"])
                #expect(m.banner == nil)
                #expect(m.sub == "protection, updates and crashes")
            }
        }

        @Test func firewallOff() {
            withLanguage(.en) {
                let m = make(input(security: SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)))
                #expect(m.tag == .hot && m.tagText == "Firewall off")
                let t = m.tiles[3]
                #expect(t.value == "off" && t.valueTone == .hot && t.dot == .hot && t.error)
                #expect(t.button == .enable && t.note == "Touch ID required" && !t.busy)
                #expect(m.protectionCaption == "3 of 4 on")
            }
        }

        @Test func enablingFirewall() {
            withLanguage(.en) {
                let m = make(input(security: SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false),
                                   action: .enabling(.firewall)))
                #expect(m.tag == .accent && m.tagText == "enabling firewall…")
                let t = m.tiles[3]
                #expect(t.value == "Enabling…" && t.busy && t.button == .enable && t.note == "waiting for Touch ID…" && t.error)
                #expect(m.protectionCaption == "3 of 4 on · enabling firewall…")
            }
            withLanguage(.en) {
                let m = make(input(security: SecurityState(fileVault: true, gatekeeper: false, sip: true, firewall: true),
                                   action: .enabling(.gatekeeper)))
                #expect(m.protectionCaption == "3 of 4 on · enabling Gatekeeper…")
                #expect(m.tagText == "enabling Gatekeeper…")
            }
        }

        @Test func failedBanners() {
            let off = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            withLanguage(.en) {
                let t = make(input(security: off, action: .failed(.firewall, .timedOut)))
                #expect(t.banner == "Touch ID didn’t respond within 30 s. The firewall is still off.")
                #expect(t.tiles[3].value == "off" && t.tiles[3].button == .enable && !t.tiles[3].busy)
                #expect(make(input(security: off, action: .failed(.firewall, .cancelled))).banner
                        == "Authorization cancelled. The firewall is still off.")
                #expect(make(input(security: off, action: .failed(.firewall, .error("boom")))).banner
                        == "Could not turn on the firewall (boom). The firewall is still off.")
                #expect(make(input(security: off, action: .failed(.firewall, .error("")))).banner
                        == "Could not turn on the firewall. The firewall is still off.")
                let long = String(repeating: "x", count: 200)
                #expect(make(input(security: off, action: .failed(.firewall, .error(long)))).banner?
                    .contains("(" + String(repeating: "x", count: 120) + ")") == true)
                let gk = SecurityState(fileVault: true, gatekeeper: false, sip: true, firewall: true)
                #expect(make(input(security: gk, action: .failed(.gatekeeper, .cancelled))).banner
                        == "Authorization cancelled. Gatekeeper is still off.")
                // Protection now reads on: no banner.
                #expect(make(input(action: .failed(.firewall, .timedOut))).banner == nil)
            }
            withLanguage(.ru) {
                #expect(make(input(security: off, action: .failed(.firewall, .timedOut))).banner
                        == "Touch ID не ответил за 30 с. Брандмауэр по-прежнему выключен.")
                #expect(make(input(security: off, action: .failed(.firewall, .cancelled))).banner
                        == "Авторизация отменена. Брандмауэр по-прежнему выключен.")
                #expect(make(input(security: off, action: .failed(.firewall, .error("x")))).banner
                        == "Не удалось включить брандмауэр (x). Брандмауэр по-прежнему выключен.")
            }
        }

        @Test func twoOffAndTagPriority() {
            withLanguage(.en) {
                let two = SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: false)
                #expect(make(input(security: two)).tagText == "2 of 4 off")
                let three = SecurityState(fileVault: false, gatekeeper: false, sip: true, firewall: false)
                #expect(make(input(security: three)).tagText == "3 of 4 off")
                #expect(make(input(security: SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true))).tagText == "FileVault off")
                #expect(make(input(security: SecurityState(fileVault: true, gatekeeper: false, sip: true, firewall: true))).tagText == "Gatekeeper off")
                #expect(make(input(security: SecurityState(fileVault: true, gatekeeper: true, sip: false, firewall: true))).tagText == "SIP off")
                // Enabling one of two off protections: the other still counts, alone → its own tag.
                let fwGk = SecurityState(fileVault: true, gatekeeper: false, sip: true, firewall: false)
                #expect(make(input(security: fwGk, action: .enabling(.firewall))).tagText == "Gatekeeper off")
                // Enabling beats updates and crashes.
                let fw = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
                let m = make(input(security: fw, action: .enabling(.firewall), updates: [upd("u")], crashes: [crash("a")]))
                #expect(m.tag == .accent)
                // Updates beat crashes.
                let u = make(input(updates: [upd("u")], crashes: [crash("a")]))
                #expect(u.tag == .amber && u.tagText == "updates available")
                let c = make(input(crashes: [crash("a", 2), crash("b")]))
                #expect(c.tag == .amber && c.tagText == "3 crashes in 7 days")
                #expect(make(input(crashes: [crash("a")])).tagText == "1 crash in 7 days")
                // Off beats updates.
                #expect(make(input(security: fw, updates: [upd("u")])).tag == .hot)
            }
        }

        @Test func fileVaultAndSip() {
            withLanguage(.en) {
                let s = SecurityState(fileVault: false, gatekeeper: true, sip: true, firewall: true)
                let a = make(input(security: s)).tiles[0]
                #expect(a.button == .openSettings && a.note == "password and recovery key needed" && a.noteTone == nil)
                let b = make(input(security: s, fvOpened: true)).tiles[0]
                #expect(b.note == "System Settings opened" && b.noteTone == .green && b.button == .openSettings)
                let sip = make(input(security: SecurityState(fileVault: true, gatekeeper: true, sip: false, firewall: true))).tiles[2]
                #expect(sip.button == nil && sip.note == "can only be turned on in Recovery mode" && sip.value == "off")
                let gk = make(input(security: SecurityState(fileVault: true, gatekeeper: false, sip: true, firewall: true))).tiles[1]
                #expect(gk.button == .enable && gk.note == "Touch ID required")
            }
        }

        @Test func unknownAndCollecting() {
            withLanguage(.en) {
                let m = make(input(security: SecurityState()))
                #expect(m.tag == .neutral && m.tagText == "0 of 4 on")
                #expect(m.tiles.allSatisfy { $0.value == "—" && $0.valueTone == .neutral && $0.dot == nil
                    && $0.note == "not determined" && $0.button == nil && !$0.error })
                let partial = make(input(security: SecurityState(fileVault: true, gatekeeper: nil, sip: true, firewall: true)))
                #expect(partial.tagText == "3 of 4 on" && partial.tag == .neutral)
                let w = make(input(security: nil))
                #expect(w.protectionWait && w.tiles.isEmpty && w.protectionCaption == nil && w.banner == nil)
                #expect(w.tag == .neutral && w.tagText == "Collecting data…")
            }
        }

        @Test func updatesCards() {
            withLanguage(.en) {
                let none = make(input(updates: [], checkedAt: now.addingTimeInterval(-300)))
                #expect(none.updatesCaption == "checked 5 min ago")
                #expect(none.updatesNote == SecurityUpdatesNote(tone: .green, text: "No macOS updates — the system is up to date.", showsInstall: false))
                #expect(none.updateRows.isEmpty && !none.updatesWait)

                let mac = SoftwareUpdate(label: "mac", title: "macOS Tahoe 26.1.1", version: "26.1.1", sizeBytes: 3_276_800 * 1024, restartRequired: true)
                let one = make(input(updates: [upd("Safari 26.2", size: 188_416 * 1024)], checkedAt: now.addingTimeInterval(-300)))
                #expect(one.updatesNote == SecurityUpdatesNote(tone: .amber, text: "1 update available.", showsInstall: true))
                #expect(one.updatesCaption == "checked 5 min ago · 1 available")
                #expect(one.updateRows == [SecurityUpdateRow(id: "Safari 26.2", name: "Safari 26.2", sub: "", value: "184.0 MB")])

                let two = make(input(updates: [mac, upd("Safari 26.2")], checkedAt: now))
                #expect(two.updatesNote?.text == "2 updates available. The macOS update requires a restart.")
                #expect(two.updateRows[0] == SecurityUpdateRow(id: "mac", name: "macOS Tahoe 26.1.1", sub: "restart required", value: "3.1 GB"))
                #expect(two.updateRows[1].value == "—")
            }
            withLanguage(.ru) {
                let m = make(input(updates: [upd("a"), upd("b"), upd("c"), upd("d"), upd("e")], checkedAt: now))
                #expect(m.updatesNote?.text == "Доступно 5 обновлений.")
                #expect(make(input(updates: [upd("a"), upd("b")], checkedAt: now)).updatesNote?.text == "Доступно 2 обновления.")
                #expect(make(input(updates: [upd("a")], checkedAt: now)).updatesNote?.text == "Доступно 1 обновление.")
            }
        }

        @Test func updatesCheckingAndFailed() {
            withLanguage(.en) {
                let c = make(input(updates: nil, checking: true))
                #expect(c.updatesWait && c.updatesWaitText == "Checking for updates…" && c.updatesCaption == "checking…")
                #expect(c.updatesNote == nil && c.updateRows.isEmpty)
                let f = make(input(updates: nil))
                #expect(!f.updatesWait && f.updatesCaption == "not checked")
                #expect(f.updatesNote == SecurityUpdatesNote(tone: .neutral, text: "Could not check for updates — press Refresh to try again.", showsInstall: false))
                #expect(SecurityPageModel.updatesCaption(updates: nil, checkedAt: nil, checking: false, now: now) == "not checked")
            }
        }

        @Test func crashes() {
            let today = at(1, 15, 9, 41)
            let jan12 = at(1, 12, 22, 17)
            let groups = [crash("MacDashboard", 2, last: today, path: "/x/MacDashboard-1.ips"),
                          crash("kernel", 1, panic: true, last: jan12, path: "/x/k.panic"),
                          crash("Xcode", 1)]
            withLanguage(.en) {
                let none = make(input(crashes: []))
                #expect(none.crashesNone && none.crashRows.isEmpty && none.crashesCaption == "own app and kernel panics")
                let m = make(input(crashes: groups))
                #expect(m.crashesCaption == "4 crashes · own app and kernel panics" && !m.crashesNone)
                #expect(m.crashRows[0] == SecurityCrashRow(id: "MacDashboard", name: "MacDashboard", sub: "last today, 09:41",
                                                          value: "×2", tone: .amber, path: "/x/MacDashboard-1.ips"))
                #expect(m.crashRows[1].name == "Kernel panic" && m.crashRows[1].tone == .hot && m.crashRows[1].sub == "Jan 12, 22:17")
                #expect(m.crashRows[2].sub == "" && m.crashRows[2].path == nil)
                #expect(m.crashFoot == "Click a row to open the report in Console.")
                #expect(make(input(crashes: groups, opened: "/x/MacDashboard-1.ips")).crashFoot == "Opened in Console: MacDashboard-1.ips")
                #expect(make(input(crashes: [crash("a")])).crashesCaption == "1 crash · own app and kernel panics")
                let w = make(input(crashes: nil))
                #expect(w.crashesWait && w.crashRows.isEmpty)
            }
            withLanguage(.ru) {
                let m = make(input(crashes: groups))
                #expect(m.crashRows[1].sub == "12 янв., 22:17" && m.crashRows[1].name == "Паника ядра")
                #expect(m.crashRows[0].sub == "последний сегодня, 09:41")
                #expect(m.crashesCaption == "4 сбоя · своё приложение и паники ядра")
                #expect(L.shortDateTime(at(5, 3, 8, 5)) == "3 мая, 08:05")
                #expect(make(input(crashes: [crash("a", 5)])).tagText == "5 сбоев за 7 дней")
                #expect(make(input(crashes: [crash("a")])).tagText == "1 сбой за 7 дней")
            }
        }

        @Test func helpers() {
            #expect(SecurityPageModel.protectionsOn(allOn) == 4)
            #expect(SecurityPageModel.protectionsOn(SecurityState()) == 0)
            let fwOff = SecurityState(fileVault: true, gatekeeper: true, sip: true, firewall: false)
            #expect(SecurityPageModel.isOff(.firewall, fwOff, action: .idle))
            #expect(!SecurityPageModel.isOff(.firewall, fwOff, action: .enabling(.firewall)))
            #expect(SecurityPageModel.isOff(.firewall, fwOff, action: .enabling(.gatekeeper)))
            #expect(!SecurityPageModel.isOff(.sip, SecurityState(), action: .idle))
            #expect(SecurityPageModel.privilegedEnableCommand(.gatekeeper) == "/usr/sbin/spctl --global-enable")
            #expect(SecurityPageModel.privilegedEnableCommand(.firewall).hasSuffix("--setglobalstate on"))
        }
    }
}
