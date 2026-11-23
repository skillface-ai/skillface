// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yokan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "yokan", targets: ["Yokan"]),
        .executable(name: "shots", targets: ["Shots"]),
    ],
    targets: [
        // Skills, apps, sessions, memory, the agent and what it's told. Foundation only: no SwiftUI,
        // so all of it runs under `swift test`.
        .target(name: "YokanCore"),
        .target(name: "YokanUI", dependencies: ["YokanCore"]),
        .executableTarget(name: "Yokan", dependencies: ["YokanUI"]),
        // Dev-only: draws every screen offscreen into PNGs, on sample data.
        .executableTarget(name: "Shots", dependencies: ["YokanCore", "YokanUI"]),
        .testTarget(name: "YokanCoreTests", dependencies: ["YokanCore"]),
    ]
)
