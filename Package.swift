// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CodeViewer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The library carries all app code so the test target can import it;
        // the executable below is a thin @main wrapper.
        .library(name: "CodeViewer", targets: ["CodeViewer"]),
    ],
    dependencies: [
        // Markdown parsing (CommonMark + GFM) for the preview tab. Only the
        // parser comes from here; rendering is the app's own SwiftUI.
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "CodeViewer",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/CodeViewer",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "CodeViewerApp",
            dependencies: ["CodeViewer"],
            path: "Sources/CodeViewerApp"
        ),
        .testTarget(
            name: "CodeViewerTests",
            dependencies: [.target(name: "CodeViewer")],
            path: "Tests/CodeViewerTests"
        )
    ]
)
