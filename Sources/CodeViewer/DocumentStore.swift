import Foundation
import Observation

enum DocumentState {
    case empty
    case loading
    case text(TextDocument)
    case binary
    case tooLarge(byteSize: Int64)
    case failed
}

/// Owns the document currently shown in the code pane. Reads happen in
/// `FileService`; the store only receives immutable results on the main actor
/// and drops them when a newer file has been requested.
@MainActor
@Observable
final class DocumentStore {
    private(set) var url: URL?
    private(set) var state: DocumentState = .empty
    private(set) var revision = 0

    @ObservationIgnored private let service: FileService
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(service: FileService = .shared) {
        self.service = service
    }

    func open(_ node: FileNode) {
        load(from: node.url)
    }

    func reload() {
        guard let url else { return }
        load(from: url)
    }

    private func load(from url: URL) {
        loadTask?.cancel()
        self.url = url
        revision += 1
        let revision = revision
        state = .loading

        loadTask = Task { [weak self] in
            guard let self else { return }
            let content: DocumentContent?
            do {
                content = try await self.service.readDocument(at: url)
            } catch {
                Log.editor.error("Could not read \(url.path): \(error.localizedDescription)")
                content = nil
            }
            guard !Task.isCancelled, self.revision == revision else { return }

            switch content {
            case .text(let document): self.state = .text(document)
            case .binary: self.state = .binary
            case .tooLarge(let byteSize): self.state = .tooLarge(byteSize: byteSize)
            case nil: self.state = .failed
            }
        }
    }
}

/// Per-workspace UI state — tree expansion, the open document, and later tabs
/// and git state. Sessions live for the lifetime of the app so switching
/// workspaces is instant.
@MainActor
@Observable
final class WorkspaceSession {
    let workspace: Workspace
    let tree: FileTreeStore
    let document: DocumentStore

    @ObservationIgnored private var hasLoadedTree = false

    init(workspace: Workspace, service: FileService = .shared) {
        self.workspace = workspace
        tree = FileTreeStore(root: workspace.url, service: service)
        document = DocumentStore(service: service)
    }

    func loadIfNeeded() async {
        guard !hasLoadedTree else { return }
        hasLoadedTree = true
        await tree.loadRoot()
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
