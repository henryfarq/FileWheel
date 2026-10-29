// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileWheel",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FileWheelCore"),
        .executableTarget(name: "FileWheel", dependencies: ["FileWheelCore"]),
        .testTarget(name: "FileWheelCoreTests", dependencies: ["FileWheelCore"]),
    ],
    swiftLanguageModes: [.v5]
)
