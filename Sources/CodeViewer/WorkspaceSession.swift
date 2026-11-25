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
    let git: GitStatusStore
    private(set) var tabs: [DocumentTab] = []
    private(set) var selectedTabID: DocumentTab.ID?

    private let service: FileService

    @ObservationIgnored private var hasLoadedTree = false
    @ObservationIgnored private var watcher: WorkspaceWatcher?

    init(workspace: Workspace, service: FileService = .shared) {
        self.workspace = workspace
        self.service = service
        tree = FileTreeStore(root: workspace.url, service: service)
        git = GitStatusStore()
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
        await git.refresh(workspaceURL: workspace.url)
        await refreshLineChanges()
        startWatching()
    }

    /// Manual refresh: the tree, git statuses and the selected document.
    func refresh() async {
        await tree.reload()
        await git.refresh(workspaceURL: workspace.url)
        await refreshLineChanges()
        reloadSelectedDocument()
    }

    /// A debounced burst of file events under the workspace: the tree, git
    /// statuses and any changed open document refresh together. Commit-diff
    /// tabs are immutable history and are skipped.
    private func handleWorkspaceChange() {
        Task {
            await tree.reload()
            await git.refresh(workspaceURL: workspace.url)
            await refreshLineChanges()
            for tab in tabs {
                if case .file(_, let document) = tab.content {
                    document.reloadIfChanged()
                }
            }
        }
    }

    /// Rebuilds the editor's diff marks for the open file tabs, so a file that
    /// was edited (or just saved) shows the changed lines right away.
    private func refreshLineChanges() async {
        await git.refreshLineChanges(for: tabs.compactMap(\.url))
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let watcher = WorkspaceWatcher(root: workspace.url) { [weak self] in
            self?.handleWorkspaceChange()
        }
        watcher.start()
        self.watcher = watcher
        Log.files.notice("Watching \(workspace.url.path) for changes")
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
        if case .file(_, let document) = tab.content {
            document.open(url: node.url)
        }
        // A borrowed mark from an earlier tab would be wrong for this file, so
        // the marks are rebuilt for every open tab.
        Task { await refreshLineChanges() }
        Log.editor.notice("Open tab \(node.url.path)")
    }

    /// Opens the commit's merged diff as a tab — every changed file stacked
    /// top to bottom. Commit content is immutable, so the tab loads once;
    /// clicking the same commit again focuses the existing tab.
    func openDiff(commit: GitCommit) {
        let tab = DocumentTab(commit: commit)
        if let existing = tabs.first(where: { $0.id == tab.id }) {
            selectedTabID = existing.id
            return
        }
        tabs.append(tab)
        selectedTabID = tab.id
        if case .commitDiff(let document) = tab.content {
            document.load(root: workspace.url)
        }
        Log.git.notice("Open commit diff \(commit.hash)")
    }

    func select(_ tab: DocumentTab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        selectedTabID = tab.id
    }

    func close(_ tab: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let wasSelected = selectedTabID == tab.id
        tabs.remove(at: index)
        if tab.url != nil {
            Task { await refreshLineChanges() }
        }
        guard wasSelected else { return }

        // Prefer the tab that slid into this position, else the new last tab.
        if tabs.indices.contains(index) {
            selectedTabID = tabs[index].id
        } else {
            selectedTabID = tabs.last?.id
        }
    }

    /// Closes every tab at once (the palette's Close All Tabs).
    func closeAllTabs() {
        guard !tabs.isEmpty else { return }
        let hadFileTabs = tabs.contains { $0.url != nil }
        tabs.removeAll()
        selectedTabID = nil
        if hadFileTabs {
            Task { await refreshLineChanges() }
        }
    }

    /// Moves the selection by `offset`, wrapping around the ends (the
    /// palette's Select Next/Previous Tab).
    func selectTab(atOffset offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let wrapped = ((index + offset) % tabs.count + tabs.count) % tabs.count
        selectedTabID = tabs[wrapped].id
    }

    // MARK: Bulk closes (tab strip context menu)

    /// Closes every tab except `anchor`, which becomes the selection.
    func closeOthers(keeping anchor: DocumentTab) {
        guard tabs.contains(where: { $0.id == anchor.id }) else { return }
        tabs = [anchor]
        selectedTabID = anchor.id
    }

    /// Closes every tab left of `anchor`. If the selection was among the
    /// closed tabs it moves to `anchor`; otherwise it is kept.
    func closeTabsToLeft(of anchor: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == anchor.id }), index > 0 else { return }
        let selectionSurvives = !selectionWasIn(0..<index)
        tabs.removeSubrange(0..<index)
        if !selectionSurvives {
            selectedTabID = anchor.id
        }
    }

    /// Closes every tab right of `anchor`. If the selection was among the
    /// closed tabs it moves to `anchor`; otherwise it is kept.
    func closeTabsToRight(of anchor: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == anchor.id }),
              index < tabs.count - 1 else { return }
        let selectionSurvives = !selectionWasIn(tabs.index(after: index)..<tabs.count)
        tabs.removeSubrange(tabs.index(after: index)..<tabs.count)
        if !selectionSurvives {
            selectedTabID = anchor.id
        }
    }

    /// Whether the current selection sits inside the closing range.
    private func selectionWasIn(_ range: Range<Int>) -> Bool {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return false
        }
        return range.contains(index)
    }

    func reloadSelectedDocument() {
        guard let tab = selectedTab else { return }
        if case .file(_, let document) = tab.content {
            document.reload()
        }
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
