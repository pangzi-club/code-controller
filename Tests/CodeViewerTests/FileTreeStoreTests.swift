import Foundation
import Testing
@testable import CodeViewer

@MainActor
struct FileTreeStoreTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTreeStoreTests-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "swift".write(
            to: sources.appendingPathComponent("App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "# Readme".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    @Test("children are loaded only when a directory is expanded")
    func expandsLazily() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileTreeStore(root: root)

        await store.loadRoot()
        #expect(store.rows.map(\.node.name) == ["Sources", "README.md"])

        let sources = try #require(store.rootNodes.first { $0.isDirectory })
        #expect(store.childrenByDirectory[sources.id] == nil)

        await store.toggle(sources)
        #expect(store.rows.map(\.node.name) == ["Sources", "App.swift", "README.md"])
        #expect(store.childrenByDirectory[sources.id]?.map(\.name) == ["App.swift"])

        await store.toggle(sources)
        #expect(store.rows.map(\.node.name) == ["Sources", "README.md"])
    }

    @Test("reload keeps the expansion state and sees new files")
    func reloadKeepsExpansion() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileTreeStore(root: root)

        await store.loadRoot()
        let sources = try #require(store.rootNodes.first { $0.isDirectory })
        await store.toggle(sources)

        try "new".write(
            to: sources.url.appendingPathComponent("Model.swift"),
            atomically: true,
            encoding: .utf8
        )
        await store.reload()

        #expect(store.expanded.contains(sources.id))
        #expect(store.rows.map(\.node.name) == ["Sources", "App.swift", "Model.swift", "README.md"])
    }
}
