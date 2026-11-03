import Foundation

/// One open tab. Most tabs are files; a commit's merged diff is a second
/// content kind with its own document. The identity is namespaced by kind, so
/// opening the same target twice focuses the existing tab instead of
/// duplicating it.
struct DocumentTab: Identifiable {
    enum Content {
        case file(URL, DocumentStore)
        case commitDiff(GitDiffDocument)
    }

    let content: Content

    var id: String {
        switch content {
        case .file(let url, _): return "file:" + url.path
        case .commitDiff(let document): return "diff:commit:" + document.commit.hash
        }
    }

    /// Tab strip label: the file name, or the commit subject (the strip
    /// truncates with middle ellipsis when it overflows).
    var name: String {
        switch content {
        case .file(let url, _): return url.lastPathComponent
        case .commitDiff(let document): return document.commit.subject
        }
    }

    var url: URL? {
        guard case .file(let url, _) = content else { return nil }
        return url
    }

    @MainActor
    init(url: URL, service: FileService = .shared) {
        content = .file(url, DocumentStore(service: service))
    }

    @MainActor
    init(commit: GitCommit) {
        content = .commitDiff(GitDiffDocument(commit: commit))
    }
}
