# MacDashboardChecks

This directory is the source root of the `MacDashboardChecks` SwiftPM executable target
(SPEC §10). XCTest and swift-testing (`import Testing`) are both unavailable under
Command Line Tools without Xcode on this machine, so instead of a `.testTarget` this is
a plain executable: `main.swift` runs a tiny assert-and-print harness and calls
`exit(1)` if anything fails, so `swift run MacDashboardChecks` is a normal CI-style
pass/fail check.

Every other file in this directory (`Models.swift`, `Parsers.swift`, `Assessment.swift`,
`CommandRunner.swift`, `LiveCollector.swift`, `ReportCollector.swift`,
`ReportWriter.swift`, `HistoryStore.swift`, `L10n.swift`, `BrewProgress.swift`,
`ThermalSensors.swift`, `AppSettings.swift`, `StringsRU.swift`, `StringsEN.swift`,
`LaunchdPlistInspector.swift`, `Formatting.swift`, `BatteryInspector.swift`,
`Advice.swift`, `HistorySeries.swift`, `AIRedaction.swift`, `AIPayload.swift`,
`AIRequest.swift`, `DirectoryAccess.swift`) is a **symlink** back into
`../Sources/MacDashboard/...`. SwiftPM compiles whatever source files it finds under a
target's `path`, following symlinks, so this target builds and tests the exact same pure
engine source files the app itself ships — no copy-paste drift, no separate module to
keep in sync. `DashboardModel.swift` and everything under `Views/` are deliberately
**not** symlinked here: `DashboardModel` is `@MainActor @Observable` (imports
`Observation`) and the Views are SwiftUI — both are app-only and out of scope for these
pure-logic checks. If a future SwiftPM/toolchain change ever makes symlinked sources
misbehave (duplicate-file errors, etc.), replace the symlinks with a `sync_checks.sh`
script that copies the files in before each build instead of restructuring `Sources/`.

`SmartToolsAvailabilityChecks.swift`, `ThermalSensorsChecks.swift`,
`HistorySeriesChecks.swift`, `LaunchdPlistInspectorChecks.swift`,
`AIRedactionChecks.swift`, and `AIPayloadRequestChecks.swift` are real
(non-symlinked) files, like `main.swift`.
Swift executable targets only permit ONE file with top-level (script-mode) statements —
`main.swift` owns that slot — so additional check files must instead define a plain
function (`runSmartToolsAvailabilityChecks()`) that `main.swift` calls explicitly. Any
future check file that doesn't fit naturally into `main.swift`'s inline `do { ... }`
blocks should follow this same function-file pattern.
