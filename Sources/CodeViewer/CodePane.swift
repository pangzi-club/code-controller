import AppKit
import SwiftUI

/// Hosts the editor for the selected tab. One editor is kept per tab, up to
/// `capacity`; switching tabs swaps views in O(1) so scroll position and
/// selection survive. Evicted tabs keep their scroll anchor and are rebuilt
/// from the tab's `DocumentStore` text when shown again.
///
/// Text paints twice: plain first (so content appears instantly), then styled
/// once the background highlighter finishes. Finished results are cached per
/// document version and theme, so switching tabs never re-highlights.
struct CodePane: NSViewRepresentable {
    let tabID: String?
    let text: String?
    let documentID: String?
    /// Canonical highlight.js language for the file extension, or nil to
    /// render plain text.
    let language: String?
    /// Working-tree change marks for this file; the editor tints the changed
    /// lines the way the commit diff tints its rows.
    var lineChanges: LineChangeMap = .empty
    let theme: HighlightTheme
    var font: EditorFont = .default

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.clipsToBounds = true
        context.coordinator.container = container
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.update(
            tabID: tabID,
            text: text,
            documentID: documentID,
            language: language,
            lineChanges: lineChanges,
            theme: theme,
            font: font
        )
    }

    @MainActor
    final class Coordinator {
        static let capacity = 8

        weak var container: NSView?

        private struct Entry {
            let editorView: CodeEditorView
            var documentID: String
            var lastUsed: Int
            var text: String
            var language: String?
            /// Theme and font the editor's current paint was made for; nil
            /// means the content is stale and needs (re)painting.
            var appliedTheme: HighlightTheme?
            var appliedFont: EditorFont?
            var highlightTask: Task<Void, Never>?
        }

        private struct SavedState {
            var scrollOrigin: NSPoint
            var selection: NSRange
        }

        private var entries: [String: Entry] = [:]
        private var savedStates: [String: SavedState] = [:]
        private var currentTabID: String?
        private var currentTheme = HighlightTheme.light
        private var currentFont = EditorFont.default
        private var clock = 0
        private let cache = HighlightCache()
        private let service = HighlightService.shared

        func update(
            tabID: String?,
            text: String?,
            documentID: String?,
            language: String?,
            lineChanges: LineChangeMap,
            theme: HighlightTheme,
            font: EditorFont
        ) {
            guard let container, let tabID, let text, let documentID else { return }
            clock += 1

            let themeChanged = theme != currentTheme
            let fontChanged = font != currentFont
            if themeChanged || fontChanged {
                currentTheme = theme
                currentFont = font
                // Hidden editors keep their old paint; mark everything stale
                // so each one repaints below or on its next update.
                entries = entries.mapValues { entry in
                    var entry = entry
                    entry.appliedTheme = nil
                    entry.appliedFont = nil
                    return entry
                }
            }

            if entries[tabID] == nil {
                entries[tabID] = Entry(
                    editorView: CodeEditorView(font: font),
                    documentID: documentID,
                    lastUsed: clock,
                    text: text,
                    language: language,
                    appliedTheme: nil,
                    appliedFont: nil,
                    highlightTask: nil
                )
            }

            var entry = entries[tabID]!
            let contentChanged = entry.documentID != documentID
            var savedState: SavedState?
            if contentChanged {
                savedState = capture(entry)
                entry.highlightTask?.cancel()
                entry.highlightTask = nil
                entry.documentID = documentID
                entry.text = text
                entry.language = language
                entry.appliedTheme = nil
                entry.appliedFont = nil
            }
            entry.lastUsed = clock
            entries[tabID] = entry

            if entry.appliedTheme != theme || entry.appliedFont != font {
                applyContent(to: tabID, theme: theme, font: font)
            }

            show(entries[tabID]!, tabID: tabID, in: container)

            // Marks ride on top of whichever paint is showing (plain or
            // highlighted), so a cached paint still gets this file's tints.
            entries[tabID]?.editorView.setLineChanges(lineChanges)

            if let savedState, let entry = entries[tabID] {
                restore(savedState, in: entry)
            }

            if themeChanged || fontChanged {
                for otherID in entries.keys where otherID != tabID {
                    applyContent(to: otherID, theme: theme, font: font)
                }
            }

            evictIfNeeded()
        }

        /// Paints one entry for `theme` and `font`: from the cache when
        /// possible, otherwise plain text first and a styled swap-in once the
        /// background highlight finishes.
        private func applyContent(to tabID: String, theme: HighlightTheme, font: EditorFont) {
            guard var entry = entries[tabID] else { return }
            entry.highlightTask?.cancel()
            entry.highlightTask = nil
            entry.appliedTheme = theme
            entry.appliedFont = font
            entries[tabID] = entry

            let editorView = entry.editorView
            let documentID = entry.documentID
            let cacheKey = "\(tabID)#\(documentID)"

            // The pane adopts the theme's own background color.
            let cached = cache.result(for: cacheKey, theme: theme, fontID: font.id)

            if let cached {
                editorView.applyFont(font)
                editorView.setBackground(cached.background)
                editorView.setAttributedText(cached.attributed)
                return
            }

            editorView.applyFont(font)
            // Plain paint first; the theme background (if any) lands with the
            // styled swap-in below.
            editorView.setBackground(nil)
            editorView.setText(entry.text)
            guard let language = entry.language else { return }

            let text = entry.text
            let task = Task { @MainActor [weak self, weak editorView] in
                guard let self, let editorView else { return }
                do {
                    let raw = try await self.service.highlight(
                        requestKey: cacheKey,
                        text: text,
                        language: language,
                        theme: theme
                    )
                    let styled = CodeTextFactory.styled(raw.attributed, font: font)
                    let background = raw.background
                    guard !Task.isCancelled,
                          let current = self.entries[tabID],
                          current.editorView === editorView,
                          current.documentID == documentID,
                          current.appliedTheme == theme,
                          current.appliedFont == font else { return }
                    self.cache.store(
                        HighlightCache.Entry(attributed: styled, background: background),
                        for: cacheKey,
                        theme: theme,
                        fontID: font.id
                    )
                    editorView.setBackground(background)
                    editorView.setAttributedText(styled)
                } catch is CancellationError {
                } catch HighlightError.unsupportedLanguage {
                    // Unknown language: plain text is the graceful fallback,
                    // already painted.
                } catch {
                    Log.editor.error(
                        "Highlighting \(language) failed: \(error.localizedDescription)"
                    )
                }
            }
            entry.highlightTask = task
            entries[tabID] = entry
        }

        private func show(_ entry: Entry, tabID: String, in container: NSView) {
            guard currentTabID != tabID else { return }

            if let currentTabID, let current = entries[currentTabID] {
                savedStates[currentTabID] = capture(current)
                current.editorView.removeFromSuperview()
            }

            container.subviews.forEach { $0.removeFromSuperview() }
            entry.editorView.frame = container.bounds
            entry.editorView.autoresizingMask = [.width, .height]
            container.addSubview(entry.editorView)
            entry.editorView.layoutSubtreeIfNeeded()
            currentTabID = tabID

            if let saved = savedStates[tabID] {
                restore(saved, in: entry)
            }
        }

        private func capture(_ entry: Entry) -> SavedState {
            SavedState(
                scrollOrigin: entry.editorView.scrollView.contentView.bounds.origin,
                selection: entry.editorView.textView.selectedRange()
            )
        }

        private func restore(_ state: SavedState, in entry: Entry) {
            let editorView = entry.editorView
            editorView.layoutSubtreeIfNeeded()

            let clipView = editorView.scrollView.contentView
            let contentSize = editorView.textView.frame.size
            let maxX = max(0, contentSize.width - clipView.bounds.width)
            let maxY = max(0, contentSize.height - clipView.bounds.height)
            let origin = NSPoint(
                x: min(max(0, state.scrollOrigin.x), maxX),
                y: min(max(0, state.scrollOrigin.y), maxY)
            )
            clipView.scroll(to: origin)
            editorView.scrollView.reflectScrolledClipView(clipView)

            let length = (editorView.textView.string as NSString).length
            let location = min(state.selection.location, length)
            let selectionLength = min(state.selection.length, max(0, length - location))
            editorView.textView.setSelectedRange(
                NSRange(location: location, length: selectionLength)
            )
        }

        private func evictIfNeeded() {
            while entries.count > Self.capacity {
                let candidates = entries.keys.filter { $0 != currentTabID }
                guard let victim = candidates.min(by: { lhs, rhs in
                    (entries[lhs]?.lastUsed ?? 0) < (entries[rhs]?.lastUsed ?? 0)
                }), let entry = entries[victim] else {
                    break
                }
                entry.highlightTask?.cancel()
                savedStates[victim] = capture(entry)
                entry.editorView.removeFromSuperview()
                entries.removeValue(forKey: victim)
            }
        }
    }
}

final class CodeEditorView: NSView {
    let scrollView: NSScrollView
    let textView: NSTextView

    private var font: EditorFont
    private let lineNumberView: LineNumberRulerView
    private var lineNumberWidthConstraint: NSLayoutConstraint!
    /// Change marks currently painted on the text; the ruler keeps its own
    /// copy for the gutter markers.
    private(set) var lineChanges = LineChangeMap.empty

    init(font: EditorFont = .default) {
        self.font = font
        let content = CodeTextFactory.makeTextView(font: font)
        scrollView = content.scrollView
        textView = content.textView
        lineNumberView = LineNumberRulerView(
            textView: content.textView,
            scrollView: content.scrollView,
            lineHeight: font.lineHeight
        )
        super.init(frame: .zero)

        clipsToBounds = true
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lineNumberView)
        addSubview(scrollView)

        lineNumberWidthConstraint = lineNumberView.widthAnchor.constraint(
            equalToConstant: LineNumberRulerView.minimumWidth
        )
        NSLayoutConstraint.activate([
            lineNumberWidthConstraint,
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberView.topAnchor.constraint(equalTo: topAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        lineNumberView.onWidthChange = { [weak self] width in
            self?.lineNumberWidthConstraint.constant = width
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Re-pins the editor's font and paragraph metrics. The attributed text
    /// painted afterwards carries the same metrics, so the line-number ruler
    /// stays aligned.
    func applyFont(_ font: EditorFont) {
        guard font != self.font else { return }
        self.font = font
        textView.font = font.nsFont
        textView.defaultParagraphStyle = CodeTextFactory.paragraphStyle(font)
        textView.typingAttributes = CodeTextFactory.attributes(font)
        lineNumberView.lineHeight = font.lineHeight
        lineNumberView.needsDisplay = true
    }

    /// `nil` restores the system control background (stock look); a theme
    /// color paints the text view, scroll view and line-number ruler alike.
    func setBackground(_ color: NSColor?) {
        let resolved = color ?? .controlBackgroundColor
        textView.backgroundColor = resolved
        scrollView.backgroundColor = resolved
        lineNumberView.backgroundColor = resolved
    }

    func setText(_ text: String) {
        setAttributedText(
            NSAttributedString(string: text, attributes: CodeTextFactory.attributes(font))
        )
    }

    /// The attributed string must carry the pinned paragraph style and font
    /// metrics (see `CodeTextFactory.styled`) — the ruler assumes one fixed
    /// line height. Content characters stay identical between the plain and
    /// highlighted paint.
    func setAttributedText(_ attributed: NSAttributedString) {
        textView.textStorage?.setAttributedString(attributed)
        lineNumberView.update(text: attributed.string)
        // Fresh storage carries no backgrounds (the pane's styled output
        // strips the highlighter's), so the change tints are painted straight
        // on top — a background never affects the metrics the ruler needs.
        paintLineTints()
    }

    /// Updates the working-tree change marks. Equality is the guard: SwiftUI
    /// re-renders the pane on unrelated updates, and rewriting thousands of
    /// background attributes is only worth it when the marks moved.
    func setLineChanges(_ changes: LineChangeMap) {
        guard changes != lineChanges else { return }
        lineChanges = changes
        lineNumberView.lineChanges = changes
        if let storage = textView.textStorage {
            storage.removeAttribute(
                .backgroundColor,
                range: NSRange(location: 0, length: storage.length)
            )
        }
        paintLineTints()
    }

    private func paintLineTints() {
        guard let storage = textView.textStorage, !lineChanges.isEmpty else { return }
        for (kind, range) in lineChanges.tintedRanges(in: storage.string as NSString) {
            storage.addAttribute(
                .backgroundColor,
                value: LineChangePalette.background(for: kind),
                range: range
            )
        }
    }
}

enum CodeTextFactory {
    static func makeTextView(font: EditorFont) -> (scrollView: NSScrollView, textView: NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .controlBackgroundColor
        textView.textColor = .labelColor
        textView.font = font.nsFont
        textView.defaultParagraphStyle = paragraphStyle(font)
        textView.typingAttributes = attributes(font)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 4
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        scrollView.documentView = textView

        return (scrollView, textView)
    }

    static func attributes(_ font: EditorFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font.nsFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(font),
        ]
    }

    /// Merges a highlighter's output with the pane's pinned metrics: keeps the
    /// color attributes, swaps the font for the editor font (preserving
    /// bold/italic traits when the theme offers them) and forces the pinned
    /// paragraph style so the line-number ruler stays aligned. Characters are
    /// never changed.
    static func styled(
        _ highlighted: NSAttributedString,
        font: EditorFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: highlighted)
        guard result.length > 0 else { return result }

        let full = NSRange(location: 0, length: result.length)
        let paragraph = paragraphStyle(font)
        result.enumerateAttributes(in: full) { attributes, range, _ in
            var styledAttributes = attributes
            styledAttributes[.paragraphStyle] = paragraph
            styledAttributes[.font] = resolvingFont(matching: attributes[.font] as? NSFont, base: font)
            styledAttributes[.foregroundColor] =
                attributes[.foregroundColor] as? NSColor ?? NSColor.labelColor
            // Themes stamp their own background on spans; the pane decides
            // the background.
            styledAttributes[.backgroundColor] = nil
            result.setAttributes(styledAttributes, range: range)
        }
        return result
    }

    private static func resolvingFont(matching themed: NSFont?, base: EditorFont) -> NSFont {
        let baseFont = base.nsFont
        guard let themed else { return baseFont }
        let traits = themed.fontDescriptor.symbolicTraits
        guard !traits.isEmpty else { return baseFont }
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    static func paragraphStyle(_ font: EditorFont) -> NSParagraphStyle {
        // The line height is pinned through minimum/maximumLineHeight so the
        // ruler can place line numbers without querying TextKit layout. Pin
        // `pinnedLineHeight`, not `lineHeight`: the latter is what TextKit
        // rounds that pin up to, and pinning it would add the font's leading a
        // second time.
        let lineHeight = font.pinnedLineHeight
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.lineSpacing = 0
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font.nsFont]).width
        style.tabStops = []
        style.defaultTabInterval = spaceWidth * 4
        return style
    }
}

#if DEBUG
#Preview {
    CodePane(
        tabID: "preview",
        text: "struct Hello {\n\tlet message = \"Hello, Code Viewer\"\n}\n",
        documentID: "preview#1",
        language: "swift",
        theme: .light
    )
    .frame(width: 700, height: 480)
    .background(Color(nsColor: .controlBackgroundColor))
}
#endif
