// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "T3Bar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "T3Bar", targets: ["T3Bar"]),
    ],
    targets: [
        // Foundation-only (plus `os` for locks and logging, `Observation` for the settings store) so every piece of
        // domain logic stays unit-testable without AppKit.
        .target(name: "T3BarCore"),
        .executableTarget(name: "T3Bar", dependencies: ["T3BarCore"]),
        .testTarget(name: "T3BarCoreTests", dependencies: ["T3BarCore"]),
    ]
)
