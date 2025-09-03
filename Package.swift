// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dmgTweakApp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "dmgTweakApp",
            targets: ["dmgTweakApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "dmgTweakApp",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
