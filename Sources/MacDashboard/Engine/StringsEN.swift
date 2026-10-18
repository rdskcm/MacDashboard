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
    var settingsIntervalNoteBalanced: String { "The working range: live charts with no noticeable load." }
    var settingsIntervalNoteEconomy: String { "Economy: values update less often, the battery lasts longer." }
    var settingsWakeIgnoredLabel: String { "Sleep: don't warn about these apps" }
    var settingsWakeIgnoredEmpty: String { "The list is empty. To add an app, right-click the Sleep warning in the main window." }
    var settingsWakeIgnoredRestore: String { "Warn again" }
    func settingsWakeIgnoredRestoreA11y(_ holder: String) -> String { "Warn again about \(holder)" }
    var settingsSectionBackup: String { "Backup" }
    var settingsBackupStaleLabel: String { "Claude backup: warn when older than" }
    func settingsBackupStaleOption(_ hours: Int) -> String { "\(hours / 24) d" }
    var settingsBackupStaleNote: String { "The age is read from ~/Library/Logs/claude-backup.log, so it is known even when the disk is unplugged or locked." }
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
    var kpiCpuLabel: String { "CPU" }
    var kpiLoadUnavailable: String { "load —" }
    func kpiCpuLoadFooter(_ l1: String, _ l2: String, _ l3: String) -> String { "load \(l1) · \(l2) · \(l3)" }
    var kpiMemLabel: String { "Memory" }
    func kpiMemUnit(_ total: String) -> String { "of \(total)" }
    func kpiMemSub(_ compressor: String, _ purgeable: String) -> String { "compressed \(compressor) · purgeable \(purgeable)" }
    var kpiSwapLabel: String { "Swap" }
    func kpiSwapUnit(_ total: String) -> String { "of \(total)" }
    func kpiSwapSub(_ free: String) -> String { "free \(free)" }
    var kpiDiskLabel: String { "Disk · free" }
    func kpiDiskUnit(_ size: String) -> String { "of \(size)" }
    func kpiDiskUsedPct(_ pct: Int) -> String { "used \(pct)%" }
    func kpiDiskUsedDetail(_ base: String, _ dataUsed: String, _ sysUsed: String) -> String {
        base + " · data \(dataUsed), system \(sysUsed)"
    }
    func kpiDiskPurgeableDetail(_ base: String, _ purgeable: String) -> String { base + " · purgeable \(purgeable)" }
    var kpiBatteryLabel: String { "Battery" }
    func kpiBatteryCycles(_ n: Int) -> String { "\(n) " + (n == 1 ? "cycle" : "cycles") }
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
    var recommendationsAllGood: String { "All good" }

    // MARK: Advice actions
    var adviceTrashConfirmTitle: String { "Empty the Trash?" }
    var adviceTrashConfirmButton: String { "Empty Trash" }
    var adviceTrashError: String { "Could not empty the Trash" }
    var adviceTrashNotPermitted: String { "MacDashboard is not allowed to control Finder, so it cannot empty the Trash. Allow it under Privacy & Security → Automation." }
    var adviceTrashOpenAutomation: String { "Open Automation settings" }
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
    func sharedMoreN(_ n: Int) -> String { "\(n) more" }
    var sharedCollapse: String { "Collapse" }

    // MARK: Storage — shared folder labels
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
    func storageFoldersNoFDA(_ folders: String) -> String { "Not shown here: \(folders) — the app doesn't have Full Disk Access." }
    var storageFoldersNoFDAButton: String { "Open Settings" }
    var storageFoldersNoFDAButtonA11y: String { "Open Full Disk Access settings" }
    func storageFoldersNotMeasured(_ folders: String) -> String { "Not measured in time: \(folders)." }

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
    var processListCaption: String { "live snapshot" }
    var processLoadingDetails: String { "Loading details…" }
    var processDetailThreads: String { "Threads" }
    var processDetailMemory: String { "Memory" }
    var processDetailPath: String { "Path" }
    var processQuit: String { "Quit" }
    var processSignalError: String { "Couldn't send signal (no permission)" }
    var processForceQuit: String { "Force quit" }
    var processForceQuitConfirm: String { "Force quit" }
    var processForceQuitInlineQuestion: String { "Force quit?" }
    func processRevealA11y(_ name: String) -> String { "Show “\(name)” in Finder" }
    func processTerminateA11y(_ name: String) -> String { "Quit process “\(name)”" }
    func processKillA11y(_ name: String) -> String { "Force quit process “\(name)”" }

    // MARK: Maintenance card
    var maintenanceTitle: String { "System maintenance" }
    var maintenanceBrewNotInstalled: String { "not installed" }
    var maintenanceBrewVersionUnknown: String { "Homebrew is installed, but its version couldn't be determined" }
    var maintenanceBrewAllFresh: String { "All packages up to date \u{2713}" }
    func maintenanceBrewOutdatedCount(_ n: Int) -> String { "Outdated packages: \(n)" }
    var maintenanceBrewOutdatedCheckFailed: String { "Couldn't check for outdated packages — run brew outdated in Terminal" }
    var maintenanceUpdatesSection: String { "macOS updates" }
    var maintenanceUpdatesAllUpdated: String { "\u{2713}" }
    var maintenanceCrashesSection: String { "Recent crashes" }
    var maintenanceCrashesNone: String { "\u{2713}" }
    var maintenanceUpdatesTip: String { "Pending macOS and App Store updates." }
    var maintenanceCrashesTip: String { "Crash reports macOS recorded in the last 7 days." }
    func maintenanceCrashRow(_ process: String, _ count: Int) -> String { count > 1 ? "\(process) \u{00D7}\(count)" : process }
    func maintenanceCrashRevealA11y(_ process: String) -> String { "Show \(process) crash reports in Finder" }
    func maintenanceAndMore(_ n: Int) -> String { "and \(n) more" }
    var maintenanceBrewUpgradeButton: String { "Upgrade packages" }
    func maintenanceBrewConfirmTitle(_ n: Int) -> String { "Upgrade \(n) \(n == 1 ? "package" : "packages")?" }
    var maintenanceBrewConfirmButton: String { "Upgrade" }
    var maintenanceBrewUpgrading: String { "Upgrading packages… (may take a few minutes)" }
    func maintenanceBrewProgressDownloading(_ files: Int) -> String {
        "Downloading packages… (\(files) \(files == 1 ? "file" : "files") done)"
    }
    func maintenanceBrewProgressUpgrading(_ name: String, _ k: Int, _ n: Int, _ pct: Int) -> String {
        "Upgrading \(name)… \(k) of \(n) (\(pct)%)"
    }
    func maintenanceBrewProgressUpgradingBare(_ name: String) -> String { "Upgrading \(name)…" }
    var maintenanceBrewUpgradeFailed: String { "Package upgrade failed — run brew upgrade in Terminal" }
    var maintenanceBrewStopButton: String { "Stop" }
    var maintenanceBrewStopA11y: String { "Stop package upgrade" }
    var maintenanceBrewStopping: String { "Stopping the upgrade…" }
    var maintenanceBrewRechecking: String { "Checking what was upgraded…" }
    func maintenanceBrewStopped(_ upgraded: Int, _ total: Int) -> String {
        "Upgrade stopped: \(upgraded) of \(total) \(total == 1 ? "package" : "packages") upgraded"
    }
    var maintenanceBrewStoppedUnknown: String { "Upgrade stopped" }
    var maintenanceOpenSoftwareUpdate: String { "Open System Settings…" }

    // MARK: Time Machine card
    var timeMachineNotConfigured: String { "Time Machine is not configured" }
    var timeMachineDestination: String { "Destination" }
    var timeMachineType: String { "Type" }
    var timeMachineTypeLocal: String { "local disk" }
    var timeMachineQuota: String { "Quota" }
    var timeMachineLastBackup: String { "Last backup" }
    var timeMachineConnection: String { "Connection" }
    var timeMachineConnectionNone: String { "not connected right now" }
    var timeMachineSnapshots: String { "Local snapshots" }
    var timeMachineSnapshotsNone: String { "none" }
    func timeMachineSnapshotsCount(_ n: Int) -> String { "\(n)" }
    func timeMachineSnapshotsLast(_ date: String) -> String { ", last \(date)" }
    var timeMachinePurgeable: String { "Purgeable space" }
    var timeMachinePurgeableTip: String { "Space macOS frees on its own when it is needed: Time Machine local snapshots and caches. A per-snapshot size cannot be computed — snapshots share disk blocks." }

    // MARK: Claude backup card (BACKUP-AGE)
    var claudeBackupCardTitle: String { "Claude backup" }
    var claudeBackupAgeLabel: String { "Age" }
    var claudeBackupLastLabel: String { "Last snapshot" }
    var claudeBackupLimitLabel: String { "Warn after" }
    func claudeBackupAgo(_ age: String) -> String { "\(age) ago" }
    var claudeBackupJustNow: String { "just now" }
    var claudeBackupNoneFound: String { "no successful snapshot in the log" }
    var claudeBackupUnreadable: String { "the log could not be read" }

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
    var autostartDeleteInvalidPath: String { "the path is not a valid autostart plist" }
    func autostartDeleteBulkFailure(_ failed: Int, _ total: Int, _ detail: String) -> String {
        "\(failed) of \(total): \(detail)"
    }

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
    var historyNotEnoughDays: String { "History will appear here once the app has checked this Mac on two different days — it saves one snapshot per day." }
    var historyRangeMonth: String { "Month" }
    var historyRangeQuarter: String { "3 mo" }
    var historyRangeYear: String { "Year" }
    var historyRangeAll: String { "All" }
    var historyRangeA11y: String { "History chart period" }
    func historyGbValue(_ n: Int) -> String { "\(n) GB" }
    var historyRestartTitle: String { "History started over" }
    func historyRestartDetail(_ file: String) -> String { "The previous history file could not be read, so History is being recorded from scratch. The old file was not deleted: it is kept in the same folder as “\(file)”." }
    var historyRestartReveal: String { "Show in Finder" }
    var historyRestartRevealA11y: String { "Show the previous history file in Finder" }
    var historyRestartHide: String { "Hide" }
    var historyRestartHideA11y: String { "Hide the History started over notice" }
    var historyInfoDate: String { "Date — one snapshot per day (every day is kept)" }
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
    func energyApplyConfirmTitle(_ n: Int) -> String { "Apply \(n) \(n == 1 ? "change" : "changes")?" }
    var energyApplyConfirmButton: String { "Apply" }
    var energyApplyConfirmAdmin: String { "Touch ID or an administrator password will be required." }
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
    func assessMemPressure(critical: Bool, apps: [String]) -> String {
        let head = critical ? "macOS reports that memory is running out — the Mac may slow down."
                            : "macOS reports that free memory is running low."
        switch apps.count {
        case 0: return head + " Close apps you are not using right now."
        case 1: return head + " \(apps[0]) uses the most memory — close what you are not using right now."
        default: return head + " \(apps.dropLast().joined(separator: ", ")) and \(apps[apps.count - 1]) use the most memory — close what you are not using right now."
        }
    }
    func assessWakeHolders(_ entries: [String]) -> String {
        let head = entries.count == 1 ? "1 program is keeping the Mac awake" : "\(entries.count) programs are keeping the Mac awake"
        return "\(head): \(entries.joined(separator: "; "))."
    }
    func assessBatteryCapacityLow(_ cap: Int) -> String { "Battery capacity is \(cap)% of new — consider a replacement." }
    func assessBatteryCapacityWarn(_ cap: Int) -> String { "Battery capacity is \(cap)% — nearing the service threshold (80%)." }
    func assessBatteryConditionBad(_ cond: String) -> String { "Battery condition: \(cond) — worth a service check." }
    var assessFileVaultOff: String { "FileVault is off — consider turning it on." }
    var assessGatekeeperOff: String { "Gatekeeper is off — consider turning it on." }
    var assessSipOff: String { "SIP is off — consider turning it on." }
    var assessFirewallOff: String { "Firewall is off — consider turning it on." }
    func assessMacUpdatesAvailable(_ n: Int) -> String { "macOS updates available: \(n)" }
    func assessBrewOutdatedTip(_ n: Int) -> String { "Homebrew: \(n) outdated packages (brew upgrade)." }
    func assessOwnCrashesRecent(_ app: String, _ n: Int) -> String { "\(app) crash reports in the last 7 days: \(n) — check Console.app." }
    func assessKernelPanicsRecent(_ n: Int) -> String { "System crashes (kernel panics) in the last 7 days: \(n) — check Console.app." }
    var assessTimeMachineNotSetUp: String { "Time Machine is not configured — no backups." }
    func assessClaudeBackupStale(_ age: String) -> String { "No Claude backup for \(age) — check that the disk is connected and unlocked." }
    var assessClaudeBackupNone: String { "The Claude backup log has no successful snapshot — check the disk." }
    func assessSmartDiskErrors(_ title: String) -> String { "Disk “\(title)”: SMART reports media errors — check the disk and your backups." }
    func assessSmartDiskWearHigh(_ title: String, _ pct: Int) -> String { "Disk “\(title)”: wear is \(pct)% — nearing end of life." }
    func assessSmartDiskUnavailableTip(_ title: String) -> String { "Disk “\(title)”: SMART unavailable — reconnect the cable or install smartmontools (brew install smartmontools)." }
    func assessDownloadsTip(_ sizeStr: String, _ shareSuffix: String) -> String { "Downloads folder takes up \(sizeStr)\(shareSuffix) — worth sorting through." }
    func assessDownloadsShareSuffix(_ pct: String) -> String { " (\(pct)% of total disk)" }
    func assessTrashTip(_ sizeStr: String) -> String { "Trash: \(sizeStr) — safe to empty." }
    func assessCachesTip(_ sizeStr: String) -> String { "~/Library/Caches: \(sizeStr) — safe to clear." }
    var assessNoFDATip: String { "Some folders are missing from the report: the app doesn't have Full Disk Access." }
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
    var reportSectionUnparsed: String { "UNRECOGNISED COMMAND OUTPUT (first lines)" }
    var reportUnparsedHint: String { "MacDashboard could not read the output of these commands. Serial numbers and UUIDs are masked; attach this block to a bug report." }
    func reportUnparsedMoreLines(_ n: Int) -> String { "(+\(n) more lines not shown)" }
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
    var reportSectionTimings: String { "COLLECTION TIMES" }
    var reportTimingsNote: String { "Sections are collected concurrently, so their times overlap." }
    func reportTimingsPass(_ v: String) -> String { "Whole pass: \(v)" }
    func reportTimingsUpdates(_ v: String, _ at: String) -> String { "macOS updates (background check at \(at)): \(v)" }
    func reportUpdatesCheckedAt(_ at: String) -> String { "(checked \(at))" }
    var updatesCheckedJustNow: String { "checked just now" }
    func updatesCheckedAgo(_ age: String) -> String { "checked \(age) ago" }
    func reportTimingsFolderSizes(_ v: String, _ at: String) -> String { "Folder sizes (background count at \(at)): \(v)" }
    func reportTimingsSectionName(_ s: ReportSection) -> String {
        switch s {
        case .system: return "System"
        case .snapshots: return "Local snapshots"
        case .homeDirs: return "Home folder"
        case .serviceDirs: return "Service folders"
        case .security: return "Security"
        case .tmDest: return "Time Machine"
        case .spotlight: return "Spotlight"
        case .crashes: return "Crashes"
        case .brew: return "Homebrew"
        case .updates: return "macOS updates"
        case .autostart: return "Startup items"
        case .smart: return "SMART"
        case .energy: return "Energy settings"
        case .battery: return "Battery"
        }
    }
    func reportFoldersCountedAt(_ at: String) -> String { "(counted \(at))" }
    func foldersCountedAgo(_ age: String) -> String { "counted \(age) ago" }
    var foldersCountedJustNow: String { "counted just now" }
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
    var attnLabelSwapHigh: String { "Memory" }
    var attnDetailMemPressureWarn: String { "running low" }
    var attnDetailMemPressureCritical: String { "running out" }
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
    var attnLabelClaudeBackup: String { "Claude backup" }
    var attnDetailClaudeBackupNone: String { "none succeeded" }
    var attnLabelWakeHolders: String { "Sleep" }
    func attnDetailWakeHolders(_ first: String, more: Int) -> String { more > 0 ? "\(first), +\(more) more" : first }
    func wakeHolderOnBehalf(_ owner: String, _ requester: String) -> String { "\(owner) (for \(requester))" }
    func wakeHolderEntry(_ holder: String, _ age: String) -> String { "\(holder) — \(age)" }
    func attnWakeIgnore(_ holder: String) -> String { "Don't warn about \(holder)" }
    var attnWakeIgnoreHint: String { "Right-click to stop warning about an app." }
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

    var attnCapBattery: String { "Battery" }
    func attnCapBatteryValue(_ p: Int) -> String { "\(p) %" }
    var attnCapBrew: String { "Homebrew" }
    func attnCapBrewValue(_ n: Int) -> String { "\(n) packages" }
    var attnCapSmartNoData: String { "no SMART data" }
    var attnCapDownloads: String { "Downloads" }
    var attnCapTrash: String { "Trash" }
    var attnCapCaches: String { "Caches" }
    var attnExplainBattery: String { "Capacity drops naturally over time. Opens the system Battery settings; nothing changes without your confirmation." }
    var attnExplainBrew: String { "Runs `brew upgrade` in the background — progress shows in the Homebrew card. Installed packages are replaced with newer versions." }
    var attnExplainSmart: String { "Opens Disk Utility. External drives often can't expose SMART attributes over USB — that is not a sign of failure." }
    var attnExplainDownloads: String { "Opens the folder in Finder. Nothing is deleted — you decide what to remove." }
    var attnExplainTrash: String { "Asks for confirmation, then empties the Trash via Finder. Files cannot be recovered afterwards." }
    var attnExplainCaches: String { "Opens ~/Library/Caches in Finder. Apps rebuild their caches on next launch." }
    var attnCapFolders: String { "Folders" }
    var attnCapFoldersNoAccess: String { "some are hidden" }
    var attnExplainNoFDA: String { "Opens System Settings → Privacy & Security → Full Disk Access. Without it the app can't see the Trash and some Library folders, so their size is missing from the report." }

    func attnMore(_ n: Int) -> String { "More \(n)" }
    var attnCollapse: String { "Less" }

    var quietUpdatesTitle: String { "Updates & crashes" }
    var quietNeedsAttention: String { "needs attention" }
    var quietStatusAllEnabled: String { "all enabled" }
    var quietStatusAllClear: String { "all clear" }
    var quietMarkOff: String { "off" }
    var quietMarkUnknown: String { "unknown" }
    func quietCountItems(_ n: Int) -> String { "\(n)" }

    // MARK: iPhone module
    var mainModeMac: String { "This Mac" }
    var mainModeIPhone: String { "iPhone" }
    var iphoneKickerDevices: String { "Devices" }
    var iphoneStatusConnected: String { "Connected by cable" }
    var iphoneStatusNeedsTrust: String { "Trust needed: unlock the iPhone and tap “Trust”" }
    var iphoneStatusReading: String { "Reading…" }
    var iphoneStatusFailed: String { "Could not read the iPhone" }
    var iphoneUnknownDevice: String { "iPhone" }
    var iphoneRetry: String { "Retry" }
    var iphoneSearchAgain: String { "Search again" }
    var iphoneRestartService: String { "Restart connection service…" }
    var iphoneRestartConfirmTitle: String { "Restart the connection service?" }
    var iphoneRestartConfirmBody: String { "The service briefly interrupts every iPhone and iPad connected to this Mac, including Finder sync. It needs an administrator password or Touch ID." }
    var iphoneRestartConfirm: String { "Restart" }
    var iphoneRestartCancel: String { "Cancel" }
    var iphoneRestartBusy: String { "Restarting the connection service" }
    func iphoneRestartFailed(_ detail: String) -> String { "Could not restart the connection service: \(detail)" }
    var iphoneBack: String { "Back" }
    var iphoneRefresh: String { "Refresh" }
    var iphoneUnavailable: String { "iPhone connection is not available on this version of macOS." }
    func iphoneStatusRemembered(_ date: String) -> String { "Not connected · last seen \(date)" }
    func iphoneOpenDeviceA11y(_ name: String) -> String { "Open \(name)" }
    var iphoneBatteryTitle: String { "Battery" }
    var iphoneHistoryTitle: String { "Battery history" }
    var iphoneBatHealth: String { "Health" }
    var iphoneBatCycles: String { "Cycles" }
    var iphoneBatCharge: String { "Charge" }
    var iphoneBatState: String { "State" }
    var iphoneBatTemperature: String { "Temperature" }
    var iphoneBatVoltage: String { "Voltage" }
    var iphoneBatCapacity: String { "Capacity" }
    var iphoneChargeCharging: String { "Charging" }
    var iphoneChargeExternal: String { "Plugged in" }
    var iphoneChargeBattery: String { "On battery" }
    var iphoneUnitMAh: String { "mAh" }
    var iphoneUnitWh: String { "Wh" }
    var iphoneCapacityUnitA11y: String { "Capacity units" }
    var iphoneWhSourceHelp: String { "Approximate: capacity × 3.88 V, the typical iPhone battery voltage (Wikipedia, iPhone 16 Pro / 17 Pro articles, from regulatory listings)" }
    var iphoneBatteryConnectToRead: String { "Connect the iPhone by cable to read the battery." }
    var iphoneBatteryNoData: String { "no data" }
    var iphoneHistoryEmpty: String { "No history yet: points appear on days the iPhone is connected." }
    var iphoneHistorySourceLive: String { "Measured" }
    var iphoneHistorySourceImport: String { "From sysdiagnose" }
    var iphoneHistoryColDate: String { "Date" }
    var iphoneHistoryColHealth: String { "Health" }
    var iphoneHistoryColCycles: String { "Cycles" }
    var iphoneHistoryColSource: String { "Source" }
    func iphoneBatteryFromHistory(_ date: String) -> String { "From history · \(date)" }
    func iphoneHistoryCaption(_ n: Int) -> String { "\(n) \(n == 1 ? "day" : "days")" }
    var iphoneHistoryChart: String { "Chart" }
    var iphoneHistoryTable: String { "Table" }
    var iphoneHistoryViewA11y: String { "Battery history view" }
    func iphoneChartCycles(_ n: Int) -> String { "\(n) \(n == 1 ? "cycle" : "cycles")" }
    var iphoneChartSourceImport: String { "Sysdiagnose" }
    func iphoneChartMonth(_ m: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names[min(max(m, 1), 12) - 1]
    }
    func iphoneChartWeekLabel(day: Int, month: Int) -> String { "\(iphoneChartMonth(month)) \(day)" }

    var iphoneLogsTitle: String { "Crash logs" }
    var iphoneLogsConnectToRead: String { "Connect the iPhone by cable to read its logs." }
    var iphoneLogsEmpty: String { "No log files found." }
    var iphoneLogsRefreshA11y: String { "Refresh the crash log list" }
    func iphoneLogsCaption(_ n: Int) -> String { "\(n) \(n == 1 ? "file" : "files")" }
    func iphoneLogsCategory(_ c: LogCategory) -> String {
        switch c {
        case .appCrash: return "App crashes"
        case .exceptionFault: return "Exception faults"
        case .jetsam: return "Memory pressure (Jetsam)"
        case .diskWrites: return "Disk writes"
        case .cpuResource: return "CPU resource"
        case .stackshot: return "Stackshots"
        case .otherReport: return "Other reports"
        case .analytics: return "Analytics"
        case .other: return "Other files"
        }
    }
    var iphoneSectionReadFailed: String { "Could not read from the iPhone. Press Refresh to try again." }

    var iphoneImportTitle: String { "Sysdiagnose import" }
    var iphoneImportButton: String { "Import" }
    func iphoneImportArchiveA11y(_ name: String) -> String { "Import archive \(name)" }
    var iphoneImportPickFile: String { "Choose file on Mac…" }
    var iphoneImportPickA11y: String { "Choose a sysdiagnose archive on this Mac" }
    var iphoneImportPickPrompt: String { "Choose" }
    func iphoneImportConfirmTitle(_ name: String, into phone: String) -> String { "Import “\(name)” into \(phone)" }
    var iphoneImportParseOnly: String { "Parse only" }
    var iphoneImportParseKeep: String { "Parse and keep" }
    var iphoneImportCancel: String { "Cancel" }
    var iphoneImportParseOnlyA11y: String { "Parse the archive without keeping it" }
    var iphoneImportParseKeepA11y: String { "Parse the archive and keep it on this Mac" }
    var iphoneImportCancelA11y: String { "Cancel the import" }
    func iphoneImportMismatchTitle(_ target: String) -> String { "Load another phone’s data into \(target)?" }
    func iphoneImportMismatchMessage(file: String, owner: String?, archiveMAh: [Int], deviceMAh: Int, target: String) -> String {
        "“\(file)” appears to be from \(owner ?? "another iPhone"): the design capacity of its battery is "
            + "\(archiveMAh.map { batteryMAh($0) }.joined(separator: ", ")), \(target)’s is \(batteryMAh(deviceMAh)). "
            + "If you load it, its battery history replaces \(target)’s for the days it covers."
    }
    var iphoneImportMismatchProceed: String { "Load anyway" }
    var iphoneImportMismatchProceedA11y: String { "Load the other phone’s battery history into this phone" }
    var iphoneImportHint: String { "Archives on the phone appear once the logs are read; you can also choose a .tar.gz file on this Mac." }
    func iphoneImportProgress(_ p: ImportProgress) -> String {
        switch p {
        case .copying(let done, let total):
            return "Copying from the phone: \(fmtBytes(done)) of \(fmtBytes(total))"
        case .extracting: return "Extracting the needed files…"
        case .parsing: return "Parsing…"
        }
    }
    func iphoneImportSummary(_ s: ImportSummary) -> String {
        var t = "Battery points: \(s.batteryPoints), log files: \(s.logFiles)"
        if s.skippedRows > 0 { t += ", skipped rows: \(s.skippedRows)" }
        return t + (s.keptPath != nil ? ". Archive kept." : ".")
    }
    func iphoneImportError(_ e: ImportError) -> String {
        switch e {
        case .copyFailed: return "Could not copy the archive from the phone."
        case .sizeMismatch: return "The copied archive size did not match the size on the phone."
        case .tarFailed: return "Could not extract the archive."
        case .keepFailed: return "Could not keep the archive."
        case .cancelled: return "Import cancelled."
        }
    }
    func iphoneImportErrorDetail(_ e: ImportError) -> String? {
        guard case .tarFailed(let f) = e else { return nil }
        switch f {
        case .message(let line): return line
        case .exitCode(let n): return "tar exited with code \(n)."
        case .signal(let s): return "tar was stopped by signal \(s)."
        case .launchFailed(let code): return "tar could not be started (error \(code))."
        case .timedOut: return "tar did not finish in time."
        case .listingTooLong: return "The archive lists too many files."
        case .workFiles: return "Could not create temporary files for extraction."
        }
    }
    var iphoneImportKeptTitle: String { "Kept archives" }
    func iphoneImportRevealA11y(_ name: String) -> String { "Show archive \(name) in Finder" }
    func iphoneLogsFromArchive(_ name: String) -> String { "From archive \(name)" }
    var iphoneIdentityTitle: String { "Device and parts" }
    var iphoneIdentityConnectToRead: String { "Connect the iPhone by cable to read its device details." }
    var iphoneIdentityRefreshA11y: String { "Refresh the device details" }
    var iphoneIdentityShow: String { "Show in full" }
    var iphoneIdentityHide: String { "Hide" }
    var iphoneIdentityCopy: String { "Copy" }
    var iphoneIdentityCopied: String { "Copied" }
    func iphoneRevealA11y(_ label: String) -> String { "Show in full: \(label)" }
    func iphoneHideA11y(_ label: String) -> String { "Hide value: \(label)" }
    func iphoneCopyA11y(_ label: String) -> String { "Copy value: \(label)" }
    func iphoneIdentityLabel(_ l: IdentityLabel) -> String {
        switch l {
        case .marketingName: return "Model"
        case .modelNumber: return "Model number"
        case .regulatoryModel: return "Regulatory model"
        case .hardwareModel: return "Hardware model"
        case .ios: return "iOS version"
        case .storage: return "Storage"
        case .colorCode: return "Colour code"
        case .serial: return "Serial number"
        case .logicBoard: return "Logic board"
        case .imei: return "IMEI"
        case .imei2: return "IMEI 2"
        case .battery: return "Battery"
        case .displayPanel: return "Display panel"
        case .displayRawPanel: return "Display raw panel"
        case .coverGlass: return "Cover glass"
        case .backGlass: return "Back glass"
        case .nova: return "Nova module"
        case .ambientLight: return "Ambient light sensor"
        case .backCamera: return "Main camera"
        case .backSuperWide: return "Ultra Wide"
        case .backTele: return "Telephoto"
        case .frontCamera: return "Front camera"
        case .frontIR: return "Face ID IR camera"
        case .faceIDProjector: return "Face ID projector"
        }
    }

    var iphoneTagNotConnected: String { "Not connected" }
    var iphoneTagTrustNeeded: String { "Trust needed" }
    var iphoneTagReadFailed: String { "Could not read" }
    var iphoneSubTrust: String { "unlock it and tap “Trust”" }
    var iphoneSubReconnect: String { "reconnect the cable" }
    func iphoneSubLastSeen(_ date: String) -> String { "last seen \(date)" }
    func iphoneSubCharge(_ percent: Int, _ state: String) -> String { "\(percent) % · \(state)" }
    var iphoneStateChargingLower: String { "charging" }
    var iphoneStateExternalLower: String { "plugged in" }
    var iphoneStateBatteryLower: String { "on battery" }
    var iphoneTileHealth: String { "Battery health" }
    var iphoneNotIdentified: String { "Not identified yet" }
    var iphonePendingTrustText: String { "Unlock the iPhone and tap “Trust” on its screen, then retry." }
    var iphonePendingFailedText: String { "Could not read the iPhone. Reconnect the cable, then retry." }
    func iphoneSummary(connected: Int, notConnected: Int, waiting: Int) -> String {
        var parts: [String] = []
        if connected > 0 { parts.append("\(connected) connected") }
        if notConnected > 0 { parts.append("\(notConnected) not connected") }
        if waiting > 0 { parts.append("\(waiting) waiting for trust") }
        return parts.joined(separator: " · ")
    }
    var iphoneSummaryNone: String { "No iPhone found yet" }
    var iphoneSummaryUnavailable: String { "Not available on this Mac" }
    var iphoneNoticeEmptyTitle: String { "No iPhone found" }
    var iphoneNoticeEmptyBody: String { "Connect the iPhone by cable, unlock it and tap “Trust”." }
    var iphoneNoticeUnavailableTitle: String { "iPhone connection is not available" }
    var iphoneRestartingShort: String { "Restarting…" }
    var iphoneRestartingBanner: String { "Restarting the connection service. Devices reconnect in a few seconds." }

    var iphoneBatteryMeasuredNow: String { "Measured now" }
    var iphoneHealthNote: String { "Maximum capacity vs design capacity" }
    func iphoneHealthHistoryNote(cycles: Int?) -> String {
        guard let n = cycles else { return "last value from history" }
        return "\(n) \(n == 1 ? "cycle" : "cycles") · last value from history"
    }
    var iphoneLiveReadings: String { "Live readings" }
    var iphoneLiveReadingsConnect: String { "Connect the iPhone by cable to see charge, state, temperature, voltage and capacity." }
    var iphoneRefreshOfflineHelp: String { "Connect the iPhone by cable to refresh" }
    var iphoneLogsSourceLive: String { "On iPhone" }
    var iphoneLogsSourceArchive: String { "From archive" }
    var iphoneLogsSourceA11y: String { "Crash log source" }
    var iphoneLogsColSize: String { "Size" }
    var iphoneImportOnPhone: String { "On the iPhone" }
    var iphoneImportChoiceBody: String { "Parse reads battery history and log files from the archive. Keep also stores a copy of the archive on this Mac." }
    var iphoneImportInArchive: String { "In the archive" }
    var iphoneIdentitySerials: String { "Serial numbers" }
    // MARK: Common (strings.json › Shared + 00 §4.16/§7; REDESIGN-FOUNDATION)
    var commonShowInFinder: String { "Show in Finder" }
    var commonFirewall: String { "Firewall" }
    var commonEnable: String { "Enable…" }
    var commonDisk: String { "Disk" }
    var commonSetUp: String { "Set up…" }
    var commonShow: String { "Show" }
    var commonMacCantSleep: String { "Mac can’t sleep" }
    var commonBattery: String { "Battery" }
    var commonInstall: String { "Install…" }
    var commonServiceRecommended: String { "service recommended" }
    var commonClaudeBackup: String { "Claude backup" }
    var commonCPU: String { "CPU" }
    var commonMemory: String { "Memory" }
    var commonStorage: String { "Storage" }
    var commonSecurity: String { "Security" }
    var commonBackups: String { "Backups" }
    var commonSystem: String { "System" }
    var commonHistory: String { "History" }
    var commonLocalSnapshots: String { "Local snapshots" }
    var commonFullDiskAccessNeeded: String { "Full Disk Access needed" }
    var commonCompressed: String { "Compressed" }
    var commonOK: String { "OK" }
    var commonCycles: String { "Cycles" }
    var commonProtection: String { "Protection" }
    var commonUpdates: String { "Updates" }
    var commonCollectingData: String { "Collecting data…" }
    var commonAllGood: String { "All good" }
    var commonNeedsAttention: String { "Needs attention" }
    var commonThisMac: String { "This Mac" }
    var commonReport: String { "Report" }
    var commonRefresh: String { "Refresh" }
    var commonRefreshReport: String { "Refresh report" }
    var commonNow: String { "Now" }
    var commonTryAgain: String { "Try again" }
    var commonShowLess: String { "Show less" }
    var commonSetting: String { "Setting" }
    var commonOnBattery: String { "Battery" }
    var commonACPower: String { "AC power" }
    var commonNormal: String { "normal" }
    var commonFree: String { "Free" }
    var commonChart: String { "Chart" }
    var commonTable: String { "Table" }
    var commonRefreshing: String { "Refreshing…" }
    var commonCancel: String { "Cancel" }
    var commonOpenPrivacySettings: String { "Open Privacy settings…" }
    func commonUpdated(_ time: String) -> String { "updated \(time)" }
    var commonChecking: String { "Checking…" }
    var commonCritical: String { "Critical" }
    func commonLastData(_ time: String) -> String { "last data — \(time)" }

    // MARK: Home (REDESIGN-HOME; strings.json › This Mac Home + 02-home.md)
    var homeMacStatus: String { "Mac status" }
    func homeTaskCount(_ n: Int) -> String { n == 1 ? "1 task" : "\(n) tasks" }
    func homeNeedAttention(_ n: Int) -> String { n == 1 ? "needs attention" : "need attention" }
    var homeCriticalCount: String { "Critical" }
    var homeWarnings: String { "Warnings" }
    func homeCheckedAt(_ t: String) -> String { "checked at \(t)" }
    func homeLastCheck(_ t: String) -> String { "last check \(t)" }
    func homeTileLastCheck(_ t: String) -> String { "last check \(t)" }
    func homeShowAll(_ n: Int) -> String { "Show all (\(n))" }
    var homeYouCan: String { "You can" }
    var homeFreeUpSpace: String { "Free up space" }
    func homeBrewOutdatedShort(_ n: Int) -> String { "\(n) outdated" }
    var homeNothingNeedsAttention: String { "Nothing needs your attention" }
    var homeFirstScanTitle: String { "Scanning this Mac for the first time…" }
    var homeFirstScanCaption: String { "usually under 30 s" }
    func homeScanFailed(timedOut: Bool, lastGood: String?) -> String { (timedOut ? "Couldn’t scan this Mac: system_profiler didn’t respond within 30 s." : "Couldn’t scan this Mac: system_profiler returned no data.") + (lastGood.map { " Showing data from \($0)." } ?? "") }
    var homeSipHelp: String { "SIP can only be turned on from macOS Recovery." }
    var homeStateOff: String { "off" }
    var homeDiskHealth: String { "Disk health" }
    var homeStateFailing: String { "failing" }
    var homeStateFailingShort: String { "failing" }
    func homeStateDiskFull(_ pct: Int) -> String { "\(pct)% full" }
    var homeStateNotSetUp: String { "not set up" }
    var homeStateKeepsAwake: String { "keeps the Mac awake" }
    func homeStateWorn(_ pct: Int) -> String { "\(pct)% worn" }
    func homeStatePackagesOutdated(_ n: Int) -> String { n == 1 ? "1 package outdated" : "\(n) packages outdated" }
    var homeStateUpdateAvailable: String { "update available" }
    func homeStateUpdatesAvailable(_ n: Int) -> String { "\(n) updates available" }
    var homeMemoryObject: String { "Memory" }
    var homeStateRunningLow: String { "running low" }
    var homeStateRunningOut: String { "running out" }
    var homeCrashes: String { "Crashes" }
    func homeStateReports(_ n: Int) -> String { n == 1 ? "1 report" : "\(n) reports" }
    var homeDiskWear: String { "Disk wear" }
    func homePercent(_ s: String) -> String { "\(s)%" }
    func homeGB(_ s: String) -> String { "\(s) GB" }
    var homeVerbDetails: String { "Details" }
    var homeVerbFreeUp: String { "Free up" }
    var homeVerbUpdate: String { "Update" }
    var homeVerbSettings: String { "Settings…" }
    var homeTagFirewallOff: String { "Firewall off" }
    var homeTagDriveFailing: String { "drive failing" }
    var homeTagTMNotSetUp: String { "TM not set up" }
    var homeTagWorn: String { "Worn" }
    var homeTagBrewOutdated: String { "Homebrew outdated" }
    var homeTagUpdateAvailable: String { "Update available" }
    var homeTagLowMemory: String { "Low memory" }
    var homeTagService: String { "Service" }
    var homeTagFileVaultOff: String { "FileVault off" }
    var homeTagGatekeeperOff: String { "Gatekeeper off" }
    var homeTagSipOff: String { "SIP off" }
    var homeTagDiskWorn: String { "Worn" }
    var homeTagClaudeStale: String { "Claude stale" }
    var homeTagNormal: String { "Normal" }
    var homeTagHealthy: String { "Healthy" }
    var homeTagAllOn: String { "All on" }
    var homeTagUpToDate: String { "Up to date" }
    func homeHistoryDays(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
    var homeSections: String { "Sections" }
    func homeSectionCount(_ n: Int) -> String { "\(n) sections" }
    func homeCPUSub(_ chip: String, _ cores: Int) -> String { "\(chip) · \(cores) cores" }
    func homeCoresOnly(_ cores: Int) -> String { "\(cores) cores" }
    var homeStorageSub: String { "disk, folders, SMART" }
    var homeBatterySub: String { "built-in" }
    var homeSecuritySub: String { "protection, updates, crashes" }
    var homeBackupsSub: String { "Time Machine, Claude" }
    var homeSystemSub: String { "sleep, login items, Homebrew" }
    var homeHistorySub: String { "daily samples" }
    var homeKVLoad: String { "Load" }
    var homeKVProcesses: String { "Processes" }
    var homeKVPurgeable: String { "Purgeable" }
    var homeKVFailing: String { "failing" }
    func homeKVWorn(_ pct: Int) -> String { "\(pct)% worn" }
    var homeKVCapacity: String { "Capacity" }
    func homeKVProtection(_ on: Int) -> String { "\(on) of 4" }
    var homeKVNone: String { "none" }
    var homeKVSnapshots: String { "Snapshots" }
    var homeKVLoginItems: String { "Login items" }
    var homeKVUpToDate: String { "up to date" }
    var homeKVDiskPerMonth: String { "Disk per month" }
    var homeBackA11y: String { "Back to This Mac" }
}
