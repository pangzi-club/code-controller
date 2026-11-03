import Foundation
import Observation

/// Owns the commit diff shown in one tab. Mirrors `DocumentStore`: the fetch
/// runs off the main actor, the store only receives immutable results, and a
/// tab that switches away keeps its highlight cache warm here.
@MainActor
@Observable
final class GitDiffDocument {
    enum State: Equatable {
        case loading
        case loaded([FileDiff])
        /// The commit produced no textual diff (e.g. a merge commit).
        case empty
        /// git failed to run or exited non-zero.
        case failed
    }

    let commit: GitCommit
    private(set) var state: State = .loading

    /// Finished per-file highlight results, keyed by `FileDiff.id`. Lives
    /// with the tab, not the view, so switching tabs does not throw it away.
    @ObservationIgnored let highlightCache = HighlightCache()

    private let service: GitService

    init(commit: GitCommit, service: GitService = .shared) {
        self.commit = commit
        self.service = service
    }

    /// Fetches and parses the commit's diff. Commit content is immutable, so
    /// there is no reload path; each tab loads once.
    func load(root: URL) {
        guard state == .loading else { return }
        state = .loading
        let commit = self.commit
        Task { [weak self] in
            let raw = await self?.service.commitDiff(root: root, hash: commit.hash)
            // Parsing is pure string work; keep it off the main thread.
            let files = await Task.detached {
                raw.map(UnifiedDiffParser.parse)
            }.value
            guard let self, self.state == .loading else { return }
            switch files {
            case .some([]): self.state = .empty
            case .some(let files): self.state = .loaded(files)
            case nil: self.state = .failed
            }
        }
    }
}
