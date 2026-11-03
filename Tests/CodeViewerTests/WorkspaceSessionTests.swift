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

        #expect(session.tabs.map(\.url) == [first.url, second.url])
        #expect(session.selectedTab?.url == second.url)
        #expect(session.tabs[0].document !== session.tabs[1].document)
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

        #expect(session.tabs.map(\.url) == [second.url])
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
        let firstStore = session.tabs[0].document
        session.close(session.tabs[0])
        session.open(file)

        #expect(session.tabs.count == 1)
        #expect(session.tabs[0].document !== firstStore)
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
            if case .image = tab.document.state { return true } else { return false }
        }

        guard case .image(let document) = tab.document.state else {
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
        guard let tab = session.selectedTab else {
            Issue.record("expected a selected tab")
            return
        }
        try await waitUntil {
            if case .image = tab.document.state { return true } else { return false }
        }
        let revisionAfterOpen = tab.document.revision

        // Append one byte so the size check in `reloadIfChanged` always trips,
        // regardless of mtime precision.
        _ = try makeImageNode("logo.png", in: root, appending: [Data([0x00])])
        tab.document.reloadIfChanged()

        #expect(tab.document.revision == revisionAfterOpen + 1)
        try await waitUntil {
            if case .image = tab.document.state { return true } else { return false }
        }
    }
}
