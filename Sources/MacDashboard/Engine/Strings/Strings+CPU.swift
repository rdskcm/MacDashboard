// Engine/Strings/Strings+CPU.swift
// Process cards and CPU page: the `CPUStrings` protocol, then the English table (`StringsEN`, the reference),
// then the Russian table (`StringsRU`, the translation). A new key goes into all three.
import Foundation

protocol CPUStrings {
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
}

extension StringsEN: CPUStrings {
    // MARK: Process cards
    var processesTitle: String { "Processes" }
    var processSegCPU: String { "CPU" }
    var processSegMem: String { "Memory" }
    var processesMetricA11y: String { "Process metric" }
    var processLoadingDetails: String { "Loading details…" }
    var processDetailPath: String { "Path" }
    var processQuit: String { "Quit" }
    var processForceQuit: String { "Force quit…" }
    var processForceQuitConfirm: String { "Force quit" }
    func processTerminateA11y(_ name: String) -> String { "Quit process “\(name)”" }
    func processKillA11y(_ name: String) -> String { "Force quit process “\(name)”" }

    // MARK: CPU page + restyled Processes card (REDESIGN-CPU)
    // REDESIGN-CPU
    var cpuLiveSnapshot: String { "live snapshot" }
    var cpuUsage: String { "Usage" }
    var cpuUser: String { "User" }
    var cpuSystem: String { "System" }
    var cpuSocTemperature: String { "SoC temperature" }
    var cpuSocHot: String { "hot · may throttle" }
    var cpuSocWarm: String { "warm" }
    var cpuNoReading: String { "No current reading" }
    func cpuLoadNote(_ a: String, _ b: String, _ c: String, _ cores: Int) -> String { "load \(a) · \(b) · \(c) · \(cores) cores" }
    func cpuHighLoadFor(_ min: Int) -> String { "High load for \(min) min" }
    var cpuTagHigh: String { "High load" }
    var cpuTagReadError: String { "Read error" }
    func cpuSubLive(_ cores: Int, _ seconds: Int) -> String { "\(cores) cores · updates every \(seconds) s" }
    var cpuSubCollecting: String { "collecting data…" }
    var cpuFailTimedOut: String { "Couldn’t read CPU counters: no response within 5 s." }
    var cpuFailNoReading: String { "Couldn’t read CPU counters: the system returned no data." }
    var readRetriesAutomatically: String { "The app keeps trying automatically." }
    var procsTopByCPU: String { "top by CPU" }
    var procsTopByMemory: String { "top by memory" }
    func procsCount(_ n: Int) -> String { n == 1 ? "1 process" : "\(n) processes" }
    var procsFoot: String { "click a process to see its PID, path and the Quit / Force quit buttons" }
    var processOwner: String { "Owner" }
    var processQuitting: String { "Quitting…" }
    func processForceQuitQuestion(_ name: String) -> String { "Force quit “\(name)”? Unsaved changes will be lost." }
    func processSignalFailed(_ name: String) -> String { "Couldn’t quit “\(name)”." }
}

extension StringsRU: CPUStrings {
    // MARK: Process cards
    var processesTitle: String { "Процессы" }
    var processSegCPU: String { "CPU" }
    var processSegMem: String { "Память" }
    var processesMetricA11y: String { "Метрика процессов" }
    var processLoadingDetails: String { "Загружаем детали…" }
    var processDetailPath: String { "Путь" }
    var processQuit: String { "Завершить" }
    var processForceQuit: String { "Снять принудительно…" }
    var processForceQuitConfirm: String { "Снять принудительно" }
    func processTerminateA11y(_ name: String) -> String { "Завершить процесс „\(name)“" }
    func processKillA11y(_ name: String) -> String { "Принудительно снять процесс „\(name)“" }

    // MARK: CPU page + restyled Processes card (REDESIGN-CPU)
    // REDESIGN-CPU
    var cpuLiveSnapshot: String { "живой снимок" }
    var cpuUsage: String { "Загрузка" }
    var cpuUser: String { "Пользователь" }
    var cpuSystem: String { "Система" }
    var cpuSocTemperature: String { "Температура SoC" }
    var cpuSocHot: String { "горячо · возможен троттлинг" }
    var cpuSocWarm: String { "тепло" }
    var cpuNoReading: String { "Нет текущих данных" }
    func cpuLoadNote(_ a: String, _ b: String, _ c: String, _ cores: Int) -> String { "нагрузка \(a) · \(b) · \(c) · \(cores) " + ruPlural(cores, "ядро", "ядра", "ядер") }
    func cpuHighLoadFor(_ min: Int) -> String { "Высокая нагрузка уже \(min) мин" }
    var cpuTagHigh: String { "Высокая нагрузка" }
    var cpuTagReadError: String { "Ошибка чтения" }
    func cpuSubLive(_ cores: Int, _ seconds: Int) -> String { "\(cores) " + ruPlural(cores, "ядро", "ядра", "ядер") + " · обновляется каждые \(seconds) с" }
    var cpuSubCollecting: String { "сбор данных…" }
    var cpuFailTimedOut: String { "Не удалось прочитать счётчики CPU: нет ответа за 5 с." }
    var cpuFailNoReading: String { "Не удалось прочитать счётчики CPU: система не вернула данных." }
    var readRetriesAutomatically: String { "Приложение повторяет попытки автоматически." }
    var procsTopByCPU: String { "топ по CPU" }
    var procsTopByMemory: String { "топ по памяти" }
    func procsCount(_ n: Int) -> String { "\(n) " + ruPlural(n, "процесс", "процесса", "процессов") }
    var procsFoot: String { "нажмите на процесс, чтобы увидеть PID, путь и кнопки «Завершить» / «Снять принудительно»" }
    var processOwner: String { "Владелец" }
    var processQuitting: String { "Завершение…" }
    func processForceQuitQuestion(_ name: String) -> String { "Снять «\(name)» принудительно? Несохранённые изменения будут потеряны." }
    func processSignalFailed(_ name: String) -> String { "Не удалось завершить «\(name)»." }
}
