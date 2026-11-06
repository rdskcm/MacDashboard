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
    var socChipTemperature: String { get }
    var gpuNotAvailable: String { get }
    var gpuWholeMac: String { get }
    var cpuSocHot: String { get }
    var cpuSocWarm: String { get }
    var cpuThermalNominal: String { get }
    var cpuThermalFair: String { get }
    var cpuThermalSerious: String { get }
    var cpuThermalCritical: String { get }
    var cpuThermalHelpNominal: String { get }
    var cpuThermalHelpFair: String { get }
    var cpuThermalHelpSerious: String { get }
    var cpuThermalHelpCritical: String { get }
    var cpuNoReading: String { get }
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

    // MARK: SoC page details (SOC-DETAILS stage 1: the keys the pure view models in Engine/SocPageModel.swift use)
    var socCoresUnknown: String { get }
    var socLoadPerCore: String { get }
    var socFrequencyIdle: String { get }
    var socFrequencyHelp: String { get }
    func socGHz(_ s: String) -> String
    func socGPUCores(_ n: Int) -> String
    var socTopByGPU: String { get }
    var socPowerLabel: String { get }
    var socPowerUnavailable: String { get }
    func socWatts(_ s: String) -> String
    var socPowerPrefix: String { get }
    var socChartMinus2: String { get }
    var socChartMinus1: String { get }
    var socChartNow: String { get }
    var cpuThermalWordNominal: String { get }
    var cpuThermalWordFair: String { get }
    var cpuThermalWordSerious: String { get }
    var cpuThermalWordCritical: String { get }

    // MARK: SoC page layout (SOC-DETAILS stage 2)
    var socCoresTitle: String { get }
    var socCoreTypePerformance: String { get }
    var socCoreTypeEfficiency: String { get }
    var socFrequency: String { get }
    var cpuIdle: String { get }
    var socLoadAverage: String { get }
    func socLoadMin(_ n: Int) -> String
    var socLoadAverageHelp: String { get }
    var socLoadAverageUnavailable: String { get }
    var socGPUListEmpty: String { get }
    var socTemperatureHelp: String { get }
    var socTemperatureUnavailable: String { get }
    var socChartTitle: String { get }
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
    var socChipTemperature: String { "Chip temperature" }
    var gpuNotAvailable: String { "Not available on this Mac" }
    var gpuWholeMac: String { "Whole Mac, including what macOS draws" }
    var cpuSocHot: String { "hot" }
    var cpuSocWarm: String { "warm" }
    var cpuThermalNominal: String { "thermal: normal" }
    var cpuThermalFair: String { "thermal: elevated" }
    var cpuThermalSerious: String { "thermal: high" }
    var cpuThermalCritical: String { "thermal: critical" }
    var cpuThermalHelpNominal: String { "macOS thermal state: normal. Temperatures are within normal limits." }
    var cpuThermalHelpFair: String { "macOS thermal state: slightly elevated. Fans, if the Mac has them, may spin up. Energy use is higher." }
    var cpuThermalHelpSerious: String { "macOS thermal state: high. Fans, if the Mac has them, run at full speed. macOS may reduce performance to cool down." }
    var cpuThermalHelpCritical: String { "macOS thermal state: critical. Performance is significantly reduced until the Mac cools down." }
    var cpuNoReading: String { "No current reading" }
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

    // MARK: SoC page details (SOC-DETAILS)
    var socCoresUnknown: String { "Cores" }
    var socLoadPerCore: String { "load per core" }
    var socFrequencyIdle: String { "idle" }
    var socFrequencyHelp: String { "Average speed while the cores were active." }
    func socGHz(_ s: String) -> String { "\(s) GHz" }
    func socGPUCores(_ n: Int) -> String { "\(n) GPU cores" }
    var socTopByGPU: String { "top by GPU" }
    var socPowerLabel: String { "Power, whole Mac" }
    var socPowerUnavailable: String { "Power, whole Mac: Not available on this Mac" }
    func socWatts(_ s: String) -> String { "\(s) W" }
    var socPowerPrefix: String { "Mac" }
    var socChartMinus2: String { "−2 min" }
    var socChartMinus1: String { "−1 min" }
    var socChartNow: String { "now" }
    var cpuThermalWordNominal: String { "normal" }
    var cpuThermalWordFair: String { "elevated" }
    var cpuThermalWordSerious: String { "high" }
    var cpuThermalWordCritical: String { "critical" }

    // MARK: SoC page layout (SOC-DETAILS stage 2)
    var socCoresTitle: String { "CPU cores" }
    var socCoreTypePerformance: String { "Performance" }
    var socCoreTypeEfficiency: String { "Efficiency" }
    var socFrequency: String { "Frequency" }
    var cpuIdle: String { "Idle" }
    var socLoadAverage: String { "Load average" }
    func socLoadMin(_ n: Int) -> String { "\(n) min" }
    var socLoadAverageHelp: String { "Average number of tasks running or waiting. Compare it with the number of cores." }
    var socLoadAverageUnavailable: String { "Load average: Not available on this Mac" }
    var socGPUListEmpty: String { "No process is using the GPU." }
    var socTemperatureHelp: String { "Chip temperature. Warm from 85 °C, hot from 95 °C." }
    var socTemperatureUnavailable: String { "Chip temperature: Not available on this Mac" }
    var socChartTitle: String { "CPU and GPU, last 2 minutes" }
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
    var socChipTemperature: String { "Температура чипа" }
    var gpuNotAvailable: String { "Недоступно на этом Mac" }
    var gpuWholeMac: String { "Весь Mac, включая отрисовку macOS" }
    var cpuSocHot: String { "горячо" }
    var cpuSocWarm: String { "тепло" }
    var cpuThermalNominal: String { "нагрев: норма" }
    var cpuThermalFair: String { "нагрев: повышен" }
    var cpuThermalSerious: String { "нагрев: высокий" }
    var cpuThermalCritical: String { "нагрев: критический" }
    var cpuThermalHelpNominal: String { "Тепловое состояние macOS: норма. Температура в пределах нормы." }
    var cpuThermalHelpFair: String { "Тепловое состояние macOS: немного повышено. Вентиляторы, если они есть, могут раскрутиться. Расход энергии выше." }
    var cpuThermalHelpSerious: String { "Тепловое состояние macOS: высокое. Вентиляторы, если они есть, работают на максимуме. macOS может снижать производительность, чтобы охладиться." }
    var cpuThermalHelpCritical: String { "Тепловое состояние macOS: критическое. Производительность заметно снижена, пока Mac не остынет." }
    var cpuNoReading: String { "Нет текущих данных" }
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

    // MARK: SoC page details (SOC-DETAILS)
    var socCoresUnknown: String { "Ядра" }
    var socLoadPerCore: String { "загрузка каждого ядра" }
    var socFrequencyIdle: String { "простой" }
    var socFrequencyHelp: String { "Средняя частота, пока ядра были активны." }
    func socGHz(_ s: String) -> String { "\(s) ГГц" }
    func socGPUCores(_ n: Int) -> String { "\(n) " + ruPlural(n, "ядро", "ядра", "ядер") + " GPU" }
    var socTopByGPU: String { "топ по GPU" }
    var socPowerLabel: String { "Потребление всего Mac" }
    var socPowerUnavailable: String { "Потребление всего Mac: Недоступно на этом Mac" }
    func socWatts(_ s: String) -> String { "\(s) Вт" }
    var socPowerPrefix: String { "Mac" }
    var socChartMinus2: String { "−2 мин" }
    var socChartMinus1: String { "−1 мин" }
    var socChartNow: String { "сейчас" }
    var cpuThermalWordNominal: String { "норма" }
    var cpuThermalWordFair: String { "повышен" }
    var cpuThermalWordSerious: String { "высокий" }
    var cpuThermalWordCritical: String { "критический" }

    // MARK: SoC page layout (SOC-DETAILS stage 2)
    var socCoresTitle: String { "Ядра CPU" }
    var socCoreTypePerformance: String { "Производительные" }
    var socCoreTypeEfficiency: String { "Энергоэффективные" }
    var socFrequency: String { "Частота" }
    var cpuIdle: String { "Простой" }
    var socLoadAverage: String { "Средняя нагрузка" }
    func socLoadMin(_ n: Int) -> String { "\(n) мин" }
    var socLoadAverageHelp: String { "Среднее число задач, которые выполняются или ждут. Сравните его с числом ядер." }
    var socLoadAverageUnavailable: String { "Средняя нагрузка: Недоступно на этом Mac" }
    var socGPUListEmpty: String { "Ни один процесс не использует GPU." }
    var socTemperatureHelp: String { "Температура чипа. Тепло от 85 °C, горячо от 95 °C." }
    var socTemperatureUnavailable: String { "Температура чипа: Недоступно на этом Mac" }
    var socChartTitle: String { "CPU и GPU за последние 2 минуты" }
}
