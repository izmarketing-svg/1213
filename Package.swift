// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchWork",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotchWork", targets: ["NotchWork"])],
    targets: [
        .executableTarget(name: "NotchWork"),
        .testTarget(name: "NotchWorkTests", dependencies: ["NotchWork"])
    ]
)
