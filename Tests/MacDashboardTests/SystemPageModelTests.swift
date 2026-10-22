// Tests/MacDashboardTests/SystemPageModelTests.swift
// REDESIGN-SYSTEM: System page tag priority, sleep / startup / Homebrew / energy states, texts (EN + RU).
import Foundation
import Testing
@testable import MacDashboard

private func at(_ month: Int, _ day: Int, _ h: Int, _ min: Int) -> Date {
    var c = DateComponents(); c.year = 2026; c.month = month; c.day = day; c.hour = h; c.minute = min
    return Calendar.current.date(from: c)!
}
private let now = at(1, 15, 12, 0)

private func plist(_ path: String, orphan: Bool = false) -> LaunchdPlistInfo {
    LaunchdPlistInfo(path: path, label: nil, executablePath: orphan ? "/gone" : nil, isOrphan: orphan, description: nil)
}
private func auto(login: [String]? = ["Dropbox", "Rectangle"], user: [LaunchdPlistInfo] = [], sysAgents: [LaunchdPlistInfo] = [],
                  daemons: [LaunchdPlistInfo] = [], bg: [(pid: String, label: String)] = []) -> AutostartInfo {
    var a = AutostartInfo(); a.loginItems = login; a.userAgents = user; a.systemAgents = sysAgents
    a.systemDaemons = daemons; a.background = bg
    return a
}
private let userHome = NSHomeDirectory() + "/Library/LaunchAgents/"

private func energy(battery: [(String, String)] = [("displaysleep", "2"), ("sleep", "1"), ("powernap", "0"),
                                                     ("hibernatemode", "3"), ("tcpkeepalive", "1")],
                    ac: [(String, String)] = [("displaysleep", "10"), ("sleep", "0"), ("powernap", "1"), ("womp", "1"),
                                              ("lidwake", "1")]) -> EnergySettings {
    EnergySettings(battery: battery, ac: ac)
}

private func input(wakeSampled: Bool = true, holders: [WakeHolder] = [], system: [WakeHolder] = [],
                   ignored: [IgnoredWakeHolder] = [], autostart: AutostartInfo? = auto(), checking: Bool = false,
                   checkedAt: Date? = nil, removed: Int = 0, deleting: Set<String> = [],
                   plistFailure: PrivilegedActionFailure? = nil, brewStatus: BrewStatus? = .installed(version: "Homebrew 4.6.0"),
                   outdated: [String]? = [], detail: [BrewOutdatedPackage]? = nil, installed: Int? = 48,
                   brewChecked: Date? = nil, upgrading: Bool = false, progress: BrewProgress? = nil, brewError: String? = nil,
                   notice: String? = nil, refreshing: Bool = false, energy: EnergySettings? = energy(),
                   pending: [EnergyChange] = [], apply: EnergyApplyState = .idle) -> SystemPageModel.Input {
    SystemPageModel.Input(wakeSampled: wakeSampled, wakeHolders: holders, systemWakeHolders: system, ignored: ignored,
                          autostart: autostart, startupChecking: checking, startupCheckedAt: checkedAt,
                          startupRemoved: removed, deletingPaths: deleting, plistFailure: plistFailure,
                          brewStatus: brewStatus, brewOutdated: outdated, brewDetail: detail, brewInstalled: installed,
                          brewCheckedAt: brewChecked, brewUpgrading: upgrading, brewProgress: progress,
                          brewError: brewError, brewNotice: notice, brewRefreshing: refreshing, energy: energy,
                          energyPending: pending, energyApply: apply, now: now)
}
private func make(_ i: SystemPageModel.Input) -> SystemPageModel { SystemPageModel.make(i) }

private func withLanguage(_ lang: AppLanguage, _ body: () -> Void) {
    let saved = L10nStore.shared.language
    defer { L10nStore.shared.language = saved }
    L10nStore.shared.language = lang
    body()
}

private let caf = WakeHolder(owner: "caffeinate", requester: "Terminal", ageSeconds: 4902)
private let zoom = WakeHolder(owner: "zoom.us", requester: nil, ageSeconds: 900)
private let backupd = WakeHolder(owner: "backupd", requester: nil, ageSeconds: 700)

extension SerialTests {
    struct SystemPageModelTests {
        @Test func tagPriority() {
            let bad = EnergyApplyState.failed(.error("boom"))
            withLanguage(.en) {
                let outdated = ["git"]
                #expect(make(input()).tag == .green && make(input()).tagText == "All good")
                #expect(make(input()).sub == "sleep, startup items, Homebrew, energy")
                let brew = make(input(outdated: outdated))
                #expect(brew.tag == .amber && brew.tagText == "Outdated packages")
                let upd = make(input(outdated: outdated, upgrading: true))
                #expect(upd.tag == .accent && upd.tagText == "Updating…")
                let stale = make(input(autostart: auto(user: [plist(userHome + "a.plist", orphan: true)]),
                                       checkedAt: now, outdated: outdated))
                #expect(stale.tag == .amber && stale.tagText == "Needs attention")
                let sleep = make(input(holders: [caf], autostart: auto(user: [plist(userHome + "a.plist", orphan: true)]),
                                       checkedAt: now, outdated: outdated))
                #expect(sleep.tag == .amber && sleep.tagText == "Mac can’t sleep")
                let failed = make(input(holders: [caf], outdated: outdated, apply: bad))
                #expect(failed.tag == .hot && failed.tagText == "Apply failed")
                // not checked -> stale items do not raise the tag; cancelled/timed out apply leaves it
                #expect(make(input(autostart: auto(user: [plist(userHome + "a.plist", orphan: true)]))).tag == .green)
                #expect(make(input(apply: .failed(.cancelled))).tag == .green && make(input(apply: .failed(.timedOut))).tag == .green)
                // before the first assertion sample the tag never says «can't sleep»
                #expect(make(input(wakeSampled: false, holders: [caf])).tag == .green)
                // an ignored holder does not raise it
                #expect(make(input(holders: [caf], ignored: [IgnoredWakeHolder(key: caf.key, since: now)])).tag == .green)
                // system holders never raise it
                #expect(make(input(system: [backupd])).tag == .green)
            }
            withLanguage(.ru) {
                #expect(make(input()).tagText == "Всё в порядке")
                #expect(make(input(outdated: ["git"])).tagText == "Есть устаревшие пакеты")
                #expect(make(input(outdated: ["git"], upgrading: true)).tagText == "Обновление…")
                #expect(make(input(holders: [caf])).tagText == "Mac не засыпает")
                #expect(make(input(apply: bad)).tagText == "Ошибка применения")
                #expect(make(input()).sub == "сон, автозагрузка, Homebrew, энергия")
            }
        }

        @Test func sleepStates() {
            withLanguage(.en) {
                let wait = make(input(wakeSampled: false))
                #expect(wait.sleepState == .wait && wait.sleepRows.isEmpty)
                let none = make(input())
                #expect(none.sleepState == .none && none.sleepCaption == "Mac sleeps normally")
                let m = make(input(holders: [caf, zoom], system: [backupd],
                                   ignored: [IgnoredWakeHolder(key: zoom.key, since: at(1, 12, 9, 0))]))
                #expect(m.sleepState == .blockers && m.sleepCaption == "what keeps the Mac awake")
                #expect(m.sleepRows.map(\.warnable) == [true, false])
                #expect(m.sleepRows.map(\.name) == ["caffeinate (for Terminal)", "backupd"])
                #expect(m.sleepRows.map(\.id) == ["caffeinate|Terminal", "backupd|"])
                #expect(m.sleepRows[0].age == WakeHolders.ageText(4902) && m.sleepRows[1].age == "11 min")
                #expect(m.hiddenCount == 1 && m.hiddenRows[0].name == "zoom.us" && m.hiddenRows[0].id == "zoom.us|")
                #expect(m.hiddenRows[0].a11y == "Warn again about zoom.us")
                // only ignored + nothing else -> the green note state, Hidden stays
                let onlyHidden = make(input(holders: [zoom], ignored: [IgnoredWakeHolder(key: zoom.key, since: nil)]))
                #expect(onlyHidden.sleepState == .none && onlyHidden.hiddenCount == 1)
                // system holders alone are listed
                #expect(make(input(system: [backupd])).sleepState == .blockers)
            }
        }

        @Test func hiddenRowDates() {
            let entries = [IgnoredWakeHolder(key: zoom.key, since: at(1, 12, 9, 0)),
                           IgnoredWakeHolder(owner: "Slack", requester: nil, since: nil)]
            withLanguage(.en) {
                let h = make(input(ignored: entries)).hiddenRows
                #expect(h.map(\.sub) == ["not warned since Jan 12", "not warned"])
                #expect(L.shortDate(at(1, 12, 9, 0)) == "Jan 12" && L.shortDate(at(10, 3, 9, 0)) == "Oct 3")
            }
            withLanguage(.ru) {
                let h = make(input(ignored: entries)).hiddenRows
                #expect(h.map(\.sub) == ["не предупреждаем с 12 янв.", "не предупреждаем"])
                #expect(L.shortDate(at(1, 12, 9, 0)) == "12 янв." && L.shortDate(at(5, 9, 9, 0)) == "9 мая"
                        && L.shortDate(at(10, 12, 9, 0)) == "12 окт.")
                #expect(h[0].a11y == "Снова предупреждать про zoom.us")
            }
        }

        @Test func startupCaptionsAndStale() {
            let orphanU = plist(userHome + "z-old.plist", orphan: true)
            let orphanD = plist("/Library/LaunchDaemons/a-old.plist", orphan: true)
            let okAgent = plist("/Library/LaunchAgents/ok.plist")
            let a = auto(user: [orphanU], sysAgents: [okAgent], daemons: [orphanD], bg: [("1", "x.y")])
            withLanguage(.en) {
                let before = make(input(autostart: a))
                #expect(before.startupWait == false && before.startupCaption == "6 items" && !before.startupChecked)
                #expect(before.staleRows.isEmpty && !before.showDeleteAll && before.startupNote == nil)
                #expect(before.groups.allSatisfy { $0.staleCount == 0 && $0.pills.allSatisfy { !$0.stale } })
                #expect(before.groups.map(\.id) == StartupGroupID.allCases)
                #expect(before.groups.map(\.count) == [2, 1, 1, 1, 1])

                let justNow = make(input(autostart: a, checkedAt: now.addingTimeInterval(-10)))
                #expect(justNow.startupCaption == "6 items · checked just now" && justNow.startupChecked)
                #expect(justNow.staleRows.map(\.fileName) == ["z-old.plist", "a-old.plist"])   // user first, then /Library
                #expect(justNow.staleRows.map(\.isSystemLevel) == [false, true])
                #expect(justNow.staleRows[0].folder == "~/Library/LaunchAgents" && justNow.staleRows[1].folder == "/Library/LaunchDaemons")
                #expect(justNow.showDeleteAll && justNow.startupNote == nil)
                #expect(justNow.groups.map(\.staleCount) == [0, 1, 0, 1, 0])
                #expect(justNow.groups[1].pills[0].stale && justNow.groups[1].openByDefault && justNow.groups[0].openByDefault)
                #expect(!justNow.groups[2].openByDefault && !justNow.groups[4].openByDefault)
                #expect(justNow.staleRows[0].a11yDelete == "Delete z-old.plist")

                let earlier = make(input(autostart: a, checkedAt: at(1, 15, 9, 5)))
                #expect(earlier.startupCaption == "6 items · checked 09:05")

                let removed = make(input(autostart: auto(), checkedAt: now, removed: 2))
                #expect(removed.startupCaption == "2 items · 2 removed" && removed.startupNote == .noStale)

                let one = make(input(autostart: auto(login: ["A"]), removed: 1))
                #expect(one.startupCaption == "1 item · 1 removed")

                let busy = make(input(autostart: a, checkedAt: now, deleting: [orphanU.path]))
                #expect(busy.startupBusy && busy.staleRows[0].deleting && !busy.staleRows[1].deleting)

                let noPerm = make(input(autostart: auto(login: nil)))
                #expect(noPerm.groups[0].noPermission && noPerm.groups[0].count == nil)
                #expect(make(input(autostart: nil)).startupWait)
                #expect(make(input(checking: true)).startupChecking)
                // a single orphan: no «Delete all»
                #expect(!make(input(autostart: auto(user: [orphanU]), checkedAt: now)).showDeleteAll)
            }
            withLanguage(.ru) {
                #expect(make(input(autostart: a)).startupCaption == "6 объектов")
                #expect(make(input(autostart: a, checkedAt: now.addingTimeInterval(-5))).startupCaption == "6 объектов · проверено только что")
                #expect(make(input(autostart: auto(), removed: 2)).startupCaption == "2 объекта · удалено 2")
            }
        }

        @Test func startupNotes() {
            let a = auto(user: [plist(userHome + "a.plist", orphan: true)])
            withLanguage(.en) {
                #expect(make(input(autostart: auto(), checkedAt: now)).startupNote == .noStale)
                #expect(make(input(autostart: a, checkedAt: now, plistFailure: .error("busy"))).startupNote == .failed("busy"))
                #expect(make(input(plistFailure: .cancelled)).startupNote == .cancelled)
                #expect(make(input(plistFailure: .timedOut)).startupNote == .timedOut)
                #expect(L.sysDeleteFailed("busy") == "Couldn’t delete: busy")
                #expect(L.sysDeleteCancelled == "Authorization cancelled. Nothing was deleted.")
                #expect(L.sysDeleteTimedOut == "Touch ID didn’t respond within 30 s. Nothing was deleted.")
                #expect(L.sysDeleteTimedOut != L.sysDeleteCancelled)
            }
        }

        @Test func confirmTitlesAndParagraphs() {
            withLanguage(.en) {
                #expect(SystemPageModel.startupConfirmTitle(1) == "Delete 1 startup item?")
                #expect(SystemPageModel.startupConfirmTitle(2) == "Delete 2 startup items?")
                #expect(SystemPageModel.startupConfirmTitle(5) == "Delete 5 startup items?")
                #expect(SystemPageModel.confirmParagraphs(userCount: 1, systemCount: 0) == [L.sysDeleteParagraphUser])
                #expect(SystemPageModel.confirmParagraphs(userCount: 0, systemCount: 2) == [L.sysDeleteParagraphSystem])
                #expect(SystemPageModel.confirmParagraphs(userCount: 1, systemCount: 1) == [L.sysDeleteParagraphUser, L.sysDeleteParagraphSystem])
                #expect(L.sysDeleteAll(3) == "Delete all (3)")
            }
            withLanguage(.ru) {
                #expect(SystemPageModel.startupConfirmTitle(1) == "Удалить 1 объект автозагрузки?")
                #expect(SystemPageModel.startupConfirmTitle(2) == "Удалить 2 объекта автозагрузки?")
                #expect(SystemPageModel.startupConfirmTitle(5) == "Удалить 5 объектов автозагрузки?")
            }
        }

        @Test func brewStates() {
            let detail = [BrewOutdatedPackage(name: "node", current: "22.9.0", latest: "22.11.0")]
            withLanguage(.en) {
                #expect(make(input(brewStatus: nil)).brewState == .wait)
                let none = make(input(brewStatus: .notInstalled))
                #expect(none.brewState == .none && none.brewCaption == "not installed" && none.brewNoteText == L.sysBrewNotInstalled)

                let out = make(input(outdated: ["node", "git"], detail: detail))
                #expect(out.brewState == .outdated && out.brewCaption == "4.6.0 · 2 of 48 packages outdated")
                #expect(out.brewRows == [BrewRow(id: "node", name: "node", sub: "22.9.0 → 22.11.0"),
                                         BrewRow(id: "git", name: "git", sub: "")])
                #expect(make(input(outdated: ["git"], installed: nil)).brewCaption == "4.6.0 · 1 outdated")
                #expect(make(input(outdated: ["git"], detail: nil)).brewRows[0].sub == "")

                let upd = make(input(outdated: ["a", "b", "c"], upgrading: true))
                #expect(upd.brewState == .updating && upd.brewCaption == "4.6.0 · updating")
                #expect(upd.brewProgressText == "Updating 3 packages…" && upd.brewUpdatingLabel == "Updating…")
                #expect(upd.brewRows.count == 3)
                let p = BrewProgress(phase: .upgrading, formula: "node", completed: 1, total: 3, downloadsDone: 3)
                #expect(make(input(outdated: ["a", "b", "c"], upgrading: true, progress: p)).brewProgressText == brewProgressText(p))
                // upgrading wins whatever the report says
                #expect(make(input(brewStatus: nil, upgrading: true)).brewState == .updating)

                let checked = at(1, 15, 10, 30)
                let ok = make(input(outdated: [], brewChecked: checked))
                #expect(ok.brewState == .ok && ok.brewCaption == "4.6.0 · 48 packages")
                #expect(ok.brewNoteText == "All 48 packages are up to date. Checked today at 10:30.")
                #expect(make(input(outdated: [], installed: nil)).brewNoteText == "All packages are up to date.")
                #expect(make(input(outdated: [], installed: nil)).brewCaption == "4.6.0")

                let failedCheck = make(input(outdated: nil))
                #expect(failedCheck.brewState == .checkFailed && failedCheck.brewNoteText == "Couldn’t check for outdated packages.")
                #expect(failedCheck.brewCaption == "4.6.0")
                #expect(make(input(outdated: nil, refreshing: true)).brewRefreshing)

                let upFail = make(input(outdated: ["node"], brewError: L.sysBrewFailedLine("Error: x")))
                #expect(upFail.brewState == .upgradeFailed("Update failed: Error: x") && upFail.brewNoteText == "Update failed: Error: x")
                #expect(upFail.brewRows.count == 1 && upFail.tag == .amber)

                let stopped = make(input(outdated: ["node"], notice: "Upgrade stopped: 2 of 3 packages upgraded"))
                #expect(stopped.brewState == .stopped("Upgrade stopped: 2 of 3 packages upgraded") && stopped.tag == .amber)
                #expect(stopped.brewCaption == "4.6.0 · 1 of 48 packages outdated")
                #expect(make(input(outdated: [], notice: "n")).tag == .green)

                #expect(make(input(brewStatus: .installed(version: nil), outdated: ["a"])).brewCaption
                        == "version unknown · 1 of 48 packages outdated")
            }
            withLanguage(.ru) {
                #expect(make(input(outdated: ["a", "b"])).brewCaption == "4.6.0 · 2 из 48 пакетов устарели")
                #expect(make(input(outdated: ["a"], installed: nil)).brewCaption == "4.6.0 · 1 пакет устарел")
                #expect(make(input(outdated: [])).brewCaption == "4.6.0 · 48 пакетов")
                #expect(make(input(outdated: [], brewChecked: at(1, 15, 10, 30))).brewNoteText
                        == "Все 48 пакетов актуальны. Проверено сегодня в 10:30.")
                #expect(make(input(outdated: ["a", "b", "c"], upgrading: true)).brewProgressText == "Обновляю 3 пакета…")
                #expect(make(input(brewStatus: .notInstalled)).brewCaption == "не установлен")
            }
        }

        @Test func brewHelpers() {
            #expect(SystemPageModel.brewVersionNumber("Homebrew 4.6.0") == "4.6.0")
            #expect(SystemPageModel.brewVersionNumber("4.6.0") == "4.6.0")
            withLanguage(.en) {
                #expect(SystemPageModel.brewCheckedText(checkedAt: at(1, 15, 8, 5), now: now) == "Checked today at 08:05.")
                #expect(SystemPageModel.brewCheckedText(checkedAt: at(1, 12, 9, 0), now: now) == "Checked Jan 12, 09:00.")
                #expect(SystemPageModel.brewCheckedText(checkedAt: nil, now: now) == "")
                #expect(SystemPageModel.checkedCaption(checkedAt: now.addingTimeInterval(-59), now: now) == " · checked just now")
                #expect(SystemPageModel.checkedCaption(checkedAt: at(1, 15, 11, 30), now: now) == " · checked 11:30")
            }
        }

        @Test func energyRowsAndDirty() {
            withLanguage(.en) {
                let m = make(input())
                #expect(m.energyRows.map(\.spec.key) == ["displaysleep", "sleep", "disksleep", "powernap", "lowpowermode",
                                                         "standby", "womp", "hibernatemode", "tcpkeepalive", "lidwake"])
                #expect(m.energyRows.map(\.spec.kind) == [.number, .number, .number, .toggle, .toggle, .toggle, .toggle,
                                                          .text, .readOnly, .readOnly])
                #expect(m.energyRows[0].battery == EnergyCell(raw: "2", shown: "2", dirty: false))
                #expect(m.energyRows[3].battery.shown == "off" && m.energyRows[3].ac.shown == "on")
                #expect(m.energyRows[2].battery == EnergyCell(raw: nil, shown: "—", dirty: false))   // disksleep missing
                #expect(m.energyRows[6].battery.raw == nil && m.energyRows[6].ac.shown == "on")      // womp AC only
                #expect(m.energyRows[7].battery.shown == "3" && m.energyRows[8].battery.shown == "on")
                #expect(m.energyRows[0].spec.label == "Display sleep, min")

                let dirty = make(input(pending: [EnergyChange(bucket: .battery, key: "displaysleep", value: "5"),
                                                 EnergyChange(bucket: .ac, key: "powernap", value: "0")]))
                #expect(dirty.dirtyCount == 2 && dirty.showActionBar)
                #expect(dirty.energyRows[0].battery == EnergyCell(raw: "5", shown: "5", dirty: true))
                #expect(dirty.energyRows[3].ac == EnergyCell(raw: "0", shown: "off", dirty: true))
                #expect(!dirty.energyRows[0].ac.dirty)

                #expect(make(input(energy: nil)).energyWait)
                let empty = make(input(energy: EnergySettings(battery: [], ac: [])))
                #expect(!empty.energyWait && empty.energyEmpty && empty.energyRows.isEmpty)
                #expect(make(input()).energyCaption == "changes require an administrator password")
                #expect(make(input(apply: .applied)).showApplied && make(input(apply: .applied)).showActionBar)
            }
        }

        @Test func energyDefaultsAndReset() {
            let d = SystemPageModel.energyDefaults
            #expect(d["displaysleep"]! == ("2", "10") && d["sleep"]! == ("1", "1") && d["disksleep"]! == ("10", "10"))
            #expect(d["powernap"]! == ("0", "1") && d["lowpowermode"]! == ("0", "0") && d["standby"]! == ("1", "1"))
            #expect(d["womp"]!.battery == nil && d["womp"]!.ac == "1")
            #expect(d["hibernatemode"] == nil)

            let e = energy()   // battery displaysleep 2 sleep 1 powernap 0; ac displaysleep 10 sleep 0 powernap 1 womp 1
            let reset = SystemPageModel.resetChanges(energy: e, pending: [])
            #expect(reset == [EnergyChange(bucket: .ac, key: "sleep", value: "1")], "only the cells that differ are staged (got \(reset))")
            // an edit away from the default is replaced by the default; womp battery (no default, absent anyway) untouched
            let edited = [EnergyChange(bucket: .battery, key: "displaysleep", value: "30")]
            #expect(SystemPageModel.resetChanges(energy: e, pending: edited).contains(EnergyChange(bucket: .ac, key: "sleep", value: "1")))
            #expect(!SystemPageModel.resetChanges(energy: e, pending: edited).contains { $0.key == "displaysleep" })
            let withWompBattery = energy(battery: [("womp", "1")], ac: [("womp", "0")])
            #expect(SystemPageModel.resetChanges(energy: withWompBattery, pending: [])
                    == [EnergyChange(bucket: .ac, key: "womp", value: "1")], "womp has no battery default: that cell is left alone")

            #expect(make(input()).resetAvailable)
            let atDefaults = energy(battery: [("displaysleep", "2"), ("sleep", "1")], ac: [("displaysleep", "10"), ("sleep", "1")])
            let m = make(input(energy: atDefaults))
            #expect(!m.resetAvailable && !m.showActionBar, "everything at defaults and nothing pending: bar hidden")

            // updatedPending: editing back to the saved value clears the entry
            let p1 = SystemPageModel.updatedPending([], bucket: .battery, key: "sleep", value: "5", original: "1")
            #expect(p1 == [EnergyChange(bucket: .battery, key: "sleep", value: "5")])
            #expect(SystemPageModel.updatedPending(p1, bucket: .battery, key: "sleep", value: "7", original: "1")
                    == [EnergyChange(bucket: .battery, key: "sleep", value: "7")])
            #expect(SystemPageModel.updatedPending(p1, bucket: .battery, key: "sleep", value: "1", original: "1").isEmpty)
            #expect(SystemPageModel.effectiveValue(bucket: .battery, key: "sleep", energy: e, pending: p1) == "5")
            #expect(SystemPageModel.effectiveValue(bucket: .ac, key: "sleep", energy: e, pending: p1) == "0")
            #expect(SystemPageModel.effectiveValue(bucket: .battery, key: "disksleep", energy: e, pending: []) == nil)
        }

        @Test func pmsetCommandAndConfirm() {
            let changes = [EnergyChange(bucket: .ac, key: "sleep", value: "0"),
                           EnergyChange(bucket: .battery, key: "displaysleep", value: "5"),
                           EnergyChange(bucket: .battery, key: "powernap", value: "1")]
            #expect(SystemPageModel.pmsetCommand(changes) == "/usr/bin/pmset -b displaysleep 5 powernap 1 && /usr/bin/pmset -c sleep 0")
            #expect(SystemPageModel.pmsetCommand([changes[0]]) == "/usr/bin/pmset -c sleep 0", "no battery edits -> only -c")
            #expect(SystemPageModel.pmsetCommand([changes[1]]) == "/usr/bin/pmset -b displaysleep 5")
            #expect(SystemPageModel.pmsetCommand([]) == nil)
            #expect(SystemPageModel.pmsetCommand([EnergyChange(bucket: .ac, key: "sleep", value: "x")]) == nil, "non-integer value dropped")
            #expect(SystemPageModel.pmsetCommand([EnergyChange(bucket: .ac, key: "sl;eep", value: "1")]) == nil, "invalid key dropped")
            #expect(SystemPageModel.isValidPmsetKey("displaysleep") && !SystemPageModel.isValidPmsetKey("a b") && !SystemPageModel.isValidPmsetKey(""))

            withLanguage(.en) {
                // table order inside a bucket (displaysleep before powernap), battery before AC
                #expect(SystemPageModel.confirmLines(changes) == [
                    "On battery:", "• Display sleep, min: 5", "• Power Nap: on",
                    "On AC power:", "• System sleep, min: 0",
                ])
                #expect(SystemPageModel.confirmLines([changes[0]]) == ["On AC power:", "• System sleep, min: 0"])
                #expect(SystemPageModel.confirmLines([]).isEmpty)
                let m = make(input(pending: changes))
                #expect(m.confirmLines.count == 5 && m.confirmTitle == "Apply 3 changes?")
                #expect(L.sysEnergyConfirmTitle(1) == "Apply 1 change?" && L.sysEnergyApply(2) == "Apply (2)")
            }
            withLanguage(.ru) {
                #expect(SystemPageModel.confirmLines([changes[0]]) == ["От сети:", "• Сон системы, мин: 0"])
                #expect(L.sysEnergyConfirmTitle(1) == "Применить 1 изменение?" && L.sysEnergyConfirmTitle(2) == "Применить 2 изменения?"
                        && L.sysEnergyConfirmTitle(5) == "Применить 5 изменений?")
            }
        }

        @Test func energyBanners() {
            withLanguage(.en) {
                #expect(SystemPageModel.energyBannerText(.cancelled) == L.sysEnergyCancelled)
                #expect(SystemPageModel.energyBannerText(.timedOut) == L.sysEnergyTimedOut)
                #expect(SystemPageModel.energyBannerText(.error("exit 1")) == "Couldn’t apply: pmset returned an error (exit 1). Values were reverted.")
                #expect(Set([L.sysEnergyCancelled, L.sysEnergyTimedOut]).count == 2)
                #expect(make(input()).energyBanner == nil)
                #expect(make(input(apply: .failed(.timedOut))).energyBanner == L.sysEnergyTimedOut)
                #expect(make(input(apply: .failed(.cancelled))).energyBanner == L.sysEnergyCancelled)
                #expect(L.sysOK == "OK")
            }
            withLanguage(.ru) {
                #expect(L.sysOK == "OK" && L.commonOK != "OK")
                #expect(SystemPageModel.energyBannerText(.timedOut).hasPrefix("Touch ID не ответил за 30 с"))
            }
        }

        @Test func rowIdentity() {
            // A2: ids come from the wake-holder key / path / name; they are unique inside each list
            let m = make(input(holders: [caf, zoom], ignored: [IgnoredWakeHolder(key: backupd.key, since: nil)],
                               outdated: ["a", "b"]))
            #expect(Set(m.sleepRows.map(\.id)).count == m.sleepRows.count)
            #expect(m.hiddenRows.map(\.id) == ["backupd|"])
            #expect(m.brewRows.map(\.id) == ["a", "b"])
            #expect(m.energyRows.map(\.id) == m.energyRows.map(\.spec.key))
        }

        @Test func ignoredCodecKeepsDatesIso() {
            let d = at(1, 12, 9, 0)
            let data = AppSettings.encodeIgnoredWakeHolders([IgnoredWakeHolder(key: zoom.key, since: d)])
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            #expect(text.contains("\"since\":\"2026-01-1"), "since is stored as ISO-8601 (got \(text))")
        }
    }
}
