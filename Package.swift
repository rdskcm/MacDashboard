// swift-tools-version: 5.10
// Package.swift — scaffold owns this file (SPEC §3). Tools-version 5.10 defaults
// to Swift 5 language mode, avoiding Swift 6 strict-concurrency build failures
// while still satisfying the "5.9+" requirement.
import PackageDescription

let package = Package(
    name: "MacDashboard",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MacDashboard",
            path: "Sources/MacDashboard"
        ),
        // NOTE: no .testTarget here — probed `import Testing` (swift-testing) under
        // Command Line Tools (no Xcode) and `swift test` failed with "no such module
        // 'Testing'" (module not shipped outside Xcode on this toolchain). Per SPEC §10,
        // real tests live in this separate `MacDashboardChecks` executable target
        // (assert + exit nonzero, no XCTest). Its Checks/ sources are symlinks into
        // Sources/MacDashboard/... so it compiles and exercises the SAME pure engine
        // files as the app (see Checks/README.md).
        .executableTarget(
            name: "MacDashboardChecks",
            path: "Checks",
            exclude: ["README.md"],
            swiftSettings: [.define("AI_ENABLED")]
        )
    ]
)
