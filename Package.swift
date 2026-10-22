// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DemoExplorer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DemoExplorer",
            path: "Sources/DemoExplorer",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DemoExplorerTests",
            dependencies: [.target(name: "DemoExplorer")],
            path: "Tests/DemoExplorerTests"
        )
    ]
)
