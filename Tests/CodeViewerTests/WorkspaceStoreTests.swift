import Foundation
import Testing
@testable import CodeViewer

// Serialized: the tests share the workspace UserDefaults key.
@Suite(.serialized)
@MainActor
struct WorkspaceStoreTests {
    private static let storageKey = "workspaceBookmarks"

    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func makeTempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("workspace identity is its standardized path")
    func identityIsPath() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let store = WorkspaceStore()

        let workspace = try #require(store.add(makeTempFolder()))

        #expect(workspace.id == workspace.url.path)
    }

    @Test("adding the same folder twice is rejected")
    func rejectsDuplicates() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let store = WorkspaceStore()

        let workspace = try #require(store.add(makeTempFolder()))

        #expect(store.add(workspace.url) == nil)
        #expect(store.workspaces.count == 1)
    }

    @Test("remove deletes exactly the given workspace")
    func removesById() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let store = WorkspaceStore()
        let workspace = try #require(store.add(makeTempFolder()))
        let other = try #require(store.add(makeTempFolder()))

        store.remove(workspace)

        #expect(!store.workspaces.contains(workspace))
        #expect(store.workspaces.contains(other))
    }

    @Test("deleted workspaces are dropped on the next launch")
    func dropsDeletedWorkspaces() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let folder = makeTempFolder()
        let store = WorkspaceStore()
        try #require(store.add(folder) != nil)

        try FileManager.default.removeItem(at: folder)

        #expect(WorkspaceStore().workspaces.isEmpty)
    }

    @Test("bookmarks survive a move and a relaunch")
    func bookmarksTrackMovedFolders() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let original = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: original) }

        let store = WorkspaceStore()
        try #require(store.add(original) != nil)

        let moved = original
            .deletingLastPathComponent()
            .appendingPathComponent(original.lastPathComponent + "-moved", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)
        defer { try? FileManager.default.removeItem(at: moved) }

        let relaunched = WorkspaceStore()

        #expect(
            relaunched.workspaces.map { $0.url.resolvingSymlinksInPath().path }
                == [moved.resolvingSymlinksInPath().path]
        )
    }
}
