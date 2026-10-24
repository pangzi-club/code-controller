import Foundation
import Testing
@testable import DemoExplorer

// Serialized: the tests share the `folderPaths` UserDefaults key.
@Suite(.serialized)
@MainActor
struct FolderStoreTests {
    private func makeTempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("adding the same folder twice is rejected")
    func rejectsDuplicates() throws {
        let store = FolderStore()
        let before = store.folders.count

        let folder = try #require(store.add(makeTempFolder()))

        #expect(store.add(folder.url) == nil)
        #expect(store.folders.count == before + 1)
    }

    @Test("remove deletes exactly the given folder")
    func removesById() throws {
        let store = FolderStore()
        let folder = try #require(store.add(makeTempFolder()))
        let other = try #require(store.add(makeTempFolder()))

        store.remove(folder)

        #expect(!store.folders.contains(folder))
        #expect(store.folders.contains(other))
    }

    @Test("persisted paths that no longer exist are dropped on init")
    func dropsStalePaths() throws {
        let live = makeTempFolder()
        UserDefaults.standard.set(
            [live.path, "/nonexistent/FolderStoreTests-\(UUID().uuidString)"],
            forKey: "folderPaths"
        )
        defer { UserDefaults.standard.removeObject(forKey: "folderPaths") }

        let store = FolderStore()

        #expect(store.folders.map(\.url.path) == [live.path])
        try? FileManager.default.removeItem(at: live)
    }
}
