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
        // PRIMARY GATE: `swift run MacDashboardChecks` — an executable target (assert +
        // exit nonzero, no XCTest/swift-testing). It was created when this Mac had
        // Command Line Tools only and `import Testing` failed (SPEC §10); it stays the
        // primary gate and the place new checks go. Its Checks/ sources are symlinks into
        // Sources/MacDashboard/... so it compiles and exercises the SAME pure engine
        // files as the app (see Checks/README.md).
        .executableTarget(
            name: "MacDashboardChecks",
            path: "Checks",
            exclude: ["README.md"],
            swiftSettings: [.define("AI_ENABLED")]
        ),
        // SWIFT-TESTING SAMPLE (CI-SWIFT-TESTING): a fixed swift-testing suite, run by
        // `swift test` locally (needs Xcode) and in .github/workflows/ci.yml. It reaches the
        // engine through `@testable import MacDashboard` (no symlinks), so it tests the
        // app module exactly as the default build compiles it (AI off). `swift build`
        // never compiles a test target (only `swift test` / `--build-tests` do) and
        // build_app.sh builds `--product MacDashboard` only, so local builds are unchanged.
        .testTarget(
            name: "MacDashboardTests",
            dependencies: ["MacDashboard"],
            path: "Tests/MacDashboardTests"
        )
    ]
)
