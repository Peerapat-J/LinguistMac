// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LinguistMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "LinguistMac",
            targets: ["LinguistMac"]
        ),
        .library(
            name: "LinguistMacCore",
            targets: ["LinguistMacCore"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LinguistMac",
            dependencies: ["LinguistMacCore"],
            path: "Sources/LinguistMac"
        ),
        .target(
            name: "LinguistMacCore",
            path: "Sources/LinguistMacCore"
        ),
        .testTarget(
            name: "LinguistMacCoreTests",
            dependencies: ["LinguistMacCore"],
            path: "Tests/LinguistMacCoreTests"
        )
    ]
)
