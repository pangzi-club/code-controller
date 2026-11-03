import Foundation
import Observation

/// A folder opened in the viewer. The path doubles as the identity so a
/// session survives switching workspaces and, later, relaunches.
struct Workspace: Identifiable, Hashable, Sendable {
    let url: URL

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// Manages the workspace list and persists it to UserDefaults.
///
/// A plain path is not enough for a sandboxed build: each entry stores an
/// app-scoped security bookmark, resolved on launch. The security scope stays
/// open while the workspace is listed, so reading the tree and its files keeps
/// working. Local builds are unsandboxed but use the same bookmarks.
@MainActor
@Observable
final class WorkspaceStore {
    private(set) var workspaces: [Workspace] = []

    private struct StoredWorkspace: Codable {
        var path: String
        var bookmark: Data?
    }

    private static let storageKey = "workspaceBookmarks"

    @ObservationIgnored private var scopedURLs: Set<URL> = []

    init() {
        for entry in Self.loadStoredWorkspaces() {
            guard let url = Self.resolve(entry) else { continue }
            // Start the scope before checking readability: the sandbox only
            // grants access to a bookmarked folder once its scope is active.
            let scoped = url.startAccessingSecurityScopedResource()
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                Log.files.error("Dropping unreadable workspace \(entry.path)")
                continue
            }
            if scoped { scopedURLs.insert(url) }
            workspaces.append(Workspace(url: url))
        }
    }

    deinit {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    @discardableResult
    func add(_ url: URL) -> Workspace? {
        let standardized = url.standardizedFileURL
        guard !workspaces.contains(where: { $0.url.standardizedFileURL == standardized }) else {
            return nil
        }
        if url.startAccessingSecurityScopedResource() {
            scopedURLs.insert(url)
        }
        let workspace = Workspace(url: url)
        workspaces.append(workspace)
        persist()
        Log.files.notice("Add workspace \(url.path)")
        return workspace
    }

    func remove(_ workspace: Workspace) {
        if let url = workspaces.first(where: { $0.id == workspace.id })?.url,
           scopedURLs.remove(url) != nil {
            url.stopAccessingSecurityScopedResource()
        }
        workspaces.removeAll { $0.id == workspace.id }
        persist()
        Log.files.notice("Remove workspace \(workspace.url.path)")
    }

    private func persist() {
        let stored = workspaces.map { workspace -> StoredWorkspace in
            StoredWorkspace(
                path: workspace.url.path,
                bookmark: try? workspace.url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            )
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadStoredWorkspaces() -> [StoredWorkspace] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([StoredWorkspace].self, from: data) else {
            return []
        }
        return stored
    }

    private static func resolve(_ entry: StoredWorkspace) -> URL? {
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
        // Inside the sandbox that path only works when it is still reachable;
        // stale entries are dropped like any other deleted folder.
        let url = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
