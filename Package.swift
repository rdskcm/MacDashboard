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
        // SWIFT-TESTING SUITE: run by `swift test` locally and in .github/workflows/ci.yml; the
        // place new tests go. It reaches the engine through `@testable import MacDashboard`
        // (no symlinks). Ported checks live under the `.serialized` root suite `SerialTests`
        // (Tests/MacDashboardTests/TestSupport.swift). `swift build` never compiles a test
        // target (only `swift test` / `--build-tests` do) and build_app.sh builds
        // `--product MacDashboard` only, so local builds are unchanged.
        .testTarget(
            name: "MacDashboardTests",
            dependencies: ["MacDashboard"],
            path: "Tests/MacDashboardTests"
        )
    ]
)
