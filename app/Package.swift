// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WinRunner",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "WinRunner",
            path: "Sources/WinRunner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
