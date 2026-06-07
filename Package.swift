// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicPin",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "MicPinCore"),
        .executableTarget(
            name: "MicPin",
            dependencies: ["MicPinCore"]
        ),
        .testTarget(
            name: "MicPinCoreTests",
            dependencies: ["MicPinCore"]
        ),
    ]
)
