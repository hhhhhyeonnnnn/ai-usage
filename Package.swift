// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AIUsage", targets: ["AIUsage"])],
    targets: [
        .executableTarget(name: "AIUsage", path: "AIUsage", exclude: ["Resources"]),
        .testTarget(name: "AIUsageTests", dependencies: ["AIUsage"], path: "Tests/AIUsageTests")
    ]
)
