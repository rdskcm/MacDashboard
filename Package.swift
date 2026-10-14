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
        // LEGACY GATE, being retired by CHECKS-SWIFT-TESTING: `swift run MacDashboardChecks`,
        // an executable target (assert + exit nonzero) created when this Mac had Command Line
        // Tools only. Xcode 27 is now installed and `swift test` works, so its checks are moving
        // to the MacDashboardTests target below stage by stage; this target is deleted at the
        // last stage. Add NO new checks here. Its Checks/ sources are symlinks into
        // Sources/MacDashboard/... (see Checks/README.md).
        .executableTarget(
            name: "MacDashboardChecks",
            path: "Checks",
            exclude: ["README.md"]
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
