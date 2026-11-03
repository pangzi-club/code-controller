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
        // Syntax highlighting (highlight.js). Hidden behind the
        // `SyntaxHighlighter` protocol so it can be replaced by tree-sitter.
        .package(url: "https://github.com/smittytone/HighlighterSwift", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "CodeViewer",
            dependencies: [
                .product(name: "Highlighter", package: "HighlighterSwift"),
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
