import Foundation
import Testing
@testable import CodeViewer

@MainActor
struct WorkspaceSessionTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeNode(_ name: String, in root: URL) throws -> FileNode {
        let url = root.appendingPathComponent(name)
        try "// \(name)".write(to: url, atomically: true, encoding: .utf8)
        return FileNode(url: url, isDirectory: false)
    }

    private func makeImageNode(_ name: String, in root: URL, appending: [Data] = []) throws -> FileNode {
        let url = root.appendingPathComponent(name)
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
                + "AAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))
        try (png + appending.reduce(Data(), +)).write(to: url)
        return FileNode(url: url, isDirectory: false)
    }

    private func documentStore(_ tab: DocumentTab) -> DocumentStore? {
        guard case .file(_, let store) = tab.content else { return nil }
        return store
    }

    private func commit(_ hash: String) -> GitCommit {
        GitCommit(hash: hash, subject: "commit \(hash)", authorName: "tester", date: nil, refName: nil)
    }

    /// The document load lands on the main actor asynchronously; suspend so
    /// it can run instead of racing it.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 where !condition() {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(condition())
    }

    @Test("opening the same file focuses its existing tab")
    func opensSingleTabPerFile() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))
        let file = try makeNode("App.swift", in: root)

        session.open(file)
        session.open(file)

        #expect(session.tabs.count == 1)
        #expect(session.selectedTab?.url == file.url)
    }

    @Test("opening another file appends and selects a new tab")
    func appendsTabs() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))
        let first = try makeNode("A.swift", in: root)
        let second = try makeNode("B.swift", in: root)

        session.open(first)
        session.open(second)

        #expect(session.tabs.compactMap(\.url) == [first.url, second.url])
        #expect(session.selectedTab?.url == second.url)
        #expect(documentStore(session.tabs[0]) !== documentStore(session.tabs[1]))
    }

    @Test("closing the selected tab selects its neighbor")
    func closingSelectsNeighbor() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))
        let first = try makeNode("A.swift", in: root)
        let second = try makeNode("B.swift", in: root)

        session.open(first)
        session.open(second)
        session.select(session.tabs[0])
        session.close(session.tabs[0])

        #expect(session.tabs.compactMap(\.url) == [second.url])
        #expect(session.selectedTab?.url == second.url)

        session.close(session.tabs[0])

        #expect(session.tabs.isEmpty)
        #expect(session.selectedTab == nil)
    }

    @Test("reopening a closed file creates a fresh document store")
    func reopensWithFreshStore() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))
        let file = try makeNode("App.swift", in: root)

        session.open(file)
        let firstStore = documentStore(session.tabs[0])
        session.close(session.tabs[0])
        session.open(file)

        #expect(session.tabs.count == 1)
        #expect(documentStore(session.tabs[0]) !== firstStore)
    }

    @Test("image files open into an image state")
    func opensImageDocuments() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))
        let file = try makeImageNode("logo.png", in: root)

        session.open(file)
        guard let tab = session.selectedTab else {
            Issue.record("expected a selected tab")
            return
        }
        try await waitUntil {
            if case .image = documentStore(tab)?.state { return true } else { return false }
        }

        guard case .image(let document) = documentStore(tab)?.state else {
            Issue.record("expected image state")
            return
        }
        #expect(document.image.size.width > 0)
    }

    @Test("image tabs reload when the file changes on disk")
    func reloadsChangedImages() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))
        let file = try makeImageNode("logo.png", in: root)

        session.open(file)
        guard let tab = session.selectedTab, let store = documentStore(tab) else {
            Issue.record("expected a selected file tab")
            return
        }
        try await waitUntil {
            if case .image = store.state { return true } else { return false }
        }
        let revisionAfterOpen = store.revision

        // Append one byte so the size check in `reloadIfChanged` always trips,
        // regardless of mtime precision.
        _ = try makeImageNode("logo.png", in: root, appending: [Data([0x00])])
        store.reloadIfChanged()

        #expect(store.revision == revisionAfterOpen + 1)
        try await waitUntil {
            if case .image = store.state { return true } else { return false }
        }
    }

    // MARK: Commit diff tabs

    @Test("opening a commit diff creates one namespaced tab and selects it")
    func opensCommitDiffTab() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))

        session.openDiff(commit: commit("abc123"))

        #expect(session.tabs.count == 1)
        #expect(session.selectedTab?.id == "diff:commit:abc123")
        #expect(session.selectedTab?.name == "commit abc123")
        guard case .commitDiff(let document) = session.selectedTab?.content else {
            Issue.record("expected a commit diff tab")
            return
        }
        #expect(document.commit.hash == "abc123")
    }

    @Test("opening the same commit focuses the existing tab; other commits append")
    func dedupesCommitDiffTabs() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))

        session.openDiff(commit: commit("abc123"))
        session.openDiff(commit: commit("abc123"))

        #expect(session.tabs.count == 1)
        #expect(session.selectedTab?.id == "diff:commit:abc123")

        session.openDiff(commit: commit("def456"))

        #expect(session.tabs.count == 2)
        #expect(session.selectedTab?.id == "diff:commit:def456")
    }

    @Test("a commit diff tab can be closed like a file tab")
    func closesCommitDiffTab() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(workspace: Workspace(url: root))
        let file = try makeNode("A.swift", in: root)

        session.open(file)
        session.openDiff(commit: commit("abc123"))
        session.close(session.selectedTab!)

        #expect(session.tabs.count == 1)
        #expect(session.selectedTab?.id == "file:" + file.url.path)
    }
}
