// Engine/Strings/Strings+IPSW.swift
// IPSW downloads: the `IPSWStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol IPSWStrings {
    // MARK: IPSW (IPHONE-IPSW). Card, confirm sheet and download panel texts.
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
    func ipswCheckedAt(_ source: String, _ time: String) -> String
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
    var ipswErrResumeRejected: String { get }
    var ipswAppQuit: String { get }
    var ipswPreparing: String { get }
    func ipswDownloading(_ done: String, _ total: String) -> String
    func ipswVerifyingProgress(_ done: String, _ total: String) -> String
    var ipswFinished: String { get }
    var ipswFileGone: String { get }
    var ipswCardTitle: String { get }
    var ipswHint: String { get }
    var ipswCheckApple: String { get }
    var ipswCheckAppleA11y: String { get }
    var ipswAskIPSWMe: String { get }
    func ipswAskIPSWMeA11y(_ id: String) -> String
    func ipswInstalled(_ version: String, _ build: String?) -> String
    var ipswInstalledFromPhone: String { get }
    func ipswInstalledLastSeen(_ day: String) -> String
    var ipswInstalledUnknown: String { get }
    var ipswAppleUnknownModel: String { get }
    var ipswDownload: String { get }
    func ipswDownloadA11y(_ version: String, _ build: String) -> String
    func ipswOlderHidden(_ n: Int) -> String
    var ipswBusyPaused: String { get }
    func ipswConfirmTitle(_ version: String, _ build: String) -> String
    var ipswConfirmSize: String { get }
    var ipswConfirmDestination: String { get }
    var ipswConfirmHost: String { get }
    var ipswConfirmFreeAfter: String { get }
    func ipswConfirmChecks(_ list: String) -> String
    func ipswLowSpaceWarning(_ free: String, _ percent: Int) -> String
    var ipswDownloadAnyway: String { get }
    var ipswCancel: String { get }
    var ipswCancelA11y: String { get }
    var ipswStop: String { get }
    var ipswStopA11y: String { get }
    func ipswPausedTitle(_ done: String, _ total: String) -> String
    func ipswInterruptedTitle(_ done: String, _ total: String) -> String
    var ipswPausedBody: String { get }
    func ipswStoppedOn(_ time: String) -> String
    func ipswParkedOutdated(_ version: String, _ build: String) -> String
    var ipswStartOver: String { get }
    var ipswStartOverA11y: String { get }
    var ipswResume: String { get }
    var ipswResumeA11y: String { get }
    var ipswDiscard: String { get }
    var ipswDiscardA11y: String { get }
    var ipswClose: String { get }
    var ipswCloseA11y: String { get }
    func ipswRevealA11y(_ name: String) -> String
}

extension StringsEN: IPSWStrings {
    // MARK: IPSW (IPHONE-IPSW). Card, confirm sheet and download panel texts.
    var ipswSigned: String { "Signed (per ipsw.me)" }
    var ipswNotSigned: String { "Not signed (per ipsw.me)" }
    var ipswNotListed: String { "Not in ipsw.me’s list" }
    var ipswIsAppleTarget: String { "Apple’s current restore build" }
    var ipswNotAppleTarget: String { "Not Apple’s current restore build" }
    func ipswAskSends(_ identifier: String) -> String { "Sends the model identifier \(identifier) to ipsw.me" }
    func ipswVerified(_ list: String) -> String { "Verified: \(list)" }
    var ipswVerifiedSizeOnly: String { "and size" }
    var ipswUnknown: String { "Unknown" }
    var ipswChecking: String { "Checking…" }
    func ipswCheckedAt(_ source: String, _ time: String) -> String { "\(source): checked \(time)" }
    var ipswErrNoIdentifier: String { "The phone’s model is unknown — connect it once." }
    var ipswErrUnknownDevice: String { "ipsw.me does not know this model." }
    var ipswErrOffline: String { "No internet connection." }
    var ipswErrTimedOut: String { "The server did not answer in time." }
    func ipswErrHTTP(_ code: Int) -> String { "The server answered with error \(code)." }
    var ipswErrBadResponse: String { "The server sent an answer the app cannot read." }
    func ipswSourceFailed(_ source: String, _ reason: String) -> String { "\(source) unavailable: \(reason)" }
    var ipswErrNotDownloadable: String { "This build is not offered from Apple’s secure download servers, so it is not downloaded." }
    var ipswNoSecureAppleLink: String { "No secure Apple link exists for this build, so it cannot be downloaded here." }
    var ipswNotFromApple: String { "Moonport downloads only the build Apple’s catalogue currently offers." }
    var ipswErrNoChecksum: String { "No checksum is known for this build, so it is not downloaded." }
    var ipswErrNoSize: String { "The file size is unknown, so it is not downloaded." }
    var ipswErrSourcesDisagree: String { "Apple and ipsw.me disagree about this file, so it is not downloaded." }
    func ipswErrNotEnoughSpace(_ needed: String, _ free: String) -> String { "Not enough space: needs \(needed), \(free) free." }
    var ipswErrDownloadsDenied: String { "No access to the Downloads folder. Allow it in System Settings › Privacy & Security › Files and Folders." }
    var ipswErrSizeMismatch: String { "The downloaded file has the wrong size and was deleted." }
    var ipswErrChecksumMismatch: String { "The downloaded file failed the checksum and was deleted." }
    func ipswErrTransfer(_ detail: String) -> String { "Download failed: \(detail)" }
    func ipswErrFileSystem(_ detail: String) -> String { "Could not save the file: \(detail)" }
    var ipswBusy: String { "Another download is in progress." }
    var ipswCancelled: String { "Download cancelled." }
    var ipswErrResumeRejected: String { "The server no longer accepts this download. The downloaded part was deleted." }
    var ipswAppQuit: String { "The app closed during the download." }
    var ipswPreparing: String { "Preparing the download…" }
    func ipswDownloading(_ done: String, _ total: String) -> String { "Downloading \(done) of \(total)" }
    func ipswVerifyingProgress(_ done: String, _ total: String) -> String { "Verifying checksums: \(done) of \(total)" }
    var ipswFinished: String { "Saved to Downloads" }
    var ipswFileGone: String { "The file is no longer in Downloads." }
    var ipswCardTitle: String { "Firmware" }
    var ipswHint: String { "Nothing is checked until you click. Apple’s catalogue names the build Apple restores this model to. ipsw.me adds which builds are still signed." }
    var ipswCheckApple: String { "Check with Apple" }
    var ipswCheckAppleA11y: String { "Check Apple’s current restore build for this model" }
    var ipswAskIPSWMe: String { "Ask ipsw.me" }
    func ipswAskIPSWMeA11y(_ id: String) -> String { "Ask ipsw.me which builds are signed. Sends the model identifier \(id)." }
    func ipswInstalled(_ version: String, _ build: String?) -> String { "Installed: iOS \(version)" + (build.map { " (\($0))" } ?? "") }
    var ipswInstalledFromPhone: String { "read from the connected iPhone" }
    func ipswInstalledLastSeen(_ day: String) -> String { "as of the last connection, \(day)" }
    var ipswInstalledUnknown: String { "The installed iOS is not known yet. Connect the iPhone once." }
    var ipswAppleUnknownModel: String { "Apple’s catalogue does not list this model." }
    var ipswDownload: String { "Download" }
    func ipswDownloadA11y(_ version: String, _ build: String) -> String { "Download iOS \(version) (\(build)) to the Downloads folder" }
    func ipswOlderHidden(_ n: Int) -> String { n == 1 ? "1 older build is not signed (per ipsw.me) and is not listed." : "\(n) older builds are not signed (per ipsw.me) and are not listed." }
    var ipswBusyPaused: String { "Another download is stopped. Resume or discard it on its iPhone’s page." }
    func ipswConfirmTitle(_ version: String, _ build: String) -> String { "Download iOS \(version) (\(build))?" }
    var ipswConfirmSize: String { "Size" }
    var ipswConfirmDestination: String { "Saved to" }
    var ipswConfirmHost: String { "Downloaded from" }
    var ipswConfirmFreeAfter: String { "Free after the download" }
    func ipswConfirmChecks(_ list: String) -> String { "Checked before saving: \(list)" }
    func ipswLowSpaceWarning(_ free: String, _ percent: Int) -> String { "After the download only \(free) stays free. That is below the low-space line set in Settings (\(percent) %)." }
    var ipswDownloadAnyway: String { "Download anyway" }
    var ipswCancel: String { "Cancel" }
    var ipswCancelA11y: String { "Cancel the download" }
    var ipswStop: String { "Stop" }
    var ipswStopA11y: String { "Stop the download. The downloaded part is kept." }
    func ipswPausedTitle(_ done: String, _ total: String) -> String { "Stopped at \(done) of \(total)" }
    func ipswInterruptedTitle(_ done: String, _ total: String) -> String { "Interrupted at \(done) of \(total)" }
    var ipswPausedBody: String { "The downloaded part stays on this Mac for 7 days, also after you quit the app." }
    func ipswStoppedOn(_ time: String) -> String { "Stopped \(time)" }
    func ipswParkedOutdated(_ version: String, _ build: String) -> String { "Apple now restores this model to iOS \(version) (\(build)). The stopped download is an older build." }
    var ipswStartOver: String { "Start over" }
    var ipswStartOverA11y: String { "Start this download again from the beginning" }
    var ipswResume: String { "Resume" }
    var ipswResumeA11y: String { "Resume the download where it stopped" }
    var ipswDiscard: String { "Discard" }
    var ipswDiscardA11y: String { "Discard the downloaded part" }
    var ipswClose: String { "Close" }
    var ipswCloseA11y: String { "Close the firmware message" }
    func ipswRevealA11y(_ name: String) -> String { "Show \(name) in Finder" }
}

extension StringsRU: IPSWStrings {
    // MARK: IPSW (IPHONE-IPSW). Card, confirm sheet and download panel texts.
    var ipswSigned: String { "Подписывается (по данным ipsw.me)" }
    var ipswNotSigned: String { "Не подписывается (по данным ipsw.me)" }
    var ipswNotListed: String { "Нет в списке ipsw.me" }
    var ipswIsAppleTarget: String { "Текущая сборка Apple для восстановления" }
    var ipswNotAppleTarget: String { "Не текущая сборка Apple для восстановления" }
    func ipswAskSends(_ identifier: String) -> String { "Отправит в ipsw.me идентификатор модели \(identifier)" }
    func ipswVerified(_ list: String) -> String { "Проверено: \(list)" }
    var ipswVerifiedSizeOnly: String { "и размер" }
    var ipswUnknown: String { "Неизвестно" }
    var ipswChecking: String { "Проверяем…" }
    func ipswCheckedAt(_ source: String, _ time: String) -> String { "\(source): проверено \(time)" }
    var ipswErrNoIdentifier: String { "Модель телефона неизвестна — подключите его хотя бы раз." }
    var ipswErrUnknownDevice: String { "ipsw.me не знает эту модель." }
    var ipswErrOffline: String { "Нет подключения к интернету." }
    var ipswErrTimedOut: String { "Сервер не ответил вовремя." }
    func ipswErrHTTP(_ code: Int) -> String { "Сервер ответил ошибкой \(code)." }
    var ipswErrBadResponse: String { "Сервер прислал ответ, который приложение не может прочитать." }
    func ipswSourceFailed(_ source: String, _ reason: String) -> String { "\(source) недоступен: \(reason)" }
    var ipswErrNotDownloadable: String { "Эта сборка не раздаётся с защищённых серверов Apple, её не скачиваем." }
    var ipswNoSecureAppleLink: String { "Защищённой ссылки Apple на эту сборку нет, здесь её не скачать." }
    var ipswNotFromApple: String { "Moonport скачивает только ту сборку, которую сейчас предлагает каталог Apple." }
    var ipswErrNoChecksum: String { "Для этой сборки нет контрольной суммы, её не скачиваем." }
    var ipswErrNoSize: String { "Размер файла неизвестен, его не скачиваем." }
    var ipswErrSourcesDisagree: String { "Apple и ipsw.me расходятся в данных об этом файле, его не скачиваем." }
    func ipswErrNotEnoughSpace(_ needed: String, _ free: String) -> String { "Не хватает места: нужно \(needed), свободно \(free)." }
    var ipswErrDownloadsDenied: String { "Нет доступа к папке «Загрузки». Разрешите его в Системных настройках › Конфиденциальность и безопасность › Файлы и папки." }
    var ipswErrSizeMismatch: String { "Скачанный файл не того размера и удалён." }
    var ipswErrChecksumMismatch: String { "Скачанный файл не прошёл проверку контрольной суммы и удалён." }
    func ipswErrTransfer(_ detail: String) -> String { "Загрузка не удалась: \(detail)" }
    func ipswErrFileSystem(_ detail: String) -> String { "Не удалось сохранить файл: \(detail)" }
    var ipswBusy: String { "Уже идёт другая загрузка." }
    var ipswCancelled: String { "Загрузка отменена." }
    var ipswErrResumeRejected: String { "Сервер больше не принимает эту загрузку. Скачанная часть удалена." }
    var ipswAppQuit: String { "Приложение закрылось во время загрузки." }
    var ipswPreparing: String { "Готовим загрузку…" }
    func ipswDownloading(_ done: String, _ total: String) -> String { "Загружено \(done) из \(total)" }
    func ipswVerifyingProgress(_ done: String, _ total: String) -> String { "Проверяем контрольные суммы: \(done) из \(total)" }
    var ipswFinished: String { "Сохранено в «Загрузки»" }
    var ipswFileGone: String { "Файла больше нет в Загрузках." }
    var ipswCardTitle: String { "Прошивка" }
    var ipswHint: String { "Ничего не проверяется без нажатия. Каталог Apple называет сборку, на которую Apple восстанавливает эту модель. ipsw.me добавляет, какие сборки ещё подписываются." }
    var ipswCheckApple: String { "Проверить у Apple" }
    var ipswCheckAppleA11y: String { "Проверить у Apple текущую сборку для восстановления этой модели" }
    var ipswAskIPSWMe: String { "Спросить ipsw.me" }
    func ipswAskIPSWMeA11y(_ id: String) -> String { "Спросить ipsw.me, какие сборки подписываются. Отправит идентификатор модели \(id)." }
    func ipswInstalled(_ version: String, _ build: String?) -> String { "Установлена iOS \(version)" + (build.map { " (\($0))" } ?? "") }
    var ipswInstalledFromPhone: String { "прочитано с подключённого iPhone" }
    func ipswInstalledLastSeen(_ day: String) -> String { "по последнему подключению, \(day)" }
    var ipswInstalledUnknown: String { "Установленная iOS пока неизвестна. Подключите iPhone хотя бы раз." }
    var ipswAppleUnknownModel: String { "В каталоге Apple нет этой модели." }
    var ipswDownload: String { "Скачать" }
    func ipswDownloadA11y(_ version: String, _ build: String) -> String { "Скачать iOS \(version) (\(build)) в папку «Загрузки»" }
    func ipswOlderHidden(_ n: Int) -> String { "Ещё \(n) \(ruPlural(n, "старая сборка", "старые сборки", "старых сборок")) без подписи (по данным ipsw.me) не \(ruPlural(n, "показана", "показаны", "показаны"))." }
    var ipswBusyPaused: String { "Другая загрузка остановлена. Продолжите её или удалите на странице того iPhone." }
    func ipswConfirmTitle(_ version: String, _ build: String) -> String { "Скачать iOS \(version) (\(build))?" }
    var ipswConfirmSize: String { "Размер" }
    var ipswConfirmDestination: String { "Куда" }
    var ipswConfirmHost: String { "Откуда" }
    var ipswConfirmFreeAfter: String { "Свободно после загрузки" }
    func ipswConfirmChecks(_ list: String) -> String { "Проверяется перед сохранением: \(list)" }
    func ipswLowSpaceWarning(_ free: String, _ percent: Int) -> String { "После загрузки останется свободно только \(free). Это ниже порога нехватки места из настроек (\(percent) %)." }
    var ipswDownloadAnyway: String { "Всё равно скачать" }
    var ipswCancel: String { "Отмена" }
    var ipswCancelA11y: String { "Отменить загрузку" }
    var ipswStop: String { "Остановить" }
    var ipswStopA11y: String { "Остановить загрузку. Скачанная часть сохранится." }
    func ipswPausedTitle(_ done: String, _ total: String) -> String { "Остановлено на \(done) из \(total)" }
    func ipswInterruptedTitle(_ done: String, _ total: String) -> String { "Прервано на \(done) из \(total)" }
    var ipswPausedBody: String { "Скачанная часть хранится на этом Mac 7 дней, в том числе после выхода из приложения." }
    func ipswStoppedOn(_ time: String) -> String { "Остановлено \(time)" }
    func ipswParkedOutdated(_ version: String, _ build: String) -> String { "Сейчас Apple восстанавливает эту модель на iOS \(version) (\(build)). Остановленная загрузка — более старая сборка." }
    var ipswStartOver: String { "Начать заново" }
    var ipswStartOverA11y: String { "Начать эту загрузку заново с начала" }
    var ipswResume: String { "Продолжить" }
    var ipswResumeA11y: String { "Продолжить загрузку с места остановки" }
    var ipswDiscard: String { "Удалить" }
    var ipswDiscardA11y: String { "Удалить скачанную часть" }
    var ipswClose: String { "Закрыть" }
    var ipswCloseA11y: String { "Закрыть сообщение о прошивке" }
    func ipswRevealA11y(_ name: String) -> String { "Показать \(name) в Finder" }
}
