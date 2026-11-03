import Foundation
import Observation

struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct FileTreeRow: Identifiable {
    let node: FileNode
    let depth: Int

    var id: String { node.id }
}

/// Lazily loaded tree for one workspace. Children are fetched only when a
/// directory is expanded, and the flattened `rows` array feeds the sidebar so
/// collapsed subtrees cost nothing to render.
@MainActor
@Observable
final class FileTreeStore {
    private(set) var rootNodes: [FileNode] = []
    private(set) var childrenByDirectory: [String: [FileNode]] = [:]
    private(set) var expanded: Set<String> = []
    private(set) var loading: Set<String> = []
    private(set) var failed: Set<String> = []
    private(set) var isLoadingRoot = false
    private(set) var rootFailed = false

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let service: FileService

    init(root: URL, service: FileService = .shared) {
        self.root = root
        self.service = service
    }

    var rows: [FileTreeRow] {
        var rows: [FileTreeRow] = []
        append(rootNodes, depth: 0, into: &rows)
        return rows
    }

    func loadRoot() async {
        isLoadingRoot = true
        defer { isLoadingRoot = false }
        do {
            rootNodes = try await service.children(of: root)
            rootFailed = false
        } catch {
            Log.tree.error("Could not list \(root.path): \(error.localizedDescription)")
            rootNodes = []
            rootFailed = true
        }
    }

    func toggle(_ node: FileNode) async {
        guard node.isDirectory else { return }
        if expanded.contains(node.id) {
            expanded.remove(node.id)
            return
        }
        expanded.insert(node.id)
        guard childrenByDirectory[node.id] == nil else { return }
        await loadChildren(of: node)
    }

    /// Re-lists the root and every directory that has been loaded before, so a
    /// refresh does not collapse the tree.
    func reload() async {
        let loadedDirectories = Array(childrenByDirectory.keys)
        await loadRoot()

        var refreshed: [String: [FileNode]] = [:]
        var failures: Set<String> = []
        for path in loadedDirectories {
            do {
                refreshed[path] = try await service.children(of: URL(fileURLWithPath: path))
            } catch {
                failures.insert(path)
                Log.tree.error("Could not refresh \(path): \(error.localizedDescription)")
            }
        }
        childrenByDirectory = refreshed
        failed = failures

        let visibleDirectories = Set(
            (rootNodes + refreshed.values.flatMap { $0 })
                .filter(\.isDirectory)
                .map(\.id)
        )
        expanded.formIntersection(visibleDirectories)
    }

    private func loadChildren(of node: FileNode) async {
        loading.insert(node.id)
        defer { loading.remove(node.id) }
        do {
            childrenByDirectory[node.id] = try await service.children(of: node.url)
            failed.remove(node.id)
        } catch {
            Log.tree.error("Could not list \(node.url.path): \(error.localizedDescription)")
            failed.insert(node.id)
        }
    }

    private func append(_ nodes: [FileNode], depth: Int, into rows: inout [FileTreeRow]) {
        for node in nodes {
            rows.append(FileTreeRow(node: node, depth: depth))
            if node.isDirectory, expanded.contains(node.id),
               let children = childrenByDirectory[node.id] {
                append(children, depth: depth + 1, into: &rows)
            }
        }
    }
}
