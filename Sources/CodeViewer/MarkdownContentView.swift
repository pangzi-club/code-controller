import AppKit
import Observation
import SwiftUI

/// How a Markdown tab shows its file. Preview is the default — the app is a
/// reader first — and Source stays one click away on the floating switch.
enum MarkdownViewMode {
    case source
    case preview
}

// MARK: - Floating switch

/// Two-segment Source / Preview toggle pinned to the pane's bottom-right
/// corner. It floats over the content in both modes with the same material
/// panel look as the quick-open panel, so switching back is always one click.
struct MarkdownViewSwitch: View {
    @Binding var mode: MarkdownViewMode
    @State private var hovered: MarkdownViewMode?

    var body: some View {
        HStack(spacing: 2) {
            segment(.source, title: "Source", symbol: "chevron.left.forwardslash.chevron.right",
                    help: "Show the Markdown source")
            segment(.preview, title: "Preview", symbol: "doc.richtext",
                    help: "Show the rendered preview")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.regularMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    private func segment(_ target: MarkdownViewMode, title: String, symbol: String, help: String) -> some View {
        let isSelected = mode == target
        let isHovered = hovered == target
        return Button {
            mode = target
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(l10nString(title))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1)
                        : isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering in
            hovered = hovering ? target : nil
        }
        .help(l10nString(help))
        .accessibilityLabel(Text(l10nString(title)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Content

/// Typography of the preview: the system font for prose at GitHub-like
/// sizes, the editor font for code and the theme's background behind code
/// blocks, so the code reads the same as it does in Source.
struct MarkdownStyle {
    /// Readable line length; wider windows center the column.
    static let columnWidth: CGFloat = 820

    let editorFont: EditorFont

    var bodyFont: Font { .system(size: 14) }
    var tableFont: Font { .system(size: 13) }
    /// Inline code sits a point under the body size so chips do not look heavy.
    var inlineCodeFont: Font { Font(editorFont.nsFont.withSize(max(9, editorFont.size - 1))) }
    var inlineCodeBackground: Color { Color.primary.opacity(0.07) }
    /// GitHub's light code surface: a faint tint, visible on the page color.
    var codeBackground: Color { Color.primary.opacity(0.05) }

    /// The theme's own background when it visibly differs from the page (a
    /// dark theme on a light page keeps its colors intact); otherwise the
    /// tinted default, so a white-background theme still shows a block edge.
    static func codeBackground(for themeBackground: NSColor?) -> Color? {
        guard let themeBackground else { return nil }
        guard let page = NSColor.controlBackgroundColor.usingColorSpace(.deviceRGB),
              let theme = themeBackground.usingColorSpace(.deviceRGB) else {
            return Color(nsColor: themeBackground)
        }
        let difference = max(abs(page.redComponent - theme.redComponent),
                            abs(page.greenComponent - theme.greenComponent),
                            abs(page.blueComponent - theme.blueComponent))
        return difference < 0.04 ? nil : Color(nsColor: themeBackground)
    }
    var ruleColor: Color { Color.primary.opacity(0.1) }

    func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 24, weight: .semibold)
        case 2: .system(size: 19, weight: .semibold)
        case 3: .system(size: 16, weight: .semibold)
        case 4: .system(size: 15, weight: .semibold)
        case 5: .system(size: 14, weight: .semibold)
        default: .system(size: 13, weight: .semibold)
        }
    }

    func headingTopPadding(_ level: Int) -> CGFloat {
        level == 1 ? 4 : 16
    }
}

/// Resolves a Markdown link destination: absolute URLs pass through, relative
/// paths resolve against the document so files open inside the app.
enum MarkdownLink {
    static func url(_ destination: String, relativeTo document: URL) -> URL? {
        let destination = destination.trimmingCharacters(in: .whitespaces)
        guard !destination.isEmpty else { return nil }
        if let url = URL(string: destination, relativeTo: document) {
            return url.absoluteURL
        }
        // Spaces and non-ASCII characters in a relative path need encoding.
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "#?%"))
        guard let encoded = destination.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: encoded, relativeTo: document) else {
            return nil
        }
        return url.absoluteURL
    }
}

/// One highlighted fenced block: the styled code and the theme background it
/// was rendered for.
struct MarkdownHighlighted {
    let text: AttributedString
    let background: Color?
}

/// Finished code-block highlights across preview instances, so switching tabs
/// or returning from Source never highlights the same README twice.
@MainActor
enum MarkdownHighlighting {
    static let cache = HighlightCache(capacity: 48)
}

/// Per-preview results that arrive asynchronously.
@Observable
@MainActor
final class MarkdownResources {
    var highlighted: [String: MarkdownHighlighted] = [:]
    var images: [URL: NSImage] = [:]
    var failedImages: Set<URL> = []
}

/// Rendered Markdown for one tab: parses with `MarkdownDocument`, lays
/// the blocks out in a scrolling column of readable width, highlights fenced
/// code through the shared highlighter and resolves images and links against
/// the file's directory. Links to other files open in tabs; everything else
/// goes to the system.
struct MarkdownContentView: View {
    let document: TextDocument
    let url: URL
    /// The store's version identity, so cached highlights never outlive the text.
    let documentID: String
    var onOpenFile: (URL) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore
    @State private var blocks: [MarkdownDocument.Block] = []
    @State private var resources = MarkdownResources()

    private var style: MarkdownStyle {
        MarkdownStyle(editorFont: settings.editorFont)
    }

    /// Changes with the text, the parsed blocks, the theme and the font.
    private var highlightKey: String {
        "\(documentID)#\(blocks.count)#\(settings.resolvedHighlightTheme(for: colorScheme))#\(settings.editorFont.id)"
    }

    var body: some View {
        ScrollView {
            MarkdownBlocks(
                blocks: blocks,
                style: style,
                resources: resources,
                baseURL: url,
                documentID: documentID
            )
            .frame(maxWidth: MarkdownStyle.columnWidth)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { target in
            if target.isFileURL {
                onOpenFile(target)
            } else {
                NSWorkspace.shared.open(target)
            }
            return .handled
        })
        .task(id: documentID) {
            // Parsing is pure string work; keep it off the main thread.
            let text = document.text
            let parsed = await Task.detached(priority: .userInitiated) {
                MarkdownDocument(parsing: text)
            }.value
            guard !Task.isCancelled else { return }
            blocks = parsed.blocks
        }
        .task(id: highlightKey) {
            await highlightCodeBlocks()
        }
    }

    /// Plain code shows first; each fenced block with a known language is
    /// styled through the shared highlighter and swapped in when it lands.
    private func highlightCodeBlocks() async {
        let theme = settings.resolvedHighlightTheme(for: colorScheme)
        let font = settings.editorFont
        for block in MarkdownCodeBlock.codeBlocks(in: blocks) {
            guard let language = MarkdownCodeBlock.language(for: block.language) else { continue }
            let key = MarkdownCodeBlock.cacheKey(documentID: documentID, language: block.language, code: block.code)
            if let cached = MarkdownHighlighting.cache.result(for: key, theme: theme, fontID: font.id) {
                resources.highlighted[key] = MarkdownHighlighted(
                    text: AttributedString(cached.attributed),
                    background: MarkdownStyle.codeBackground(for: cached.background)
                )
                continue
            }
            let raw = await HighlightService.shared.highlight(
                requestKey: key,
                text: block.code,
                language: language,
                theme: theme
            )
            guard !Task.isCancelled else { return }
            let styled = CodeTextFactory.styled(raw.attributed, font: font)
            MarkdownHighlighting.cache.store(
                HighlightCache.Entry(attributed: styled, background: raw.background),
                for: key,
                theme: theme,
                fontID: font.id
            )
            resources.highlighted[key] = MarkdownHighlighted(
                text: AttributedString(styled),
                background: MarkdownStyle.codeBackground(for: raw.background)
            )
        }
    }
}

// MARK: - Blocks

struct MarkdownBlocks: View {
    let blocks: [MarkdownDocument.Block]
    let style: MarkdownStyle
    let resources: MarkdownResources
    let baseURL: URL
    let documentID: String
    var tone: Color = .primary
    /// List nesting depth, for the bullet glyph.
    var depth: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(
                    block: block,
                    style: style,
                    resources: resources,
                    baseURL: baseURL,
                    documentID: documentID,
                    tone: tone,
                    depth: depth
                )
            }
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownDocument.Block
    let style: MarkdownStyle
    let resources: MarkdownResources
    let baseURL: URL
    let documentID: String
    let tone: Color
    let depth: Int

    var body: some View {
        switch block {
        case .heading(let level, let content):
            VStack(alignment: .leading, spacing: 10) {
                inline(content, font: style.headingFont(level))
                if level <= 2 {
                    Rectangle().fill(style.ruleColor).frame(height: 1)
                }
            }
            .padding(.top, style.headingTopPadding(level))
            .accessibilityAddTraits(.isHeader)
        case .paragraph(let content):
            inline(content, font: style.bodyFont)
        case .codeBlock(let language, let code):
            MarkdownCodeBlock(
                language: language,
                code: code,
                documentID: documentID,
                style: style,
                resources: resources
            )
            .padding(.vertical, 2)
        case .quote(let inner):
            // The bar is an overlay so it can never take part in sizing; as
            // a sibling shape it would soak up any spare height a container
            // proposes and outgrow the text.
            MarkdownBlocks(
                blocks: inner,
                style: style,
                resources: resources,
                baseURL: baseURL,
                documentID: documentID,
                tone: tone == .primary ? .secondary : tone
            )
            .padding(.leading, 15)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 3)
            }
            .padding(.vertical, 2)
        case .list(let list):
            MarkdownList(
                list: list,
                style: style,
                resources: resources,
                baseURL: baseURL,
                documentID: documentID,
                tone: tone,
                depth: depth
            )
        case .thematicBreak:
            Rectangle().fill(style.ruleColor).frame(height: 1).padding(.vertical, 10)
        case .table(let table):
            MarkdownTable(table: table, style: style, resources: resources, baseURL: baseURL, tone: tone)
                .padding(.vertical, 2)
        case .html(let content):
            inline(content, font: style.bodyFont)
        }
    }

    private func inline(_ content: [MarkdownDocument.Inline], font: Font) -> some View {
        MarkdownInlineText(
            content: content,
            font: font,
            style: style,
            baseURL: baseURL,
            resources: resources,
            tone: tone
        )
        .lineSpacing(4)
    }
}

/// Inline runs as styled text. Images break the run and become blocks of
/// their own, since `Text` cannot embed them — the way GitHub lays out an
/// image that stands alone in a paragraph.
private struct MarkdownInlineText: View {
    let content: [MarkdownDocument.Inline]
    let font: Font
    let style: MarkdownStyle
    let baseURL: URL
    let resources: MarkdownResources
    let tone: Color

    private enum Segment {
        case text([MarkdownDocument.Inline])
        case image(source: String, alt: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.segments(content).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let runs):
                    Text(MarkdownText.attributed(runs, font: font, style: style, tone: tone, baseURL: baseURL))
                case .image(let source, let alt):
                    MarkdownImage(source: source, alt: alt, baseURL: baseURL, resources: resources)
                }
            }
        }
    }

    private static func segments(_ content: [MarkdownDocument.Inline]) -> [Segment] {
        var segments: [Segment] = []
        var runs: [MarkdownDocument.Inline] = []
        for inline in content {
            guard case .image(let source, let alt) = inline else {
                runs.append(inline)
                continue
            }
            if !runs.isEmpty {
                segments.append(.text(runs))
                runs = []
            }
            segments.append(.image(source: source, alt: alt))
        }
        if !runs.isEmpty {
            segments.append(.text(runs))
        }
        return segments
    }
}

/// Lists: a marker column and the item's blocks. Nested lists sit inside the
/// blocks column, so indentation follows naturally.
private struct MarkdownList: View {
    let list: MarkdownDocument.List
    let style: MarkdownStyle
    let resources: MarkdownResources
    let baseURL: URL
    let documentID: String
    let tone: Color
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: list.isLoose ? 6 : 2) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(number: list.start + offset, task: item.task)
                    MarkdownBlocks(
                        blocks: item.blocks,
                        style: style,
                        resources: resources,
                        baseURL: baseURL,
                        documentID: documentID,
                        tone: tone,
                        depth: depth + 1
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func marker(number: Int, task: MarkdownDocument.Item.TaskState) -> some View {
        switch task {
        case .none:
            if list.isOrdered {
                Text("\(number).")
                    .font(style.bodyFont.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
            } else {
                bullet
                    .frame(width: 12)
            }
        case .unchecked:
            Image(systemName: "square")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 12)
        case .checked:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tint)
                .frame(width: 12)
        }
    }

    /// Bullets are drawn rather than typed: the •, ◦ and ▪ glyphs read too
    /// small at body size. The guide centers each shape on the text's x-height.
    private var bullet: some View {
        Group {
            switch depth % 3 {
            case 1: Circle().stroke(Color.secondary, lineWidth: 1).frame(width: 6, height: 6)
            case 2: RoundedRectangle(cornerRadius: 0.5).fill(Color.secondary).frame(width: 5, height: 5)
            default: Circle().fill(Color.secondary).frame(width: 5, height: 5)
            }
        }
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[VerticalAlignment.center] + 3.5
        }
    }
}

/// Tables keep their natural width and left alignment; a table wider than the
/// column scrolls horizontally instead of wrapping.
private struct MarkdownTable: View {
    let table: MarkdownDocument.Table
    let style: MarkdownStyle
    let resources: MarkdownResources
    let baseURL: URL
    let tone: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid.fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                grid.fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                    cellView(cell, alignment: alignment(column), isHeader: true)
                }
            }
            Divider()
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        cellView(cell, alignment: alignment(column), isHeader: false)
                    }
                }
                Divider()
            }
        }
    }

    private func alignment(_ column: Int) -> Alignment {
        guard table.alignments.indices.contains(column) else { return .leading }
        switch table.alignments[column] {
        case .center: return .center
        case .trailing: return .trailing
        case .leading: return .leading
        }
    }

    private func cellView(_ cell: [MarkdownDocument.Inline], alignment: Alignment, isHeader: Bool) -> some View {
        Text(MarkdownText.attributed(
            cell,
            font: .system(size: 13, weight: isHeader ? .semibold : .regular),
            style: style,
            tone: tone,
            baseURL: baseURL
        ))
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isHeader ? Color.primary.opacity(0.04) : Color.clear)
    }
}

/// A fenced code block on the theme's background. Fits the column when it
/// can and scrolls horizontally when a line is too long; the height comes
/// from the line count and the editor font's pinned line height.
struct MarkdownCodeBlock: View {
    let language: String?
    let code: String
    let documentID: String
    let style: MarkdownStyle
    let resources: MarkdownResources

    private static let padding: CGFloat = 10

    /// Every fenced block in document order.
    static func codeBlocks(in blocks: [MarkdownDocument.Block]) -> [(language: String?, code: String)] {
        blocks.flatMap { block -> [(language: String?, code: String)] in
            switch block {
            case .codeBlock(let language, let code):
                return [(language, code)]
            case .quote(let inner):
                return codeBlocks(in: inner)
            case .list(let list):
                return list.items.flatMap { codeBlocks(in: $0.blocks) }
            default:
                return []
            }
        }
    }

    /// Cache key by content, so the flatten pass and the view agree without
    /// threading indices through the tree.
    static func cacheKey(documentID: String, language: String?, code: String) -> String {
        "markdown:\(documentID)#\(language ?? "-")#\(code.hashValue)"
    }

    /// Maps a fence's info word onto a language the highlighter knows.
    /// `nil` keeps the block plain.
    static func language(for info: String?) -> String? {
        guard let info else { return nil }
        let name = info.lowercased()
        let aliases = [
            "c++": "cpp", "cxx": "cpp", "cc": "cpp", "golang": "go", "js": "javascript",
            "jsx": "javascript", "ts": "typescript", "kt": "kotlin", "objc": "objectivec",
            "objective-c": "objectivec", "py": "python", "rb": "ruby", "rs": "rust",
            "cs": "csharp", "sh": "bash", "shell": "bash", "zsh": "bash", "console": "bash",
            "ps": "powershell", "ps1": "powershell", "yml": "yaml",
        ]
        if ["text", "txt", "plain", "plaintext", "nohighlight", ""].contains(name) { return nil }
        let candidate = aliases[name] ?? name
        return SyntaxLanguageMapper.highlightLanguage(forExtension: candidate)
    }

    private var key: String {
        Self.cacheKey(documentID: documentID, language: language, code: code)
    }

    private var lineCount: Int {
        max(1, code.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    var body: some View {
        let highlighted = resources.highlighted[key]
        let codeText = Text(highlighted?.text ?? Self.plain(code, font: style.editorFont))
            .padding(.horizontal, 12)
            .padding(.vertical, Self.padding)
            .fixedSize(horizontal: true, vertical: false)
        ViewThatFits(in: .horizontal) {
            codeText
            // A scroll view cannot hug its content, so the height comes from
            // the line count and the editor font's pinned line height.
            ScrollView(.horizontal, showsIndicators: true) { codeText }
                .frame(height: CGFloat(lineCount) * style.editorFont.lineHeight + 2 * Self.padding)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlighted?.background ?? style.codeBackground)
        )
        .textSelection(.enabled)
    }

    private static func plain(_ code: String, font: EditorFont) -> AttributedString {
        AttributedString(NSAttributedString(string: code, attributes: CodeTextFactory.attributes(font)))
    }
}

/// A local image, loaded off the main thread and scaled to the column without
/// upscaling. Remote images stay a link: the sandboxed build has no network,
/// and a README's screenshots are usually local anyway.
private struct MarkdownImage: View {
    let source: String
    let alt: String
    let baseURL: URL
    let resources: MarkdownResources

    var body: some View {
        if let url = MarkdownLink.url(source, relativeTo: baseURL) {
            if url.isFileURL {
                MarkdownLocalImage(url: url, alt: alt, resources: resources)
            } else {
                Link(destination: url) {
                    Label(alt.isEmpty ? url.absoluteString : alt, systemImage: "photo")
                        .font(.system(size: 12))
                }
                .help(url.absoluteString)
            }
        } else if !alt.isEmpty {
            Text(alt).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

private struct MarkdownLocalImage: View {
    let url: URL
    let alt: String
    let resources: MarkdownResources
    @State private var image: NSImage?

    init(url: URL, alt: String, resources: MarkdownResources) {
        self.url = url
        self.alt = alt
        self.resources = resources
        // A warm cache shows the image on the first frame.
        _image = State(initialValue: resources.images[url])
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: image.size.width)
                    .accessibilityLabel(alt)
            } else if resources.failedImages.contains(url) {
                Label(alt.isEmpty ? url.lastPathComponent : alt, systemImage: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .help(url.path)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        if let cached = resources.images[url] {
            image = cached
            return
        }
        let url = url
        // NSImage is documented thread-safe; decoding stays off the main actor.
        let loaded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        guard !Task.isCancelled else { return }
        image = loaded
        if let loaded {
            resources.images[url] = loaded
        } else {
            resources.failedImages.insert(url)
        }
    }
}

// MARK: - Inline text

enum MarkdownText {
    /// Inline runs as one styled string. Emphasis and strong apply their
    /// trait to whatever fonts the inner runs already carry, so code inside
    /// bold text stays monospaced.
    static func attributed(
        _ inlines: [MarkdownDocument.Inline],
        font: Font,
        style: MarkdownStyle,
        tone: Color,
        baseURL: URL
    ) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let text):
                result += run(text, font: font, color: tone)
            case .code(let code):
                result += run(code, font: style.inlineCodeFont, color: tone, background: style.inlineCodeBackground)
            case .emphasis(let children):
                let inner = attributed(children, font: font, style: style, tone: tone, baseURL: baseURL)
                result += applying({ $0.italic() }, to: inner)
            case .strong(let children):
                let inner = attributed(children, font: font, style: style, tone: tone, baseURL: baseURL)
                result += applying({ $0.bold() }, to: inner)
            case .strikethrough(let children):
                var piece = attributed(children, font: font, style: style, tone: tone, baseURL: baseURL)
                piece.strikethroughStyle = .single
                piece.foregroundColor = tone.opacity(0.6)
                result += piece
            case .link(let destination, let children):
                var piece = attributed(children, font: font, style: style, tone: tone, baseURL: baseURL)
                piece.foregroundColor = .accentColor
                if let url = MarkdownLink.url(destination, relativeTo: baseURL) {
                    piece.link = url
                }
                result += piece
            case .image(_, let alt):
                // An image nested in emphasis or a link cannot leave the run;
                // its alt text stands in.
                if !alt.isEmpty {
                    result += run("[\(alt)]", font: font, color: .secondary)
                }
            case .lineBreak:
                result += run("\n", font: font, color: tone)
            }
        }
        return result
    }

    private static func run(_ text: String, font: Font, color: Color, background: Color? = nil) -> AttributedString {
        var piece = AttributedString(text)
        piece.font = font
        piece.foregroundColor = color
        if let background {
            piece.backgroundColor = background
        }
        return piece
    }

    private static func applying(_ transform: (Font) -> Font, to string: AttributedString) -> AttributedString {
        var string = string
        for range in string.runs.map(\.range) {
            string[range].font = transform(string[range].font ?? .body)
        }
        return string
    }
}

#if DEBUG
#Preview {
    MarkdownContentView(
        document: TextDocument(
            text: """
            # CodeCtrl

            A code reader for macOS. See `README.md` and [the docs](docs/ui-testing.md).

            ## Features

            - Tabs with **git status**
            - Quick open with ⌘P
            - [x] Markdown preview
            - [ ] Source toggle

            > Read first, edit elsewhere.

            | Key | Action |
            | :-- | --: |
            | ⌘W | Close tab |
            | ⌘P | Quick open |

            ```swift
            struct ContentView: View {
                var body: some View { Text("Hello") }
            }
            ```
            """,
            encoding: .utf8,
            byteSize: 0,
            modificationDate: nil
        ),
        url: URL(fileURLWithPath: "/tmp/README.md"),
        documentID: "preview#1"
    )
    .environmentObject(SettingsStore())
    .frame(width: 720, height: 640)
}
#endif

