// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yonka",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "yonka", targets: ["Yonka"]),
        .executable(name: "shots", targets: ["Shots"]),
    ],
    targets: [
        // Skills, apps, sessions, memory, the agent and what it's told. Foundation only: no SwiftUI,
        // so all of it runs under `swift test`.
        .target(name: "YonkaCore"),
        .target(name: "YonkaUI", dependencies: ["YonkaCore"]),
        .executableTarget(name: "Yonka", dependencies: ["YonkaUI"]),
        // Dev-only: draws every screen offscreen into PNGs, on sample data.
        .executableTarget(name: "Shots", dependencies: ["YonkaCore", "YonkaUI"]),
        .testTarget(name: "YonkaCoreTests", dependencies: ["YonkaCore"]),
    ]
)
