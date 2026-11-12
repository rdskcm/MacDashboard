// Engine/Strings/Strings+Legacy.swift
// MOONPORT-RENAME: the one-time Moonport Welcome panel (amendment 3) and the Settings › About old-app row.
// The only strings that name the old app (V5 excludes this file). Protocol, English table, Russian table.
// No semicolons in user-visible text: two short sentences instead.
import Foundation

protocol LegacyStrings {
    var legacyNoticeTitle: String { get }
    var legacySubtitle: String { get }
    var legacySectionDone: String { get }
    var legacySectionTodo: String { get }
    var legacyDoneAllInPlace: String { get }
    var legacyDoneWithNotes: String { get }
    func legacyDoneProgress(done: Int, total: Int) -> String
    var legacyDataMovedTitle: String { get }
    var legacyDataMovedSub: String { get }
    func legacyFilesTag(_ n: Int) -> String
    var legacyArchivesMovingTitle: String { get }
    var legacyArchivesMovingTag: String { get }
    var legacyArchivesMovedTitle: String { get }
    var legacyArchivesDeniedTitle: String { get }
    var legacyArchivesDeniedSub: String { get }
    var legacyArchivesDeniedAgainSub: String { get }
    func legacyArchivesTag(_ n: Int) -> String
    func legacyArchivesLeftSub(_ n: Int) -> String
    func legacyParkedTitle(_ n: Int) -> String
    var legacyParkedSub: String { get }
    var legacyShowButton: String { get }
    func legacyFailedTitle(_ n: Int) -> String
    var legacyFailedSub: String { get }
    var legacyPermsTitle: String { get }
    var legacyPermsSub: String { get }
    var legacyOpenButton: String { get }
    var legacyCheckingLabel: String { get }
    var legacyGrantedLabel: String { get }
    var legacyOptionalTag: String { get }
    var legacyLoginSub: String { get }
    var legacyOldAppTitle: String { get }
    var legacyInApplications: String { get }
    var legacyOldAppNoneSub: String { get }
    var legacyOldAppKeptSub: String { get }
    var legacyOldAppTrashedSub: String { get }
    var legacyNoticeOldAppRunning: String { get }
    var legacyTrashButton: String { get }
    var legacyKeepButton: String { get }
    var legacyKeptLabel: String { get }
    var legacyInTrashLabel: String { get }
    var legacyUndoButton: String { get }
    var legacyQuitRefused: String { get }
    func legacyTrashFailed(reason: String) -> String
    var legacyRestoreOccupied: String { get }
    var legacyRestoreGone: String { get }
    var legacyRestoreFailed: String { get }
    var settingsOldAppLabel: String { get }
    var settingsOldAppSub: String { get }
    var legacyLaterButton: String { get }
    var legacyDoneButton: String { get }
    var legacyAllDone: String { get }
    func legacyStepsLeft(_ n: Int) -> String
}

extension StringsEN: LegacyStrings {
    var legacyNoticeTitle: String { "It’s Moonport now" }
    var legacySubtitle: String { "MacDashboard has a new name. Your data moves over by itself, the rest takes a minute." }
    var legacySectionDone: String { "Done automatically" }
    var legacySectionTodo: String { "For you to do" }
    var legacyDoneAllInPlace: String { "all in place" }
    var legacyDoneWithNotes: String { "with notes" }
    func legacyDoneProgress(done: Int, total: Int) -> String { "\(done) of \(total)" }
    var legacyDataMovedTitle: String { "Report, history and iPhone data" }
    var legacyDataMovedSub: String { "Moved to Moonport" }
    func legacyFilesTag(_ n: Int) -> String { n == 1 ? "1 file" : "\(n) files" }
    var legacyArchivesMovingTitle: String { "iPhone archives are moving" }
    var legacyArchivesMovingTag: String { "in progress" }
    var legacyArchivesMovedTitle: String { "iPhone archives moved" }
    var legacyArchivesDeniedTitle: String { "iPhone archives not moved" }
    var legacyArchivesDeniedSub: String { "No access to the Documents folder. The transfer continues after step 1." }
    var legacyArchivesDeniedAgainSub: String { "No access to the Documents folder. The transfer runs again at the next launch." }
    func legacyArchivesTag(_ n: Int) -> String { n == 1 ? "1 archive" : "\(n) archives" }
    func legacyArchivesLeftSub(_ n: Int) -> String {
        n == 1 ? "1 file stayed in the old folder. Move it manually." : "\(n) files stayed in the old folder. Move them manually."
    }
    func legacyParkedTitle(_ n: Int) -> String { n == 1 ? "Both versions of a file kept" : "Both versions of \(n) files kept" }
    var legacyParkedSub: String { "A file with this name was already in the new folder. We didn’t replace anything." }
    var legacyShowButton: String { "Show" }
    func legacyFailedTitle(_ n: Int) -> String { n == 1 ? "1 file could not be moved" : "\(n) files could not be moved" }
    var legacyFailedSub: String { "They’re still in the old folder. Move them manually." }
    var legacyPermsTitle: String { "Allow Full Disk Access" }
    var legacyPermsSub: String { "macOS sees this as a new app. Only Full Disk Access is needed here. macOS asks for the rest itself when it’s needed." }
    var legacyOpenButton: String { "Open" }
    var legacyCheckingLabel: String { "Checking…" }
    var legacyGrantedLabel: String { "Granted" }
    var legacyOptionalTag: String { "optional" }
    var legacyLoginSub: String { "Turn on if you want Moonport to open by itself." }
    var legacyOldAppTitle: String { "Old app" }
    var legacyInApplications: String { "in Applications" }
    var legacyOldAppNoneSub: String { "Your data is already in Moonport. Remove its Dock tile manually." }
    var legacyOldAppKeptSub: String { "The Dock tile still opens the old app." }
    var legacyOldAppTrashedSub: String { "Remove its Dock tile, it won’t open anymore." }
    var legacyNoticeOldAppRunning: String { "MacDashboard is running. It will be asked to quit first." }
    var legacyTrashButton: String { "Move to Trash" }
    var legacyKeepButton: String { "Keep" }
    var legacyKeptLabel: String { "Kept" }
    var legacyInTrashLabel: String { "In Trash" }
    var legacyUndoButton: String { "Undo" }
    var legacyQuitRefused: String { "MacDashboard did not quit. Quit it and try again." }
    func legacyTrashFailed(reason: String) -> String { "Could not move it to the Trash: \(reason). Drag it to the Trash in Finder." }
    var legacyRestoreOccupied: String { "Couldn’t put it back. Its old place already holds an app with this name." }
    var legacyRestoreGone: String { "Couldn’t put it back. It’s no longer in the Trash." }
    var legacyRestoreFailed: String { "Couldn’t put it back. Use Put Back in the Trash in Finder." }
    var settingsOldAppLabel: String { "Old MacDashboard app" }
    var settingsOldAppSub: String { "Moonport replaced it. Its data was moved." }
    var legacyLaterButton: String { "Later" }
    var legacyDoneButton: String { "Done" }
    var legacyAllDone: String { "All set" }
    func legacyStepsLeft(_ n: Int) -> String { n == 1 ? "1 step left" : "\(n) steps left" }
}

extension StringsRU: LegacyStrings {
    var legacyNoticeTitle: String { "Теперь это Moonport" }
    var legacySubtitle: String { "Новое название MacDashboard. Данные переносятся сами, остальное займёт минуту." }
    var legacySectionDone: String { "Сделано автоматически" }
    var legacySectionTodo: String { "Сделайте сами" }
    var legacyDoneAllInPlace: String { "всё на месте" }
    var legacyDoneWithNotes: String { "с замечаниями" }
    func legacyDoneProgress(done: Int, total: Int) -> String { "\(done) из \(total)" }
    var legacyDataMovedTitle: String { "Отчёт, история и данные iPhone" }
    var legacyDataMovedSub: String { "Перенесены в Moonport" }
    func legacyFilesTag(_ n: Int) -> String { "\(n) " + ruPlural(n, "файл", "файла", "файлов") }
    var legacyArchivesMovingTitle: String { "Архивы iPhone переносятся" }
    var legacyArchivesMovingTag: String { "идёт" }
    var legacyArchivesMovedTitle: String { "Архивы iPhone перенесены" }
    var legacyArchivesDeniedTitle: String { "Архивы iPhone не перенесены" }
    var legacyArchivesDeniedSub: String { "Нет доступа к папке «Документы». Перенос продолжится после шага 1." }
    var legacyArchivesDeniedAgainSub: String { "Нет доступа к папке «Документы». Перенос повторится при следующем запуске." }
    func legacyArchivesTag(_ n: Int) -> String { "\(n) " + ruPlural(n, "архив", "архива", "архивов") }
    func legacyArchivesLeftSub(_ n: Int) -> String {
        "\(n) " + ruPlural(n, "файл остался", "файла остались", "файлов остались") + " в старой папке. Перенесите вручную."
    }
    func legacyParkedTitle(_ n: Int) -> String {
        n == 1 ? "Сохранены обе версии файла" : "Сохранены обе версии \(n) " + ruPlural(n, "файла", "файлов", "файлов")
    }
    var legacyParkedSub: String { "Файл с таким именем уже был в новой папке. Мы ничего не заменили." }
    var legacyShowButton: String { "Показать" }
    func legacyFailedTitle(_ n: Int) -> String { "\(n) " + ruPlural(n, "файл", "файла", "файлов") + " не удалось перенести" }
    var legacyFailedSub: String { "Остались в старой папке. Перенесите их вручную." }
    var legacyPermsTitle: String { "Разрешите доступ к диску" }
    var legacyPermsSub: String { "Для macOS это новое приложение. Здесь нужен только полный доступ к диску. Остальное macOS спросит сама, когда понадобится." }
    var legacyOpenButton: String { "Открыть" }
    var legacyCheckingLabel: String { "Проверка…" }
    var legacyGrantedLabel: String { "Выдан" }
    var legacyOptionalTag: String { "по желанию" }
    var legacyLoginSub: String { "Включите, если хотите, чтобы Moonport запускался сам." }
    var legacyOldAppTitle: String { "Старое приложение" }
    var legacyInApplications: String { "в Программах" }
    var legacyOldAppNoneSub: String { "Данные уже в Moonport. Плитку в Dock уберите вручную." }
    var legacyOldAppKeptSub: String { "Плитка в Dock по-прежнему открывает старое приложение." }
    var legacyOldAppTrashedSub: String { "Уберите его плитку из Dock, она больше не откроется." }
    var legacyNoticeOldAppRunning: String { "MacDashboard сейчас запущен. Сначала ему будет предложено завершиться." }
    var legacyTrashButton: String { "В корзину" }
    var legacyKeepButton: String { "Оставить" }
    var legacyKeptLabel: String { "Оставлено" }
    var legacyInTrashLabel: String { "В корзине" }
    var legacyUndoButton: String { "Отменить" }
    var legacyQuitRefused: String { "MacDashboard не завершился. Завершите его и попробуйте снова." }
    func legacyTrashFailed(reason: String) -> String { "Не удалось переместить в корзину: \(reason). Перетащите приложение в корзину в Finder." }
    var legacyRestoreOccupied: String { "Вернуть не удалось. На прежнем месте уже есть приложение с этим именем." }
    var legacyRestoreGone: String { "Вернуть не удалось. В корзине его больше нет." }
    var legacyRestoreFailed: String { "Вернуть не удалось. Верните его из корзины в Finder." }
    var settingsOldAppLabel: String { "Старое приложение MacDashboard" }
    var settingsOldAppSub: String { "Его заменил Moonport. Данные перенесены." }
    var legacyLaterButton: String { "Позже" }
    var legacyDoneButton: String { "Готово" }
    var legacyAllDone: String { "Всё готово" }
    func legacyStepsLeft(_ n: Int) -> String {
        ruPlural(n, "Остался \(n) шаг", "Осталось \(n) шага", "Осталось \(n) шагов")
    }
}
