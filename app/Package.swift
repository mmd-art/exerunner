// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExeRunner",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ExeRunner",
            path: "Sources/ExeRunner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
