// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SignalLock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SignalLock", targets: ["SignalLock"])
    ],
    targets: [
        .executableTarget(
            name: "SignalLock",
            path: "Sources/SignalLock"
        )
    ]
)
