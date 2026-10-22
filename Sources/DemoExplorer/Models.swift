import AppKit
import Foundation

/// A row in the file list.
struct FileItem: Identifiable {
    let url: URL
    let isDirectory: Bool
    let byteSize: Int64?
    let modificationDate: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

enum FileLoader {
    /// Reads the direct children of a folder: directories first, then by name;
    /// dot-files are hidden.
    static func load(from folder: URL) -> [FileItem]? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        ) else { return nil }

        let items = entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { url -> FileItem? in
                guard let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
                ) else { return nil }
                return FileItem(
                    url: url,
                    isDirectory: values.isDirectory ?? false,
                    byteSize: values.isDirectory == true ? nil : Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate
                )
            }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

enum FileOpener {
    /// Opens with the system default app.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Reveals and selects the item in Finder.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum FolderPicker {
    @MainActor
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.message = l10nString("Choose a folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
