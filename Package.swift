// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentForgeTelegramNotifier",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "AgentForgeTelegramNotifier", targets: ["AgentForgeTelegramNotifier"]),
    ],
    targets: [
        .target(name: "AgentForgeTelegramNotifier", path: "Sources/AgentForgeTelegramNotifier"),
        .executableTarget(
            name: "AgentForgeTelegramNotifierConformance",
            dependencies: ["AgentForgeTelegramNotifier"],
            path: "Sources/AgentForgeTelegramNotifierConformance"
        ),
        .testTarget(
            name: "AgentForgeTelegramNotifierTests",
            dependencies: ["AgentForgeTelegramNotifier"],
            path: "Tests/AgentForgeTelegramNotifierTests"
        ),
    ]
)
