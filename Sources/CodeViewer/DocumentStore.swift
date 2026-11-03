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

/// Owns the document currently shown in one tab. Reads happen in
/// `FileService`; the store only receives immutable results on the main actor
/// and drops them when a newer file has been requested.
@MainActor
@Observable
final class DocumentStore {
    private(set) var url: URL?
    private(set) var state: DocumentState = .empty
    private(set) var revision = 0

    /// Distinguishes two stores for the same path (close and reopen) so the
    /// text view pool can tell that its cached text is stale.
    private let instanceID = UUID()
    private let service: FileService

    /// Read-time metadata for `reloadIfChanged`; nil until a text read lands.
    @ObservationIgnored private var lastReadModificationDate: Date?
    @ObservationIgnored private var lastReadByteSize: Int?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(service: FileService = .shared) {
        self.service = service
    }

    var versionID: String {
        "\(instanceID.uuidString)#\(revision)"
    }

    func open(url: URL) {
        load(from: url)
    }

    func reload() {
        guard let url else { return }
        load(from: url)
    }

    /// Reloads only when the file actually changed on disk (mtime or size),
    /// so a watcher burst touching unrelated files does not invalidate every
    /// open tab's highlight cache.
    func reloadIfChanged() {
        guard let url, case .text = state else { return }
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let modificationDate = values?.contentModificationDate
        let byteSize = values?.fileSize
        if modificationDate == lastReadModificationDate, byteSize == lastReadByteSize {
            return
        }
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
            case .text(let document):
                self.lastReadModificationDate = document.modificationDate
                self.lastReadByteSize = document.byteSize
                self.state = .text(document)
            case .binary: self.state = .binary
            case .tooLarge(let byteSize): self.state = .tooLarge(byteSize: byteSize)
            case nil: self.state = .failed
            }
        }
    }
}
