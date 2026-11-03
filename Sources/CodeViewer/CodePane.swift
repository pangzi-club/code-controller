import AppKit
import SwiftUI

/// Hosts the editor for the selected tab. One editor is kept per tab, up to
/// `capacity`; switching tabs swaps views in O(1) so scroll position and
/// selection survive. Evicted tabs keep their scroll anchor and are rebuilt
/// from the tab's `DocumentStore` text when shown again.
struct CodePane: NSViewRepresentable {
    let tabID: String?
    let text: String?
    let documentID: String?

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
        context.coordinator.update(tabID: tabID, text: text, documentID: documentID)
    }

    final class Coordinator {
        static let capacity = 8

        weak var container: NSView?

        private struct Entry {
            let editorView: CodeEditorView
            var documentID: String
            var lastUsed: Int
        }

        private struct SavedState {
            var scrollOrigin: NSPoint
            var selection: NSRange
        }

        private var entries: [String: Entry] = [:]
        private var savedStates: [String: SavedState] = [:]
        private var currentTabID: String?
        private var clock = 0

        func update(tabID: String?, text: String?, documentID: String?) {
            guard let container, let tabID, let text, let documentID else { return }
            clock += 1

            if var entry = entries[tabID] {
                if entry.documentID != documentID {
                    let state = capture(entry)
                    entry.editorView.setText(text)
                    entry.documentID = documentID
                    restore(state, in: entry)
                }
                entry.lastUsed = clock
                entries[tabID] = entry
                show(entry, tabID: tabID, in: container)
                return
            }

            let editorView = CodeEditorView()
            editorView.setText(text)
            let entry = Entry(
                editorView: editorView,
                documentID: documentID,
                lastUsed: clock
            )
            entries[tabID] = entry
            show(entry, tabID: tabID, in: container)
            evictIfNeeded()
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

    private let lineNumberView: LineNumberRulerView
    private var lineNumberWidthConstraint: NSLayoutConstraint!

    init() {
        let content = CodeTextFactory.makeTextView()
        scrollView = content.scrollView
        textView = content.textView
        lineNumberView = LineNumberRulerView(
            textView: content.textView,
            scrollView: content.scrollView
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

    func setText(_ text: String) {
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: CodeTextFactory.attributes())
        )
        lineNumberView.update(text: text)
    }
}

enum CodeTextFactory {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    /// Pinned through `minimumLineHeight`/`maximumLineHeight` so the ruler can
    /// place line numbers without querying TextKit layout.
    static let lineHeight: CGFloat = (lineHeight(for: font) + 2).rounded()

    private static let metricsManager = NSLayoutManager()

    static func lineHeight(for font: NSFont) -> CGFloat {
        metricsManager.defaultLineHeight(for: font)
    }

    static func makeTextView() -> (scrollView: NSScrollView, textView: NSTextView) {
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
        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle()
        textView.typingAttributes = attributes()
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

    static func attributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(),
        ]
    }

    private static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.lineSpacing = 0
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
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
        documentID: "preview#1"
    )
    .frame(width: 700, height: 480)
    .background(Color(nsColor: .controlBackgroundColor))
}
#endif
