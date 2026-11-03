import Foundation
import Testing
@testable import CodeViewer

struct FileServiceTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeOnePixelPNG() throws -> Data {
        try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
                + "AAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))
    }

    // MARK: - Children

    @Test("one level is listed with directories first; dot-files stay, .git does not")
    func listsChildren() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appendingPathComponent("Zeta"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("alpha"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        for name in [".gitignore", ".DS_Store", "2.txt", "10.txt"] {
            try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let children = try await FileService().children(of: root)
        let names = children.map(\.name)
        let twoIndex = try #require(names.firstIndex(of: "2.txt"))
        let tenIndex = try #require(names.firstIndex(of: "10.txt"))

        #expect(!names.contains(".git"))
        #expect(!names.contains(".DS_Store"))
        #expect(names.contains(".gitignore"))
        #expect(names.filter { $0 != ".gitignore" }.prefix(2) == ["alpha", "Zeta"])
        #expect(twoIndex < tenIndex)
    }

    @Test("symlinked directories are reported as files so the tree cannot cycle")
    func symlinkedDirectoryIsNotExpandable() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileManager = FileManager.default
        let target = root.appendingPathComponent("target", isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: target
        )

        let children = try await FileService().children(of: root)
        let link = try #require(children.first { $0.name == "link" })

        #expect(link.isDirectory == false)
    }

    @Test("a missing directory throws")
    func missingDirectoryThrows() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileServiceTests-missing-\(UUID().uuidString)")
        do {
            _ = try await FileService().children(of: missing)
            Issue.record("expected a listing error")
        } catch {}
    }

    // MARK: - Reading

    @Test("UTF-8 text is decoded")
    func readsUTF8() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hello.txt")
        try "hello\nworld".write(to: url, atomically: true, encoding: .utf8)

        let content = try await FileService().readDocument(at: url)
        guard case .text(let document) = content else {
            Issue.record("expected text content")
            return
        }

        #expect(document.text == "hello\nworld")
        #expect(document.encoding == .utf8)
        #expect(document.byteSize == 11)
    }

    @Test("files above the size limit are reported without being read")
    func reportsLargeFiles() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("big.txt")
        try Data(repeating: 0x61, count: 32).write(to: url)

        let content = try await FileService(maximumTextFileSize: 16).readDocument(at: url)
        guard case .tooLarge(let byteSize) = content else {
            Issue.record("expected tooLarge")
            return
        }

        #expect(byteSize == 32)
    }

    @Test("a missing file throws")
    func missingFileThrows() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileServiceTests-missing-\(UUID().uuidString).txt")
        do {
            _ = try await FileService().readDocument(at: missing)
            Issue.record("expected a read error")
        } catch {}
    }

    @Test("image files decode into image documents")
    func readsImages() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try makeOnePixelPNG()
        let url = root.appendingPathComponent("pixel.png")
        try png.write(to: url)

        let content = try await FileService().readDocument(at: url)
        guard case .image(let document) = content else {
            Issue.record("expected image content")
            return
        }

        #expect(document.image.size.width > 0)
        #expect(document.byteSize == png.count)
    }

    @Test("a corrupted image falls back to the binary verdict")
    func corruptedImageIsBinary() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // PNG signature bytes plus a NUL: NSImage rejects it and the text
        // decoder sees binary, so the existing binary message is shown.
        let url = root.appendingPathComponent("broken.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x11]).write(to: url)

        let content = try await FileService().readDocument(at: url)

        #expect(content == .binary)
    }

    @Test("an image above the size limit is reported without being read")
    func largeImageIsTooLarge() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try makeOnePixelPNG()
        let url = root.appendingPathComponent("big.png")
        try png.write(to: url)

        let content = try await FileService(maximumTextFileSize: 8).readDocument(at: url)

        #expect(content == .tooLarge(byteSize: Int64(png.count)))
    }

    // MARK: - Decoding

    @Test("UTF-8 and UTF-16 byte order marks are stripped")
    func decodesBOMs() throws {
        var utf8 = Data([0xEF, 0xBB, 0xBF])
        utf8.append(Data("hi".utf8))
        #expect(TextDecoder.decode(utf8)?.text == "hi")

        var utf16 = Data([0xFF, 0xFE])
        utf16.append(try #require("hi".data(using: .utf16LittleEndian)))
        let decoded = try #require(TextDecoder.decode(utf16))
        #expect(decoded.text == "hi")
        #expect(decoded.encoding == .utf16LittleEndian)
    }

    @Test("invalid UTF-8 falls back to Windows-1252")
    func fallsBackToWindows1252() throws {
        let decoded = try #require(TextDecoder.decode(Data([0x63, 0x61, 0x66, 0xE9])))

        #expect(decoded.text == "café")
        #expect(decoded.encoding == .windowsCP1252)
    }

    @Test("a NUL byte marks the content as binary")
    func detectsBinary() {
        #expect(TextDecoder.decode(Data([0x50, 0x4B, 0x00, 0x01])) == nil)
    }

    @Test("CRLF and CR line endings are normalized")
    func normalizesLineEndings() throws {
        let decoded = try #require(TextDecoder.decode(Data("a\r\nb\rc".utf8)))

        #expect(decoded.text == "a\nb\nc")
    }
}
