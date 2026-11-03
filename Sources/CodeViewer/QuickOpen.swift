import AppKit
import SwiftUI
import Observation

/// One searchable workspace file for the ⌘P panel.
struct QuickOpenEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    /// Path relative to the workspace root, e.g. "Sources/CodeViewer/Support.swift".
    let relativePath: String
    /// Containing directory relative to the workspace root, "" at the root.
    let directoryPath: String

    var id: String { url.path }

    init(url: URL, root: URL) {
        self.url = url
        self.name = url.lastPathComponent
        let relative = url.path.hasPrefix(root.path + "/")
            ? String(url.path.dropFirst(root.path.count + 1))
            : url.path
        self.relativePath = relative
        self.directoryPath = (relative as NSString).deletingLastPathComponent
    }
}

/// One result row: an entry plus where the query matched in its name, so the
/// row can highlight the hit. `nameRange` is nil for path-fallback matches and
/// for the empty query.
struct QuickOpenMatch {
    let entry: QuickOpenEntry
    let nameRange: Range<String.Index>?
}

/// Pure file-name/path matching for the quick-open panel, free of SwiftUI so
/// it can be unit tested.
enum QuickOpenMatcher {
    static let defaultLimit = 100

    /// An empty query keeps the index order (tree order), so the panel doubles
    /// as a workspace browser. Otherwise file names match first — ranked by
    /// match position, then shorter names, then path — and entries whose name
    /// does not match fall back to a substring match on the relative path.
    static func filter(
        _ entries: [QuickOpenEntry],
        query: String,
        limit: Int = defaultLimit
    ) -> [QuickOpenMatch] {
        guard !query.isEmpty else {
            return entries.prefix(limit).map { QuickOpenMatch(entry: $0, nameRange: nil) }
        }

        var nameMatches: [(match: QuickOpenMatch, position: Int)] = []
        var pathMatches: [QuickOpenMatch] = []
        for entry in entries {
            if let range = entry.name.range(of: query, options: .caseInsensitive) {
                let position = entry.name.distance(
                    from: entry.name.startIndex,
                    to: range.lowerBound
                )
                nameMatches.append((QuickOpenMatch(entry: entry, nameRange: range), position))
            } else if entry.relativePath.range(of: query, options: .caseInsensitive) != nil {
                pathMatches.append(QuickOpenMatch(entry: entry, nameRange: nil))
            }
        }

        nameMatches.sort {
            if $0.position != $1.position { return $0.position < $1.position }
            if $0.match.entry.name.count != $1.match.entry.name.count {
                return $0.match.entry.name.count < $1.match.entry.name.count
            }
            return $0.match.entry.relativePath.localizedStandardCompare(
                $1.match.entry.relativePath
            ) == .orderedAscending
        }
        pathMatches.sort {
            $0.entry.relativePath.localizedStandardCompare(
                $1.entry.relativePath
            ) == .orderedAscending
        }

        return Array((nameMatches.map(\.match) + pathMatches).prefix(limit))
    }
}

/// Recursively scanned file list for one quick-open presentation. The panel
/// rescans on every open, so results are always fresh and no cache needs
/// invalidation; dismissal cancels the scan between directories.
@MainActor
@Observable
final class QuickOpenIndex {
    private(set) var entries: [QuickOpenEntry] = []
    private(set) var isScanning = false

    func load(root: URL) async {
        isScanning = true
        defer { isScanning = false }
        do {
            let files = try await FileService.shared.allFiles(under: root)
            entries = files.map { QuickOpenEntry(url: $0.url, root: root) }
        } catch is CancellationError {
            // Panel dismissed mid-scan; keep whatever the scan found.
        } catch {
            Log.files.error("Quick open scan failed: \(error.localizedDescription)")
            entries = []
        }
    }
}

/// Floating ⌘P panel: a search field on top and matching workspace files
/// below, over a light scrim. Dismisses on Esc, on a click outside the panel,
/// and after opening a file.
struct QuickOpenView: View {
    let root: URL
    let onOpen: (URL) -> Void
    let onDismiss: () -> Void

    @State private var index = QuickOpenIndex()
    @State private var query = ""
    @State private var selectedIndex = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.primary.opacity(0.08)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            panel
                .padding(.top, 12)
        }
        .task(id: root) { await index.load(root: root) }
    }

    private var matches: [QuickOpenMatch] {
        QuickOpenMatcher.filter(index.entries, query: query)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            QuickOpenSearchField(
                query: $query,
                onSelectPrevious: moveSelectionUp,
                onSelectNext: moveSelectionDown,
                onConfirm: openSelection,
                onCancel: onDismiss
            )
            .padding(10)

            Divider()

            results
        }
        .frame(width: 600)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    @ViewBuilder
    private var results: some View {
        if index.isScanning && index.entries.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if index.entries.isEmpty {
            emptyState(icon: "folder", message: "This workspace is empty")
        } else if matches.isEmpty {
            emptyState(icon: "magnifyingglass", message: "No matching files")
        } else {
            list
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            l10n(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var list: some View {
        let currentMatches = matches
        // Rows are fixed (24pt + 1pt spacing) inside 4pt container padding, so
        // the scroll view is sized to hug the results exactly until they pass
        // the 380pt cap. A taller scroll view centers its content and leaves a
        // dead band above the first row; fixedSize on a ScrollView does not
        // reliably hug, so the height comes from the row math instead.
        let listHeight = min(CGFloat(currentMatches.count) * 25 + 7, 380)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(currentMatches.enumerated()), id: \.element.entry.id) { offset, match in
                        QuickOpenRowView(
                            match: match,
                            isSelected: offset == selectedIndex,
                            onActivate: { open(match.entry.url) }
                        )
                        .id(offset)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity)
            }
            .frame(height: listHeight)
            .onChange(of: selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    private func moveSelectionUp() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    private func moveSelectionDown() {
        selectedIndex = min(selectedIndex + 1, max(matches.count - 1, 0))
    }

    private func openSelection() {
        let currentMatches = matches
        guard currentMatches.indices.contains(selectedIndex) else { return }
        open(currentMatches[selectedIndex].entry.url)
    }

    private func open(_ url: URL) {
        onOpen(url)
    }
}

private struct QuickOpenRowView: View {
    let match: QuickOpenMatch
    let isSelected: Bool
    let onActivate: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 6) {
                Image(systemName: FileIcon.symbolName(for: match.entry.url, isDirectory: false))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: 16)

                highlightedName
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if !match.entry.directoryPath.isEmpty {
                    Text(match.entry.directoryPath)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(height: 24)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(match.entry.relativePath)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }

    /// The file name with the matched query substring emphasized, VS Code
    /// style. Path-fallback matches and the empty query render plain.
    private var highlightedName: Text {
        guard let range = match.nameRange else { return Text(match.entry.name) }
        let name = match.entry.name
        let matchColor: Color = isSelected ? .white : .accentColor
        return Text(String(name[name.startIndex..<range.lowerBound]))
            + Text(String(name[range])).bold().foregroundStyle(matchColor)
            + Text(String(name[range.upperBound...]))
    }
}

/// The panel's query field. AGENTS.md: SwiftUI `@FocusState` cannot move first
/// responder into a text field, so this is an `NSSearchField` that grabs focus
/// when it lands in a window and reports ↑/↓/Enter/Esc through the field
/// editor's `doCommandBy` hook.
private struct QuickOpenSearchField: NSViewRepresentable {
    @Binding var query: String
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusableSearchField()
        field.placeholderString = l10nString("Search files…")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: QuickOpenSearchField

        init(_ parent: QuickOpenSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.query = field.stringValue
        }

        /// The field editor asks the delegate before running editing commands;
        /// consuming these four keeps the panel in charge of navigation.
        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onSelectPrevious()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onSelectNext()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onConfirm()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }

    /// Becomes first responder once it is in the window, so ⌘P lands typing
    /// straight into the query.
    private final class FocusableSearchField: NSSearchField {
        private var hasRequestedFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !hasRequestedFocus else { return }
            hasRequestedFocus = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}

#if DEBUG
#Preview {
    QuickOpenView(
        root: PreviewFixtures.sampleWorkspace,
        onOpen: { _ in },
        onDismiss: {}
    )
    .frame(width: 800, height: 500)
    .background(Color(nsColor: .controlBackgroundColor))
}
#endif
