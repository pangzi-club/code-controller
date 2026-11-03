import Foundation

/// A folder shown in the sidebar.
struct Folder: Identifiable, Hashable {
    let id: UUID
    let url: URL

    var name: String { url.lastPathComponent }
}

/// Manages the sidebar folder list and persists it to UserDefaults.
///
/// The App Store build is sandboxed, so a plain path is not enough after
/// relaunch: each entry stores an app-scoped security bookmark, resolved on
/// launch. The security scope stays open while the folder is listed, so
/// loading its children and opening its files keeps working. Local builds are
/// unsandboxed but use the same bookmarks.
@MainActor
final class FolderStore: ObservableObject {
    @Published private(set) var folders: [Folder] {
        didSet { persist() }
    }

    private struct StoredFolder: Codable {
        var path: String
        var bookmark: Data?
    }

    private static let storageKey = "folderBookmarks"

    /// Folders saved by older builds (and by `swift run`) had no bookmarks.
    private static let legacyStorageKey = "folderPaths"

    private var scopedURLs: Set<URL> = []

    init() {
        let stored = Self.loadStoredFolders()
        var restored: [Folder] = []
        for entry in stored {
            guard let url = Self.resolve(entry) else { continue }
            // Start the scope before checking readability: the sandbox only
            // grants access to a bookmarked folder once its scope is active.
            let scoped = url.startAccessingSecurityScopedResource()
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                Log.files.error("Dropping unreadable folder \(entry.path)")
                continue
            }
            if scoped { scopedURLs.insert(url) }
            restored.append(Folder(id: UUID(), url: url))
        }
        folders = restored
    }

    deinit {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    @discardableResult
    func add(_ url: URL) -> Folder? {
        let standardized = url.standardizedFileURL
        guard !folders.contains(where: { $0.url.standardizedFileURL == standardized }) else { return nil }
        if url.startAccessingSecurityScopedResource() {
            scopedURLs.insert(url)
        }
        let folder = Folder(id: UUID(), url: url)
        folders.append(folder)
        Log.files.notice("Add folder \(url.path)")
        return folder
    }

    func remove(_ folder: Folder) {
        if let url = folders.first(where: { $0.id == folder.id })?.url,
           scopedURLs.remove(url) != nil {
            url.stopAccessingSecurityScopedResource()
        }
        folders.removeAll { $0.id == folder.id }
        Log.files.notice("Remove folder \(folder.url.path)")
    }

    private func persist() {
        let stored = folders.map { folder -> StoredFolder in
            StoredFolder(
                path: folder.url.path,
                bookmark: try? folder.url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            )
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadStoredFolders() -> [StoredFolder] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([StoredFolder].self, from: data) {
            return stored
        }
        let paths = UserDefaults.standard.stringArray(forKey: legacyStorageKey) ?? []
        return paths.map { StoredFolder(path: $0, bookmark: nil) }
    }

    private static func resolve(_ entry: StoredFolder) -> URL? {
        if let bookmark = entry.bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Missing or unresolvable bookmarks fall back to the last known path.
        // Inside the sandbox (the App Store build) that path only works when
        // it is still reachable; stale entries are dropped like any other
        // deleted folder.
        let url = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
