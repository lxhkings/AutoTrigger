// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoTriggerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AutoTriggerCore", targets: ["AutoTriggerCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.11.0"),
    ],
    targets: [
        .target(name: "AutoTriggerCore"),
        .testTarget(name: "AutoTriggerCoreTests", dependencies: [
            "AutoTriggerCore",
            .product(name: "Testing", package: "swift-testing"),
        ])
    ]
)
