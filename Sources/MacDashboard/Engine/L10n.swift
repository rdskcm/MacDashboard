// Engine/L10n.swift
// In-app localization core. AppStrings is the compile-enforced string table
// protocol (a missing key on a future language struct is a compile error, unlike
// dictionary lookups). Foundation-only: also covered by Tests/MacDashboardTests.
import Foundation
import Observation

enum AppLanguage: String, CaseIterable {
    case ru, en
}

/// REDESIGN-SETTINGS: the persisted language choice; `system` follows the macOS preferred language.
enum LanguageChoice: String, CaseIterable { case system, en, ru }

extension LanguageChoice {
    /// Effective language for a choice; `system` follows the first preferred language (`ru…` → RU, anything else → EN).
    static func resolve(_ c: LanguageChoice, preferredLanguages: [String]) -> AppLanguage {
        switch c {
        case .en: return .en
        case .ru: return .ru
        case .system: return (preferredLanguages.first ?? "").hasPrefix("ru") ? .ru : .en
        }
    }
}

/// The full UI string table. Grouped with MARKs by card/screen; later migration
/// waves append members. Parameterized strings are funcs returning plain String
/// (never LocalizedStringKey — avoids SwiftUI's interpolation-localization trap).
protocol AppStrings {
    // MARK: App
    // The app name is deliberately NOT here — it is a brand, not a phrase to
    // translate, and lives in `AppInfo.name` (V2-NAME-ONE).
    /// Decimal separator for number formatting (`fmtNum`): "," RU, "." EN.
    var decimalSeparator: String { get }

    // MARK: Settings
    var settingsLanguageLabel: String { get }
    var settingsIntervalLabel: String { get }
    func settingsIntervalOption(_ seconds: Int) -> String
    /// Per-value note below the interval segmented control (§7.3, SW:96-99),
    /// switching with the current `fastIntervalSeconds` selection.
    var settingsSectionBackup: String { get }
    var settingsMenuLanguageHint: String { get }
    var settingsRelaunchNow: String { get }
    var settingsSectionGeneral: String { get }
    var settingsSectionMonitoring: String { get }
    var settingsVersionLabel: String { get }
    var settingsWindowTitle: String { get }
    var settingsSectionIPhone: String { get }
    var settingsKeepArchivesLabel: String { get }
    var settingsSectionAbout: String { get }
    var settingsInstantNote: String { get }
    var settingsOptionSystem: String { get }
    var settingsThemeLabel: String { get }
    var settingsThemeLight: String { get }
    var settingsThemeDark: String { get }
    var settingsOrbsLabel: String { get }
    var settingsOrbsSub: String { get }
    var settingsRimLabel: String { get }
    var settingsRimSub: String { get }
    var settingsRimNarrow: String { get }
    var settingsRimMedium: String { get }
    var settingsRimWide: String { get }
    var settingsLaunchAtLoginLabel: String { get }
    var settingsLaunchAtLoginApproval: String { get }
    var settingsSnapshotLabel: String { get }
    var settingsSnapshotSub: String { get }
    var settingsLowSpaceLabel: String { get }
    var settingsClaudeLogLabel: String { get }
    var settingsChoose: String { get }
    var settingsPathMissing: String { get }
    var settingsWarnAfterLabel: String { get }
    var settingsWarnAfterSub: String { get }
    var settingsWarnAfterFewer: String { get }
    var settingsWarnAfterMore: String { get }
    var settingsPermTitle: String { get }
    var settingsPermBody: String { get }
    var settingsReportFolderLabel: String { get }
    var settingsMenuItem: String { get }
    func settingsLowSpaceOption(_ percent: Int) -> String
    func settingsWarnAfterDays(_ days: Int) -> String
    // REDESIGN-NOTIFY (handoff 11-settings.md :26, Settings.dc.html :188-195)
    var settingsNotifyCaption: String { get }
    var settingsNotifyProtection: String { get }
    var settingsNotifyDisk: String { get }
    var settingsNotifyBattery: String { get }
    var settingsNotifyBackup: String { get }
    var settingsNotifyUpdates: String { get }
    var settingsNotifyCrashes: String { get }
    var settingsNotifyDenied: String { get }
    var settingsNotifyOpen: String { get }
    var settingsNotifyOpenA11y: String { get }
    var settingsAutoReadLabel: String { get }
    var settingsAutoReadSub: String { get }
    var settingsArchiveFolderLabel: String { get }
    func settingsArchiveFolderMoveFailed(_ n: Int) -> String

    // MARK: Main dashboard (header + tab picker)
    var mainCollectingInfo: String { get }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { get }
    var overviewKickerMemory: String { get }
    var overviewKickerProcesses: String { get }
    var overviewKickerFolders: String { get }
    var overviewKickerSystem: String { get }
    func headerLoadChip(_ load: String, _ ncpu: Int) -> String
    func headerUptimeChip(_ uptime: String) -> String
    /// Status chip label when `assessment.problems` is non-empty (pairs with `recommendationsAllGood`).
    var headerStatusNeedsAttention: String { get }

    // MARK: KPI tiles
    var kpiCpuLabel: String { get }
    /// V2-TILES footer: all three load averages, e.g. "нагрузка 1,73 · 2,05 · 2,20".
    /// The core count is NOT repeated here — it already lives in the header's load chip.
    var kpiSwapLabel: String { get }
    func kpiSwapUnit(_ total: String) -> String
    func kpiSwapSub(_ free: String) -> String
    /// V2-DISK-TILE-LABEL: the Disk tile leads with FREE space, so its header label
    /// names the quantity («Диск · свободно» / "Disk · free") — do not shorten to the
    /// bare noun; the tile has no other slot that can say what the big number is.
    var kpiDiskLabel: String { get }
    func kpiDiskUnit(_ size: String) -> String
    func kpiDiskUsedPct(_ pct: Int) -> String
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String
    func kpiDiskPurgeableDetail(_ base: String, _ purgeable: String) -> String
    var kpiBatteryLabel: String { get }
    func kpiBatteryCycles(_ n: Int) -> String

    // MARK: Security card
    var securityTitle: String { get }
    var securityFileVault: String { get }
    var securitySip: String { get }
    var securityFirewall: String { get }
    var securityGatekeeper: String { get }
    var securityFileVaultTip: String { get }
    var securitySipTip: String { get }
    var securityFirewallTip: String { get }
    var securityGatekeeperTip: String { get }

    // MARK: Report tab
    var reportPlaceholder: String { get }
    var reportShowInFinder: String { get }
    var reportCopy: String { get }
    var reportCollecting: String { get }
    func reportFileUpdatedCaption(_ time: String) -> String
    var reportCopied: String { get }
    var reportNotUpdated: String { get }
    func reportNotUpdatedShowing(_ time: String) -> String
    var reportFailedTimedOut: String { get }
    var reportFailedNoReading: String { get }

    // MARK: Recommendations card
    var recommendationsTitle: String { get }
    var recommendationsAllGood: String { get }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { get }
    var adviceTrashConfirmButton: String { get }
    var adviceTrashError: String { get }
    var adviceTrashNotPermitted: String { get }
    var adviceTrashOpenAutomation: String { get }
    var adviceFirewallConfirmTitle: String { get }
    var adviceFirewallConfirmMessage: String { get }
    var adviceFirewallConfirmButton: String { get }
    var adviceFirewallError: String { get }
    var adviceCancel: String { get }

    // MARK: Shared (cross-card)
    var sharedUnavailable: String { get }
    var sharedCollectingData: String { get }
    var sharedEmpty: String { get }
    func sharedMoreN(_ n: Int) -> String
    var sharedCollapse: String { get }

    // MARK: Storage — shared folder labels
    var storageColShare: String { get }
    var storageTrashLabel: String { get }
    var storageAppsLabel: String { get }



    // MARK: Storage — folders that could not be read (V2-FDA-DEGRADE)
    func storageFoldersNoFDA(_ folders: String) -> String
    var storageFoldersNoFDAButton: String { get }
    var storageFoldersNoFDAButtonA11y: String { get }
    // MARK: Storage — folders the count did not reach before its deadline (SERVICE-DIRS-TIMEOUT)
    func storageFoldersNotMeasured(_ folders: String) -> String

    // MARK: Storage — Диски (SMART)
    func storageSmartUpdatedCaption(_ time: String) -> String

    // MARK: Process cards
    var processesTitle: String { get }
    var processSegCPU: String { get }
    var processSegMem: String { get }
    var processesMetricA11y: String { get }
    var processLoadingDetails: String { get }
    var processDetailPath: String { get }
    var processQuit: String { get }
    var processForceQuit: String { get }
    var processForceQuitConfirm: String { get }
    func processTerminateA11y(_ name: String) -> String
    func processKillA11y(_ name: String) -> String

    // MARK: Memory page (REDESIGN-MEMORY)
    var memUsageTitle: String { get }
    func memUsageCaption(_ total: String) -> String
    var memCompTitle: String { get }
    func memCompCaption(_ total: String) -> String
    var memProcsTitle: String { get }
    func memProcsTop(_ n: Int) -> String
    func memProcCPU(_ pct: String) -> String
    var memUsed: String { get }
    func memHeroNote(_ total: String, _ pct: String) -> String
    var memPurgeable: String { get }
    var memSwap: String { get }
    func memSwapOf(_ pct: String, _ total: String) -> String
    var memFileCache: String { get }
    var memOtherShort: String { get }
    var memTagLow: String { get }
    var memTagMedium: String { get }
    var memTagHigh: String { get }
    var memTagUnknown: String { get }
    var memTagReadFailed: String { get }
    func memUpdatesEvery(_ seconds: Int) -> String
    var memFailTimedOut: String { get }
    var memFailNoReading: String { get }
    var memCompViewA11y: String { get }

    // MARK: Storage page (REDESIGN-STORAGE)
    var groupingSeparator: String { get }
    var storageTagDriveFailing: String { get }
    var storageTagAlmostFull: String { get }
    var storageTagDriveWorn: String { get }
    var storageTagLowSpace: String { get }
    var storageDiskTitle: String { get }
    var storageFree: String { get }
    func storageHeroNote(_ size: String, _ pct: String) -> String
    var storageData: String { get }
    var storageSystem: String { get }
    var storagePurgeable: String { get }
    var storageNVMeTemp: String { get }
    var storageTempNormal: String { get }
    var storageTempHigh: String { get }
    func storageCelsius(_ t: Int) -> String
    var storageDownloads: String { get }
    var storageCaches: String { get }
    func storageFreeItem(_ name: String, _ size: String) -> String
    func storageNoteLow(_ pct: String) -> String
    func storageNoteLowItems(_ pct: String, _ list: String) -> String
    func storageNoteCritical(_ pct: String) -> String
    func storageNoteCriticalItems(_ pct: String, _ list: String) -> String
    var storageSettingsButton: String { get }
    var storageSettingsA11y: String { get }
    var storageFoldersTitle: String { get }
    var storageSegHome: String { get }
    var storageSegSystem: String { get }
    var storageSegA11y: String { get }
    var storageCaptionTop: String { get }
    func storageCaptionCounted(_ age: String) -> String
    func storageAgo(_ m: Int) -> String
    var storageJustNow: String { get }
    var storageCaptionCounting: String { get }
    var storageCaptionCountFailed: String { get }
    func storageCaptionTrashEmptied(_ size: String) -> String
    var storageCaptionSomeHidden: String { get }
    var storageCounting: String { get }
    var storageCountTimedOut: String { get }
    var storageCountNoResult: String { get }
    var storageCountTryAgainA11y: String { get }
    var storageNoFolders: String { get }
    func storageShowA11y(_ name: String) -> String
    var storageEmptyTrashButton: String { get }
    var storageEmptyTrashA11y: String { get }
    var storageConfirmTitle: String { get }
    func storageConfirmText(_ n: Int, _ size: String) -> String
    func storageConfirmTextNoCount(_ size: String) -> String
    var storageConfirmEmpty: String { get }
    var storageConfirmCancel: String { get }
    func storageFDANote(_ names: String) -> String
    func storageFDANoteMore(_ names: String, _ n: Int) -> String
    var storageFDAButtonA11y: String { get }
    var storageSmartCardTitle: String { get }
    var storageSubInternalOK: String { get }
    var storageSubExternalOK: String { get }
    var storageSubInternalNoData: String { get }
    var storageSubExternalNoData: String { get }
    var storageSubInternalFailing: String { get }
    var storageSubExternalFailing: String { get }
    func storageSubInternalWorn(_ pct: String) -> String
    func storageSubExternalWorn(_ pct: String) -> String
    var storageStatusUnavailable: String { get }
    var storageStatusFailing: String { get }
    func storageWearNote(_ pct: String) -> String
    var storageKVTemp: String { get }
    var storageKVUsed: String { get }
    var storageKVSpare: String { get }
    var storageKVSpareThreshold: String { get }
    var storageKVHours: String { get }
    var storageKVCycles: String { get }
    var storageKVUnsafe: String { get }
    var storageKVRead: String { get }
    var storageKVWritten: String { get }
    var storageKVMediaErrors: String { get }
    var storageKVErrorLog: String { get }
    var storageKVCritical: String { get }
    var storageYes: String { get }
    var storageNo: String { get }
    var storageToolsInstallable: String { get }
    var storageToolsNeedsBrew: String { get }
    var storageToolsInstall: String { get }
    var storageToolsInstallA11y: String { get }
    var storageToolsHowToBrew: String { get }
    var storageToolsHowToBrewA11y: String { get }
    func storageInstallFailedCode(_ c: Int32) -> String
    var storageInstallTimedOut: String { get }
    var storageInstallNoBrew: String { get }
    var storageInstallRetryA11y: String { get }
    var storageRefreshA11y: String { get }

    // MARK: CPU page + restyled Processes card (REDESIGN-CPU)
    var cpuLiveSnapshot: String { get }
    var cpuUsage: String { get }
    var cpuUser: String { get }
    var cpuSystem: String { get }
    var cpuSocTemperature: String { get }
    var cpuSocHot: String { get }
    var cpuSocWarm: String { get }
    var cpuNoReading: String { get }
    func cpuLoadNote(_ a: String, _ b: String, _ c: String, _ cores: Int) -> String
    func cpuHighLoadFor(_ min: Int) -> String
    var cpuTagHigh: String { get }
    var cpuTagReadError: String { get }
    func cpuSubLive(_ cores: Int, _ seconds: Int) -> String
    var cpuSubCollecting: String { get }
    var cpuFailTimedOut: String { get }
    var cpuFailNoReading: String { get }
    /// REFRESH-BUTTONS-AUDIT: appended to the CPU, Memory and Battery failure notes — their loops retry on their own, there is no button.
    var readRetriesAutomatically: String { get }
    var procsTopByCPU: String { get }
    var procsTopByMemory: String { get }
    func procsCount(_ n: Int) -> String
    var procsFoot: String { get }
    var processOwner: String { get }
    var processQuitting: String { get }
    func processForceQuitQuestion(_ name: String) -> String
    func processSignalFailed(_ name: String) -> String

    // MARK: Maintenance card
    var maintenanceBrewNotInstalled: String { get }
    var maintenanceBrewVersionUnknown: String { get }
    var maintenanceBrewOutdatedCheckFailed: String { get }
    var maintenanceUpdatesTip: String { get }
    var maintenanceCrashesTip: String { get }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String
    func maintenanceCrashRevealA11y(_ process: String) -> String
    func maintenanceAndMore(_ n: Int) -> String
    func maintenanceBrewConfirmTitle(_ n: Int) -> String
    var maintenanceBrewConfirmButton: String { get }
    var maintenanceBrewUpgrading: String { get }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String
    var maintenanceBrewUpgradeFailed: String { get }
    var maintenanceBrewStopButton: String { get }
    var maintenanceBrewStopA11y: String { get }
    var maintenanceBrewStopping: String { get }
    var maintenanceBrewRechecking: String { get }
    func maintenanceBrewStopped(_ upgraded: Int, _ total: Int) -> String
    var maintenanceBrewStoppedUnknown: String { get }
    var maintenanceOpenSoftwareUpdate: String { get }

    // MARK: Time Machine card
    var timeMachineNotConfigured: String { get }
    var timeMachineDestination: String { get }
    var timeMachineType: String { get }
    var timeMachineTypeLocal: String { get }
    var timeMachineQuota: String { get }
    var timeMachineLastBackup: String { get }
    /// V2-TM-CONNSTATE: label + value of the row shown only while the destination has no
    /// mount point (disk unplugged, or network share not mounted).
    var timeMachineConnection: String { get }
    var timeMachineConnectionNone: String { get }
    var timeMachineSnapshots: String { get }
    var timeMachineSnapshotsNone: String { get }
    func timeMachineSnapshotsCount(_ n: Int) -> String
    func timeMachineSnapshotsLast(_ date: String) -> String
    var timeMachinePurgeable: String { get }
    /// Records the constraint the tip text encodes: the number is a VOLUME total that also
    /// covers caches, and a per-snapshot size is not a real number because snapshots share
    /// disk blocks (BACKLOG F1).
    var timeMachinePurgeableTip: String { get }

    // MARK: Claude backup card (BACKUP-AGE)
    var claudeBackupCardTitle: String { get }
    var claudeBackupAgeLabel: String { get }
    var claudeBackupLastLabel: String { get }
    var claudeBackupLimitLabel: String { get }
    func claudeBackupAgo(_ age: String) -> String
    var claudeBackupJustNow: String { get }
    var claudeBackupNoneFound: String { get }
    var claudeBackupUnreadable: String { get }

    // MARK: Autostart card
    var autostartNoPermission: String { get }
    /// Detail for `autostartDeleteError` when a delete request contains no path the
    /// validator accepts — both the single-path guard and the bulk "nothing survived
    /// validation" case, which used to no-op silently (V2-POLISH B7).
    var autostartDeleteInvalidPath: String { get }
    /// Detail for `autostartDeleteError` when a bulk delete had more than one failure:
    /// how many of how many, plus the first failure's own (already localized) message.
    func autostartDeleteBulkFailure(_ failed: Int, _ total: Int, _ detail: String) -> String

    // MARK: Memory card
    var memoryLegendActive: String { get }
    var memoryLegendWired: String { get }
    var memoryLegendOther: String { get }
    var memoryLegendInactive: String { get }
    var memoryLegendSpeculative: String { get }
    var memoryLegendFree: String { get }
    var memoryNoteActive: String { get }
    var memoryNoteWired: String { get }
    var memoryNoteOther: String { get }
    var memoryNoteInactive: String { get }
    var memoryNoteSpeculative: String { get }
    var memoryNoteFree: String { get }

    // MARK: History page (REDESIGN-HISTORY)
    func historySub(_ samples: Int) -> String                 // "500 daily samples · mac_check_state.json"
    var historyTagUnreadable: String { get }                   // "file unreadable"
    var historyTagReading: String { get }                      // "reading…"
    func historySince(day: Int, month: Int, year: Int?) -> String   // "since Sep 2, 2025" / "с 2 сентября 2025"
    var historyTitleDisk: String { get }                       // "Disk: used"
    var historyTitleBattery: String { get }                    // "Battery: maximum capacity"
    var historyTitleCycles: String { get }                     // "Battery: charge cycles"
    var historyTitleSwap: String { get }                       // "Swap: used"
    var historyAllMetrics: String { get }                      // "All metrics"
    func historyDaysCaption(_ n: Int) -> String                // "30 days"
    func historySamples(_ n: Int) -> String                    // "1 sample" / "5 samples"
    var historyEmptyTitle: String { get }                      // "Not enough data yet"
    func historyEmptySub(_ samples: Int) -> String             // "1 sample · the chart needs at least 2"
    var historyNeedsTwo: String { get }                        // "Needs at least 2 samples"
    func historyOnlyMonths(_ n: Int) -> String                 // "Only 4 months of data"
    var historyRangeMonth: String { get }                      // "1M"   (kept, value changes)
    var historyRangeQuarter: String { get }                    // "3M"
    var historyRangeYear: String { get }                       // "1Y"
    var historyRangeAll: String { get }                        // "All"
    var historyRangeA11y: String { get }                       // "Range" (kept, value changes)
    var historyMetricPickerDisk: String { get }                // kept
    var historyMetricPickerBattery: String { get }             // kept
    var historyMetricPickerCycles: String { get }              // kept
    var historyMetricPickerSwap: String { get }                // kept
    var historyMetricA11y: String { get }                      // kept
    var historyViewA11y: String { get }                        // "History view"
    func historyDeltaPerMonth(_ value: String) -> String       // "+24 GB per month"
    func historyCycles(_ n: Int) -> String                     // "412 cycles"
    func historyPercent(_ n: Int) -> String                    // "76%" / "76 %"
    func historyPercentText(_ number: String) -> String        // "0.37%" / "0,37 %" (already formatted number)
    var historyColDate: String { get }                         // kept
    var historyColDiskUsed: String { get }                     // kept
    var historyColFree: String { get }                         // kept
    var historyColCycles: String { get }                       // kept
    func historyGbValue(_ n: Int) -> String                    // kept, "312 GB"
    var historyBatteryHelp: String { get }                     // "Maximum capacity, not the current charge"
    var historyTableA11y: String { get }                       // "Sample history"
    var historyReading: String { get }                         // "Reading history…"
    var historyUnreadableTitle: String { get }                 // "Can’t read the history file"
    var historyTryAgainA11y: String { get }                    // "Read the history file again"
    var historyRefreshA11y: String { get }                     // "Reload history from disk"
    func historyShortDate(day: Int, month: Int, year: Int?) -> String            // "Oct 14" · "Sep 2, 2025"
    func historyTooltipDate(weekday: Int, day: Int, month: Int, year: Int) -> String   // "Fri, Oct 17, 2026"
    func historyMonthLabel(_ month: Int) -> String             // "Jun" / "июнь" (standalone form)
    var historyRestartTitle: String { get }                    // kept
    func historyRestartDetail(_ file: String) -> String        // kept
    var historyRestartReveal: String { get }                   // kept
    var historyRestartRevealA11y: String { get }               // kept
    var historyRestartHide: String { get }                     // kept
    var historyRestartHideA11y: String { get }                 // kept

    // MARK: Energy card
    var energyValueOn: String { get }
    var energyValueOff: String { get }
    func energyApply(_ n: Int) -> String

    // MARK: Battery page (REDESIGN-BATTERY; strings.json › Battery + 06-battery.md)
    var batteryLoadingText: String { get }
    func batteryMinutes(_ m: Int) -> String
    func batteryHoursMinutes(_ h: Int, _ m: Int) -> String
    var batteryStatusOnBattery: String { get }
    func batteryStatusRemaining(_ time: String) -> String
    var batteryStatusCharging: String { get }
    func batteryStatusUntilFull(_ time: String) -> String
    var batteryStatusACFull: String { get }
    var batteryStatusACNotCharging: String { get }
    var batterySectionNow: String { get }
    var batteryLabelPower: String { get }
    func batteryWatts(_ v: String) -> String
    var batteryLabelCurrent: String { get }
    var batteryLabelVoltage: String { get }
    func batteryVolts(_ v: String) -> String
    var batteryLabelTemperature: String { get }
    func batteryCelsius(_ v: String) -> String
    func batteryCellsLine(_ joined: String) -> String
    var batterySectionCapacity: String { get }
    var batteryCapMax: String { get }
    func batteryMAh(_ n: Int) -> String
    var batteryCapDesign: String { get }
    var batteryCapHealth: String { get }
    var batteryCapCycles: String { get }
    func batteryCyclesOf(_ cycles: String, _ design: String) -> String
    var batteryCapCurrentCharge: String { get }
    var batteryCapCondition: String { get }
    var batterySectionCharging: String { get }
    var batteryChargeAdapter: String { get }
    var batteryChargeProtocol: String { get }
    var batteryChargeProfiles: String { get }
    var batteryChargeCurrentLabel: String { get }
    var batteryChargeStatus: String { get }
    func batteryAdapterUsbC(_ watts: Int) -> String
    func batteryAdapterWattsSuffix(_ watts: Int) -> String
    var batteryAdapterWireless: String { get }
    func batteryUsbPdLine(_ v: String, _ a: String) -> String
    var batteryStatusFullyCharged: String { get }
    var batteryStatusNotCharging: String { get }
    func batteryNotChargingCode(_ n: Int) -> String
    var batterySectionLifetime: String { get }
    var batteryLifetimeTempLabel: String { get }
    func batteryLifetimeTempValue(_ min: Int, _ avg: String, _ max: Int) -> String
    var batteryLifetimeMaxCharge: String { get }
    var batteryLifetimeMaxDischarge: String { get }
    var batteryLifetimeVoltage: String { get }
    func batteryLifetimeVoltageRange(_ min: String, _ max: String) -> String
    var batteryLifetimeOperatingTime: String { get }
    var batteryDetailLowPower: String { get }
    var batteryDetailPassportSection: String { get }
    var batteryDetailManufacturer: String { get }
    var batteryDetailSerial: String { get }
    var batteryDetailMfgDate: String { get }
    func batSub(_ cycles: Int?) -> String
    func batTagCapacity(_ pct: String) -> String
    var batTagReadFailed: String { get }
    var batTagUnknown: String { get }
    func batNowCaption(_ time: String) -> String
    var batFailTimedOut: String { get }
    var batFailNoReading: String { get }
    var batFailShowingSaved: String { get }
    var batHealthNote: String { get }
    var batWornNote: String { get }
    func batServiceNote(_ parts: [String]) -> String
    func batServiceCapacity(_ pct: String) -> String
    var batServiceCycles: String { get }
    var batBatterySettings: String { get }
    var batBatterySettingsA11y: String { get }
    var batChargingCaption: String { get }
    var batLifetimeCaption: String { get }
    func batHours(_ s: String) -> String
    var batEstimate: String { get }
    func batCode(_ code: String) -> String
    var batHistoryTitle: String { get }
    func batHistoryDelta(_ signedPct: String, months: Int) -> String
    var batHistoryNotEnough: String { get }
    var batHistoryFoot: String { get }
    var batHistoryFootA11y: String { get }
    var privilegedTimedOut: String { get }   // REDESIGN-SECURITY step 2
    var secGatekeeperError: String { get }
    var secRestartRequired: String { get }   // REDESIGN-SECURITY (step 1 minimum; the rest of the table lands in step 3)
    // MARK: Security page (REDESIGN-SECURITY)
    func shortDateTime(_ d: Date) -> String
    var secSub: String { get }
    func secTagOffCount(_ n: Int) -> String
    func secTagEnabling(_ p: SecurityProtection) -> String
    var secTagUpdates: String { get }
    func secTagCrashes(_ n: Int) -> String
    func secTagOnCount(_ n: Int) -> String
    func secCaptionOn(_ n: Int) -> String
    func secCaptionEnabling(_ p: SecurityProtection) -> String
    var secValueOn: String { get }
    var secValueOff: String { get }
    var secValueEnabling: String { get }
    var secNoteUnknown: String { get }
    var secNoteTouchID: String { get }
    var secNoteWaitingTouchID: String { get }
    var secNoteFileVault: String { get }
    var secNoteFileVaultOpened: String { get }
    var secNoteSip: String { get }
    var secOpenSettings: String { get }
    var secBannerTimeout: String { get }
    var secBannerCancelled: String { get }
    func secBannerFailed(_ p: SecurityProtection, _ detail: String) -> String
    func secStillOff(_ p: SecurityProtection) -> String
    func secEnableA11y(_ name: String) -> String
    var secOpenFileVaultA11y: String { get }
    var secRefreshA11y: String { get }
    var secUpdatesCaptionChecking: String { get }
    var secUpdatesCaptionNever: String { get }
    func secUpdatesCaptionAvailable(_ n: Int) -> String
    var secCheckingUpdates: String { get }
    var secUpdatesNone: String { get }
    func secUpdatesAvailable(_ n: Int) -> String
    var secUpdatesRestart: String { get }
    var secUpdatesFailed: String { get }
    var secInstallA11y: String { get }
    var secOpenSoftwareUpdateA11y: String { get }
    var secCrashesTitle: String { get }
    var secCrashesCaption: String { get }
    func secCrashesCaptionCount(_ n: Int) -> String
    var secNoCrashes: String { get }
    var secKernelPanic: String { get }
    func secCrashLastToday(_ t: String) -> String
    func secCrashDate(_ d: String) -> String
    var secCrashFootDefault: String { get }
    func secCrashFootOpened(_ file: String) -> String
    var secOpenInConsole: String { get }
    func secCrashRowA11y(_ name: String, _ count: String) -> String
    var secCrashHide: String { get }
    var secCrashDelete: String { get }
    var secCrashUnhide: String { get }
    func secCrashHideA11y(_ name: String) -> String
    func secCrashDeleteA11y(_ name: String) -> String
    func secCrashUnhideA11y(_ name: String) -> String
    func secCrashDeleteConfirmTitle(_ n: Int) -> String
    var secCrashDeleteParagraphUser: String { get }
    var secCrashDeleteParagraphSystem: String { get }
    func secCrashDeleteRefused(_ name: String) -> String
    // MARK: Backups page (REDESIGN-BACKUPS)
    var bkSub: String { get }
    var bkTagTMNotSet: String { get }
    var bkTagOverdue: String { get }
    var bkTagBacking: String { get }
    var bkTagClaudeStale: String { get }
    var bkTagClaudeMissing: String { get }
    var bkTagClaudeUnreadable: String { get }
    var bkCaptionAutoHourly: String { get }
    var bkCaptionAutoDaily: String { get }
    var bkCaptionAutoWeekly: String { get }
    func bkCaptionAutoEveryHours(_ n: Int) -> String
    var bkCaptionManual: String { get }
    var bkCaptionDiskNotConnected: String { get }
    var bkCaptionBacking: String { get }
    var bkNoteNotSet: String { get }
    func bkNoteOverdueDisconnected(_ days: Int, _ disk: String) -> String
    func bkNoteOverdueDisconnectedHot(_ days: Int, _ disk: String) -> String
    func bkNoteOverdueConnected(_ days: Int) -> String
    func bkNoteOverdueConnectedHot(_ days: Int) -> String
    var bkTheBackupDisk: String { get }
    func bkDaysAgo(_ n: Int) -> String
    func bkToday(_ t: String) -> String
    func bkYesterday(_ t: String) -> String
    var bkLastBackup: String { get }
    var bkNextBackup: String { get }
    func bkNextIn(_ d: String) -> String
    var bkNextSoon: String { get }
    var bkNextWhenConnected: String { get }
    var bkNextAfterThis: String { get }
    var bkNextAutoOff: String { get }
    func bkFree(_ s: String) -> String
    var bkNotConnected: String { get }
    var bkPurgeable: String { get }
    var bkPurgeableNote: String { get }
    func bkLatestSnapshotToday(_ t: String) -> String
    func bkLatestSnapshot(_ d: String) -> String
    var bkBackUpNow: String { get }
    var bkBackUpNowA11y: String { get }
    func bkConnectFirst(_ disk: String) -> String
    var bkStop: String { get }
    var bkStopA11y: String { get }
    var bkSetUpA11y: String { get }
    func bkBackingTo(_ disk: String) -> String
    func bkProgressBytes(_ done: String, _ total: String) -> String
    func bkTimeLeft(_ d: String) -> String
    var bkPreparing: String { get }
    func bkFindingChanges(_ count: String) -> String
    var bkFindingChangesNoCount: String { get }
    var bkStopping: String { get }
    func bkStartFailed(_ why: String) -> String
    var bkStartDidNotBegin: String { get }
    func bkStopFailed(_ why: String) -> String
    var bkFailedNoReason: String { get }
    func bkClaudeCaption(_ path: String) -> String
    var bkAgeOK: String { get }
    var bkOverLimit: String { get }
    var bkChangeInSettings: String { get }
    func bkNoteClaudeStale(_ limit: String) -> String
    var bkNoteClaudeNone: String { get }
    func bkNoteClaudeMissing(_ path: String) -> String
    var bkOpenSettingsBackups: String { get }
    var bkOpenSettingsBackupsA11y: String { get }
    func bkNoteClaudeUnreadable(_ path: String) -> String
    var bkOpenPrivacy: String { get }
    var bkOpenPrivacyA11y: String { get }
    // MARK: - System page (REDESIGN-SYSTEM)
    func shortDate(_ d: Date) -> String
    var sysSub: String { get }
    var sysTagApplyFailed: String { get }
    var sysTagOutdated: String { get }
    var sysTagUpdating: String { get }
    var sysOK: String { get }
    var sysSleepTitle: String { get }
    var sysSleepCaption: String { get }
    var sysSleepCaptionNone: String { get }
    var sysSleepNone: String { get }
    var sysActivityMonitor: String { get }
    var sysDontWarn: String { get }
    func sysDontWarnA11y(_ name: String) -> String
    var sysHidden: String { get }
    func sysHiddenSince(_ date: String) -> String
    var sysHiddenNoDate: String { get }
    var sysWarnAgain: String { get }
    func sysWarnAgainA11y(_ name: String) -> String
    var sysStartupTitle: String { get }
    func sysStartupItems(_ n: Int) -> String
    func sysStartupRemoved(_ n: Int) -> String
    var sysCheckedJustNow: String { get }
    func sysCheckedAt(_ t: String) -> String
    var sysCheckStale: String { get }
    var sysChecking: String { get }
    var sysGroupLogin: String { get }
    var sysGroupUserAgents: String { get }
    var sysGroupSystemAgents: String { get }
    var sysGroupSystemDaemons: String { get }
    var sysGroupBackground: String { get }
    var sysGroupExpandedA11y: String { get }
    var sysGroupCollapsedA11y: String { get }
    func sysGroupStale(_ n: Int) -> String
    var sysStaleHelp: String { get }
    var sysNoStale: String { get }
    var sysDelete: String { get }
    func sysDeleteA11y(_ file: String) -> String
    func sysDeleteAll(_ n: Int) -> String
    var sysDeleting: String { get }
    func sysDeleteConfirmTitle(_ n: Int) -> String
    var sysDeleteParagraphUser: String { get }
    var sysDeleteParagraphSystem: String { get }
    func sysDeleteFailed(_ detail: String) -> String
    var sysDeleteCancelled: String { get }
    var sysDeleteTimedOut: String { get }
    var sysBrewTitle: String { get }
    func sysBrewCaptionOutdated(_ v: String, _ n: Int, _ total: Int?) -> String
    func sysBrewCaptionUpdating(_ v: String) -> String
    func sysBrewCaptionOk(_ v: String, _ total: Int?) -> String
    var sysBrewCaptionNone: String { get }
    var sysBrewCaptionUnknown: String { get }
    var sysBrewUpdate: String { get }
    func sysBrewUpdatingN(_ n: Int) -> String
    func sysBrewAllUpToDate(_ total: Int?) -> String
    func sysBrewCheckedToday(_ t: String) -> String
    func sysBrewCheckedOn(_ d: String) -> String
    var sysBrewNotInstalled: String { get }
    var sysBrewHowToInstall: String { get }
    func sysBrewFailedLine(_ line: String) -> String
    var sysBrewCheckFailed: String { get }
    var sysEnergyTitle: String { get }
    var sysEnergyCaption: String { get }
    var sysEnergyEmpty: String { get }
    var sysEnergyColSetting: String { get }
    var sysEnergyColBattery: String { get }
    var sysEnergyColAC: String { get }
    var sysEnergyRowDisplaySleep: String { get }
    var sysEnergyRowSleep: String { get }
    var sysEnergyRowDiskSleep: String { get }
    var sysEnergyRowPowerNap: String { get }
    var sysEnergyRowLPM: String { get }
    var sysEnergyRowStandby: String { get }
    var sysEnergyRowWoN: String { get }
    var sysEnergyRowHibernate: String { get }
    var sysEnergyRowTcpKeepalive: String { get }
    var sysEnergyRowLidwake: String { get }
    var sysEnergyInfoDisplaySleep: String { get }
    var sysEnergyInfoSleep: String { get }
    var sysEnergyInfoDiskSleep: String { get }
    var sysEnergyInfoPowerNap: String { get }
    var sysEnergyInfoLPM: String { get }
    var sysEnergyInfoStandby: String { get }
    var sysEnergyInfoWoN: String { get }
    var sysEnergyInfoHibernate: String { get }
    var sysEnergyInfoTcpKeepalive: String { get }
    var sysEnergyInfoLidwake: String { get }
    var sysEnergyOn: String { get }
    var sysEnergyOff: String { get }
    func sysEnergyInfoA11y(_ row: String) -> String
    func sysEnergyApply(_ n: Int) -> String
    var sysEnergyCancel: String { get }
    var sysEnergyReset: String { get }
    var sysEnergyResetHelp: String { get }
    var sysEnergyApplied: String { get }
    func sysEnergyConfirmTitle(_ n: Int) -> String
    var sysEnergyOnBattery: String { get }
    var sysEnergyOnAC: String { get }
    var sysEnergyConfirmAdmin: String { get }
    var sysEnergyConfirmApply: String { get }
    var sysEnergyCancelled: String { get }
    var sysEnergyTimedOut: String { get }
    func sysEnergyFailed(_ detail: String) -> String
    func batMAh(_ s: String) -> String
    func batMA(_ s: String) -> String
    var batConditionNormal: String { get }
    var batConditionService: String { get }
    var batConditionReplaceSoon: String { get }
    var batConditionReplaceNow: String { get }
    var batConditionCheck: String { get }

    // MARK: Assessment
    func assessDiskFull(_ pct: String) -> String
    func assessDiskFullSoon(_ pct: String) -> String
    func assessMemPressure(critical: Bool, apps: [String]) -> String
    func assessWakeHolders(_ entries: [String]) -> String
    func assessBatteryCapacityLow(_ cap: Int) -> String
    func assessBatteryCapacityWarn(_ cap: Int) -> String
    func assessBatteryConditionBad(_ cond: String) -> String
    var assessFileVaultOff: String { get }
    var assessGatekeeperOff: String { get }
    var assessSipOff: String { get }
    var assessFirewallOff: String { get }
    func assessMacUpdatesAvailable(_ n: Int) -> String
    func assessBrewOutdatedTip(_ n: Int) -> String
    func assessOwnCrashesRecent(_ app: String, _ n: Int) -> String
    func assessKernelPanicsRecent(_ n: Int) -> String
    var assessTimeMachineNotSetUp: String { get }
    func assessClaudeBackupStale(_ age: String) -> String
    var assessClaudeBackupNone: String { get }
    func assessSmartDiskErrors(_ title: String) -> String
    func assessSmartDiskWearHigh(_ title: String, _ pct: Int) -> String
    func assessSmartDiskUnavailableTip(_ title: String) -> String
    func assessDownloadsTip(_ sizeStr: String, _ shareSuffix: String) -> String
    func assessDownloadsShareSuffix(_ pct: String) -> String
    func assessTrashTip(_ sizeStr: String) -> String
    func assessCachesTip(_ sizeStr: String) -> String
    var assessNoFDATip: String { get }
    func assessSummaryCount(_ n: Int) -> String

    // MARK: Parsers / live status
    var battStateCharging: String { get }
    var battStateDischarging: String { get }
    var battStateCharged: String { get }
    var battStateFinishingCharge: String { get }
    var battStateNotCharging: String { get }
    var battSourceAC: String { get }
    var battSourceBattery: String { get }
    var uptimeUnitDay: String { get }
    var uptimeUnitHour: String { get }
    var uptimeUnitMinute: String { get }
    var uptimeUnitSecond: String { get }
    func uptimeHourMinuteCombo(_ h: Int, _ mm: Int) -> String

    // MARK: Byte units
    var byteUnitTB: String { get }
    var byteUnitGB: String { get }
    var byteUnitMB: String { get }
    var byteUnitKB: String { get }
    var byteUnitB: String { get }

    // MARK: AppModel errors
    func errorHistorySaveFailed(_ msg: String) -> String
    func errorReportWriteFailed(_ msg: String) -> String

    // MARK: Report text
    func reportTitle(_ model: String) -> String
    func reportGenerated(_ dateTime: String, _ os: String) -> String
    func reportGeneratedNoOS(_ dateTime: String) -> String
    var reportKeyStatus: String { get }
    var reportKeyCPU: String { get }
    var reportKeyMemory: String { get }
    var reportKeyStorage: String { get }
    var reportKeyBattery: String { get }
    var reportKeySecurity: String { get }
    var reportKeyBackups: String { get }
    var reportKeyUptime: String { get }
    func reportStorageFree(_ free: String, _ total: String) -> String
    func reportPurgeable(_ v: String) -> String
    func reportCapacity(_ v: String) -> String
    func reportCycles(_ n: Int) -> String
    var reportFirewall: String { get }
    var reportOff: String { get }
    func reportLocalSnapshots(_ n: Int) -> String

    var reportSectionSystem: String { get }
    var reportSectionDisk: String { get }
    var reportSectionSnapshots: String { get }
    var reportSectionHomeDirs: String { get }
    var reportSectionServiceDirs: String { get }
    var reportSectionMemory: String { get }
    var reportSectionTopMem: String { get }
    var reportSectionTopCPU: String { get }
    var reportSectionLoginItems: String { get }
    var reportSectionAgents: String { get }
    var reportSectionBackground: String { get }
    var reportSectionBattery: String { get }
    var reportSectionEnergy: String { get }
    var reportSectionSecurity: String { get }
    var reportSectionTMDest: String { get }
    var reportSectionCrashes: String { get }
    var reportSectionUpdates: String { get }
    var reportSectionSmart: String { get }
    var reportSectionUnparsed: String { get }
    var reportUnparsedHint: String { get }
    func reportUnparsedMoreLines(_ n: Int) -> String
    var reportNone: String { get }
    func reportUptime(_ v: String) -> String
    var reportAgentsUserHeader: String { get }
    var reportEmpty: String { get }
    var reportAgentsSystemHeader: String { get }
    var reportNoBattery: String { get }
    func reportBatterySource(_ v: String) -> String
    func reportBatteryCharge(_ v: String) -> String
    func reportBatteryState(_ v: String) -> String
    var reportTMNotChecked: String { get }
    var reportTMNotConfigured: String { get }
    func reportTMLastBackup(_ v: String) -> String
    var reportNotChecked: String { get }
    var reportSectionTimings: String { get }
    var reportTimingsNote: String { get }
    func reportTimingsPass(_ v: String) -> String
    func reportTimingsUpdates(_ v: String, _ at: String) -> String
    func reportUpdatesCheckedAt(_ at: String) -> String
    var updatesCheckedJustNow: String { get }
    func updatesCheckedAgo(_ age: String) -> String
    func reportTimingsFolderSizes(_ v: String, _ at: String) -> String
    /// Short name of a report section for the COLLECTION TIMES list.
    func reportTimingsSectionName(_ s: ReportSection) -> String
    func reportFoldersCountedAt(_ at: String) -> String
    func foldersCountedAgo(_ age: String) -> String
    var foldersCountedJustNow: String { get }
    var reportBrewOutdatedHeader: String { get }
    func reportSmartDiskLine(_ title: String, _ device: String, _ status: String) -> String
    var reportSmartWarningNone: String { get }
    var reportSmartWarningLowSpareCapacity: String { get }
    var reportSmartWarningCriticalTemp: String { get }
    var reportSmartWarningReliabilityDegraded: String { get }
    var reportSmartWarningReadOnlyMode: String { get }
    var reportSmartWarningBackupPowerFail: String { get }
    var reportSmartWarningPersistentMemoryReadOnly: String { get }
    func reportSmartWarningGeneric(_ hex: String) -> String

    // MARK: SMART attribute/status render-time localization (smartctl output is
    // always raw English; these translate known labels for display without touching
    // the collected `SmartDisk` model — see `smartLocalizedLabel(_:)`).
    var smartAttrCriticalWarning: String { get }
    var smartAttrTemperature: String { get }
    var smartAttrAvailableSpare: String { get }
    var smartAttrPercentageUsed: String { get }
    var smartAttrPowerCycles: String { get }
    var smartAttrPowerOnHours: String { get }
    var smartAttrUnsafeShutdowns: String { get }
    var smartAttrMediaAndDataIntegrityErrors: String { get }
    var smartAttrErrorInformationLogEntries: String { get }
    var reportSmartStatusOk: String { get }

    // MARK: Report collector
    var reportCollectorNoBackupsYet: String { get }
    var reportCollectorDiskNotConnected: String { get }
    var reportCollectorNoCompletedBackups: String { get }
    var reportCollectorDateUnavailableNoFDA: String { get }
    var reportCollectorSpotlightEnabled: String { get }
    var reportCollectorSpotlightDisabled: String { get }
    var reportCollectorInternalDiskFallbackTitle: String { get }
    var reportCollectorSmartOkVerified: String { get }
    var reportCollectorSmartNotSupported: String { get }
    var reportCollectorSmartStatusUnavailable: String { get }
    var reportCollectorSmartMediaErrors: String { get }
    var reportCollectorSmartWearHigh: String { get }
    var reportCollectorSmartUnavailable: String { get }
    var reportCollectorSmartUnavailableNoTools: String { get }

    // MARK: v2 attention
    // Chip labels + details (one pair per AttentionKind; see Engine/AttentionModel.swift).
    var attnLabelDiskFull: String { get }
    func attnDetailDiskFull(_ pct: String) -> String
    var attnLabelDiskFullSoon: String { get }
    func attnDetailDiskFullSoon(_ pct: String) -> String
    var attnLabelSwapHigh: String { get }
    var attnDetailMemPressureWarn: String { get }
    var attnDetailMemPressureCritical: String { get }
    var attnLabelBatteryCapacity: String { get }
    func attnDetailBatteryCapacity(_ cap: Int) -> String
    var attnLabelBatteryCondition: String { get }
    func attnDetailBatteryCondition(_ cond: String) -> String
    var attnLabelFileVaultOff: String { get }
    var attnDetailFileVaultOff: String { get }
    var attnLabelGatekeeperOff: String { get }
    var attnDetailGatekeeperOff: String { get }
    var attnLabelSipOff: String { get }
    var attnDetailSipOff: String { get }
    var attnLabelFirewallOff: String { get }
    var attnDetailFirewallOff: String { get }
    var attnLabelUpdates: String { get }
    func attnDetailUpdates(_ n: Int) -> String
    var attnLabelCrashes: String { get }
    func attnDetailCrashes(_ n: Int) -> String
    var attnLabelTimeMachine: String { get }
    var attnDetailTimeMachine: String { get }
    var attnLabelClaudeBackup: String { get }
    var attnDetailClaudeBackupNone: String { get }
    var attnLabelWakeHolders: String { get }
    func attnDetailWakeHolders(_ first: String, more: Int) -> String
    func wakeHolderOnBehalf(_ owner: String, _ requester: String) -> String
    func wakeHolderEntry(_ holder: String, _ age: String) -> String
    /// Sleep plate context-menu entry and the hint appended to its hover tip (SLEEP-IGNORE-APP).
    func attnWakeIgnore(_ holder: String) -> String
    var attnWakeIgnoreHint: String { get }
    func attnLabelSmartErrors(_ title: String) -> String
    var attnDetailSmartErrors: String { get }
    func attnLabelSmartWear(_ title: String) -> String
    func attnDetailSmartWear(_ pu: Int) -> String

    // Verbs (single source of truth — see AttentionModel.verb(for:lang:)).
    var attnVerbSettings: String { get }
    var attnVerbActivityMonitor: String { get }
    var attnVerbDiskUtility: String { get }
    var attnVerbShow: String { get }
    var attnVerbEmpty: String { get }
    var attnVerbEnable: String { get }
    var attnVerbUpgrade: String { get }
    var attnVerbOpen: String { get }

    // Capsule objects + values + explanations.
    var attnCapBattery: String { get }
    func attnCapBatteryValue(_ p: Int) -> String
    var attnCapBrew: String { get }
    func attnCapBrewValue(_ n: Int) -> String
    var attnCapSmartNoData: String { get }
    var attnCapDownloads: String { get }
    var attnCapTrash: String { get }
    var attnCapCaches: String { get }
    var attnExplainBattery: String { get }
    var attnExplainBrew: String { get }
    var attnExplainSmart: String { get }
    var attnExplainDownloads: String { get }
    var attnExplainTrash: String { get }
    var attnExplainCaches: String { get }
    var attnCapFolders: String { get }
    var attnCapFoldersNoAccess: String { get }
    var attnExplainNoFDA: String { get }

    // Attention summary card overflow toggles (Block V2-SUMMARY).
    func attnMore(_ n: Int) -> String
    var attnCollapse: String { get }

    // Quiet-strip strings.
    var quietUpdatesTitle: String { get }
    var quietNeedsAttention: String { get }
    var quietStatusAllEnabled: String { get }
    var quietStatusAllClear: String { get }
    var quietMarkOff: String { get }
    var quietMarkUnknown: String { get }
    func quietCountItems(_ n: Int) -> String

    // MARK: iPhone module
    var mainModeMac: String { get }
    var mainModeDevices: String { get }
    var iphoneKickerDevices: String { get }
    var iphoneStatusConnected: String { get }
    var iphoneStatusNeedsTrust: String { get }
    var iphoneStatusReading: String { get }
    var iphoneStatusFailed: String { get }
    var iphoneUnknownDevice: String { get }
    var iphoneRetry: String { get }
    var iphoneSearchAgain: String { get }
    var iphoneRestartService: String { get }
    var iphoneRestartConfirmTitle: String { get }
    var iphoneRestartConfirmBody: String { get }
    var iphoneRestartConfirm: String { get }
    var iphoneRestartCancel: String { get }
    var iphoneRestartBusy: String { get }
    func iphoneRestartFailed(_ detail: String) -> String
    var iphoneBack: String { get }
    var iphoneRefresh: String { get }
    var iphoneUnavailable: String { get }
    func iphoneStatusRemembered(_ date: String) -> String
    func iphoneOpenDeviceA11y(_ name: String) -> String

    var iphoneBatteryTitle: String { get }
    var iphoneHistoryTitle: String { get }
    var iphoneBatHealth: String { get }
    var iphoneBatCycles: String { get }
    var iphoneBatCharge: String { get }
    var iphoneBatState: String { get }
    var iphoneBatTemperature: String { get }
    var iphoneTempNormal: String { get }
    var iphoneTempWarm: String { get }
    var iphoneTempHot: String { get }
    var iphoneCyclesAging: String { get }
    var iphoneCyclesHigh: String { get }
    var iphoneBatVoltage: String { get }
    var iphoneBatCapacity: String { get }
    var iphoneChargeCharging: String { get }
    var iphoneChargeExternal: String { get }
    var iphoneChargeBattery: String { get }
    var iphoneUnitMAh: String { get }
    var iphoneUnitWh: String { get }
    var iphoneCapacityUnitA11y: String { get }
    var iphoneWhSourceHelp: String { get }
    var iphoneBatteryConnectToRead: String { get }
    var iphoneBatteryNoData: String { get }
    var iphoneBatteryAutoReadOff: String { get }
    var iphoneHistoryEmpty: String { get }
    var iphoneHistorySourceLive: String { get }
    var iphoneHistorySourceImport: String { get }
    var iphoneHistoryColDate: String { get }
    var iphoneHistoryColHealth: String { get }
    var iphoneHistoryColCycles: String { get }
    var iphoneHistoryColSource: String { get }
    func iphoneBatteryFromHistory(_ date: String) -> String
    func iphoneHistoryCaption(_ n: Int) -> String
    var iphoneHistoryChart: String { get }
    var iphoneHistoryTable: String { get }
    var iphoneHistoryViewA11y: String { get }
    func iphoneChartCycles(_ n: Int) -> String
    var iphoneChartSourceImport: String { get }
    func iphoneChartMonth(_ m: Int) -> String
    func iphoneChartWeekLabel(day: Int, month: Int) -> String

    var iphoneLogsTitle: String { get }
    var iphoneLogsConnectToRead: String { get }
    var iphoneLogsEmpty: String { get }
    var iphoneLogsRefreshA11y: String { get }
    func iphoneLogsCaption(_ n: Int) -> String
    func iphoneLogsCategory(_ c: LogCategory) -> String
    var iphoneSectionReadFailed: String { get }

    var iphoneImportTitle: String { get }
    var iphoneImportButton: String { get }
    func iphoneImportArchiveA11y(_ name: String) -> String
    var iphoneImportPickFile: String { get }
    var iphoneImportPickA11y: String { get }
    var iphoneImportPickPrompt: String { get }
    func iphoneImportConfirmTitle(_ name: String, into phone: String) -> String
    var iphoneImportParseOnly: String { get }
    var iphoneImportParseKeep: String { get }
    var iphoneImportCancel: String { get }
    var iphoneImportParseOnlyA11y: String { get }
    var iphoneImportParseKeepA11y: String { get }
    var iphoneImportCancelA11y: String { get }
    func iphoneImportMismatchTitle(_ target: String) -> String
    func iphoneImportMismatchMessage(file: String, owner: String?, archiveMAh: [Int], deviceMAh: Int, target: String) -> String
    var iphoneImportMismatchProceed: String { get }
    var iphoneImportMismatchProceedA11y: String { get }
    var iphoneImportHint: String { get }
    func iphoneImportProgress(_ p: ImportProgress) -> String
    func iphoneImportSummary(_ s: ImportSummary) -> String
    func iphoneImportError(_ e: ImportError) -> String
    func iphoneImportErrorDetail(_ e: ImportError) -> String?
    var iphoneImportKeptTitle: String { get }
    func iphoneImportRevealA11y(_ name: String) -> String
    func iphoneLogsFromArchive(_ name: String) -> String
    var iphoneIdentityTitle: String { get }
    var iphoneIdentityConnectToRead: String { get }
    var iphoneIdentityRefreshA11y: String { get }
    var iphoneIdentityShow: String { get }
    var iphoneIdentityHide: String { get }
    var iphoneIdentityCopy: String { get }
    var iphoneIdentityCopied: String { get }
    func iphoneRevealA11y(_ label: String) -> String
    func iphoneHideA11y(_ label: String) -> String
    func iphoneCopyA11y(_ label: String) -> String
    func iphoneIdentityLabel(_ l: IdentityLabel) -> String

    var iphoneTagNotConnected: String { get }
    var iphoneTagTrustNeeded: String { get }
    var iphoneTagReadFailed: String { get }
    var iphoneSubTrust: String { get }
    var iphoneSubReconnect: String { get }
    func iphoneSubLastSeen(_ date: String) -> String
    func iphoneSubCharge(_ percent: Int, _ state: String) -> String
    var iphoneStateChargingLower: String { get }
    var iphoneStateExternalLower: String { get }
    var iphoneStateBatteryLower: String { get }
    var iphoneTileHealth: String { get }
    var iphoneTileHealthFull: String { get }
    var iphoneNotIdentified: String { get }
    var iphonePendingTrustText: String { get }
    var iphonePendingFailedText: String { get }
    func iphoneSummary(connected: Int, notConnected: Int, waiting: Int) -> String
    var iphoneSummaryNone: String { get }
    var iphoneSummaryUnavailable: String { get }
    var iphoneNoticeEmptyTitle: String { get }
    var iphoneNoticeEmptyBody: String { get }
    var iphoneNoticeUnavailableTitle: String { get }
    var iphoneRestartingShort: String { get }
    var iphoneRestartingBanner: String { get }

    var iphoneBatteryMeasuredNow: String { get }
    var iphoneHealthNote: String { get }
    func iphoneHealthHistoryNote(cycles: Int?) -> String
    var iphoneLiveReadings: String { get }
    var iphoneLiveReadingsConnect: String { get }
    var iphoneRefreshOfflineHelp: String { get }
    var iphoneLogsSourceLive: String { get }
    var iphoneLogsSourceArchive: String { get }
    var iphoneLogsSourceA11y: String { get }
    var iphoneLogsColSize: String { get }
    var iphoneImportOnPhone: String { get }
    var iphoneImportChoiceBody: String { get }
    var iphoneImportInArchive: String { get }
    var iphoneIdentitySerials: String { get }
    // MARK: Common (strings.json › Shared + 00 §4.16/§7; REDESIGN-FOUNDATION)
    var commonShowInFinder: String { get }
    var commonFirewall: String { get }
    var commonEnable: String { get }
    var commonDisk: String { get }
    var commonSetUp: String { get }
    var commonShow: String { get }
    var commonDone: String { get }
    var commonMacCantSleep: String { get }
    var commonBattery: String { get }
    var commonInstall: String { get }
    var commonServiceRecommended: String { get }
    var commonClaudeBackup: String { get }
    var commonCPU: String { get }
    var commonMemory: String { get }
    var commonStorage: String { get }
    var commonSecurity: String { get }
    var commonBackups: String { get }
    var commonSystem: String { get }
    var commonHistory: String { get }
    var commonLocalSnapshots: String { get }
    var commonFullDiskAccessNeeded: String { get }
    var commonCompressed: String { get }
    var commonOK: String { get }
    var commonCycles: String { get }
    var commonProtection: String { get }
    var commonUpdates: String { get }
    var commonCollectingData: String { get }
    var commonAllGood: String { get }
    var commonNeedsAttention: String { get }
    var commonThisMac: String { get }
    var commonReport: String { get }
    var commonRefresh: String { get }
    var commonRefreshReport: String { get }
    var commonNow: String { get }
    var commonTryAgain: String { get }
    var commonShowLess: String { get }
    var commonSetting: String { get }
    var commonOnBattery: String { get }
    var commonACPower: String { get }
    var commonNormal: String { get }
    var commonFree: String { get }
    var commonChart: String { get }
    var commonTable: String { get }
    var commonRefreshing: String { get }
    var commonInProgress: String { get }
    var commonCancel: String { get }
    var commonOpenPrivacySettings: String { get }
    func commonUpdated(_ time: String) -> String
    var commonChecking: String { get }
    var commonCritical: String { get }
    func commonLastData(_ time: String) -> String
    // MARK: IPSW (IPHONE-IPSW). Button and a11y labels arrive with the UI step.
    var ipswSigned: String { get }
    var ipswNotSigned: String { get }
    var ipswNotListed: String { get }
    var ipswIsAppleTarget: String { get }
    var ipswNotAppleTarget: String { get }
    func ipswAskSends(_ identifier: String) -> String
    func ipswVerified(_ list: String) -> String
    var ipswVerifiedSizeOnly: String { get }
    var ipswUnknown: String { get }
    var ipswChecking: String { get }
    func ipswCheckedAgo(_ rel: String) -> String
    var ipswErrNoIdentifier: String { get }
    var ipswErrUnknownDevice: String { get }
    var ipswErrOffline: String { get }
    var ipswErrTimedOut: String { get }
    func ipswErrHTTP(_ code: Int) -> String
    var ipswErrBadResponse: String { get }
    func ipswSourceFailed(_ source: String, _ reason: String) -> String
    var ipswErrNotDownloadable: String { get }
    var ipswNoSecureAppleLink: String { get }
    var ipswNotFromApple: String { get }
    var ipswErrNoChecksum: String { get }
    var ipswErrNoSize: String { get }
    var ipswErrSourcesDisagree: String { get }
    func ipswErrNotEnoughSpace(_ needed: String, _ free: String) -> String
    var ipswErrDownloadsDenied: String { get }
    var ipswErrSizeMismatch: String { get }
    var ipswErrChecksumMismatch: String { get }
    func ipswErrTransfer(_ detail: String) -> String
    func ipswErrFileSystem(_ detail: String) -> String
    var ipswBusy: String { get }
    var ipswCancelled: String { get }
    var ipswPreparing: String { get }
    func ipswDownloading(_ done: String, _ total: String) -> String
    var ipswVerifying: String { get }
    var ipswFinished: String { get }

    // MARK: Home (REDESIGN-HOME; strings.json › This Mac Home + 02-home.md)
    var homeMacStatus: String { get }
    func homeTaskCount(_ n: Int) -> String
    func homeNeedAttention(_ n: Int) -> String
    var homeCriticalCount: String { get }
    var homeWarnings: String { get }
    func homeCheckedAt(_ t: String) -> String
    func homeLastCheck(_ t: String) -> String
    func homeTileLastCheck(_ t: String) -> String
    func homeShowAll(_ n: Int) -> String
    var homeYouCan: String { get }
    var homeFreeUpSpace: String { get }
    func homeBrewOutdatedShort(_ n: Int) -> String
    var homeNothingNeedsAttention: String { get }
    var homeFirstScanTitle: String { get }
    var homeFirstScanCaption: String { get }
    func homeScanFailed(timedOut: Bool, lastGood: String?) -> String
    var homeSipHelp: String { get }
    var homeStateOff: String { get }
    var homeDiskHealth: String { get }
    var homeStateFailing: String { get }
    var homeStateFailingShort: String { get }
    func homeStateDiskFull(_ pct: Int) -> String
    var homeStateNotSetUp: String { get }
    var homeStateKeepsAwake: String { get }
    func homeStateWorn(_ pct: Int) -> String
    func homeStatePackagesOutdated(_ n: Int) -> String
    var homeStateUpdateAvailable: String { get }
    func homeStateUpdatesAvailable(_ n: Int) -> String
    var homeMemoryObject: String { get }
    var homeStateRunningLow: String { get }
    var homeStateRunningOut: String { get }
    var homeCrashes: String { get }
    func homeStateReports(_ n: Int) -> String
    var homeDiskWear: String { get }
    func homePercent(_ s: String) -> String
    func homeGB(_ s: String) -> String
    var homeVerbDetails: String { get }
    var homeVerbFreeUp: String { get }
    var homeVerbUpdate: String { get }
    var homeVerbSettings: String { get }
    var homeTagFirewallOff: String { get }
    var homeTagDriveFailing: String { get }
    var homeTagTMNotSetUp: String { get }
    var homeTagWorn: String { get }
    var homeTagBrewOutdated: String { get }
    var homeTagUpdateAvailable: String { get }
    var homeTagLowMemory: String { get }
    var homeTagService: String { get }
    var homeTagFileVaultOff: String { get }
    var homeTagGatekeeperOff: String { get }
    var homeTagSipOff: String { get }
    var homeTagDiskWorn: String { get }
    var homeTagClaudeStale: String { get }
    var homeTagNormal: String { get }
    var homeTagHealthy: String { get }
    var homeTagAllOn: String { get }
    var homeTagUpToDate: String { get }
    func homeHistoryDays(_ n: Int) -> String
    var homeSections: String { get }
    func homeSectionCount(_ n: Int) -> String
    func homeCPUSub(_ chip: String, _ cores: Int) -> String
    func homeCoresOnly(_ cores: Int) -> String
    var homeStorageSub: String { get }
    var homeBatterySub: String { get }
    var homeSecuritySub: String { get }
    var homeBackupsSub: String { get }
    var homeSystemSub: String { get }
    var homeHistorySub: String { get }
    var homeKVLoad: String { get }
    var homeKVProcesses: String { get }
    var homeKVPurgeable: String { get }
    var homeKVFailing: String { get }
    func homeKVWorn(_ pct: Int) -> String
    var homeKVCapacity: String { get }
    func homeKVProtection(_ on: Int) -> String
    var homeKVNone: String { get }
    var homeKVSnapshots: String { get }
    var homeKVLoginItems: String { get }
    var homeKVUpToDate: String { get }
    var homeKVDiskPerMonth: String { get }
    var homeBackA11y: String { get }
    // HOME-C: the Now card
    func homeEverySeconds(_ n: Int) -> String
    func homeLoadCores(_ load: String, _ cores: Int) -> String
    func homeOf(_ s: String) -> String
    var homePressureLow: String { get }
    var homePressureMedium: String { get }
    var homePressureHigh: String { get }
    func homeLegendActive(_ v: String, short: Bool) -> String
    func homeLegendWired(_ v: String) -> String
    func homeLegendInactive(_ v: String, short: Bool) -> String
    func homeLegendCompressed(_ v: String, short: Bool) -> String
    func homeMemFoot(_ used: String, _ total: String, _ compressed: String) -> String
    func homeMemFootNoSwap(_ compressed: String) -> String
    var homeFreeWord: String { get }
    var homeChipHealthy: String { get }
    var homeChipLowSpace: String { get }
    func homeChipDriveFailing(short: Bool) -> String
    var homeChipWorn: String { get }
    var homeChipService: String { get }
    func homeLegendData(_ v: String) -> String
    func homeLegendSystem(_ v: String, short: Bool) -> String
    func homeLegendOther(_ v: String, short: Bool) -> String
    func homeStorageFoot(size: String, purgeable: String?, short: Bool) -> String
    var homeCapacityWord: String { get }
    var homeOfNew: String { get }
    var homeWearThreshold: String { get }
    var homeWearThresholdHelp: String { get }
    func homeBatteryFoot(cycles: Int?, charge: Int?, state: String?, short: Bool) -> String
}

/// Russian plural picker: ruPlural(1, ...)="цикл", (2)="цикла", (5)="циклов",
/// (11)="циклов", (21)="цикл". Standard Russian plural-form rules.
func ruPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m100 = abs(n) % 100, m10 = abs(n) % 10
    if (11...14).contains(m100) { return many }
    switch m10 {
    case 1: return one
    case 2...4: return few
    default: return many
    }
}

/// Current-language holder. @Observable so any SwiftUI body that reads `L`
/// re-renders instantly on language change; Engine code reads the same global at
/// collection time (its output refreshes on the next tick — accepted design).
@Observable
final class L10nStore {
    static let shared = L10nStore()
    /// Language the process started with — UI offers «Relaunch Now» only while
    /// the current choice differs (menus/system chrome are fixed at launch).
    static let launchLanguage: AppLanguage = shared.language
    static let defaultsKey = "appLanguage"
    static let choiceKey = "appLanguageChoice"

    var choice: LanguageChoice {
        didSet {
            UserDefaults.standard.set(choice.rawValue, forKey: Self.choiceKey)
            language = LanguageChoice.resolve(choice, preferredLanguages: Locale.preferredLanguages)
        }
    }

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private var localeObserver: NSObjectProtocol?

    private init() {
        let d = UserDefaults.standard
        let initial: LanguageChoice
        if let raw = d.string(forKey: Self.choiceKey), let c = LanguageChoice(rawValue: raw) {
            initial = c
        } else if let raw = d.string(forKey: Self.defaultsKey), let lang = AppLanguage(rawValue: raw) {
            // An existing install: the stored language stays an explicit choice (D9).
            initial = lang == .ru ? .ru : .en
        } else {
            initial = .system
        }
        choice = initial
        language = LanguageChoice.resolve(initial, preferredLanguages: Locale.preferredLanguages)
        localeObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.choice == .system else { return }
            let l = LanguageChoice.resolve(.system, preferredLanguages: Locale.preferredLanguages)
            if l != self.language { self.language = l }
        }
    }
}

extension AppStrings {
    /// Toggle label of a notify category — also the notification title (D5).
    func settingsNotifyLabel(_ c: NotifyCategory) -> String {
        switch c {
        case .protection: return settingsNotifyProtection
        case .disk: return settingsNotifyDisk
        case .battery: return settingsNotifyBattery
        case .backup: return settingsNotifyBackup
        case .updates: return settingsNotifyUpdates
        case .crashes: return settingsNotifyCrashes
        }
    }
}

var L: AppStrings { L10nStore.shared.language == .en ? StringsEN() : StringsRU() }
