# MacDashboardChecks

This directory is the source root of the `MacDashboardChecks` SwiftPM executable target
(SPEC §10), a LEGACY gate being retired by CHECKS-SWIFT-TESTING. It was built as a plain
executable because this Mac once had Command Line Tools only, where neither XCTest nor
swift-testing was available. Xcode 27 is now installed and `swift test` works, so these
checks are being ported to `Tests/MacDashboardTests/` and this target is deleted at the
block's last stage. Until then `main.swift` runs a tiny assert-and-print harness and calls
`exit(1)` if anything fails, so `swift run MacDashboardChecks` is still a pass/fail check.

Every other file in this directory (`Models.swift`, `AppInfo.swift`, `AttentionModel.swift`,
`Parsers.swift`, `Assessment.swift`,
`CommandRunner.swift`, `LiveCollector.swift`, `ProcessSampler.swift`, `ReportCollector.swift`,
`ReportWriter.swift`, `HistoryStore.swift`, `L10n.swift`, `BrewProgress.swift`,
`ThermalSensors.swift`, `AppSettings.swift`, `StringsRU.swift`, `StringsEN.swift`,
`LaunchdPlistInspector.swift`, `Formatting.swift`, `BarHitTest.swift`, `BatteryInspector.swift`,
`Advice.swift`, `HistorySeries.swift`,
`DirectoryAccess.swift`, `AppleScriptResult.swift`, `PrivilegedRunner.swift`, `BrewUpgrader.swift`,
`ParsedCommands.swift`, `WakeHolders.swift`, `BackupLog.swift`, `VisualFixture.swift`, `IPhoneData.swift`, `InFlightReads.swift`, `RimAngle.swift`, `SysdiagnoseExtractor.swift`) is a **symlink** back into
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
`ProcessSamplerChecks.swift`, `HistorySeriesChecks.swift`, `LaunchdPlistInspectorChecks.swift`,
`SudoPathSafetyChecks.swift`,
`CommandRunnerExitChecks.swift`, `CommandRunnerCoreChecks.swift`, `ParserFixtureChecks.swift`,
`ReportWriterChecks.swift`, `PrivilegedRunnerChecks.swift`, `BrewUpgraderChecks.swift`,
`HistoryStoreChecks.swift`, `IPhoneChecks.swift`, `WakeHoldersChecks.swift`, `BackupLogChecks.swift`, `VisualFixtureChecks.swift`, `FolderSizesChecks.swift`, `SysdiagnoseExtractorChecks.swift`, `InFlightReadsChecks.swift`, `RimAngleChecks.swift`, and `LiveCanary.swift`
are real (non-symlinked) files, like `main.swift`.
Swift executable targets only permit ONE file with top-level (script-mode) statements —
`main.swift` owns that slot — so additional check files must instead define a plain
function (`runSmartToolsAvailabilityChecks()`) that `main.swift` calls explicitly. Any
future check file that doesn't fit naturally into `main.swift`'s inline `do { ... }`
blocks should follow this same function-file pattern.

`Tests/Fixtures/` holds the parser fixtures, captured or hand-built command output filed
one directory per `ParsedCommand` (see its own README). `ParserFixtureChecks.swift` finds
that tree via `#filePath` and checks every fixture against the shared registry in
`ParsedCommands.swift`. `swift run MacDashboardChecks --live` runs only the live parser
canary (`LiveCanary.swift`): it runs every registry command for real and exits 1 iff a
real command's output was rejected by its parser.
`swift run MacDashboardChecks --sysdiagnose <archive.tar.gz>` runs the import's extractor on a real archive in a fresh temp dir and prints what it selected.

**swift-testing target.** `Tests/MacDashboardTests/` is the `.testTarget`
(`MacDashboardTests`) run with `swift test`, locally and in CI (`.github/workflows/ci.yml`).
It reaches the engine through `@testable import MacDashboard`, not through symlinks, and it
is where new checks go: add no new checks to this directory. `swift build` and
`build_app.sh` never compile the test target.
