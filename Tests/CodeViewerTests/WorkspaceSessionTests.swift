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
}
