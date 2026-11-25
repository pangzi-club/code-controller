import SwiftUI

/// Inline commit diff shown in a tab: every file the commit touched is
/// stacked top to bottom, each rendered as an inline diff — old and new line
/// number gutters, a full-row tint on added/removed lines and static
/// "N hidden lines" bands where the hunks omit context. Clicking a file
/// header collapses or expands that file's section.
///
/// Layout model: the tab scrolls vertically (lazy per file), each file's
/// code scrolls horizontally on its own — the header row and the number
/// gutters stay pinned while long lines pan. Gutters and code columns are
/// separate stacks whose row heights are pinned to the same metrics, so
/// they stay aligned while only one side pans.
///
/// Unlike the code pane this view does not reuse `CodeEditorView`: the
/// dual-number gutters and the interleaved hidden-line bands do not fit the
/// editor's single-ruler contract, and a read-only diff needs no text view.
struct GitDiffContentView: View {
    let document: GitDiffDocument

    var body: some View {
        ZStack {
            switch document.state {
            case .loading:
                Color(nsColor: .controlBackgroundColor)
                ProgressView()
                    .controlSize(.small)
            case .empty:
                StatusView(icon: "tray", message: l10n("No changes"))
            case .failed:
                StatusView(
                    icon: "exclamationmark.triangle",
                    message: l10n("Couldn't load this diff")
                )
            case .loaded(let files):
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(files) { file in
                                FileDiffSection(
                                    file: file,
                                    document: document,
                                    availableWidth: geometry.size.width
                                )
                                Divider()
                            }
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - One file's section

/// One display row: either a diff line (clamped to a render-safe length) or
/// a static "N hidden lines" band standing in for context the hunks omit.
struct DiffSectionRow: Identifiable {
    enum Kind {
        case hiddenLines(Int)
        case line(kind: DiffLineKind, oldNumber: Int?, newNumber: Int?, text: String)
    }

    let id: String
    let kind: Kind
    /// Index into the file's joined highlight text; nil for meta lines and
    /// bands, which never enter that text.
    let highlightIndex: Int?
}

private struct FileDiffSection: View {
    let file: FileDiff
    let document: GitDiffDocument
    /// Viewport width of the tab, for the pinned band/header sizing and the
    /// code rows' minimum tint width.
    let availableWidth: CGFloat

    /// Prebuilt in `init`: rows, the joined highlight text and its line
    /// count all derive from the immutable parsed diff and must not be
    /// recomputed on every body evaluation of a multi-thousand-row file.
    private let displayRows: [DiffSectionRow]
    private let joinedRenderableText: String
    private let renderableCount: Int

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore
    @State private var isExpanded = true
    @State private var isHovered = false
    /// Converted highlight lines per `highlightIndex`; nil while plain text
    /// is showing or no language could be resolved.
    @State private var highlightedLines: [AttributedString]?

    init(file: FileDiff, document: GitDiffDocument, availableWidth: CGFloat) {
        self.file = file
        self.document = document
        self.availableWidth = availableWidth

        var rows: [DiffSectionRow] = []
        var renderable: [String] = []
        var nextHighlightIndex = 0
        for row in DiffRowsBuilder.rows(for: file) {
            switch row.payload {
            case .hiddenLines(let count):
                rows.append(DiffSectionRow(id: row.id, kind: .hiddenLines(count), highlightIndex: nil))
            case .line(let line):
                // Very long lines are cut for display: Text would otherwise
                // lay out the whole run at its full width. The horizontal
                // pan reaches everything inside the clamp.
                let text = line.kind == .meta ? line.text : String(line.text.prefix(Self.maxLineLength))
                rows.append(DiffSectionRow(
                    id: row.id,
                    kind: .line(kind: line.kind, oldNumber: line.oldNumber, newNumber: line.newNumber, text: text),
                    highlightIndex: line.kind == .meta ? nil : nextHighlightIndex
                ))
                if line.kind != .meta {
                    renderable.append(text)
                    nextHighlightIndex += 1
                }
            }
        }
        self.displayRows = rows
        self.joinedRenderableText = renderable.joined(separator: "\n")
        self.renderableCount = renderable.count
    }

    /// Above this many characters a line's tail is never read anyway.
    private static let maxLineLength = 2_000

    private static let gutterWidth: CGFloat = 38

    /// Width of both number columns, deducted from the viewport for the code
    /// rows' minimum tint width.
    private var guttersWidth: CGFloat {
        2 * (Self.gutterWidth + 6)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                if file.isBinary {
                    binaryPlaceholder
                } else {
                    rowsArea
                }
            }
        }
        .task(id: highlightTaskID) {
            guard isExpanded, renderableCount > 0, file.language != nil else { return }
            await highlight()
        }
    }

    // MARK: Header

    private var header: some View {
        Button {
            // No animation on purpose: animating a multi-thousand-row
            // section's collapse hitches; the toggle is instant instead.
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text(file.status.badge)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(file.status.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(file.status.color.opacity(0.15)))
                    .accessibilityLabel(l10n(file.status.labelKey))
                Text(file.displayPath)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                changeCounts
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .background(headerBackground)
        .help(file.displayPath)
        .accessibilityHint(l10n("Toggle this file's diff"))
        .onHover { isHovered = $0 }
    }

    /// Sits on the section's page background; the tint plus the semibold
    /// title and chevron keep the header clearly distinct from diff rows.
    private var headerBackground: some View {
        Color.primary.opacity(isHovered ? 0.08 : 0.045)
    }

    /// `+n -n` at the trailing edge, one side hidden when it is zero; binary
    /// files have no hunks and show nothing.
    @ViewBuilder
    private var changeCounts: some View {
        if file.addedCount > 0 {
            Text("+\(file.addedCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.green)
        }
        if file.removedCount > 0 {
            Text("-\(file.removedCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.red)
        }
    }

    private var binaryPlaceholder: some View {
        l10n("Binary file")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: Rows

    /// Pinned gutters on the left, horizontally pannable code on the right.
    /// Both stacks enumerate the same rows with identical pinned heights, so
    /// they stay aligned while only the code pans.
    private var rowsArea: some View {
        HStack(alignment: .top, spacing: 0) {
            guttersColumn
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: true) {
                codeColumn
            }
        }
    }

    /// Line-height for code rows and the hidden-band height; pinned on both
    /// sides of the split so the columns cannot drift apart.
    private var rowHeight: CGFloat {
        settings.editorFont.lineHeight
    }

    private static let bandHeight: CGFloat = 22

    private var guttersColumn: some View {
        let font = settings.editorFont
        return VStack(spacing: 0) {
            ForEach(displayRows) { row in
                switch row.kind {
                case .hiddenLines:
                    // Width pinned: Color.clear is infinitely flexible, and an
                    // unpinned band row would make this whole column flexible,
                    // so the outer HStack would split the width 50/50 with
                    // the code ScrollView.
                    Color.clear
                        .frame(width: guttersWidth, height: Self.bandHeight)
                case .line(let kind, let oldNumber, let newNumber, _):
                    HStack(spacing: 0) {
                        gutter(number: oldNumber, font: font)
                        gutter(number: newNumber, font: font)
                    }
                    .frame(height: rowHeight)
                    .background(rowBackground(kind))
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var codeColumn: some View {
        let font = settings.editorFont
        // Short rows still tint across the whole visible width.
        let minWidth = max(0, availableWidth - guttersWidth)
        // Leading alignment is load-bearing: the widest long line stretches
        // this stack, and the default .center would shove every short row
        // sideways instead of keeping them flush with the gutters.
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(displayRows) { row in
                switch row.kind {
                case .hiddenLines(let count):
                    l10n("%d hidden lines", count)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: minWidth, height: Self.bandHeight)
                case .line(let kind, _, _, let text):
                    codeRow(
                        kind: kind,
                        text: text,
                        font: font,
                        minWidth: minWidth,
                        highlighted: highlightedLine(for: row)
                    )
                }
            }
        }
    }

    /// Resolves this row's styled line; range-checked so stale state can
    /// only fall back to plain text, never crash.
    private func highlightedLine(for row: DiffSectionRow) -> AttributedString? {
        guard let index = row.highlightIndex, let lines = highlightedLines else { return nil }
        return lines.indices.contains(index) ? lines[index] : nil
    }

    private func gutter(number: Int?, font: EditorFont) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary.opacity(0.75))
            .frame(width: Self.gutterWidth, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private func codeRow(
        kind: DiffLineKind,
        text: String,
        font: EditorFont,
        minWidth: CGFloat,
        highlighted: AttributedString?
    ) -> some View {
        HStack(spacing: 0) {
            lineText(kind: kind, text: text, font: font, highlighted: highlighted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .frame(height: rowHeight, alignment: .center)
        .background(rowBackground(kind))
    }

    private func lineText(
        kind: DiffLineKind,
        text: String,
        font: EditorFont,
        highlighted: AttributedString?
    ) -> Text {
        if let highlighted {
            return Text(highlighted)
        }
        var plain = AttributedString(text)
        plain.font = Font(font.nsFont)
        plain.foregroundColor = kind == .meta ? Color(nsColor: .tertiaryLabelColor) : Color(nsColor: .labelColor)
        let line = Text(plain)
        return kind == .meta ? line.italic() : line
    }

    private func rowBackground(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.16)
        case .removed: return Color.red.opacity(0.16)
        case .context, .meta: return .clear
        }
    }

    // MARK: Highlight pipeline

    private var highlightTaskID: String {
        let theme = settings.resolvedHighlightTheme(for: colorScheme)
        return "\(document.commit.hash)#\(file.id)#\(theme.rawValue)#\(settings.editorFont.id)#\(isExpanded)"
    }

    /// Highlights the file's lines in one pass and slices the result back
    /// per line, converting to `AttributedString` once here instead of per
    /// row render. Plain text paints first; the styled lines swap in when
    /// the background run lands. Unknown languages quietly stay plain.
    private func highlight() async {
        guard let language = file.language else { return }
        let theme = settings.resolvedHighlightTheme(for: colorScheme)
        let font = settings.editorFont
        let cacheKey = "gitdiff:\(document.commit.hash)#\(file.id)"

        if let cached = document.highlightCache.result(for: cacheKey, theme: theme, fontID: font.id) {
            highlightedLines = Self.attributedLines(cached.attributed, expectedCount: renderableCount, font: font.nsFont)
            return
        }

        let raw = await HighlightService.shared.highlight(
            requestKey: cacheKey,
            text: joinedRenderableText,
            language: language,
            theme: theme
        )
        guard !Task.isCancelled, isExpanded else { return }
        guard let lines = Self.attributedLines(raw.attributed, expectedCount: renderableCount, font: font.nsFont) else {
            return  // line mapping broke; keep the plain rows
        }
        document.highlightCache.store(
            HighlightCache.Entry(attributed: raw.attributed, background: raw.background),
            for: cacheKey,
            theme: theme,
            fontID: font.id
        )
        highlightedLines = lines
    }

    /// Slices highlighted text into per-line `AttributedString`s. The theme
    /// background must not ride along into the rows (they tint themselves),
    /// and every line needs the editor font for stable metrics.
    private static func attributedLines(
        _ attributed: NSAttributedString,
        expectedCount: Int,
        font: NSFont
    ) -> [AttributedString]? {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.backgroundColor, range: full)
        mutable.addAttribute(.font, value: font, range: full)

        let string = mutable.string as NSString
        var pieces: [NSAttributedString] = []
        var start = 0
        for position in 0..<string.length where string.character(at: position) == 0x0A {
            pieces.append(mutable.attributedSubstring(from: NSRange(location: start, length: position - start)))
            start = position + 1
        }
        pieces.append(mutable.attributedSubstring(from: NSRange(location: start, length: string.length - start)))
        // A trailing newline yields one extra empty piece.
        if pieces.count == expectedCount + 1, pieces.last?.string.isEmpty == true {
            pieces.removeLast()
        }
        guard pieces.count == expectedCount else { return nil }
        return pieces.map { AttributedString($0) }
    }
}
