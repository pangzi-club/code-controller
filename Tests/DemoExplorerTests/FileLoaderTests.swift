import Foundation
import Testing
@testable import DemoExplorer

struct FileLoaderTests {
    /// Makes a temp folder populated with a fixed set of entries.
    private func makeSampleFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoExplorerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Zeta"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("alpha"), withIntermediateDirectories: true)
        try "hidden".write(to: root.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        try "ten-bytes!".data(using: .utf8)!.write(to: root.appendingPathComponent("10.txt"))
        try "two".data(using: .utf8)!.write(to: root.appendingPathComponent("2.txt"))
        try "one".data(using: .utf8)!.write(to: root.appendingPathComponent("1.txt"))
        return root
    }

    @Test("directories come first, then files in localized numeric order; dot-files hidden")
    func loadSortsAndHides() throws {
        let folder = try makeSampleFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let items = try #require(FileLoader.load(from: folder))

        #expect(items.map(\.name) == ["alpha", "Zeta", "1.txt", "2.txt", "10.txt"])
    }

    @Test("directories have no byte size, files do")
    func loadsSizes() throws {
        let folder = try makeSampleFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let items = try #require(FileLoader.load(from: folder))
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

        #expect(byName["alpha"]?.byteSize == nil)
        #expect(byName["10.txt"]?.byteSize == 10)
        #expect(byName["10.txt"]?.isDirectory == false)
        #expect(byName["10.txt"]?.modificationDate != nil)
    }

    @Test("a missing folder yields nil")
    func missingFolderYieldsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoExplorerTests-missing-\(UUID().uuidString)")
        #expect(FileLoader.load(from: missing) == nil)
    }

    @Test("id is the path, so the same file is stable across reloads")
    func idIsStable() throws {
        let folder = try makeSampleFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try #require(FileLoader.load(from: folder))
        let second = try #require(FileLoader.load(from: folder))
        #expect(first.map(\.id) == second.map(\.id))
    }
}
