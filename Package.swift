// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Skillface",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "skillface", targets: ["Skillface"]),
        .executable(name: "shots", targets: ["Shots"]),
    ],
    targets: [
        // Skills, apps, sessions, memory, the agent and what it's told. Foundation only: no SwiftUI,
        // so all of it runs under `swift test`.
        .target(name: "SkillfaceCore"),
        .target(name: "SkillfaceUI", dependencies: ["SkillfaceCore"]),
        .executableTarget(name: "Skillface", dependencies: ["SkillfaceUI"]),
        // Dev-only: draws every screen offscreen into PNGs, on sample data.
        .executableTarget(name: "Shots", dependencies: ["SkillfaceCore", "SkillfaceUI"]),
        .testTarget(name: "SkillfaceCoreTests", dependencies: ["SkillfaceCore"]),
    ]
)
