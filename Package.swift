// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftTUI",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "SwiftTUI",
            targets: ["SwiftTUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.18.7"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SwiftTUI",
            dependencies: []),
        .testTarget(
            name: "SwiftTUITests",
            dependencies: [
                "SwiftTUI",
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]),
        .executableTarget(
            name: "SwiftTUIExample",
            dependencies: ["SwiftTUI"]),
    ]
)
