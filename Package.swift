// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnappyNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TouchbarPet",       targets: ["TouchbarPet"]),
        .executable(name: "Probe01TouchBar",   targets: ["Probe01TouchBar"]),
        .executable(name: "Probe02Presenter",  targets: ["Probe02Presenter"]),
        .executable(name: "Probe03Brightness", targets: ["Probe03Brightness"]),
        .executable(name: "Probe04Volume",     targets: ["Probe04Volume"]),
        .executable(name: "Probe05Media",      targets: ["Probe05Media"]),
        .library(name: "SnappyNestCore", targets: ["SnappyNestCore"]),
        .library(name: "SnappyNestUI",   targets: ["SnappyNestUI"])
    ],
    targets: [
        .target(
            name: "SnappyNestCore",
            path: "Sources/SnappyNestCore"
        ),
        .target(
            name: "SnappyNestUI",
            dependencies: ["SnappyNestCore"],
            path: "Sources/SnappyNestUI"
        ),
        .executableTarget(
            name: "TouchbarPet",
            dependencies: ["SnappyNestCore", "SnappyNestUI"],
            path: "Sources/TouchbarPet"
        ),
        .executableTarget(name: "Probe01TouchBar",   path: "Sources/Probe01TouchBar"),
        .executableTarget(name: "Probe02Presenter",  path: "Sources/Probe02Presenter"),
        .executableTarget(name: "Probe03Brightness", path: "Sources/Probe03Brightness"),
        .executableTarget(name: "Probe04Volume",     path: "Sources/Probe04Volume"),
        .executableTarget(name: "Probe05Media",      path: "Sources/Probe05Media"),
        .testTarget(
            name: "SnappyNestCoreTests",
            dependencies: ["SnappyNestCore"],
            path: "Tests/SnappyNestCoreTests"
        ),
        .testTarget(
            name: "SnappyNestUITests",
            dependencies: ["SnappyNestUI"],
            path: "Tests/SnappyNestUITests"
        )
    ]
)
