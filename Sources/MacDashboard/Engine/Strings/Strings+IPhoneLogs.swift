// Engine/Strings/Strings+IPhoneLogs.swift
// iPhone module: logs, import, identity, device tiles: the `IPhoneLogsStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol IPhoneLogsStrings {
    // MARK: iPhone module (logs, import, identity, device tiles)
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
    func iphoneImportConfirmTitle(into target: String) -> String
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
    var iphoneImportKeptTrash: String { get }
    func iphoneImportKeptTrashA11y(_ name: String) -> String
    var iphoneImportKeptTrashFailed: String { get }
    func iphoneLogsFromArchive(_ name: String) -> String
    var iphoneLogsDetailProcess: String { get }
    var iphoneLogsDetailType: String { get }
    var iphoneLogsDetailCreated: String { get }
    func iphoneLogsType(_ c: LogCategory, bugType: String?) -> String
    var iphoneLogsOpenInConsole: String { get }
    var iphoneLogsSaveToMac: String { get }
    var iphoneLogsSaved: String { get }
    var iphoneLogsSavePanelTitle: String { get }
    var iphoneLogsSavePrompt: String { get }
    var iphoneLogsRowHint: String { get }
    func iphoneLogsOpenInConsoleA11y(_ name: String) -> String
    func iphoneLogsSaveA11y(_ name: String) -> String
    func iphoneLogsActionError(_ e: IPhoneLogActionError) -> String
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
    var iphoneHealthAppleNote: String { get }
    var iphoneHealthEstimateNote: String { get }
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
    var iphoneRequestButton: String { get }
    var iphoneRequestButtonA11y: String { get }
    var iphoneRequestPreparing: String { get }
    var iphoneRequestWaitingTitle: String { get }
    var iphoneRequestWaitingBody: String { get }
    var iphoneRequestCreatingTitle: String { get }
    var iphoneRequestCreatingBody: String { get }
    var iphoneRequestReconnect: String { get }
    var iphoneRequestReadyTitle: String { get }
    var iphoneRequestAmbiguousTitle: String { get }
    var iphoneRequestAmbiguousBody: String { get }
    var iphoneRequestExpiredTitle: String { get }
    var iphoneRequestExpiredBody: String { get }
    var iphoneRequestTimedOutTitle: String { get }
    var iphoneRequestTimedOutBody: String { get }
    var iphoneRequestFailedTitle: String { get }
    var iphoneRequestFailedBody: String { get }
    var iphoneRequestStop: String { get }
    var iphoneRequestStopA11y: String { get }
    var iphoneRequestClose: String { get }
    var iphoneRequestCloseA11y: String { get }
    var iphoneImportDeleteNote: String { get }
    func iphonePhoneCleanup(_ c: PhoneCleanup) -> String
    var iphoneIdentitySerials: String { get }
}

extension StringsEN: IPhoneLogsStrings {
    // MARK: iPhone module (logs, import, identity, device tiles)
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
        case .pending: return "Identifying type…"
        }
    }
    var iphoneSectionReadFailed: String { "Could not read from the iPhone. Press Refresh to try again." }
    var iphoneImportTitle: String { "Sysdiagnose import" }
    var iphoneImportButton: String { "Import" }
    func iphoneImportArchiveA11y(_ name: String) -> String { "Import archive \(name)" }
    var iphoneImportPickFile: String { "Choose file on Mac…" }
    var iphoneImportPickA11y: String { "Choose a sysdiagnose archive on this Mac" }
    var iphoneImportPickPrompt: String { "Choose" }
    func iphoneImportConfirmTitle(into target: String) -> String { "Import into \(target)" }
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
    var iphoneImportHint: String { "Archives on the phone appear once the logs are read. You can also choose a .tar.gz file on this Mac." }
    func iphoneImportProgress(_ p: ImportProgress) -> String {
        switch p {
        case .copying(let done, let total):
            return "Copying from the phone: \(fmtBytes(done, language: .en)) of \(fmtBytes(total, language: .en))"
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
        case .copyFailed: return "Could not copy the archive from the iPhone. Keep it connected and unlocked, then try again."
        case .interrupted: return "The iPhone disconnected during the copy. Nothing was kept. Reconnect it and import again."
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
    var iphoneImportKeptTrash: String { "Move to Trash" }
    func iphoneImportKeptTrashA11y(_ name: String) -> String { "Move \(name) to the Trash" }
    var iphoneImportKeptTrashFailed: String { "Could not move it to the Trash. Check the file in Finder." }
    func iphoneLogsFromArchive(_ name: String) -> String { "From archive \(name)" }
    var iphoneLogsDetailProcess: String { "Process" }
    var iphoneLogsDetailType: String { "Type" }
    var iphoneLogsDetailCreated: String { "Created" }
    func iphoneLogsType(_ c: LogCategory, bugType: String?) -> String {
        switch c {
        case .appCrash: return "App crash"
        case .exceptionFault: return "Exception fault"
        case .jetsam: return "Jetsam event"
        case .diskWrites: return "Disk writes"
        case .cpuResource: return "CPU resource"
        case .stackshot: return "Stackshot"
        case .otherReport: return bugType.map { "Other report (\($0))" } ?? "Other report"
        case .analytics: return "Analytics"
        case .other: return "Other"
        case .pending: return iphoneLogsCategory(.pending)
        }
    }
    var iphoneLogsOpenInConsole: String { "Open in Console" }
    var iphoneLogsSaveToMac: String { "Save to Mac…" }
    var iphoneLogsSaved: String { "Saved" }
    var iphoneLogsSavePanelTitle: String { "Save crash log" }
    var iphoneLogsSavePrompt: String { "Save" }
    var iphoneLogsRowHint: String { "Shows the file’s details and actions" }
    func iphoneLogsOpenInConsoleA11y(_ name: String) -> String { "Open \(name) in Console" }
    func iphoneLogsSaveA11y(_ name: String) -> String { "Save \(name) to the Mac" }
    func iphoneLogsActionError(_ e: IPhoneLogActionError) -> String {
        switch e {
        case .disconnected: return "Connect the iPhone by cable to copy this file."
        case .copyFailed: return "Could not copy the file from the iPhone. Press Refresh and try again."
        case .noSpace: return "Not enough free space on the Mac for this file."
        case .gone: return "This copy is no longer on the Mac. Import the archive again."
        case .consoleFailed: return "Console could not open the file."
        case .saveFailed: return "Could not save the file there. Choose another folder."
        }
    }
    var iphoneIdentityTitle: String { "Device and parts" }
    var iphoneIdentityConnectToRead: String { "Connect the iPhone by cable to read its device details." }
    var iphoneIdentityRefreshA11y: String { "Refresh the device details" }
    var iphoneIdentityShow: String { "Show" }
    var iphoneIdentityHide: String { "Hide" }
    var iphoneIdentityCopy: String { "Copy" }
    var iphoneIdentityCopied: String { "Copied" }
    func iphoneRevealA11y(_ label: String) -> String { "Show value: \(label)" }
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
    var iphoneTileHealth: String { "Health" }
    var iphoneTileHealthFull: String { "Battery health" }
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
    var iphoneHealthAppleNote: String { "Apple's figure from imported logs" }
    var iphoneHealthEstimateNote: String { "Estimate. Import a sysdiagnose for Apple's figure." }
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
    var iphoneRequestButton: String { "Create new sysdiagnose…" }
    var iphoneRequestButtonA11y: String { "Ask the iPhone for a new sysdiagnose archive" }
    var iphoneRequestPreparing: String { "Checking the archives on the iPhone…" }
    var iphoneRequestWaitingTitle: String { "Waiting for the iPhone" }
    var iphoneRequestWaitingBody: String { "On the iPhone, press and release both volume buttons and the side button at the same time. It vibrates briefly when it starts." }
    var iphoneRequestCreatingTitle: String { "The iPhone is creating the archive" }
    var iphoneRequestCreatingBody: String { "This takes several minutes. Keep the iPhone connected." }
    var iphoneRequestReconnect: String { "Reconnect the iPhone to continue." }
    var iphoneRequestReadyTitle: String { "New archive ready" }
    var iphoneRequestAmbiguousTitle: String { "More than one new archive appeared" }
    var iphoneRequestAmbiguousBody: String { "None of them will be deleted from the iPhone. You can still import them." }
    var iphoneRequestExpiredTitle: String { "No new archive appeared" }
    var iphoneRequestExpiredBody: String { "Nothing started within 15 minutes. Try again." }
    var iphoneRequestTimedOutTitle: String { "The archive did not finish in time" }
    var iphoneRequestTimedOutBody: String { "If it appears later, it is listed under On the iPhone and stays on the iPhone." }
    var iphoneRequestFailedTitle: String { "Could not read the archives on the iPhone" }
    var iphoneRequestFailedBody: String { "Keep the iPhone connected and unlocked, then try again." }
    var iphoneRequestStop: String { "Stop waiting" }
    var iphoneRequestStopA11y: String { "Stop waiting for the new archive" }
    var iphoneRequestClose: String { "Close" }
    var iphoneRequestCloseA11y: String { "Close this message" }
    var iphoneImportDeleteNote: String { "This app requested this archive, so it is deleted from the iPhone after a successful import." }
    func iphonePhoneCleanup(_ c: PhoneCleanup) -> String {
        switch c {
        case .deleting: return "Deleting it from the iPhone…"
        case .deleted: return "Deleted from the iPhone."
        case .keptBySetting: return "Kept on the iPhone (Settings › Devices)."
        case .keptIncomplete: return "Kept on the iPhone: the import was not complete."
        case .notConnected: return "Kept on the iPhone: it was disconnected. Import the archive again while it is connected to delete it."
        case .alreadyGone: return "It is no longer on the iPhone."
        case .changed: return "Kept on the iPhone: the file there changed after it was requested."
        case .unavailable: return "Kept on the iPhone: this version of macOS cannot delete files on it."
        case .failed(let code): return "Could not delete it from the iPhone (error \(code)). It stays there."
        }
    }
    var iphoneIdentitySerials: String { "Serial numbers" }
}

extension StringsRU: IPhoneLogsStrings {
    // MARK: iPhone module (logs, import, identity, device tiles)
    var iphoneLogsTitle: String { "Журналы сбоев" }
    var iphoneLogsConnectToRead: String { "Подключите iPhone кабелем, чтобы прочитать журналы." }
    var iphoneLogsEmpty: String { "Файлов журналов не найдено." }
    var iphoneLogsRefreshA11y: String { "Обновить список журналов сбоев" }
    func iphoneLogsCaption(_ n: Int) -> String { "\(n) \(ruPlural(n, "файл", "файла", "файлов"))" }
    func iphoneLogsCategory(_ c: LogCategory) -> String {
        switch c {
        case .appCrash: return "Сбои приложений"
        case .exceptionFault: return "Исключения"
        case .jetsam: return "Нехватка памяти (Jetsam)"
        case .diskWrites: return "Запись на диск"
        case .cpuResource: return "Нагрузка CPU"
        case .stackshot: return "Стекшоты"
        case .otherReport: return "Другие отчёты"
        case .analytics: return "Аналитика"
        case .other: return "Прочие файлы"
        case .pending: return "Определяется тип…"
        }
    }
    var iphoneSectionReadFailed: String { "Не удалось прочитать данные с iPhone. Нажмите «Обновить», чтобы попробовать снова." }
    var iphoneImportTitle: String { "Импорт sysdiagnose" }
    var iphoneImportButton: String { "Импортировать" }
    func iphoneImportArchiveA11y(_ name: String) -> String { "Импортировать архив \(name)" }
    var iphoneImportPickFile: String { "Выбрать файл на Mac…" }
    var iphoneImportPickA11y: String { "Выбрать архив sysdiagnose на Mac" }
    var iphoneImportPickPrompt: String { "Выбрать" }
    func iphoneImportConfirmTitle(into target: String) -> String { "Импорт в \(target)" }
    var iphoneImportParseOnly: String { "Только разобрать" }
    var iphoneImportParseKeep: String { "Разобрать и сохранить" }
    var iphoneImportCancel: String { "Отмена" }
    var iphoneImportParseOnlyA11y: String { "Только разобрать архив, не сохраняя его" }
    var iphoneImportParseKeepA11y: String { "Разобрать архив и сохранить его на Mac" }
    var iphoneImportCancelA11y: String { "Отменить импорт" }
    func iphoneImportMismatchTitle(_ target: String) -> String { "Загрузить данные другого телефона в \(target)?" }
    func iphoneImportMismatchMessage(file: String, owner: String?, archiveMAh: [Int], deviceMAh: Int, target: String) -> String {
        "Похоже, файл «\(file)» снят с \(owner ?? "другого iPhone"): проектная ёмкость его аккумулятора — "
            + "\(archiveMAh.map { batteryMAh($0) }.joined(separator: ", ")), у \(target) — \(batteryMAh(deviceMAh)). "
            + "Если загрузить, история аккумулятора из файла заменит историю \(target) за те же дни."
    }
    var iphoneImportMismatchProceed: String { "Всё равно загрузить" }
    var iphoneImportMismatchProceedA11y: String { "Загрузить историю аккумулятора другого телефона в этот" }
    var iphoneImportHint: String { "Архивы с телефона видны после чтения журналов. Можно выбрать и файл .tar.gz на Mac." }
    func iphoneImportProgress(_ p: ImportProgress) -> String {
        switch p {
        case .copying(let done, let total):
            return "Копирование с телефона: \(fmtBytes(done, language: .ru)) из \(fmtBytes(total, language: .ru))"
        case .extracting: return "Распаковка нужных файлов…"
        case .parsing: return "Разбор…"
        }
    }
    func iphoneImportSummary(_ s: ImportSummary) -> String {
        var t = "Точек батареи: \(s.batteryPoints), файлов журналов: \(s.logFiles)"
        if s.skippedRows > 0 { t += ", пропущено строк: \(s.skippedRows)" }
        return t + (s.keptPath != nil ? ". Архив сохранён." : ".")
    }
    func iphoneImportError(_ e: ImportError) -> String {
        switch e {
        case .copyFailed: return "Не удалось скопировать архив с iPhone. Не отключайте его, разблокируйте и попробуйте ещё раз."
        case .interrupted: return "iPhone отключился во время копирования. Ничего не сохранено. Подключите его и импортируйте снова."
        case .sizeMismatch: return "Размер скопированного архива не совпал с размером на телефоне."
        case .tarFailed: return "Не удалось распаковать архив."
        case .keepFailed: return "Не удалось сохранить архив."
        case .cancelled: return "Импорт отменён."
        }
    }
    func iphoneImportErrorDetail(_ e: ImportError) -> String? {
        guard case .tarFailed(let f) = e else { return nil }
        switch f {
        case .message(let line): return line
        case .exitCode(let n): return "tar завершился с кодом \(n)."
        case .signal(let s): return "tar остановлен сигналом \(s)."
        case .launchFailed(let code): return "Не удалось запустить tar (ошибка \(code))."
        case .timedOut: return "tar не завершился вовремя."
        case .listingTooLong: return "В архиве слишком много файлов."
        case .workFiles: return "Не удалось создать временные файлы для распаковки."
        }
    }
    var iphoneImportKeptTitle: String { "Сохранённые архивы" }
    func iphoneImportRevealA11y(_ name: String) -> String { "Показать архив \(name) в Finder" }
    var iphoneImportKeptTrash: String { "В Корзину" }
    func iphoneImportKeptTrashA11y(_ name: String) -> String { "Переместить \(name) в Корзину" }
    var iphoneImportKeptTrashFailed: String { "Не удалось переместить в Корзину. Проверьте файл в Finder." }
    func iphoneLogsFromArchive(_ name: String) -> String { "Из архива \(name)" }
    var iphoneLogsDetailProcess: String { "Процесс" }
    var iphoneLogsDetailType: String { "Тип" }
    var iphoneLogsDetailCreated: String { "Создан" }
    func iphoneLogsType(_ c: LogCategory, bugType: String?) -> String {
        switch c {
        case .appCrash: return "Сбой приложения"
        case .exceptionFault: return "Исключение"
        case .jetsam: return "Событие Jetsam"
        case .diskWrites: return "Запись на диск"
        case .cpuResource: return "Нагрузка CPU"
        case .stackshot: return "Стекшот"
        case .otherReport: return bugType.map { "Другой отчёт (\($0))" } ?? "Другой отчёт"
        case .analytics: return "Аналитика"
        case .other: return "Прочее"
        case .pending: return iphoneLogsCategory(.pending)
        }
    }
    var iphoneLogsOpenInConsole: String { "Открыть в Console" }
    var iphoneLogsSaveToMac: String { "Сохранить на Mac…" }
    var iphoneLogsSaved: String { "Сохранено" }
    var iphoneLogsSavePanelTitle: String { "Сохранить журнал сбоя" }
    var iphoneLogsSavePrompt: String { "Сохранить" }
    var iphoneLogsRowHint: String { "Показывает подробности файла и действия" }
    func iphoneLogsOpenInConsoleA11y(_ name: String) -> String { "Открыть \(name) в Console" }
    func iphoneLogsSaveA11y(_ name: String) -> String { "Сохранить \(name) на Mac" }
    func iphoneLogsActionError(_ e: IPhoneLogActionError) -> String {
        switch e {
        case .disconnected: return "Подключите iPhone кабелем, чтобы скопировать файл."
        case .copyFailed: return "Не удалось скопировать файл с iPhone. Нажмите «Обновить» и попробуйте ещё раз."
        case .noSpace: return "На Mac не хватает места для этого файла."
        case .gone: return "Этой копии уже нет на Mac. Импортируйте архив ещё раз."
        case .consoleFailed: return "Console не смог открыть файл."
        case .saveFailed: return "Не удалось сохранить файл в эту папку. Выберите другую."
        }
    }
    var iphoneIdentityTitle: String { "Устройство и детали" }
    var iphoneIdentityConnectToRead: String { "Подключите iPhone кабелем, чтобы прочитать данные устройства." }
    var iphoneIdentityRefreshA11y: String { "Обновить данные устройства" }
    var iphoneIdentityShow: String { "Показать" }
    var iphoneIdentityHide: String { "Скрыть" }
    var iphoneIdentityCopy: String { "Копировать" }
    var iphoneIdentityCopied: String { "Скопировано" }
    func iphoneRevealA11y(_ label: String) -> String { "Показать значение: \(label)" }
    func iphoneHideA11y(_ label: String) -> String { "Скрыть значение: \(label)" }
    func iphoneCopyA11y(_ label: String) -> String { "Копировать значение: \(label)" }
    func iphoneIdentityLabel(_ l: IdentityLabel) -> String {
        switch l {
        case .marketingName: return "Модель"
        case .modelNumber: return "Номер модели"
        case .regulatoryModel: return "Регуляторная модель"
        case .hardwareModel: return "Аппаратная модель"
        case .ios: return "Версия iOS"
        case .storage: return "Память"
        case .colorCode: return "Код цвета"
        case .serial: return "Серийный номер"
        case .logicBoard: return "Логическая плата"
        case .imei: return "IMEI"
        case .imei2: return "IMEI 2"
        case .battery: return "Батарея"
        case .displayPanel: return "Дисплей (панель)"
        case .displayRawPanel: return "Дисплей (заводской номер)"
        case .coverGlass: return "Защитное стекло"
        case .backGlass: return "Задняя панель"
        case .nova: return "Модуль Nova"
        case .ambientLight: return "Датчик освещённости"
        case .backCamera: return "Основная камера"
        case .backSuperWide: return "Сверхширокоугольная"
        case .backTele: return "Телефото"
        case .frontCamera: return "Фронтальная камера"
        case .frontIR: return "ИК-камера Face ID"
        case .faceIDProjector: return "Проектор Face ID"
        }
    }
    var iphoneTagNotConnected: String { "Не подключён" }
    var iphoneTagTrustNeeded: String { "Нужно доверие" }
    var iphoneTagReadFailed: String { "Не удалось прочитать" }
    var iphoneSubTrust: String { "разблокируйте и нажмите «Доверять»" }
    var iphoneSubReconnect: String { "переподключите кабель" }
    func iphoneSubLastSeen(_ date: String) -> String { "был \(date)" }
    func iphoneSubCharge(_ percent: Int, _ state: String) -> String { "\(percent) % · \(state)" }
    var iphoneStateChargingLower: String { "заряжается" }
    var iphoneStateExternalLower: String { "от сети" }
    var iphoneStateBatteryLower: String { "от батареи" }
    var iphoneTileHealth: String { "Здоровье" }
    var iphoneTileHealthFull: String { "Здоровье батареи" }
    var iphoneNotIdentified: String { "Ещё не опознан" }
    var iphonePendingTrustText: String { "Разблокируйте iPhone, нажмите «Доверять» на его экране и повторите." }
    var iphonePendingFailedText: String { "Не удалось прочитать iPhone. Переподключите кабель и повторите." }
    func iphoneSummary(connected: Int, notConnected: Int, waiting: Int) -> String {
        var parts: [String] = []
        if connected > 0 { parts.append("подключено: \(connected)") }
        if notConnected > 0 { parts.append("не подключено: \(notConnected)") }
        if waiting > 0 { parts.append("ждёт доверия: \(waiting)") }
        return parts.joined(separator: " · ")
    }
    var iphoneSummaryNone: String { "iPhone пока не найден" }
    var iphoneSummaryUnavailable: String { "Недоступно на этом Mac" }
    var iphoneNoticeEmptyTitle: String { "iPhone не найден" }
    var iphoneNoticeEmptyBody: String { "Подключите iPhone кабелем, разблокируйте его и нажмите «Доверять»." }
    var iphoneNoticeUnavailableTitle: String { "Подключение к iPhone недоступно" }
    var iphoneRestartingShort: String { "Перезапуск…" }
    var iphoneRestartingBanner: String { "Служба подключения перезапускается. Устройства переподключатся через несколько секунд." }
    var iphoneBatteryMeasuredNow: String { "Измерено сейчас" }
    var iphoneHealthNote: String { "Текущая ёмкость к проектной" }
    var iphoneHealthAppleNote: String { "Цифра Apple из импортированных логов" }
    var iphoneHealthEstimateNote: String { "Оценка. Импорт sysdiagnose покажет цифру Apple." }
    func iphoneHealthHistoryNote(cycles: Int?) -> String {
        guard let n = cycles else { return "последнее значение из истории" }
        return "\(n) \(ruPlural(n, "цикл", "цикла", "циклов")) · последнее значение из истории"
    }
    var iphoneLiveReadings: String { "Текущие показания" }
    var iphoneLiveReadingsConnect: String { "Подключите iPhone кабелем, чтобы увидеть заряд, состояние, температуру, напряжение и ёмкость." }
    var iphoneRefreshOfflineHelp: String { "Подключите iPhone кабелем, чтобы обновить" }
    var iphoneLogsSourceLive: String { "На iPhone" }
    var iphoneLogsSourceArchive: String { "Из архива" }
    var iphoneLogsSourceA11y: String { "Источник журналов сбоев" }
    var iphoneLogsColSize: String { "Размер" }
    var iphoneImportOnPhone: String { "На iPhone" }
    var iphoneImportChoiceBody: String { "Разбор читает из архива историю батареи и журналы. «Сохранить» также оставляет копию архива на этом Mac." }
    var iphoneImportInArchive: String { "В архиве" }
    var iphoneRequestButton: String { "Создать новый sysdiagnose…" }
    var iphoneRequestButtonA11y: String { "Попросить iPhone создать новый архив sysdiagnose" }
    var iphoneRequestPreparing: String { "Проверяем архивы на iPhone…" }
    var iphoneRequestWaitingTitle: String { "Ждём iPhone" }
    var iphoneRequestWaitingBody: String { "На iPhone одновременно нажмите и отпустите обе кнопки громкости и боковую кнопку. Он коротко завибрирует, когда начнёт." }
    var iphoneRequestCreatingTitle: String { "iPhone создаёт архив" }
    var iphoneRequestCreatingBody: String { "Это займёт несколько минут. Не отключайте iPhone." }
    var iphoneRequestReconnect: String { "Подключите iPhone снова, чтобы продолжить." }
    var iphoneRequestReadyTitle: String { "Новый архив готов" }
    var iphoneRequestAmbiguousTitle: String { "Появилось больше одного нового архива" }
    var iphoneRequestAmbiguousBody: String { "Ни один из них не будет удалён с iPhone. Импортировать их по-прежнему можно." }
    var iphoneRequestExpiredTitle: String { "Новый архив не появился" }
    var iphoneRequestExpiredBody: String { "За 15 минут ничего не началось. Попробуйте ещё раз." }
    var iphoneRequestTimedOutTitle: String { "Архив не успел создаться" }
    var iphoneRequestTimedOutBody: String { "Если он появится позже, он будет в списке «На iPhone» и останется на iPhone." }
    var iphoneRequestFailedTitle: String { "Не удалось прочитать архивы на iPhone" }
    var iphoneRequestFailedBody: String { "Не отключайте iPhone, разблокируйте его и попробуйте ещё раз." }
    var iphoneRequestStop: String { "Не ждать" }
    var iphoneRequestStopA11y: String { "Перестать ждать новый архив" }
    var iphoneRequestClose: String { "Закрыть" }
    var iphoneRequestCloseA11y: String { "Закрыть это сообщение" }
    var iphoneImportDeleteNote: String { "Этот архив запросило приложение, поэтому после успешного импорта он будет удалён с iPhone." }
    func iphonePhoneCleanup(_ c: PhoneCleanup) -> String {
        switch c {
        case .deleting: return "Удаляем его с iPhone…"
        case .deleted: return "Удалён с iPhone."
        case .keptBySetting: return "Оставлен на iPhone (Настройки › Устройства)."
        case .keptIncomplete: return "Оставлен на iPhone: импорт прошёл не полностью."
        case .notConnected: return "Оставлен на iPhone: он был отключён. Импортируйте архив ещё раз, пока iPhone подключён, чтобы удалить его."
        case .alreadyGone: return "На iPhone его уже нет."
        case .changed: return "Оставлен на iPhone: файл там изменился после запроса."
        case .unavailable: return "Оставлен на iPhone: эта версия macOS не умеет удалять на нём файлы."
        case .failed(let code): return "Не удалось удалить его с iPhone (ошибка \(code)). Он остался там."
        }
    }
    var iphoneIdentitySerials: String { "Серийные номера" }
}
