// Engine/L10n.swift
// In-app localization core. AppStrings is the compile-enforced string table
// protocol (a missing key on a future language struct is a compile error, unlike
// dictionary lookups). Foundation-only: also covered by Tests/MacDashboardTests.
import Foundation
import Observation

enum AppLanguage: String, CaseIterable {
    case ru, en
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
    var settingsIntervalNoteBalanced: String { get }
    var settingsIntervalNoteEconomy: String { get }
    /// Settings → Мониторинг, SLEEP-IGNORE-APP card.
    var settingsWakeIgnoredLabel: String { get }
    var settingsWakeIgnoredEmpty: String { get }
    var settingsWakeIgnoredRestore: String { get }
    func settingsWakeIgnoredRestoreA11y(_ holder: String) -> String
    var settingsSectionBackup: String { get }
    var settingsBackupStaleLabel: String { get }
    func settingsBackupStaleOption(_ hours: Int) -> String
    var settingsBackupStaleNote: String { get }
    var settingsMenuLanguageHint: String { get }
    var settingsRelaunchNow: String { get }
    var settingsSectionGeneral: String { get }
    var settingsSectionMonitoring: String { get }
    var settingsVersionLabel: String { get }
    var settingsWindowTitle: String { get }

    // MARK: Main dashboard (header + tab picker)
    var mainCollectingInfo: String { get }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { get }
    var overviewKickerMemory: String { get }
    var overviewKickerProcesses: String { get }
    var overviewKickerFolders: String { get }
    var overviewKickerSystem: String { get }
    var overviewKickerHistory: String { get }
    func headerLoadChip(_ load: String, _ ncpu: Int) -> String
    func headerUptimeChip(_ uptime: String) -> String
    var headerRefreshReport: String { get }
    /// Status chip label when `assessment.problems` is non-empty (pairs with `recommendationsAllGood`).
    var headerStatusNeedsAttention: String { get }

    // MARK: KPI tiles
    var kpiCpuLabel: String { get }
    var kpiLoadUnavailable: String { get }
    /// V2-TILES footer: all three load averages, e.g. "нагрузка 1,73 · 2,05 · 2,20".
    /// The core count is NOT repeated here — it already lives in the header's load chip.
    func kpiCpuLoadFooter(_ l1: String, _ l2: String, _ l3: String) -> String
    var kpiMemLabel: String { get }
    func kpiMemUnit(_ total: String) -> String
    func kpiMemSub(_ compressor: String, _ purgeable: String) -> String
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
    func kpiBatteryChargeNow(_ charge: Int) -> String
    var kpiBatteryDetailsButton: String { get }

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
    var sharedToggleToChart: String { get }
    var sharedToggleToTable: String { get }
    var sharedToggleShowChart: String { get }
    var sharedToggleShowTable: String { get }
    var sharedInfoHide: String { get }
    var sharedInfoShow: String { get }
    func sharedMoreN(_ n: Int) -> String
    var sharedCollapse: String { get }

    // MARK: Storage — shared folder labels
    var storageColShare: String { get }
    var storageTrashLabel: String { get }
    var storageAppsLabel: String { get }

    // MARK: Storage — Домашняя папка
    var storageHomeDirsTitle: String { get }
    var storageHomeDirsCaption: String { get }

    // MARK: Storage — Служебные папки
    var storageServiceDirsTitle: String { get }
    var storageServiceDirsCaption: String { get }
    var folderTabHome: String { get }
    var folderTabSvc: String { get }

    // MARK: Storage — folders that could not be read (V2-FDA-DEGRADE)
    func storageFoldersNoFDA(_ folders: String) -> String
    var storageFoldersNoFDAButton: String { get }
    var storageFoldersNoFDAButtonA11y: String { get }
    // MARK: Storage — folders the count did not reach before its deadline (SERVICE-DIRS-TIMEOUT)
    func storageFoldersNotMeasured(_ folders: String) -> String

    // MARK: Storage — Диски (SMART)
    var storageSmartTitle: String { get }
    func storageSmartUpdatedCaption(_ time: String) -> String
    var storageSmartRefreshButton: String { get }
    var storageSmartColAttribute: String { get }
    var storageSmartColValue: String { get }
    var storageSmartInstallButton: String { get }
    var storageSmartNeedsHomebrew: String { get }
    func storageSmartInstallFailed(_ msg: String) -> String
    // MARK: Storage — SMART disk capsule kind sublabel (V2-CARD-DISK)
    var storageSmartKindInternal: String { get }
    var storageSmartKindExternal: String { get }

    // MARK: Process cards
    var processesTitle: String { get }
    var processSegCPU: String { get }
    var processSegMem: String { get }
    var processesMetricA11y: String { get }
    var processListCaption: String { get }
    var processLoadingDetails: String { get }
    var processDetailThreads: String { get }
    var processDetailMemory: String { get }
    var processDetailPath: String { get }
    var processQuit: String { get }
    var processSignalError: String { get }
    var processForceQuit: String { get }
    var processForceQuitConfirm: String { get }
    var processForceQuitInlineQuestion: String { get }
    func processRevealA11y(_ name: String) -> String
    func processTerminateA11y(_ name: String) -> String
    func processKillA11y(_ name: String) -> String

    // MARK: Maintenance card
    var maintenanceTitle: String { get }
    var maintenanceBrewNotInstalled: String { get }
    var maintenanceBrewVersionUnknown: String { get }
    var maintenanceBrewAllFresh: String { get }
    func maintenanceBrewOutdatedCount(_ n: Int) -> String
    var maintenanceBrewOutdatedCheckFailed: String { get }
    var maintenanceUpdatesSection: String { get }
    var maintenanceUpdatesAllUpdated: String { get }
    var maintenanceCrashesSection: String { get }
    var maintenanceCrashesNone: String { get }
    var maintenanceUpdatesTip: String { get }
    var maintenanceCrashesTip: String { get }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String
    func maintenanceCrashRevealA11y(_ process: String) -> String
    func maintenanceAndMore(_ n: Int) -> String
    var maintenanceBrewUpgradeButton: String { get }
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
    var autostartTitle: String { get }
    var autostartNoPermission: String { get }
    var autostartUserAgents: String { get }
    var autostartSystemAgents: String { get }
    var autostartSystemDaemons: String { get }
    var autostartBackgroundTasks: String { get }
    var autostartCheckOutdated: String { get }
    func autostartCheckOutdatedCount(_ n: Int) -> String
    var autostartOrphanEmptyText: String { get }
    var autostartOrphanTooltip: String { get }
    var autostartDeleteButton: String { get }
    var autostartDeleteConfirmMessageUser: String { get }
    var autostartDeleteConfirmMessageSystem: String { get }
    func autostartDeleteError(_ detail: String) -> String
    func autostartDeleteAllButton(_ n: Int) -> String
    func autostartDeleteAllConfirmMessageUser(_ n: Int) -> String
    func autostartDeleteAllConfirmMessageSystem(_ n: Int) -> String
    var autostartDeletingAll: String { get }
    var autostartOkTooltip: String { get }
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
    var memoryLegendPurgeable: String { get }
    var memoryLegendFileCache: String { get }
    var memoryNoteActive: String { get }
    var memoryNoteWired: String { get }
    var memoryNoteOther: String { get }
    var memoryNoteInactive: String { get }
    var memoryNoteSpeculative: String { get }
    var memoryNoteFree: String { get }
    var memoryNotePurgeable: String { get }
    var memoryNoteFileCache: String { get }
    func memoryTitle(_ total: String) -> String
    var memoryCaption: String { get }
    var memoryInfoHelp: String { get }
    func memorySwapNote(_ used: String, _ total: String) -> String
    var memoryOtherNote: String { get }
    var memoryColCategory: String { get }
    var memoryColVolume: String { get }

    // MARK: History card
    var historyTitle: String { get }
    func historyCaption(_ n: Int) -> String
    var historyColDate: String { get }
    var historyColDiskUsed: String { get }
    var historyColFree: String { get }
    var historyColCycles: String { get }
    var historyMetricPickerDisk: String { get }
    var historyMetricPickerBattery: String { get }
    var historyMetricPickerCycles: String { get }
    var historyMetricPickerSwap: String { get }
    var historyMetricA11y: String { get }
    var historyMetricYLabelDisk: String { get }
    var historyMetricYLabelBattery: String { get }
    var historyMetricYLabelCycles: String { get }
    var historyMetricYLabelSwap: String { get }
    var historyMetricInsufficientData: String { get }
    var historyNotEnoughDays: String { get }
    var historyRangeMonth: String { get }
    var historyRangeQuarter: String { get }
    var historyRangeYear: String { get }
    var historyRangeAll: String { get }
    var historyRangeA11y: String { get }
    func historyGbValue(_ n: Int) -> String
    var historyRestartTitle: String { get }
    func historyRestartDetail(_ file: String) -> String
    var historyRestartReveal: String { get }
    var historyRestartRevealA11y: String { get }
    var historyRestartHide: String { get }
    var historyRestartHideA11y: String { get }
    var historyInfoDate: String { get }
    var historyInfoDiskFree: String { get }
    var historyInfoBattery: String { get }
    var historyInfoCycles: String { get }
    var historyInfoSwap: String { get }
    var historyInfoMacos: String { get }
    var historyInfoSource: String { get }
    var historyInfoHideLabel: String { get }
    var historyInfoShowLabel: String { get }

    // MARK: Energy card
    var energyParamDisplaySleep: String { get }
    var energyParamSleep: String { get }
    var energyParamDiskSleep: String { get }
    var energyParamLowPowerMode: String { get }
    var energyParamHibernateMode: String { get }
    var energyParamWoMP: String { get }
    var energyInfoDisplaySleep: String { get }
    var energyInfoSleep: String { get }
    var energyInfoDiskSleep: String { get }
    var energyInfoPowerNap: String { get }
    var energyInfoLowPowerMode: String { get }
    var energyInfoStandby: String { get }
    var energyInfoHibernateMode: String { get }
    var energyInfoWoMP: String { get }
    var energyValueOn: String { get }
    var energyValueOff: String { get }
    var energyValueNever: String { get }
    var energyCardTitle: String { get }
    func energyApply(_ n: Int) -> String
    func energyApplyConfirmTitle(_ n: Int) -> String
    var energyApplyConfirmButton: String { get }
    var energyApplyConfirmAdmin: String { get }
    var energyCancel: String { get }
    var energyResetToDefaults: String { get }
    var energyResetHelp: String { get }
    var energyApplyCancelled: String { get }
    func energyApplyFailed(_ msg: String) -> String
    var energyColParam: String { get }
    var energyColBattery: String { get }
    var energyColAC: String { get }

    // MARK: Battery detail popover
    func batteryUpdatedAt(_ time: String) -> String
    var batteryLoadingText: String { get }
    var batteryPercentSign: String { get }
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
    func batteryMA(_ n: Int) -> String
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
    func batteryPercent(_ n: Int) -> String
    var batteryCapCycles: String { get }
    func batteryCyclesOf(_ cycles: Int, _ design: Int) -> String
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
    func batteryOperatingHours(_ n: Int) -> String
    var batteryDetailLowPower: String { get }
    var batteryDetailPassportSection: String { get }
    var batteryDetailManufacturer: String { get }
    var batteryDetailSerial: String { get }
    var batteryDetailMfgDate: String { get }
    func batteryDetailMfgDateValue(_ month: String, _ code: String) -> String

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

    // MARK: DashboardModel errors
    func errorHistorySaveFailed(_ msg: String) -> String
    func errorReportWriteFailed(_ msg: String) -> String

    // MARK: Report writer
    func reportCreatedAt(_ time: String) -> String
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
    var reportDoneBanner: String { get }
    func reportSavedTo(_ path: String) -> String
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
    var mainModeIPhone: String { get }
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

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let lang = AppLanguage(rawValue: raw) {
            language = lang
        } else {
            // First launch: follow the system language (Russian systems get RU,
            // everything else EN).
            language = (Locale.preferredLanguages.first ?? "").hasPrefix("ru") ? .ru : .en
        }
    }
}

var L: AppStrings { L10nStore.shared.language == .en ? StringsEN() : StringsRU() }
