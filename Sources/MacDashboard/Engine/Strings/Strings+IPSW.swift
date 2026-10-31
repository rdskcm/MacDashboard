// Engine/Strings/Strings+IPSW.swift
// IPSW downloads: the `IPSWStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol IPSWStrings {
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
}

extension StringsEN: IPSWStrings {
    // MARK: IPSW (IPHONE-IPSW). Button and a11y labels arrive with the UI step.
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
    func ipswCheckedAgo(_ rel: String) -> String { "Checked \(rel)" }
    var ipswErrNoIdentifier: String { "The phone’s model is unknown — connect it once." }
    var ipswErrUnknownDevice: String { "ipsw.me does not know this model." }
    var ipswErrOffline: String { "No internet connection." }
    var ipswErrTimedOut: String { "The server did not answer in time." }
    func ipswErrHTTP(_ code: Int) -> String { "The server answered with error \(code)." }
    var ipswErrBadResponse: String { "The server sent an answer the app cannot read." }
    func ipswSourceFailed(_ source: String, _ reason: String) -> String { "\(source) unavailable: \(reason)" }
    var ipswErrNotDownloadable: String { "This build is not offered from Apple’s secure download servers, so it is not downloaded." }
    var ipswNoSecureAppleLink: String { "No secure Apple link exists for this build, so it cannot be downloaded here." }
    var ipswNotFromApple: String { "MacDashboard downloads only the build Apple’s catalogue currently offers." }
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
    var ipswPreparing: String { "Preparing the download…" }
    func ipswDownloading(_ done: String, _ total: String) -> String { "Downloading \(done) of \(total)" }
    var ipswVerifying: String { "Verifying checksums…" }
    var ipswFinished: String { "Saved to Downloads" }
}

extension StringsRU: IPSWStrings {
    // MARK: IPSW (IPHONE-IPSW). Button and a11y labels arrive with the UI step.
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
    func ipswCheckedAgo(_ rel: String) -> String { "Проверено \(rel)" }
    var ipswErrNoIdentifier: String { "Модель телефона неизвестна — подключите его хотя бы раз." }
    var ipswErrUnknownDevice: String { "ipsw.me не знает эту модель." }
    var ipswErrOffline: String { "Нет подключения к интернету." }
    var ipswErrTimedOut: String { "Сервер не ответил вовремя." }
    func ipswErrHTTP(_ code: Int) -> String { "Сервер ответил ошибкой \(code)." }
    var ipswErrBadResponse: String { "Сервер прислал ответ, который приложение не может прочитать." }
    func ipswSourceFailed(_ source: String, _ reason: String) -> String { "\(source) недоступен: \(reason)" }
    var ipswErrNotDownloadable: String { "Эта сборка не раздаётся с защищённых серверов Apple, её не скачиваем." }
    var ipswNoSecureAppleLink: String { "Защищённой ссылки Apple на эту сборку нет, здесь её не скачать." }
    var ipswNotFromApple: String { "MacDashboard скачивает только ту сборку, которую сейчас предлагает каталог Apple." }
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
    var ipswPreparing: String { "Готовим загрузку…" }
    func ipswDownloading(_ done: String, _ total: String) -> String { "Загружено \(done) из \(total)" }
    var ipswVerifying: String { "Проверяем контрольные суммы…" }
    var ipswFinished: String { "Сохранено в «Загрузки»" }
}
