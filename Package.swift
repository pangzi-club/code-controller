// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DemoExplorer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The library carries all app code so the test target can import it;
        // the executable below is a thin @main wrapper.
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
