// Engine/L10n.swift
// In-app localization core. AppStrings is the compile-enforced string table
// protocol (a missing key on a future language struct is a compile error, unlike
// dictionary lookups). Foundation-only: also compiled into the Checks target.
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
    var appWindowTitle: String { get }
    /// Decimal separator for number formatting (`fmtNum`): "," RU, "." EN.
    var decimalSeparator: String { get }

    // MARK: Settings
    var settingsLanguageLabel: String { get }
    var settingsIntervalLabel: String { get }
    func settingsIntervalOption(_ seconds: Int) -> String
    var settingsMenuLanguageHint: String { get }
    var settingsRelaunchNow: String { get }
    var settingsSectionGeneral: String { get }
    var settingsSectionMonitoring: String { get }
    var settingsVersionLabel: String { get }
    var settingsWindowTitle: String { get }

    // MARK: Main dashboard (header + tab picker)
    var mainTabOverview: String { get }
    var mainTabReport: String { get }
    var mainCollectingInfo: String { get }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { get }
    var overviewKickerMemory: String { get }
    var overviewKickerProcesses: String { get }
    var overviewKickerSystem: String { get }
    var overviewKickerHistory: String { get }
    func headerLoadChip(_ load: String, _ ncpu: Int) -> String
    func headerUptimeChip(_ uptime: String) -> String
    var headerRefreshReport: String { get }
    /// Status chip label when `assessment.problems` is non-empty (pairs with `recommendationsAllGood`).
    var headerStatusNeedsAttention: String { get }

    // MARK: KPI tiles
    var kpiCpuLabel: String { get }
    func kpiLoad(_ v: String) -> String
    var kpiLoadUnavailable: String { get }
    func kpiCpuSub(_ loadStr: String, _ ncpu: Int) -> String
    func kpiCpuSocTemp(_ t: Int) -> String
    var kpiCpuChartTimeLabel: String { get }
    var kpiMemLabel: String { get }
    func kpiMemUnit(_ total: String) -> String
    func kpiMemSub(_ compressor: String, _ purgeable: String) -> String
    var kpiSwapLabel: String { get }
    func kpiSwapUnit(_ total: String) -> String
    func kpiSwapSub(_ free: String) -> String
    var kpiDiskLabel: String { get }
    func kpiDiskUnit(_ size: String) -> String
    func kpiDiskUsedPct(_ pct: Int) -> String
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String
    func kpiDiskTemp(_ t: Int) -> String
    var kpiBatteryLabel: String { get }
    func kpiBatteryCycles(_ n: Int) -> String
    func kpiBatteryCondition(_ cond: String) -> String
    func kpiBatteryChargeNow(_ charge: Int) -> String
    var kpiBatteryDetailsButton: String { get }

    // MARK: Security card
    var securityTitle: String { get }
    var securityFileVault: String { get }
    var securitySip: String { get }
    var securityFirewall: String { get }

    // MARK: Report tab
    var reportPlaceholder: String { get }
    var reportShowInFinder: String { get }
    var reportCopy: String { get }
    var reportCollecting: String { get }
    func reportFileUpdatedCaption(_ time: String) -> String

    // MARK: Recommendations card
    var recommendationsTitle: String { get }
    var recommendationsCaption: String { get }
    var recommendationsAllGood: String { get }
    var recommendationsTipPrefix: String { get }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { get }
    var adviceTrashConfirmButton: String { get }
    var adviceTrashError: String { get }
    var adviceDone: String { get }
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

    // MARK: Storage — shared folder labels
    var storageColFolder: String { get }
    var storageColSize: String { get }
    var storageColShare: String { get }
    var storageTrashLabel: String { get }
    var storageAppsLabel: String { get }

    // MARK: Storage — Домашняя папка
    var storageHomeDirsTitle: String { get }
    var storageHomeDirsCaption: String { get }

    // MARK: Storage — Служебные папки
    var storageServiceDirsTitle: String { get }
    var storageServiceDirsCaption: String { get }

    // MARK: Storage — Диски (SMART)
    var storageSmartTitle: String { get }
    func storageSmartUpdatedCaption(_ time: String) -> String
    var storageSmartRefreshButton: String { get }
    var storageSmartColAttribute: String { get }
    var storageSmartColValue: String { get }
    var storageSmartInstallButton: String { get }
    var storageSmartNeedsHomebrew: String { get }
    func storageSmartInstallFailed(_ msg: String) -> String

    // MARK: Process cards
    var processCpuTitle: String { get }
    var processMemTitle: String { get }
    var processListCaption: String { get }
    var processLoadingDetails: String { get }
    var processDetailThreads: String { get }
    var processDetailMemory: String { get }
    var processDetailPath: String { get }
    var processQuit: String { get }
    var processSignalError: String { get }
    var processForceQuit: String { get }
    var processForceQuitConfirm: String { get }
    func processForceQuitTitle(_ name: String) -> String

    // MARK: Maintenance card
    var maintenanceTitle: String { get }
    var maintenanceBrewNotInstalled: String { get }
    var maintenanceBrewAllFresh: String { get }
    func maintenanceBrewOutdatedCount(_ n: Int) -> String
    var maintenanceUpdatesSection: String { get }
    var maintenanceUpdatesAllUpdated: String { get }
    var maintenanceCrashesSection: String { get }
    var maintenanceCrashesNone: String { get }
    func maintenanceAndMore(_ n: Int) -> String
    var maintenanceBrewUpgradeButton: String { get }
    var maintenanceBrewUpgrading: String { get }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String
    var maintenanceBrewUpgradeFailed: String { get }
    var maintenanceOpenSoftwareUpdate: String { get }

    // MARK: Time Machine card
    var timeMachineNotConfigured: String { get }
    var timeMachineDestination: String { get }
    var timeMachineType: String { get }
    var timeMachineTypeLocal: String { get }
    var timeMachineQuota: String { get }
    var timeMachineLastBackup: String { get }
    var timeMachineSnapshots: String { get }
    var timeMachineSnapshotsNone: String { get }
    func timeMachineSnapshotsCount(_ n: Int) -> String
    func timeMachineSnapshotsLast(_ date: String) -> String

    // MARK: Autostart card
    var autostartTitle: String { get }
    var autostartNoPermission: String { get }
    var autostartUserAgents: String { get }
    var autostartSystemAgents: String { get }
    var autostartSystemDaemons: String { get }
    var autostartBackgroundTasks: String { get }
    var autostartCheckOutdated: String { get }
    func autostartCheckOutdatedCount(_ n: Int) -> String
    var autostartOrphanTooltip: String { get }
    var autostartDeleteButton: String { get }
    var autostartDeleteConfirmTitle: String { get }
    var autostartDeleteConfirmMessageUser: String { get }
    var autostartDeleteConfirmMessageSystem: String { get }
    func autostartDeleteError(_ detail: String) -> String
    var autostartOkTooltip: String { get }
    var autostartNoOrphans: String { get }

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
    var historyMetricYLabelDisk: String { get }
    var historyMetricYLabelBattery: String { get }
    var historyMetricYLabelCycles: String { get }
    var historyMetricYLabelSwap: String { get }
    var historyMetricInsufficientData: String { get }
    func historyGbValue(_ n: Int) -> String
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
    func assessSwapHighSerious(_ used: String) -> String
    func assessSwapHighWarn(_ used: String) -> String
    func assessBatteryCapacityLow(_ cap: Int) -> String
    func assessBatteryCapacityWarn(_ cap: Int) -> String
    func assessBatteryConditionBad(_ cond: String) -> String
    var assessFileVaultOff: String { get }
    var assessGatekeeperOff: String { get }
    var assessSipOff: String { get }
    var assessFirewallOff: String { get }
    func assessMacUpdatesAvailable(_ n: Int) -> String
    func assessBrewOutdatedTip(_ n: Int) -> String
    func assessCrashesRecent(_ n: Int) -> String
    var assessTimeMachineNotSetUp: String { get }
    func assessSmartDiskErrors(_ title: String) -> String
    func assessSmartDiskWearHigh(_ title: String, _ pct: Int) -> String
    func assessSmartDiskUnavailableTip(_ title: String) -> String
    func assessDownloadsTip(_ sizeStr: String, _ shareSuffix: String) -> String
    func assessDownloadsShareSuffix(_ pct: String) -> String
    func assessTrashTip(_ sizeStr: String) -> String
    func assessCachesTip(_ sizeStr: String) -> String
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

    // MARK: AI assistant
    var settingsSectionAI: String { get }
    var aiSettingsProviderLabel: String { get }
    var aiSettingsBaseURLLabel: String { get }
    var aiSettingsBaseURLPlaceholder: String { get }
    var aiSettingsModelLabel: String { get }
    var aiSettingsKeyLabel: String { get }
    var aiSettingsKeySave: String { get }
    var aiSettingsKeyDelete: String { get }
    var aiSettingsKeyStored: String { get }
    var aiSettingsKeyMissing: String { get }
    var aiSettingsPrivacyNote: String { get }
    var aiSettingsModelCustom: String { get }
    var aiSettingsModelCustomPlaceholder: String { get }
    var aiSettingsInDevelopmentNote: String { get }
    var aiAskButton: String { get }
    var aiSheetTitle: String { get }
    var aiSheetPayloadCaption: String { get }
    var aiToggleSerials: String { get }
    var aiToggleUsername: String { get }
    var aiToggleHostname: String { get }
    var aiToggleSSID: String { get }
    var aiSendButton: String { get }
    var aiSending: String { get }
    var aiAnswerTitle: String { get }
    func aiRequestFailed(_ msg: String) -> String
    var aiKeyReadFailed: String { get }
    var aiNoReport: String { get }
    var aiPayloadSectionAssessment: String { get }
    var aiPayloadSectionLive: String { get }
    var aiPayloadSectionReport: String { get }
    var aiPayloadTipPrefix: String { get }
    var aiSystemPrompt: String { get }
    var aiPrivacyContract: String { get }

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
    func attnDetailSwapHigh(_ used: String) -> String
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
    var attnCapSwap: String { get }
    var attnCapBattery: String { get }
    func attnCapBatteryValue(_ p: Int) -> String
    var attnCapBrew: String { get }
    func attnCapBrewValue(_ n: Int) -> String
    var attnCapSmartNoData: String { get }
    var attnCapDownloads: String { get }
    var attnCapTrash: String { get }
    var attnCapCaches: String { get }
    var attnExplainSwap: String { get }
    var attnExplainBattery: String { get }
    var attnExplainBrew: String { get }
    var attnExplainSmart: String { get }
    var attnExplainDownloads: String { get }
    var attnExplainTrash: String { get }
    var attnExplainCaches: String { get }

    // Attention summary card overflow toggles (Block V2-SUMMARY).
    func attnMore(_ n: Int) -> String
    var attnCollapse: String { get }

    // Quiet-strip strings (consumed by a later block — unused for now).
    var quietSecurityTitle: String { get }
    var quietUpdatesTitle: String { get }
    var quietSecurityStatus: String { get }
    var quietUpdatesStatus: String { get }
    var quietNeedsAttention: String { get }
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
