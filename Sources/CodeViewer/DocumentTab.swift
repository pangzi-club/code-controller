import Foundation

/// One open file tab. The URL doubles as identity, so opening the same file
/// twice focuses the existing tab instead of duplicating it.
struct DocumentTab: Identifiable {
    let url: URL
    let document: DocumentStore

    @MainActor
    init(url: URL, service: FileService = .shared) {
        self.url = url
        document = DocumentStore(service: service)
    }

    var id: String { "file:" + url.path }
    var name: String { url.lastPathComponent }
}
