import Foundation
import Testing
@testable import DemoExplorer

// Serialized: the tests share the folder UserDefaults keys.
@Suite(.serialized)
@MainActor
struct FolderStoreTests {
    private static let bookmarksKey = "folderBookmarks"
    private static let pathsKey = "folderPaths"

    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarksKey)
        UserDefaults.standard.removeObject(forKey: Self.pathsKey)
    }

    private func makeTempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("adding the same folder twice is rejected")
    func rejectsDuplicates() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let store = FolderStore()

        let folder = try #require(store.add(makeTempFolder()))

        #expect(store.add(folder.url) == nil)
        #expect(store.folders.count == 1)
    }

    @Test("remove deletes exactly the given folder")
    func removesById() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let store = FolderStore()
        let folder = try #require(store.add(makeTempFolder()))
        let other = try #require(store.add(makeTempFolder()))

        store.remove(folder)

        #expect(!store.folders.contains(folder))
        #expect(store.folders.contains(other))
    }

    @Test("legacy paths that no longer exist are dropped on init")
    func dropsStalePaths() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let live = makeTempFolder()
        UserDefaults.standard.set(
            [live.path, "/nonexistent/FolderStoreTests-\(UUID().uuidString)"],
            forKey: Self.pathsKey
        )

        let store = FolderStore()

        #expect(store.folders.map(\.url.path) == [live.path])
        try? FileManager.default.removeItem(at: live)
    }

    @Test("bookmarks survive a move and a relaunch")
    func bookmarksTrackMovedFolders() throws {
        cleanDefaults()
        defer { cleanDefaults() }
        let original = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: original) }

        let store = FolderStore()
        try #require(store.add(original) != nil)

        let moved = original
            .deletingLastPathComponent()
            .appendingPathComponent(original.lastPathComponent + "-moved", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)
        defer { try? FileManager.default.removeItem(at: moved) }

        let relaunched = FolderStore()

        #expect(
            relaunched.folders.map { $0.url.resolvingSymlinksInPath().path }
                == [moved.resolvingSymlinksInPath().path]
        )
    }
}
