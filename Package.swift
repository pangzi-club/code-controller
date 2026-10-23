// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DemoExplorer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The library carries all app code; the executable below is a thin
        // @main wrapper. This split is what makes Xcode Previews work —
        // previews need a library product, not a command-line tool.
        .library(name: "DemoExplorer", targets: ["DemoExplorer"]),
    ],
    targets: [
        .target(
            name: "DemoExplorer",
            path: "Sources/DemoExplorer",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "DemoExplorerApp",
            dependencies: ["DemoExplorer"],
            path: "Sources/DemoExplorerApp"
        ),
        .testTarget(
            name: "DemoExplorerTests",
            dependencies: [.target(name: "DemoExplorer")],
            path: "Tests/DemoExplorerTests"
        )
    ]
)
