// Tests/MacDashboardTests/CommonStringsTests.swift
// REDESIGN-FOUNDATION: the common* strings match the handoff text exactly (strings.json › Shared, 00 §4.16/§7).
import Foundation
import Testing
@testable import MacDashboard

struct CommonStringsTests {
    @Test func commonStringsMatchHandoff() {
        let en = StringsEN(), ru = StringsRU()
        let rows: [(gotEN: String, wantEN: String, gotRU: String, wantRU: String)] = [
            (en.commonShowInFinder, "Show in Finder", ru.commonShowInFinder, "Показать в Finder"),
            (en.commonFirewall, "Firewall", ru.commonFirewall, "Брандмауэр"),
            (en.commonEnable, "Enable…", ru.commonEnable, "Включить…"),
            (en.commonDisk, "Disk", ru.commonDisk, "Диск"),
            (en.commonSetUp, "Set up…", ru.commonSetUp, "Настроить…"),
            (en.commonShow, "Show", ru.commonShow, "Показать"),
            (en.commonMacCantSleep, "Mac can’t sleep", ru.commonMacCantSleep, "Mac не засыпает"),
            (en.commonBattery, "Battery", ru.commonBattery, "Батарея"),
            (en.commonInstall, "Install…", ru.commonInstall, "Установить…"),
            (en.commonServiceRecommended, "service recommended", ru.commonServiceRecommended, "нужен сервис"),
            (en.commonClaudeBackup, "Claude backup", ru.commonClaudeBackup, "Бэкап Claude"),
            (en.commonCPU, "CPU", ru.commonCPU, "Процессор"),
            (en.commonMemory, "Memory", ru.commonMemory, "Память"),
            (en.commonStorage, "Storage", ru.commonStorage, "Хранилище"),
            (en.commonSecurity, "Security", ru.commonSecurity, "Безопасность"),
            (en.commonBackups, "Backups", ru.commonBackups, "Резервные копии"),
            (en.commonSystem, "System", ru.commonSystem, "Система"),
            (en.commonHistory, "History", ru.commonHistory, "История"),
            (en.commonLocalSnapshots, "Local snapshots", ru.commonLocalSnapshots, "Локальные снимки"),
            (en.commonFullDiskAccessNeeded, "Full Disk Access needed", ru.commonFullDiskAccessNeeded, "Нужен полный доступ к диску"),
            (en.commonCompressed, "Compressed", ru.commonCompressed, "Сжатая"),
            (en.commonOK, "OK", ru.commonOK, "в норме"),
            (en.commonCycles, "Cycles", ru.commonCycles, "Циклы"),
            (en.commonProtection, "Protection", ru.commonProtection, "Защита"),
            (en.commonUpdates, "Updates", ru.commonUpdates, "Обновления"),
            (en.commonCollectingData, "Collecting data…", ru.commonCollectingData, "Сбор данных…"),
            (en.commonAllGood, "All good", ru.commonAllGood, "Всё в порядке"),
            (en.commonNeedsAttention, "Needs attention", ru.commonNeedsAttention, "Требует внимания"),
            (en.commonThisMac, "This Mac", ru.commonThisMac, "Этот Mac"),
            (en.commonReport, "Report", ru.commonReport, "Отчёт"),
            (en.commonRefresh, "Refresh", ru.commonRefresh, "Обновить"),
            (en.commonRefreshReport, "Refresh report", ru.commonRefreshReport, "Обновить отчёт"),
            (en.commonNow, "Now", ru.commonNow, "Сейчас"),
            (en.commonTryAgain, "Try again", ru.commonTryAgain, "Повторить"),
            (en.commonShowLess, "Show less", ru.commonShowLess, "Свернуть"),
            (en.commonSetting, "Setting", ru.commonSetting, "Параметр"),
            (en.commonOnBattery, "Battery", ru.commonOnBattery, "От батареи"),
            (en.commonACPower, "AC power", ru.commonACPower, "От сети"),
            (en.commonNormal, "normal", ru.commonNormal, "норма"),
            (en.commonFree, "Free", ru.commonFree, "Свободно"),
            (en.commonChart, "Chart", ru.commonChart, "График"),
            (en.commonTable, "Table", ru.commonTable, "Таблица"),
            (en.commonRefreshing, "Refreshing…", ru.commonRefreshing, "Обновление…"),
            (en.commonCancel, "Cancel", ru.commonCancel, "Отмена"),
            (en.commonOpenPrivacySettings, "Open Privacy settings…", ru.commonOpenPrivacySettings, "Открыть «Конфиденциальность»…"),
            (en.commonUpdated("14:02"), "updated 14:02", ru.commonUpdated("14:02"), "обновлено 14:02"),
            (en.commonChecking, "Checking…", ru.commonChecking, "Проверка…"),
            (en.commonCritical, "Critical", ru.commonCritical, "Критично"),
            (en.commonLastData("10:29:52"), "last data — 10:29:52", ru.commonLastData("10:29:52"), "последние данные — 10:29:52"),
        ]
        #expect(rows.count == 49, "49 common rows")
        for r in rows {
            #expect(r.gotEN == r.wantEN, "\(r.wantEN)")
            #expect(r.gotRU == r.wantRU, "\(r.wantEN)")
        }
    }
}
