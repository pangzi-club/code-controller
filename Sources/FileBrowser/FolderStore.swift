import Foundation

/// A folder shown in the sidebar.
struct Folder: Identifiable, Hashable {
    let id: UUID
    let url: URL

    var name: String { url.lastPathComponent }
}

/// Manages the sidebar folder list and persists it to UserDefaults.
@MainActor
final class FolderStore: ObservableObject {
    @Published private(set) var folders: [Folder] {
        didSet { UserDefaults.standard.set(folders.map(\.url.path), forKey: Self.storageKey) }
    }

    private static let storageKey = "FileBrowser.folderPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        let fileManager = FileManager.default
        // Drop folders that were moved or deleted since the last launch.
        folders = paths
            .map { Folder(id: UUID(), url: URL(fileURLWithPath: $0)) }
            .filter { fileManager.fileExists(atPath: $0.url.path) }
    }

    @discardableResult
    func add(_ url: URL) -> Folder? {
        let standardized = url.standardizedFileURL
        guard !folders.contains(where: { $0.url.standardizedFileURL == standardized }) else { return nil }
        let folder = Folder(id: UUID(), url: url)
        folders.append(folder)
        return folder
    }

    func remove(_ folder: Folder) {
        folders.removeAll { $0.id == folder.id }
    }
}
