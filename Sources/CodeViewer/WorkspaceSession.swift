import Foundation
import Observation

/// Per-workspace UI state: tree expansion, open tabs and the selected tab.
/// Sessions live for the lifetime of the app, so switching workspaces keeps
/// both the tree and the tab strip intact.
@MainActor
@Observable
final class WorkspaceSession {
    let workspace: Workspace
    let tree: FileTreeStore
    private(set) var tabs: [DocumentTab] = []
    private(set) var selectedTabID: DocumentTab.ID?

    private let service: FileService

    @ObservationIgnored private var hasLoadedTree = false

    init(workspace: Workspace, service: FileService = .shared) {
        self.workspace = workspace
        self.service = service
        tree = FileTreeStore(root: workspace.url, service: service)
    }

    var selectedTab: DocumentTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var selectedURL: URL? {
        selectedTab?.url
    }

    func loadIfNeeded() async {
        guard !hasLoadedTree else { return }
        hasLoadedTree = true
        await tree.loadRoot()
    }

    func open(_ node: FileNode) {
        guard !node.isDirectory else { return }

        if let existing = tabs.first(where: { $0.url == node.url }) {
            selectedTabID = existing.id
            return
        }

        let tab = DocumentTab(url: node.url, service: service)
        tabs.append(tab)
        selectedTabID = tab.id
        tab.document.open(url: node.url)
        Log.editor.notice("Open tab \(node.url.path)")
    }

    func select(_ tab: DocumentTab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        selectedTabID = tab.id
    }

    func close(_ tab: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let wasSelected = selectedTabID == tab.id
        tabs.remove(at: index)
        guard wasSelected else { return }

        // Prefer the tab that slid into this position, else the new last tab.
        if tabs.indices.contains(index) {
            selectedTabID = tabs[index].id
        } else {
            selectedTabID = tabs.last?.id
        }
    }

    func reloadSelectedDocument() {
        selectedTab?.document.reload()
    }
}

@MainActor
final class WorkspaceSessions {
    private var sessions: [Workspace.ID: WorkspaceSession] = [:]

    func session(for workspace: Workspace) -> WorkspaceSession {
        if let existing = sessions[workspace.id] { return existing }
        let session = WorkspaceSession(workspace: workspace)
        sessions[workspace.id] = session
        return session
    }

    func remove(_ workspace: Workspace) {
        sessions.removeValue(forKey: workspace.id)
    }
}
