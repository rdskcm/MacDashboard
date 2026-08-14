// Engine/StringsEN.swift
// English string table: idiomatic UI translations mirroring StringsRU's MARK
// structure and member order for reviewability.
import Foundation

struct StringsEN: AppStrings {
    // MARK: App
    var decimalSeparator: String { "." }

    // MARK: Settings
    var settingsLanguageLabel: String { "Interface language" }
    var settingsIntervalLabel: String { "Refresh interval (CPU/RAM)" }
    func settingsIntervalOption(_ seconds: Int) -> String { "\(seconds) s" }
    var settingsIntervalNoteFast: String { "1 s — the most responsive chart, noticeable background load." }
    var settingsIntervalNoteBalanced: String { "The working range: live charts with no noticeable load." }
    var settingsIntervalNoteEconomy: String { "Economy: values update less often, the battery lasts longer." }
    var settingsProcessLimitLabel: String { "Processes listed" }
    func settingsProcessLimitOption(_ count: Int) -> String { "\(count)" }
    var settingsProcessLimitApply: String { "Apply" }
    var settingsMenuLanguageHint: String { "The menu bar and system dialogs follow the app language after a relaunch" }
    var settingsRelaunchNow: String { "Relaunch Now" }
    var settingsSectionGeneral: String { "General" }
    var settingsSectionMonitoring: String { "Monitoring" }
    var settingsVersionLabel: String { "Version" }
    var settingsWindowTitle: String { "Settings" }

    // MARK: Main dashboard (header + tab picker)
    var mainTabOverview: String { "Overview" }
    var mainTabReport: String { "Report" }
    var mainCollectingInfo: String { "Collecting system information…" }

    // MARK: Overview page section kickers
    var overviewKickerMetrics: String { "Metrics" }
    var overviewKickerMemory: String { "Memory" }
    var overviewKickerProcesses: String { "Processes" }
    var overviewKickerFolders: String { "Folders" }
    var overviewKickerSystem: String { "System" }
    var overviewKickerHistory: String { "History" }

    func headerLoadChip(_ load: String, _ ncpu: Int) -> String { "load \(load) · \(ncpu) cores" }
    func headerUptimeChip(_ uptime: String) -> String { "uptime \(uptime)" }
    var headerRefreshReport: String { "Refresh report" }
    var headerStatusNeedsAttention: String { "Needs attention" }

    // MARK: KPI tiles
    var kpiCpuLabel: String { "Processor (CPU)" }
    func kpiLoad(_ v: String) -> String { "load \(v)" }
    var kpiLoadUnavailable: String { "load —" }
    func kpiCpuSub(_ loadStr: String, _ ncpu: Int) -> String { "\(loadStr) · \(ncpu) cores" }
    func kpiCpuLoadFooter(_ l1: String, _ l2: String, _ l3: String) -> String { "load \(l1) · \(l2) · \(l3)" }
    func kpiCpuSocTemp(_ t: Int) -> String { "SOC \(t) °C" }
    var kpiCpuChartTimeLabel: String { "Time" }
    var kpiMemLabel: String { "Memory" }
    func kpiMemUnit(_ total: String) -> String { "of \(total)" }
    func kpiMemSub(_ compressor: String, _ purgeable: String) -> String { "compressed \(compressor) · purgeable \(purgeable)" }
    var kpiSwapLabel: String { "Swap" }
    func kpiSwapUnit(_ total: String) -> String { "of \(total)" }
    func kpiSwapSub(_ free: String) -> String { "free \(free)" }
    var kpiDiskLabel: String { "Disk" }
    func kpiDiskUnit(_ size: String) -> String { "of \(size)" }
    var kpiDiskFreeLabel: String { "free" }
    func kpiDiskUsedPct(_ pct: Int) -> String { "used \(pct)%" }
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String {
        base + " · data \(dataUsed), system \(sysUsed)"
    }
    func kpiDiskTemp(_ t: Int) -> String { "temp \(t) °C" }
    var kpiBatteryLabel: String { "Battery" }
    func kpiBatteryCycles(_ n: Int) -> String { "\(n) " + (n == 1 ? "cycle" : "cycles") }
    func kpiBatteryCondition(_ cond: String) -> String { "condition \(cond)" }
    func kpiBatteryChargeNow(_ charge: Int) -> String { "now \(charge)%" }
    var kpiBatteryDetailsButton: String { "Details" }

    // MARK: Security card
    var securityTitle: String { "Security" }
    var securityFileVault: String { "FileVault" }
    var securitySip: String { "SIP" }
    var securityFirewall: String { "Firewall" }
    var securityGatekeeper: String { "Gatekeeper" }
    var securityFileVaultTip: String { "Full-disk encryption — without your password the data on the drive cannot be read." }
    var securitySipTip: String { "System Integrity Protection — even an administrator cannot modify system files." }
    var securityFirewallTip: String { "Blocks unsolicited incoming network connections." }
    var securityGatekeeperTip: String { "Checks that the apps you launch are signed and notarized by Apple." }

    // MARK: Report tab
    var reportPlaceholder: String { "Report not generated yet. Click “Refresh report”." }
    var reportShowInFinder: String { "Show in Finder" }
    var reportCopy: String { "Copy" }
    var reportCollecting: String { "Generating report…" }
    func reportFileUpdatedCaption(_ time: String) -> String { "mac_report.txt · updated \(time)" }

    // MARK: Recommendations card
    var recommendationsTitle: String { "Recommendations" }
    var recommendationsCaption: String { "based on the report" }
    var recommendationsAllGood: String { "All good" }
    var recommendationsTipPrefix: String { "Tip: " }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { "Empty the Trash?" }
    var adviceTrashConfirmButton: String { "Empty Trash" }
    var adviceTrashError: String { "Could not empty the Trash" }
    var adviceDone: String { "done" }
    var adviceFirewallConfirmTitle: String { "Turn on the firewall?" }
    var adviceFirewallConfirmMessage: String { "Touch ID or an administrator password will be required." }
    var adviceFirewallConfirmButton: String { "Turn On" }
    var adviceFirewallError: String { "Could not turn on the firewall" }
    var adviceCancel: String { "Cancel" }

    // MARK: Shared (cross-card)
    var sharedUnavailable: String { "(unavailable)" }
    var sharedCollectingData: String { "Collecting data…" }
    var sharedEmpty: String { "empty" }
    var sharedToggleToChart: String { "Chart" }
    var sharedToggleToTable: String { "Table" }
    var sharedToggleShowChart: String { "Show chart" }
    var sharedToggleShowTable: String { "Show table" }
    var sharedInfoHide: String { "Hide explanation" }
    var sharedInfoShow: String { "Show explanation" }

    // MARK: Storage — shared folder labels
    var storageColFolder: String { "Folder" }
    var storageColSize: String { "Size" }
    var storageColShare: String { "Share" }
    var storageTrashLabel: String { "Trash" }
    var storageAppsLabel: String { "Applications" }

    // MARK: Storage — Домашняя папка
    var storageHomeDirsTitle: String { "Home folder" }
    var storageHomeDirsCaption: String { "top by size" }

    // MARK: Storage — Служебные папки
    var storageServiceDirsTitle: String { "Service folders" }
    var storageServiceDirsCaption: String { "caches, containers, logs, apps" }
    var folderTabHome: String { "Home" }
    var folderTabSvc: String { "System" }

    // MARK: Storage — Диски (SMART)
    var storageSmartTitle: String { "Disks (SMART)" }
    func storageSmartUpdatedCaption(_ time: String) -> String { "updated \(time)" }
    var storageSmartRefreshButton: String { "Refresh" }
    var storageSmartColAttribute: String { "Attribute" }
    var storageSmartColValue: String { "Value" }
    var storageSmartInstallButton: String { "Install smartmontools" }
    var storageSmartNeedsHomebrew: String { "External-disk SMART needs Homebrew and smartmontools" }
    func storageSmartInstallFailed(_ msg: String) -> String { "Install failed: \(msg)" }
    var storageSmartKindInternal: String { "INTERNAL" }
    var storageSmartKindExternal: String { "EXTERNAL" }

    // MARK: Process cards
    var processesTitle: String { "Processes" }
    var processSegCPU: String { "CPU" }
    var processSegMem: String { "Memory" }
    var processesMetricA11y: String { "Process metric" }
    var processListCaption: String { "live snapshot from top" }
    var processLoadingDetails: String { "Loading details…" }
    var processDetailThreads: String { "Threads" }
    var processDetailMemory: String { "Memory" }
    var processDetailPath: String { "Path" }
    var processQuit: String { "Quit" }
    var processSignalError: String { "Couldn't send signal (no permission)" }
    var processForceQuit: String { "Force quit" }
    var processForceQuitConfirm: String { "Force quit" }
    var processForceQuitInlineQuestion: String { "Force quit?" }
    func processForceQuitTitle(_ name: String) -> String { "Force quit “\(name)”?" }
    func processRevealA11y(_ name: String) -> String { "Show “\(name)” in Finder" }
    func processTerminateA11y(_ name: String) -> String { "Quit process “\(name)”" }
    func processKillA11y(_ name: String) -> String { "Force quit process “\(name)”" }

    // MARK: Maintenance card
    var maintenanceTitle: String { "System maintenance" }
    var maintenanceBrewNotInstalled: String { "not installed" }
    var maintenanceBrewAllFresh: String { "All packages up to date \u{2713}" }
    func maintenanceBrewOutdatedCount(_ n: Int) -> String { "Outdated packages: \(n)" }
    var maintenanceUpdatesSection: String { "macOS updates" }
    var maintenanceUpdatesAllUpdated: String { "\u{2713}" }
    var maintenanceCrashesSection: String { "Recent crashes" }
    var maintenanceCrashesNone: String { "\u{2713}" }
    var maintenanceUpdatesTip: String { "Pending macOS and App Store updates." }
    var maintenanceCrashesTip: String { "Crash reports macOS has recorded recently." }
    func maintenanceAndMore(_ n: Int) -> String { "and \(n) more" }
    var maintenanceBrewUpgradeButton: String { "Upgrade packages" }
    var maintenanceBrewUpgrading: String { "Upgrading packages… (may take a few minutes)" }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String {
        "Downloading packages… (\(files) \(files == 1 ? "file" : "files") done)"
    }
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String {
        "Upgrading \(name)… \(k) of \(n) (\(pct)%)"
    }
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String { "Upgrading \(name)…" }
    var maintenanceBrewUpgradeFailed: String { "Package upgrade failed — run brew upgrade in Terminal" }
    var maintenanceOpenSoftwareUpdate: String { "Open System Settings…" }

    // MARK: Time Machine card
    var timeMachineNotConfigured: String { "Time Machine is not configured" }
    var timeMachineDestination: String { "Destination" }
    var timeMachineType: String { "Type" }
    var timeMachineTypeLocal: String { "local disk" }
    var timeMachineQuota: String { "Quota" }
    var timeMachineLastBackup: String { "Last backup" }
    var timeMachineSnapshots: String { "Local snapshots" }
    var timeMachineSnapshotsNone: String { "none" }
    func timeMachineSnapshotsCount(_ n: Int) -> String { "\(n)" }
    func timeMachineSnapshotsLast(_ date: String) -> String { ", last \(date)" }

    // MARK: Autostart card
    var autostartTitle: String { "Startup items" }
    var autostartNoPermission: String { "(no permission)" }
    var autostartUserAgents: String { "User agents" }
    var autostartSystemAgents: String { "System agents" }
    var autostartSystemDaemons: String { "System daemons" }
    var autostartBackgroundTasks: String { "Background tasks (non-Apple)" }
    var autostartCheckOutdated: String { "Check for outdated" }
    func autostartCheckOutdatedCount(_ n: Int) -> String { "Outdated: \(n)" }
    var autostartOrphanEmptyText: String { "No outdated plists" }
    var autostartOrphanTooltip: String { "Orphaned — app no longer installed, safe to remove" }
    var autostartDeleteButton: String { "Delete" }
    var autostartDeleteConfirmMessageUser: String { "The file will be moved to the Trash. The change takes effect after the next login or restart." }
    var autostartDeleteConfirmMessageSystem: String { "The file will be permanently deleted (requires Touch ID or an admin password). The change takes effect after the next login or restart." }
    func autostartDeleteError(_ detail: String) -> String { "Couldn't delete: \(detail)" }
    func autostartDeleteAllButton(_ n: Int) -> String { "Delete all (\(n))" }
    func autostartDeleteAllConfirmMessageUser(_ n: Int) -> String { "Move all \(n) plists to the Trash?" }
    func autostartDeleteAllConfirmMessageSystem(_ n: Int) -> String { "Some are system-level — a password is required. Delete all \(n)?" }
    var autostartDeletingAll: String { "Deleting…" }
    var autostartOkTooltip: String { "OK" }

    // MARK: Memory card
    var memoryLegendActive: String { "Active" }
    var memoryLegendWired: String { "Wired (kernel)" }
    var memoryLegendOther: String { "Other (incl. compressed)" }
    var memoryLegendInactive: String { "Inactive" }
    var memoryLegendSpeculative: String { "Speculative" }
    var memoryLegendFree: String { "Free" }
    var memoryLegendPurgeable: String { "Purgeable (informational)" }
    var memoryLegendFileCache: String { "File cache (informational)" }
    var memoryNoteActive: String { "Memory that apps are using right now or have accessed recently." }
    var memoryNoteWired: String { "Held by the macOS kernel and drivers; can't be swapped out or freed." }
    var memoryNoteOther: String { "Mostly compressed memory: macOS compresses rarely used pages instead of writing them to swap." }
    var memoryNoteInactive: String { "Hasn't been used in a while and will be reclaimed when needed; often data from recently closed apps." }
    var memoryNoteSpeculative: String { "Read from disk ahead of time, “just in case”; the first to be freed." }
    var memoryNoteFree: String { "Completely unused memory. A small value here is normal." }
    var memoryNotePurgeable: String { "Memory the system can free without loss when needed (caches, temporary data)." }
    var memoryNoteFileCache: String { "File contents kept in memory to speed up repeat access; freed when needed." }
    func memoryTitle(_ total: String) -> String { "Memory · total \(total)" }
    var memoryCaption: String { "Live snapshot, updates continuously" }
    var memoryInfoHelp: String { "Hover over a memory type to see what it means" }
    func memorySwapNote(_ used: String, _ total: String) -> String { "swap: \(used) of \(total)" }
    var memoryOtherNote: String { "“other” — compressed memory and anything not captured above" }
    var memoryColCategory: String { "Category" }
    var memoryColVolume: String { "Amount" }

    // MARK: History card
    var historyTitle: String { "History" }
    func historyCaption(_ n: Int) -> String { "mac_check_state.json · \(n) samples" }
    var historyColDate: String { "Date" }
    var historyColDiskUsed: String { "Disk used" }
    var historyColFree: String { "Free" }
    var historyColCycles: String { "Cycles" }
    var historyMetricPickerDisk: String { "Disk" }
    var historyMetricPickerBattery: String { "Battery" }
    var historyMetricPickerCycles: String { "Cycles" }
    var historyMetricPickerSwap: String { "Swap" }
    var historyMetricA11y: String { "History metric" }
    var historyMetricYLabelDisk: String { "Used, GB" }
    var historyMetricYLabelBattery: String { "%" }
    var historyMetricYLabelCycles: String { "cycles" }
    var historyMetricYLabelSwap: String { "GB" }
    var historyMetricInsufficientData: String { "Not enough data for this metric's chart" }
    func historyGbValue(_ n: Int) -> String { "\(n) GB" }
    var historyInfoDate: String { "Date — one snapshot per day (kept for up to 60 days)" }
    var historyInfoDiskFree: String { "Disk used / Free — data and free space on the system volume" }
    var historyInfoBattery: String { "Battery — maximum capacity as % of new (battery health), not current charge" }
    var historyInfoCycles: String { "Cycles — charge cycle counter" }
    var historyInfoSwap: String { "Swap — swap file usage at the time of the snapshot" }
    var historyInfoMacos: String { "macOS — system version at the time of the snapshot" }
    var historyInfoSource: String { "Source: mac_check_state.json (Application Support)" }
    var historyInfoHideLabel: String { "Hide column explanations" }
    var historyInfoShowLabel: String { "Show column explanations" }

    // MARK: Energy card
    var energyParamDisplaySleep: String { "Display sleep, min" }
    var energyParamSleep: String { "System sleep, min" }
    var energyParamDiskSleep: String { "Disk sleep, min" }
    var energyParamLowPowerMode: String { "Low Power Mode" }
    var energyParamHibernateMode: String { "Hibernate mode" }
    var energyParamWoMP: String { "Wake on network access" }
    var energyInfoDisplaySleep: String { "Minutes of inactivity before the display turns off. 0 — never. Laptop defaults: 2 min on battery, 10 min on AC power." }
    var energyInfoSleep: String { "Minutes of inactivity before the whole system sleeps (the display is already off by then). 0 — never. Usually set to 0 on AC power so the Mac doesn't sleep." }
    var energyInfoDiskSleep: String { "Minutes of idle time before hard disks spin down. Doesn't matter for the built-in SSD, affects external HDDs. 0 — never." }
    var energyInfoPowerNap: String { "Power Nap: while asleep, the Mac periodically wakes up for mail, iCloud, and Time Machine. On by default on AC power, off on battery." }
    var energyInfoLowPowerMode: String { "Low Power Mode: reduces CPU frequency and brightness to extend battery life. Off by default; sensible to enable on battery." }
    var energyInfoStandby: String { "Standby: after ~3 hours of regular sleep, memory contents are flushed to the SSD and RAM power is cut (deep sleep). On by default." }
    var energyInfoHibernateMode: String { "Sleep format: 0 — RAM only (desktop Macs), 3 — RAM + SSD copy (laptops, default), 25 — SSD copy only (slower wake, maximum savings). Change manually only — a risky setting." }
    var energyInfoWoMP: String { "Wake on LAN: lets the Mac be woken by a network packet. Works on AC power; on by default on AC power." }
    var energyValueOn: String { "on" }
    var energyValueOff: String { "off" }
    var energyValueNever: String { "never" }
    var energyCardTitle: String { "Energy settings (pmset)" }
    func energyApply(_ n: Int) -> String { "Apply (\(n))" }
    var energyCancel: String { "Cancel" }
    var energyResetToDefaults: String { "Reset to defaults" }
    var energyResetHelp: String { "Reset the editable parameters to macOS defaults" }
    var energyApplyCancelled: String { "Cancelled" }
    func energyApplyFailed(_ msg: String) -> String { "Failed to apply: \(msg)" }
    var energyColParam: String { "Parameter" }
    var energyColBattery: String { "Battery" }
    var energyColAC: String { "AC power" }

    // MARK: Battery detail popover
    func batteryUpdatedAt(_ time: String) -> String { "updated \(time)" }
    var batteryLoadingText: String { "Reading battery data…" }
    var batteryPercentSign: String { "%" }
    func batteryMinutes(_ m: Int) -> String { "\(m) min" }
    func batteryHoursMinutes(_ h: Int, _ m: Int) -> String { "\(h) h \(m) min" }
    var batteryStatusOnBattery: String { "On battery" }
    func batteryStatusRemaining(_ time: String) -> String { " · \(time) remaining" }
    var batteryStatusCharging: String { "Charging" }
    func batteryStatusUntilFull(_ time: String) -> String { " · \(time) until full" }
    var batteryStatusACFull: String { "AC power · charged" }
    var batteryStatusACNotCharging: String { "AC power · not charging" }
    var batterySectionNow: String { "Now" }
    var batteryLabelPower: String { "Power" }
    func batteryWatts(_ v: String) -> String { "\(v) W" }
    var batteryLabelCurrent: String { "Current" }
    func batteryMA(_ n: Int) -> String { "\(n) mA" }
    var batteryLabelVoltage: String { "Voltage" }
    func batteryVolts(_ v: String) -> String { "\(v) V" }
    var batteryLabelTemperature: String { "Temperature" }
    func batteryCelsius(_ v: String) -> String { "\(v) °C" }
    func batteryCellsLine(_ joined: String) -> String { "Cells: \(joined) V" }
    var batterySectionCapacity: String { "Capacity and health" }
    var batteryCapMax: String { "Maximum" }
    func batteryMAh(_ n: Int) -> String { "\(n) mAh" }
    var batteryCapDesign: String { "Design" }
    var batteryCapHealth: String { "Health" }
    func batteryPercent(_ n: Int) -> String { "\(n)%" }
    var batteryCapCycles: String { "Cycles" }
    func batteryCyclesOf(_ cycles: Int, _ design: Int) -> String { "\(cycles) of \(design)" }
    var batteryCapCurrentCharge: String { "Current charge" }
    var batteryCapCondition: String { "Condition" }
    var batterySectionCharging: String { "Charging" }
    var batteryChargeAdapter: String { "Adapter" }
    var batteryChargeProtocol: String { "Protocol" }
    var batteryChargeProfiles: String { "Profiles" }
    var batteryChargeCurrentLabel: String { "Charging current" }
    var batteryChargeStatus: String { "Status" }
    func batteryAdapterUsbC(_ watts: Int) -> String { "USB-C · \(watts) W" }
    func batteryAdapterWattsSuffix(_ watts: Int) -> String { " (\(watts) W)" }
    var batteryAdapterWireless: String { ", wireless" }
    func batteryUsbPdLine(_ v: String, _ a: String) -> String { "USB PD · \(v) V × \(a) A" }
    var batteryStatusFullyCharged: String { "Charged" }
    var batteryStatusNotCharging: String { "Not charging" }
    func batteryNotChargingCode(_ n: Int) -> String { " (code \(n))" }
    var batterySectionLifetime: String { "Lifetime" }
    var batteryLifetimeTempLabel: String { "Temperature min/avg/max" }
    func batteryLifetimeTempValue(_ min: Int, _ avg: String, _ max: Int) -> String { "\(min) / \(avg) / \(max) °C" }
    var batteryLifetimeMaxCharge: String { "Max charge current" }
    var batteryLifetimeMaxDischarge: String { "Max discharge current" }
    var batteryLifetimeVoltage: String { "Pack voltage" }
    func batteryLifetimeVoltageRange(_ min: String, _ max: String) -> String { "\(min)–\(max) V" }
    var batteryLifetimeOperatingTime: String { "Time in service" }
    func batteryOperatingHours(_ n: Int) -> String { "\(n) h (estimate)" }
    var batteryDetailLowPower: String { "Low Power Mode" }
    var batteryDetailPassportSection: String { "Battery ID" }
    var batteryDetailManufacturer: String { "Manufacturer" }
    var batteryDetailSerial: String { "Serial number" }
    var batteryDetailMfgDate: String { "Manufacture date" }
    func batteryDetailMfgDateValue(_ month: String, _ code: String) -> String { "\(month) (code \(code))" }

    // MARK: Assessment
    func assessDiskFull(_ pct: String) -> String { "Disk is \(pct)% full — free up space now." }
    func assessDiskFullSoon(_ pct: String) -> String { "Disk is \(pct)% full — time to free up some space." }
    func assessSwapHighSerious(_ used: String) -> String { "Swap usage is \(used) — memory is clearly insufficient." }
    func assessSwapHighWarn(_ used: String) -> String { "Swap usage is \(used) — memory is tight, close heavy apps." }
    func assessBatteryCapacityLow(_ cap: Int) -> String { "Battery capacity is \(cap)% of new — consider a replacement." }
    func assessBatteryCapacityWarn(_ cap: Int) -> String { "Battery capacity is \(cap)% — nearing the service threshold (80%)." }
    func assessBatteryConditionBad(_ cond: String) -> String { "Battery condition: \(cond) — worth a service check." }
    var assessFileVaultOff: String { "FileVault is off — consider turning it on." }
    var assessGatekeeperOff: String { "Gatekeeper is off — consider turning it on." }
    var assessSipOff: String { "SIP is off — consider turning it on." }
    var assessFirewallOff: String { "Firewall is off — consider turning it on." }
    func assessMacUpdatesAvailable(_ n: Int) -> String { "macOS updates available: \(n)" }
    func assessBrewOutdatedTip(_ n: Int) -> String { "Homebrew: \(n) outdated packages (brew upgrade)." }
    func assessCrashesRecent(_ n: Int) -> String { "Recent crash reports: \(n) — check Console.app." }
    var assessTimeMachineNotSetUp: String { "Time Machine is not configured — no backups." }
    func assessSmartDiskErrors(_ title: String) -> String { "Disk “\(title)”: SMART reports media errors — check the disk and your backups." }
    func assessSmartDiskWearHigh(_ title: String, _ pct: Int) -> String { "Disk “\(title)”: wear is \(pct)% — nearing end of life." }
    func assessSmartDiskUnavailableTip(_ title: String) -> String { "Disk “\(title)”: SMART unavailable — reconnect the cable or install smartmontools (brew install smartmontools)." }
    func assessDownloadsTip(_ sizeStr: String, _ shareSuffix: String) -> String { "Downloads folder takes up \(sizeStr)\(shareSuffix) — worth sorting through." }
    func assessDownloadsShareSuffix(_ pct: String) -> String { " (\(pct)% of total disk)" }
    func assessTrashTip(_ sizeStr: String) -> String { "Trash: \(sizeStr) — safe to empty." }
    func assessCachesTip(_ sizeStr: String) -> String { "~/Library/Caches: \(sizeStr) — safe to clear." }
    func assessSummaryCount(_ n: Int) -> String { "Findings: \(n)" }

    // MARK: Parsers / live status
    var battStateCharging: String { "charging" }
    var battStateDischarging: String { "discharging" }
    var battStateCharged: String { "charged" }
    var battStateFinishingCharge: String { "finishing charge" }
    var battStateNotCharging: String { "not charging" }
    var battSourceAC: String { "AC power" }
    var battSourceBattery: String { "battery" }
    var uptimeUnitDay: String { "d" }
    var uptimeUnitHour: String { "h" }
    var uptimeUnitMinute: String { "min" }
    var uptimeUnitSecond: String { "s" }
    func uptimeHourMinuteCombo(_ h: Int, _ mm: Int) -> String { "\(h) h \(mm) min" }

    // MARK: Byte units
    var byteUnitTB: String { "TB" }
    var byteUnitGB: String { "GB" }
    var byteUnitMB: String { "MB" }
    var byteUnitKB: String { "KB" }
    var byteUnitB: String { "B" }

    // MARK: DashboardModel errors
    func errorHistorySaveFailed(_ msg: String) -> String { "Failed to save history: \(msg)" }
    func errorReportWriteFailed(_ msg: String) -> String { "Failed to write report: \(msg)" }

    // MARK: Report writer
    func reportCreatedAt(_ time: String) -> String { "Report created: \(time)" }
    var reportSectionSystem: String { "SYSTEM" }
    var reportSectionDisk: String { "DISK" }
    var reportSectionSnapshots: String { "LOCAL TIME MACHINE SNAPSHOTS" }
    var reportSectionHomeDirs: String { "HOME FOLDER: what's taking up space (top 20)" }
    var reportSectionServiceDirs: String { "LARGE SERVICE FOLDERS" }
    var reportSectionMemory: String { "MEMORY" }
    var reportSectionTopMem: String { "TOP 10 PROCESSES BY MEMORY" }
    var reportSectionTopCPU: String { "TOP 10 PROCESSES BY CPU" }
    var reportSectionLoginItems: String { "STARTUP: Login Items" }
    var reportSectionAgents: String { "STARTUP: LaunchAgents / LaunchDaemons" }
    var reportSectionBackground: String { "BACKGROUND TASKS (non-Apple)" }
    var reportSectionBattery: String { "BATTERY" }
    var reportSectionEnergy: String { "ENERGY SETTINGS" }
    var reportSectionSecurity: String { "SECURITY" }
    var reportSectionTMDest: String { "TIME MACHINE: backup destination" }
    var reportSectionCrashes: String { "RECENT APP CRASHES" }
    var reportSectionUpdates: String { "macOS UPDATES" }
    var reportSectionSmart: String { "EXTERNAL AND INTERNAL DISKS: SMART" }
    var reportDoneBanner: String { "DONE" }
    func reportSavedTo(_ path: String) -> String { "Report saved: \(path)" }
    var reportNone: String { "(none)" }
    func reportUptime(_ v: String) -> String { "Uptime: \(v)" }
    var reportAgentsUserHeader: String { "--- User:" }
    var reportEmpty: String { "(empty)" }
    var reportAgentsSystemHeader: String { "--- System (third-party):" }
    var reportNoBattery: String { "no battery (desktop Mac)" }
    func reportBatterySource(_ v: String) -> String { "Power source: \(v)" }
    func reportBatteryCharge(_ v: String) -> String { "Charge: \(v)" }
    func reportBatteryState(_ v: String) -> String { "State: \(v)" }
    var reportTMNotChecked: String { "(not checked)" }
    var reportTMNotConfigured: String { "(not configured)" }
    func reportTMLastBackup(_ v: String) -> String { "Last backup: \(v)" }
    var reportNotChecked: String { "(not checked)" }
    var reportBrewOutdatedHeader: String { "Outdated packages:" }
    func reportSmartDiskLine(_ title: String, _ device: String, _ status: String) -> String {
        "\(title) (\(device)) — status: \(status)"
    }
    var reportSmartWarningNone: String { "None" }
    var reportSmartWarningLowSpareCapacity: String { "low spare capacity" }
    var reportSmartWarningCriticalTemp: String { "critical temperature" }
    var reportSmartWarningReliabilityDegraded: String { "reliability degraded" }
    var reportSmartWarningReadOnlyMode: String { "read-only mode" }
    var reportSmartWarningBackupPowerFail: String { "backup power failure" }
    var reportSmartWarningPersistentMemoryReadOnly: String { "persistent memory read-only" }
    func reportSmartWarningGeneric(_ hex: String) -> String { "Warning present (\(hex))" }

    var smartAttrCriticalWarning: String { "Critical Warning" }
    var smartAttrTemperature: String { "Temperature" }
    var smartAttrAvailableSpare: String { "Available Spare" }
    var smartAttrPercentageUsed: String { "Percentage Used" }
    var smartAttrPowerCycles: String { "Power Cycles" }
    var smartAttrPowerOnHours: String { "Power On Hours" }
    var smartAttrUnsafeShutdowns: String { "Unsafe Shutdowns" }
    var smartAttrMediaAndDataIntegrityErrors: String { "Media and Data Integrity Errors" }
    var smartAttrErrorInformationLogEntries: String { "Error Information Log Entries" }
    var reportSmartStatusOk: String { "SMART: OK" }

    // MARK: AI assistant
    var settingsSectionAI: String { "AI assistant" }
    var aiSettingsProviderLabel: String { "Provider" }
    var aiSettingsBaseURLLabel: String { "Base URL" }
    var aiSettingsBaseURLPlaceholder: String { "Anthropic defaults to api.anthropic.com when left empty" }
    var aiSettingsModelLabel: String { "Model" }
    var aiSettingsKeyLabel: String { "API key" }
    var aiSettingsKeySave: String { "Save key" }
    var aiSettingsKeyDelete: String { "Delete key" }
    var aiSettingsKeyStored: String { "Key stored" }
    var aiSettingsKeyMissing: String { "No key set — the \"Ask AI\" button is hidden" }
    var aiSettingsPrivacyNote: String { "The key is stored in Keychain only. Nothing is sent without explicit confirmation." }
    var aiSettingsModelCustom: String { "Other…" }
    var aiSettingsModelCustomPlaceholder: String { "Enter model ID" }
    var aiSettingsInDevelopmentNote: String { "This feature is under development" }
    var aiAskButton: String { "Ask AI" }
    var aiSheetTitle: String { "Ask AI" }
    var aiSheetPayloadCaption: String { "Exactly the text below will be sent" }
    var aiToggleSerials: String { "Redact serial numbers" }
    var aiToggleUsername: String { "Redact username in paths" }
    var aiToggleHostname: String { "Redact computer name" }
    var aiToggleSSID: String { "Redact Wi-Fi network name" }
    var aiSendButton: String { "Send" }
    var aiSending: String { "Sending…" }
    var aiAnswerTitle: String { "Answer" }
    func aiRequestFailed(_ msg: String) -> String { "Request failed: \(msg)" }
    var aiKeyReadFailed: String { "Could not read the key from Keychain" }
    var aiNoReport: String { "No report has been collected yet" }
    var aiPayloadSectionAssessment: String { "ASSESSMENT" }
    var aiPayloadSectionLive: String { "CURRENT METRICS" }
    var aiPayloadSectionReport: String { "REPORT" }
    var aiPayloadTipPrefix: String { "- tip: " }
    var aiSystemPrompt: String { "You are a Mac diagnostics assistant. Below is a diagnostic report for the user's computer. Briefly answer: what's fine, what problems exist, and what to fix first." }
    var aiPrivacyContract: String { "Nothing is sent without a key and explicit confirmation. The key stays in Keychain and never appears in reports or logs. No telemetry." }

    // MARK: Report collector
    var reportCollectorNoBackupsYet: String { "no backups yet" }
    var reportCollectorDiskNotConnected: String { "disk not connected" }
    var reportCollectorNoCompletedBackups: String { "no completed backups" }
    var reportCollectorDateUnavailableNoFDA: String { "date unavailable (no Full Disk Access)" }
    var reportCollectorSpotlightEnabled: String { "Indexing enabled" }
    var reportCollectorSpotlightDisabled: String { "Indexing disabled" }
    var reportCollectorInternalDiskFallbackTitle: String { "Internal drive" }
    var reportCollectorSmartOkVerified: String { "SMART: OK (verified)" }
    var reportCollectorSmartNotSupported: String { "SMART not supported" }
    var reportCollectorSmartStatusUnavailable: String { "SMART: status unavailable" }
    var reportCollectorSmartMediaErrors: String { "SMART: media errors" }
    var reportCollectorSmartWearHigh: String { "SMART: wear nearing end of life" }
    var reportCollectorSmartUnavailable: String { "SMART unavailable" }
    var reportCollectorSmartUnavailableNoTools: String { "SMART unavailable (no smartmontools)" }

    // MARK: v2 attention
    var attnLabelDiskFull: String { "Disk" }
    func attnDetailDiskFull(_ pct: String) -> String { "\(pct) % full" }
    var attnLabelDiskFullSoon: String { "Disk" }
    func attnDetailDiskFullSoon(_ pct: String) -> String { "\(pct) % full" }
    var attnLabelSwapHigh: String { "Swap" }
    func attnDetailSwapHigh(_ used: String) -> String { used }
    var attnLabelBatteryCapacity: String { "Battery" }
    func attnDetailBatteryCapacity(_ cap: Int) -> String { "capacity \(cap) %" }
    var attnLabelBatteryCondition: String { "Battery" }
    func attnDetailBatteryCondition(_ cond: String) -> String { "condition: \(cond)" }
    var attnLabelFileVaultOff: String { "FileVault" }
    var attnDetailFileVaultOff: String { "off" }
    var attnLabelGatekeeperOff: String { "Gatekeeper" }
    var attnDetailGatekeeperOff: String { "off" }
    var attnLabelSipOff: String { "SIP" }
    var attnDetailSipOff: String { "off" }
    var attnLabelFirewallOff: String { "Firewall" }
    var attnDetailFirewallOff: String { "off" }
    var attnLabelUpdates: String { "Updates" }
    func attnDetailUpdates(_ n: Int) -> String { "\(n) available" }
    var attnLabelCrashes: String { "Crashes" }
    func attnDetailCrashes(_ n: Int) -> String { "\(n) reports" }
    var attnLabelTimeMachine: String { "Time Machine" }
    var attnDetailTimeMachine: String { "not set up" }
    func attnLabelSmartErrors(_ title: String) -> String { title }
    var attnDetailSmartErrors: String { "SMART errors" }
    func attnLabelSmartWear(_ title: String) -> String { title }
    func attnDetailSmartWear(_ pu: Int) -> String { "wear \(pu) %" }

    var attnVerbSettings: String { "Settings" }
    var attnVerbActivityMonitor: String { "Activity Monitor" }
    var attnVerbDiskUtility: String { "Disk Utility" }
    var attnVerbShow: String { "Show" }
    var attnVerbEmpty: String { "Empty" }
    var attnVerbEnable: String { "Enable" }
    var attnVerbUpgrade: String { "Upgrade" }
    var attnVerbOpen: String { "Open" }

    var attnCapSwap: String { "Swap" }
    var attnCapBattery: String { "Battery" }
    func attnCapBatteryValue(_ p: Int) -> String { "\(p) %" }
    var attnCapBrew: String { "Homebrew" }
    func attnCapBrewValue(_ n: Int) -> String { "\(n) packages" }
    var attnCapSmartNoData: String { "no SMART data" }
    var attnCapDownloads: String { "Downloads" }
    var attnCapTrash: String { "Trash" }
    var attnCapCaches: String { "Caches" }
    var attnExplainSwap: String { "The system is paging memory to disk. Opens Activity Monitor — the Memory tab shows which processes are using it." }
    var attnExplainBattery: String { "Capacity drops naturally over time. Opens the system Battery settings; nothing changes without your confirmation." }
    var attnExplainBrew: String { "Runs `brew upgrade` in the background — progress shows in the Homebrew card. Installed packages are replaced with newer versions." }
    var attnExplainSmart: String { "Opens Disk Utility. External drives often can't expose SMART attributes over USB — that is not a sign of failure." }
    var attnExplainDownloads: String { "Opens the folder in Finder. Nothing is deleted — you decide what to remove." }
    var attnExplainTrash: String { "Asks for confirmation, then empties the Trash via Finder. Files cannot be recovered afterwards." }
    var attnExplainCaches: String { "Opens ~/Library/Caches in Finder. Apps rebuild their caches on next launch." }

    func attnMore(_ n: Int) -> String { "More \(n)" }
    var attnCollapse: String { "Less" }

    var quietSecurityTitle: String { "Security" }
    var quietUpdatesTitle: String { "Updates & crashes" }
    var quietSecurityStatus: String { "all on" }
    var quietUpdatesStatus: String { "no updates or crashes" }
    var quietNeedsAttention: String { "needs attention" }
    var quietStatusAllEnabled: String { "all enabled" }
    var quietStatusAllClear: String { "all clear" }
    var quietMarkOff: String { "off" }
    var quietMarkUnknown: String { "unknown" }
    func quietCountItems(_ n: Int) -> String { "\(n)" }
}
