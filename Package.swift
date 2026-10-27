// swift-tools-version: 6.2
// Package.swift — scaffold owns this file (SPEC §3). Tools-version 6.2 is the first whose
// PackageDescription has `.v26`; it ships with Xcode 26, the minimum Xcode the README and
// .github/actions/select-xcode already require. Swift 5 language mode is set explicitly
// (`swiftLanguageModes` below): tools-version 6.x would otherwise default to Swift 6 mode
// and its strict-concurrency errors.
import PackageDescription

let package = Package(
    name: "MacDashboard",
    platforms: [
        // MIN-MACOS-26: keep in step with MIN_MACOS in build_app.sh (the release build's target).
        .macOS(.v26)
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
    ],
    swiftLanguageModes: [.v5]
)
