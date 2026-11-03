import SwiftUI

/// One pending diff presentation. `item`-presentable so the sheet binding
/// can clear the session's `requestDiff` on dismiss.
struct GitDiffRequest: Identifiable {
    enum Target {
        /// Working-tree diff of one file against HEAD.
        case file(URL)
        /// Full diff of one commit (`git show`).
        case commit(hash: String)
    }

    let target: Target
    /// Sheet subtitle: the file name or the commit subject.
    let title: String

    init(url: URL) {
        target = .file(url)
        title = url.lastPathComponent
    }

    init(commitHash: String, subject: String) {
        target = .commit(hash: commitHash)
        title = subject
    }

    var id: String {
        switch target {
        case .file(let url): return "file:\(url.path)"
        case .commit(let hash): return "commit:\(hash)"
        }
    }
}

/// Read-only sheet showing git diff output for a file or a whole commit.
/// The CLI output renders through the same pinned-metrics text pipeline as
/// code, highlighted with the diff language when the engine can.
struct GitDiffSheet: View {
    let request: GitDiffRequest
    let root: URL?
    let colorScheme: ColorScheme

    private enum Content {
        case loading
        case text(NSAttributedString)
        case empty
    }

    @State private var content: Content = .loading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                switch content {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                case .empty:
                    emptyState
                case .text(let attributed):
                    DiffTextView(attributed: attributed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 440)
        // Keyed by the request: switching to another commit or file while
        // the sheet identity survives must reload from scratch.
        .task(id: request.id) {
            content = .loading
            await load()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            l10n("Git Diff")
                .font(.system(size: 12, weight: .semibold))
            Text(request.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(l10nString("Close"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            l10n("No changes")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let root else {
            content = .empty
            return
        }
        let text: String?
        switch request.target {
        case .file(let url):
            text = await GitService.shared.diff(for: url, root: root)
        case .commit(let hash):
            text = await GitService.shared.commitDiff(root: root, hash: hash)
        }
        guard let text, !text.isEmpty else {
            content = .empty
            return
        }
        // Highlight as a diff; a missing engine or language falls back to
        // plain pinned-metrics text rather than an error.
        if let highlighted = try? await HighlightService.shared.highlight(
            requestKey: request.id,
            text: text,
            language: "diff",
            theme: HighlightTheme(colorScheme: colorScheme)
        ) {
            content = .text(CodeTextFactory.styled(highlighted.attributed))
        } else {
            content = .text(
                NSAttributedString(string: text, attributes: CodeTextFactory.attributes())
            )
        }
    }
}

/// One-shot read-only text view for the diff output, reusing the code pane's
/// editor (fixed line height + line-number ruler).
private struct DiffTextView: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CodeEditorView {
        let editor = CodeEditorView()
        editor.setAttributedText(attributed)
        context.coordinator.textHash = attributed.hashValue
        return editor
    }

    func updateNSView(_ editor: CodeEditorView, context: Context) {
        guard context.coordinator.textHash != attributed.hashValue else { return }
        context.coordinator.textHash = attributed.hashValue
        editor.setAttributedText(attributed)
    }

    final class Coordinator {
        var textHash: Int?
    }
}
