// Engine/Strings/Strings+Attention.swift
// Assessment texts and attention items: the `AttentionStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol AttentionStrings {
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
    var attnVerbOpen: String { get }

    // Capsule objects + values + explanations.
    var attnCapBattery: String { get }
    func attnCapBatteryValue(_ p: Int) -> String
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
    // BACKUP-CARD-FAILURE
    func assessClaudeBackupStaleFailed(_ age: String, _ reason: String) -> String
    func assessClaudeBackupNoneFailed(_ reason: String) -> String
    func assessClaudeBackupStaleInterrupted(_ age: String) -> String
    var attnDetailClaudeBackupFailed: String { get }
    var attnDetailClaudeBackupInterrupted: String { get }
    // TRIAGE-THRESHOLDS-REVIEW: why it matters
    var attnWhyDiskFull: String { get }
    var attnWhyDiskFullSoon: String { get }
    var attnWhyMemPressure: String { get }
    var attnWhyFileVault: String { get }
    var attnWhyGatekeeper: String { get }
    var attnWhySip: String { get }
    var attnWhyFirewall: String { get }
    var attnWhyUpdates: String { get }
    var attnWhyKernelPanic: String { get }
    var attnWhyOwnCrash: String { get }
    var attnWhyTimeMachine: String { get }
    var attnWhyTimeMachineOverdue: String { get }
    var attnWhyClaudeBackup: String { get }
    var attnWhySmartErrors: String { get }
    var attnWhySmartWear: String { get }
    var attnWhyWakeHolders: String { get }
    var attnWhyBatteryWorn: String { get }
    var attnWhyBatteryService: String { get }
    func assessTimeMachineOverdue(_ days: Int) -> String
}

extension StringsEN: AttentionStrings {
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
    var attnVerbOpen: String { "Open" }
    var attnCapBattery: String { "Battery" }
    func attnCapBatteryValue(_ p: Int) -> String { "\(p) %" }
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
    // BACKUP-CARD-FAILURE
    func assessClaudeBackupStaleFailed(_ age: String, _ reason: String) -> String { "No Claude backup for \(age) — the last attempt failed: \(reason). Older snapshots were not touched." }
    func assessClaudeBackupNoneFailed(_ reason: String) -> String { "The Claude backup log has no successful snapshot — the last attempt failed: \(reason)." }
    func assessClaudeBackupStaleInterrupted(_ age: String) -> String { "No Claude backup for \(age) — the last attempt did not finish." }
    var attnDetailClaudeBackupFailed: String { "last attempt failed" }
    var attnDetailClaudeBackupInterrupted: String { "last attempt did not finish" }
    // TRIAGE-THRESHOLDS-REVIEW: why it matters
    var attnWhyDiskFull: String { "macOS needs free space for updates and for swap; without it, updates fail and apps slow down or can't save files." }
    var attnWhyDiskFullSoon: String { "A macOS update alone needs tens of gigabytes free; freeing space now avoids a failed update later." }
    var attnWhyMemPressure: String { "macOS reports that memory has run out and the disk is standing in for it, so apps slow down." }
    var attnWhyFileVault: String { "Without FileVault your password isn't needed to unlock the disk, so anyone holding the Mac has an easier path to your files." }
    var attnWhyGatekeeper: String { "Gatekeeper checks before first launch that an app comes from an identified developer and was checked by Apple for malware." }
    var attnWhySip: String { "System Integrity Protection stops any program, even one with administrator rights, from changing macOS system files." }
    var attnWhyFirewall: String { "The firewall blocks unwanted incoming connections; it matters most on public Wi-Fi." }
    var attnWhyUpdates: String { "macOS updates close security holes; Apple lists the fixes for every release." }
    var attnWhyKernelPanic: String { "A kernel panic restarts the whole Mac and loses unsaved work; repeated panics usually point to a driver or hardware." }
    var attnWhyOwnCrash: String { "The report shows where the app failed and helps get it fixed." }
    var attnWhyTimeMachine: String { "Without a backup, a lost, stolen or broken Mac takes your files with it." }
    var attnWhyTimeMachineOverdue: String { "Files changed since the last backup exist only on this Mac." }
    var attnWhyClaudeBackup: String { "Claude sessions and settings changed since then exist only on this Mac." }
    var attnWhySmartErrors: String { "The drive reports data it could not read back or a failure warning; files on it may already be damaged, so back up now." }
    var attnWhySmartWear: String { "The drive has used most of its rated write endurance; it can work past 100 %, but plan a replacement and keep backups current." }
    var attnWhyWakeHolders: String { "While a program holds this, the Mac doesn't go to sleep on its own, which drains the battery and keeps it warm." }
    var attnWhyBatteryWorn: String { "The battery now holds less than 80 % of its original capacity, so a full charge runs out sooner than when it was new. Apple designs Mac batteries to keep up to 80 % at their maximum cycle count." }
    var attnWhyBatteryService: String { "macOS has flagged this battery for service: it holds less charge than when new or isn't working normally. It's safe to keep using it, but Apple recommends having it checked." }
    func assessTimeMachineOverdue(_ days: Int) -> String { "Time Machine: the last backup was \(bkDaysAgo(days))." }
}

extension StringsRU: AttentionStrings {
    // MARK: Assessment
    func assessDiskFull(_ pct: String) -> String { "Диск заполнен на \(pct)% — срочно освободите место." }
    func assessDiskFullSoon(_ pct: String) -> String { "Диск заполнен на \(pct)% — пора освобождать место." }
    func assessMemPressure(critical: Bool, apps: [String]) -> String {
        let head = critical ? "macOS сообщает, что оперативной памяти не хватает — Mac может замедляться."
                            : "macOS сообщает, что свободной оперативной памяти мало."
        let tail = " — закройте то, чем сейчас не пользуетесь."
        switch apps.count {
        case 0: return head + " Закройте приложения, которыми сейчас не пользуетесь."
        case 1: return head + " Больше всего памяти занимает \(apps[0])" + tail
        default: return head + " Больше всего памяти занимают \(apps.dropLast().joined(separator: ", ")) и \(apps[apps.count - 1])" + tail
        }
    }
    func assessWakeHolders(_ entries: [String]) -> String {
        let n = entries.count
        return "\(n) \(ruPlural(n, "программа не даёт", "программы не дают", "программ не дают")) Mac уснуть: \(entries.joined(separator: "; "))."
    }
    func assessBatteryCapacityLow(_ cap: Int) -> String { "Ёмкость батареи \(cap)% от новой — думайте о замене." }
    func assessBatteryCapacityWarn(_ cap: Int) -> String { "Ёмкость батареи \(cap)% — ресурс подходит к сервисному порогу (80%)." }
    func assessBatteryConditionBad(_ cond: String) -> String { "Состояние батареи: \(cond) — загляните в сервис." }
    var assessFileVaultOff: String { "FileVault выключен — стоит включить." }
    var assessGatekeeperOff: String { "Gatekeeper выключен — стоит включить." }
    var assessSipOff: String { "SIP выключен — стоит включить." }
    var assessFirewallOff: String { "Файрвол выключен — стоит включить." }
    func assessMacUpdatesAvailable(_ n: Int) -> String { "Доступны обновления macOS: \(n) шт." }
    func assessOwnCrashesRecent(_ app: String, _ n: Int) -> String { "Сбои \(app) за последние 7 дней: \(n) шт. — отчёты в Console.app." }
    func assessKernelPanicsRecent(_ n: Int) -> String { "Сбой системы (паника ядра) за последние 7 дней: \(n) шт. — отчёты в Console.app." }
    var assessTimeMachineNotSetUp: String { "Time Machine не настроен — бэкапов нет." }
    func assessClaudeBackupStale(_ age: String) -> String { "Бэкапа Claude не было \(age) — проверьте, подключён ли диск и разблокирован ли он." }
    var assessClaudeBackupNone: String { "В журнале бэкапа Claude нет ни одного успешного снимка — проверьте диск." }
    func assessSmartDiskErrors(_ title: String) -> String { "Диск «\(title)»: SMART сообщает об ошибках носителя — проверьте диск и бэкапы." }
    func assessSmartDiskWearHigh(_ title: String, _ pct: Int) -> String { "Диск «\(title)»: износ \(pct)% — ресурс на исходе." }
    func assessSmartDiskUnavailableTip(_ title: String) -> String { "Диск «\(title)»: SMART недоступен — переподключите кабель или установите smartmontools (brew install smartmontools)." }
    func assessDownloadsTip(_ sizeStr: String, _ shareSuffix: String) -> String { "«Загрузки» занимают \(sizeStr)\(shareSuffix) — стоит разобрать." }
    func assessDownloadsShareSuffix(_ pct: String) -> String { " (\(pct)% всего диска)" }
    func assessTrashTip(_ sizeStr: String) -> String { "Корзина: \(sizeStr) — можно очистить." }
    func assessCachesTip(_ sizeStr: String) -> String { "Кэши ~/Library/Caches: \(sizeStr) — чистить безопасно." }
    var assessNoFDATip: String { "Часть папок не попала в отчёт: у приложения нет полного доступа к диску." }
    func assessSummaryCount(_ n: Int) -> String { "Замечаний: \(n)" }

    // MARK: v2 attention
    var attnLabelDiskFull: String { "Диск" }
    func attnDetailDiskFull(_ pct: String) -> String { "заполнен на \(pct) %" }
    var attnLabelDiskFullSoon: String { "Диск" }
    func attnDetailDiskFullSoon(_ pct: String) -> String { "заполнен на \(pct) %" }
    var attnLabelSwapHigh: String { "Память" }
    var attnDetailMemPressureWarn: String { "памяти мало" }
    var attnDetailMemPressureCritical: String { "памяти не хватает" }
    var attnLabelBatteryCapacity: String { "Батарея" }
    func attnDetailBatteryCapacity(_ cap: Int) -> String { "ёмкость \(cap) %" }
    var attnLabelBatteryCondition: String { "Батарея" }
    func attnDetailBatteryCondition(_ cond: String) -> String { "состояние: \(cond)" }
    var attnLabelFileVaultOff: String { "FileVault" }
    var attnDetailFileVaultOff: String { "выключен" }
    var attnLabelGatekeeperOff: String { "Gatekeeper" }
    var attnDetailGatekeeperOff: String { "выключен" }
    var attnLabelSipOff: String { "SIP" }
    var attnDetailSipOff: String { "выключен" }
    var attnLabelFirewallOff: String { "Брандмауэр" }
    var attnDetailFirewallOff: String { "выключен" }
    var attnLabelUpdates: String { "Обновления" }
    func attnDetailUpdates(_ n: Int) -> String { "\(n) доступно" }
    var attnLabelCrashes: String { "Сбои" }
    func attnDetailCrashes(_ n: Int) -> String { "\(n) \(ruPlural(n, "отчёт", "отчёта", "отчётов"))" }
    var attnLabelTimeMachine: String { "Time Machine" }
    var attnDetailTimeMachine: String { "не настроена" }
    var attnLabelClaudeBackup: String { "Бэкап Claude" }
    var attnDetailClaudeBackupNone: String { "нет успешных" }
    var attnLabelWakeHolders: String { "Сон" }
    func attnDetailWakeHolders(_ first: String, more: Int) -> String { more > 0 ? "\(first), ещё \(more)" : first }
    func wakeHolderOnBehalf(_ owner: String, _ requester: String) -> String { "\(owner) (от \(requester))" }
    func wakeHolderEntry(_ holder: String, _ age: String) -> String { "\(holder) — \(age)" }
    func attnWakeIgnore(_ holder: String) -> String { "Не предупреждать про \(holder)" }
    var attnWakeIgnoreHint: String { "Правый щелчок — не предупреждать про приложение." }
    func attnLabelSmartErrors(_ title: String) -> String { title }
    var attnDetailSmartErrors: String { "ошибки SMART" }
    func attnLabelSmartWear(_ title: String) -> String { title }
    func attnDetailSmartWear(_ pu: Int) -> String { "износ \(pu) %" }
    var attnVerbSettings: String { "Настройки" }
    var attnVerbActivityMonitor: String { "Мониторинг системы" }
    var attnVerbDiskUtility: String { "Дисковая утилита" }
    var attnVerbShow: String { "Показать" }
    var attnVerbEmpty: String { "Очистить" }
    var attnVerbEnable: String { "Включить" }
    var attnVerbOpen: String { "Открыть" }
    var attnCapBattery: String { "Батарея" }
    func attnCapBatteryValue(_ p: Int) -> String { "\(p) %" }
    var attnCapSmartNoData: String { "нет данных SMART" }
    var attnCapDownloads: String { "Загрузки" }
    var attnCapTrash: String { "Корзина" }
    var attnCapCaches: String { "Кэши" }
    var attnExplainBattery: String { "Ёмкость снижается естественным образом со временем. Откроются системные настройки батареи; ничего не изменится без вашего подтверждения." }
    var attnExplainBrew: String { "Запустит `brew upgrade` в фоне — прогресс виден в карточке Homebrew. Установленные пакеты заменяются на свежие версии." }
    var attnExplainSmart: String { "Откроет «Дисковую утилиту». У внешних дисков SMART-атрибуты часто недоступны через USB — это не признак поломки." }
    var attnExplainDownloads: String { "Откроет папку в Finder. Ничего не удаляется — вы сами решаете, что убрать." }
    var attnExplainTrash: String { "Спросит подтверждение, затем очистит Корзину через Finder. Восстановить файлы после этого нельзя." }
    var attnExplainCaches: String { "Откроет ~/Library/Caches в Finder. Приложения пересоздадут кэш при следующем запуске." }
    var attnCapFolders: String { "Папки" }
    var attnCapFoldersNoAccess: String { "видны не все" }
    var attnExplainNoFDA: String { "Откроет «Системные настройки» → «Конфиденциальность и безопасность» → «Полный доступ к диску». Без него приложение не видит Корзину и часть служебных папок, поэтому их размер не попадает в отчёт." }
    func attnMore(_ n: Int) -> String { "Ещё \(n)" }
    var attnCollapse: String { "Свернуть" }
    var quietUpdatesTitle: String { "Обновления и краши" }
    var quietNeedsAttention: String { "требует внимания" }
    var quietStatusAllEnabled: String { "всё включено" }
    var quietStatusAllClear: String { "всё в норме" }
    var quietMarkOff: String { "выключен" }
    var quietMarkUnknown: String { "неизвестно" }
    func quietCountItems(_ n: Int) -> String { "\(n) шт." }
    // BACKUP-CARD-FAILURE
    func assessClaudeBackupStaleFailed(_ age: String, _ reason: String) -> String { "Бэкапа Claude не было \(age) — последняя попытка не удалась: \(reason). Старые снимки не затронуты." }
    func assessClaudeBackupNoneFailed(_ reason: String) -> String { "В журнале бэкапа Claude нет ни одного успешного снимка — последняя попытка не удалась: \(reason)." }
    func assessClaudeBackupStaleInterrupted(_ age: String) -> String { "Бэкапа Claude не было \(age) — последняя попытка не завершилась." }
    var attnDetailClaudeBackupFailed: String { "последняя попытка не удалась" }
    var attnDetailClaudeBackupInterrupted: String { "последняя попытка не завершилась" }
    // TRIAGE-THRESHOLDS-REVIEW: why it matters
    var attnWhyDiskFull: String { "macOS нужно свободное место для обновлений и подкачки; без него обновления не ставятся, а приложения тормозят или не могут сохранить файлы." }
    var attnWhyDiskFullSoon: String { "Одному обновлению macOS нужны десятки гигабайт свободного места; лучше освободить их заранее, чем получить сбой установки." }
    var attnWhyMemPressure: String { "macOS сообщает, что память закончилась и её подменяет диск, поэтому приложения замедляются." }
    var attnWhyFileVault: String { "Без FileVault для разблокировки диска не нужен пароль, и у того, кто получит Mac в руки, проще путь к вашим файлам." }
    var attnWhyGatekeeper: String { "Gatekeeper перед первым запуском проверяет, что приложение от известного разработчика и проверено Apple на вредоносный код." }
    var attnWhySip: String { "Защита целостности системы не даёт программам, даже с правами администратора, менять системные файлы macOS." }
    var attnWhyFirewall: String { "Брандмауэр блокирует нежелательные входящие подключения; важнее всего это в публичных сетях Wi-Fi." }
    var attnWhyUpdates: String { "Обновления macOS закрывают уязвимости; Apple публикует список исправлений к каждому выпуску." }
    var attnWhyKernelPanic: String { "При панике ядра весь Mac перезагружается и несохранённая работа теряется; повторы обычно указывают на драйвер или железо." }
    var attnWhyOwnCrash: String { "Отчёт показывает, где приложение упало, и помогает это исправить." }
    var attnWhyTimeMachine: String { "Без резервной копии потеря, кража или поломка Mac означает потерю файлов." }
    var attnWhyTimeMachineOverdue: String { "Файлы, изменённые после последней копии, есть только на этом Mac." }
    var attnWhyClaudeBackup: String { "Сессии и настройки Claude, изменённые с тех пор, есть только на этом Mac." }
    var attnWhySmartErrors: String { "Накопитель сообщает о данных, которые не удалось прочитать, или о предупреждении об отказе; файлы на нём могут быть повреждены, сделайте копию сейчас." }
    var attnWhySmartWear: String { "Накопитель израсходовал большую часть расчётного ресурса записи; он может работать и после 100 %, но планируйте замену и держите копии свежими." }
    var attnWhyWakeHolders: String { "Пока программа держит этот запрет, Mac не засыпает сам: батарея садится, корпус греется." }
    var attnWhyBatteryWorn: String { "Батарея теперь держит меньше 80 % исходной ёмкости, поэтому полного заряда хватает меньше, чем в новой. Apple рассчитывает батареи Mac на сохранение до 80 % к максимальному числу циклов." }
    var attnWhyBatteryService: String { "macOS пометила батарею для сервиса: она держит меньше заряда, чем новая, или работает не как положено. Пользоваться ею безопасно, но Apple советует её проверить." }
    func assessTimeMachineOverdue(_ days: Int) -> String { "Time Machine: последняя копия была \(bkDaysAgo(days))." }
}
