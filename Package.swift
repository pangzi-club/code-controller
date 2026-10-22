// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileBrowser",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FileBrowser",
            path: "Sources/FileBrowser",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
