// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "blurpy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "blurpy",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "blurpyTests",
            dependencies: ["blurpy"]
        ),
    ]
)
