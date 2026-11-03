#if DEBUG
import Foundation

/// Sample workspace for Xcode Previews, written under the temporary directory
/// so previews never depend on the developer's home folder.
@MainActor
enum PreviewFixtures {
    static let sampleWorkspace: URL = makeSampleWorkspace()

    private static func makeSampleWorkspace() -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodeViewerPreviews", isDirectory: true)
            .appendingPathComponent("Hello", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try? fileManager.createDirectory(at: sources, withIntermediateDirectories: true)

        let files: [(URL, String)] = [
            (root.appendingPathComponent("README.md"), "# Hello\n\nPreview workspace for Code Viewer.\n"),
            (root.appendingPathComponent(".gitignore"), ".build/\n"),
            (sources.appendingPathComponent("App.swift"), """
            import SwiftUI

            @main
            struct App: App {
                var body: some Scene {
                    WindowGroup {
                        Text("Hello")
                    }
                }
            }
            """),
            (sources.appendingPathComponent("Model.swift"), """
            struct Item: Identifiable {
                let id = UUID()
            }
            """),
        ]
        for (url, contents) in files where !fileManager.fileExists(atPath: url.path) {
            try? contents.write(to: url, atomically: true, encoding: .utf8)
        }

        return root
    }
}
#endif
