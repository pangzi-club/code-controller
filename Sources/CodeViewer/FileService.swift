import AppKit
import Foundation

enum FileServiceError: Error {
    case notAFile
}

struct TextDocument: Sendable, Equatable {
    let text: String
    let encoding: String.Encoding
    let byteSize: Int
    /// Modification time at read; the store compares it on watcher events
    /// to decide whether a reload is worth doing.
    let modificationDate: Date?
}

/// A previewable image file. NSImage is documented thread-safe, so the
/// FileService actor can build one off the main thread; identity equality is
/// enough because each read decodes a fresh instance.
struct ImageDocument: @unchecked Sendable, Equatable {
    let image: NSImage
    let byteSize: Int
    let modificationDate: Date?

    static func == (lhs: ImageDocument, rhs: ImageDocument) -> Bool {
        lhs.image === rhs.image
            && lhs.byteSize == rhs.byteSize
            && lhs.modificationDate == rhs.modificationDate
    }
}

enum DocumentContent: Sendable, Equatable {
    case text(TextDocument)
    case image(ImageDocument)
    case binary
    case tooLarge(byteSize: Int64)
}

/// Decodes file bytes into text, or reports that they look binary.
enum TextDecoder {
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LittleEndianBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BigEndianBOM: [UInt8] = [0xFE, 0xFF]
    private static let binaryProbeLength = 8_000

    /// Returns nil for content that should not be shown in a text view.
    static func decode(_ data: Data) -> (text: String, encoding: String.Encoding)? {
        if data.isEmpty { return ("", .utf8) }

        if data.starts(with: utf8BOM) {
            guard let text = String(data: data.dropFirst(utf8BOM.count), encoding: .utf8) else {
                return nil
            }
            return (normalizeLineEndings(text), .utf8)
        }
        if data.starts(with: utf16LittleEndianBOM) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
                return nil
            }
            return (normalizeLineEndings(text), .utf16LittleEndian)
        }
        if data.starts(with: utf16BigEndianBOM) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
                return nil
            }
            return (normalizeLineEndings(text), .utf16BigEndian)
        }

        // A NUL byte in the probe range means binary. UTF-16 without a BOM is
        // deliberately treated as binary until the encoding detection pass.
        if data.prefix(binaryProbeLength).contains(0) { return nil }

        if let text = String(data: data, encoding: .utf8) {
            return (normalizeLineEndings(text), .utf8)
        }
        if let text = String(data: data, encoding: .windowsCP1252) {
            return (normalizeLineEndings(text), .windowsCP1252)
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return (normalizeLineEndings(text), .isoLatin1)
        }
        return nil
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

/// Reads directory listings and file contents off the main thread. The actor
/// serializes disk access; callers cancel stale loads themselves.
actor FileService {
    static let shared = FileService()
    static let defaultMaximumTextFileSize: Int64 = 10 * 1024 * 1024

    private static let skippedDirectoryNames: Set<String> = [".git"]

    /// Extensions that open as an image preview instead of a text view.
    /// Corrupted files in these formats still fall through to the binary
    /// verdict, so the failure path stays the existing one.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "heif",
        "tiff", "tif", "bmp", "avif",
    ]

    private let maximumTextFileSize: Int64

    init(maximumTextFileSize: Int64 = FileService.defaultMaximumTextFileSize) {
        self.maximumTextFileSize = maximumTextFileSize
    }

    /// Lists one directory level. Dot-files stay visible — `.gitignore` and
    /// friends are part of a code workspace — but VCS metadata directories and
    /// Finder noise are skipped. Symlinked directories are reported as files
    /// so the tree cannot follow a cycle.
    func children(of directory: URL) throws -> [FileNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        var nodes: [FileNode] = []
        nodes.reserveCapacity(urls.count)
        for url in urls {
            let name = url.lastPathComponent
            if name == ".DS_Store" { continue }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isSymbolicLink = values.isSymbolicLink ?? false
            let isDirectory = (values.isDirectory ?? false) && !isSymbolicLink
            if isDirectory && Self.skippedDirectoryNames.contains(name) { continue }
            nodes.append(FileNode(url: url, isDirectory: isDirectory))
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Recursively lists every file under `root`, directories excluded. Same
    /// skip rules as `children(of:)` — `.git` and `.DS_Store` go, other
    /// dot-files stay, symlinked directories are never followed (they surface
    /// as files and cannot start a cycle). Depth-first, so the order mirrors
    /// the expanded tree. Throws `CancellationError` through when the caller's
    /// task is cancelled between directories.
    func allFiles(under root: URL) throws -> [FileNode] {
        var files: [FileNode] = []
        try appendFiles(under: root, into: &files)
        return files
    }

    private func appendFiles(under directory: URL, into files: inout [FileNode]) throws {
        guard !Task.isCancelled else { throw CancellationError() }
        for node in try children(of: directory) {
            if node.isDirectory {
                try appendFiles(under: node.url, into: &files)
            } else {
                files.append(node)
            }
        }
    }

    func readDocument(at url: URL) throws -> DocumentContent {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey]
        )
        guard values.isRegularFile == true else { throw FileServiceError.notAFile }

        let size = Int64(values.fileSize ?? 0)
        guard size <= maximumTextFileSize else { return .tooLarge(byteSize: size) }

        if Self.imageExtensions.contains(url.pathExtension.lowercased()),
           let image = NSImage(contentsOf: url) {
            return .image(ImageDocument(
                image: image,
                byteSize: Int(size),
                modificationDate: values.contentModificationDate
            ))
        }

        let data = try Data(contentsOf: url)
        guard let decoded = TextDecoder.decode(data) else { return .binary }
        return .text(TextDocument(
            text: decoded.text,
            encoding: decoded.encoding,
            byteSize: data.count,
            modificationDate: values.contentModificationDate
        ))
    }
}
