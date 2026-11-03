import Foundation
import Testing
@testable import CodeViewer

struct WorkspaceWatcherTests {
    @Test("git metadata and Finder noise are ignored")
    func filtersNoise() {
        #expect(WorkspaceWatcher.isNoise("/repo/.git"))
        #expect(WorkspaceWatcher.isNoise("/repo/.git/objects/ab/cdef"))
        #expect(WorkspaceWatcher.isNoise("/repo/somewhere/.DS_Store"))
        #expect(!WorkspaceWatcher.isNoise("/repo/Sources/main.swift"))
        #expect(!WorkspaceWatcher.isNoise("/repo/.gitignore"))
    }
}

@MainActor
struct DocumentStoreReloadTests {
    /// Waits until the store leaves the loading state (or times out).
    private func awaitLoad(_ store: DocumentStore) async {
        for _ in 0..<100 {
            if case .loading = store.state {} else { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("unchanged files do not trigger a reload")
    func skipsUnchangedFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try Data("first".utf8).write(to: url)

        let store = DocumentStore()
        store.open(url: url)
        await awaitLoad(store)
        guard case .text(let first) = store.state else {
            Issue.record("expected text state, got \(store.state)")
            return
        }
        #expect(first.text == "first")

        let revisionBefore = store.revision
        store.reloadIfChanged()

        #expect(store.revision == revisionBefore)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("changed files reload with the new content")
    func reloadsChangedFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try Data("first".utf8).write(to: url)

        let store = DocumentStore()
        store.open(url: url)
        await awaitLoad(store)

        // A different length guarantees a size change even if the
        // filesystem's mtime granularity is coarse.
        try Data("first and now much longer".utf8).write(to: url)
        store.reloadIfChanged()
        await awaitLoad(store)

        guard case .text(let updated) = store.state else {
            Issue.record("expected text state, got \(store.state)")
            return
        }
        #expect(updated.text == "first and now much longer")
        try? FileManager.default.removeItem(at: url)
    }
}
