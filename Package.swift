// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TurtlePod",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "TurtlePodCore", targets: ["TurtlePodCore"]),
        .executable(name: "TurtlePodApp", targets: ["TurtlePodApp"])
    ],
    targets: [
        .target(
            name: "TurtlePodCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TurtlePodApp",
            dependencies: ["TurtlePodCore"]
        ),
        .testTarget(
            name: "TurtlePodCoreTests",
            dependencies: ["TurtlePodCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
