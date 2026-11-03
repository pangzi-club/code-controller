import AppKit
import SwiftUI

/// Hosts the text view for the selected tab. One NSTextView is kept per tab,
/// up to `capacity`; switching tabs swaps views in O(1) so scroll position and
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
            let scrollView: NSScrollView
            let textView: NSTextView
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
                    // Same tab, new content (refresh): keep the anchor around.
                    let state = capture(entry)
                    setText(text, in: entry.textView)
                    entry.documentID = documentID
                    restore(state, in: entry)
                }
                entry.lastUsed = clock
                entries[tabID] = entry
                show(entry, tabID: tabID, in: container)
                return
            }

            let (scrollView, textView) = CodeTextFactory.makeTextView()
            let entry = Entry(
                scrollView: scrollView,
                textView: textView,
                documentID: documentID,
                lastUsed: clock
            )
            setText(text, in: textView)
            entries[tabID] = entry
            show(entry, tabID: tabID, in: container)
            evictIfNeeded()
        }

        /// Saves the outgoing tab's anchor, mounts the new scroll view, and
        /// restores the incoming tab's anchor. Re-adding a scroll view can reset
        /// its clip view, so the explicit restore is what keeps the position.
        private func show(_ entry: Entry, tabID: String, in container: NSView) {
            guard currentTabID != tabID else { return }

            if let currentTabID, let current = entries[currentTabID] {
                savedStates[currentTabID] = capture(current)
                current.scrollView.removeFromSuperview()
            }

            container.subviews.forEach { $0.removeFromSuperview() }
            entry.scrollView.frame = container.bounds
            entry.scrollView.autoresizingMask = [.width, .height]
            container.addSubview(entry.scrollView)
            currentTabID = tabID

            if let saved = savedStates[tabID] {
                restore(saved, in: entry)
            }
        }

        private func setText(_ text: String, in textView: NSTextView) {
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: CodeTextFactory.attributes())
            )
        }

        private func capture(_ entry: Entry) -> SavedState {
            SavedState(
                scrollOrigin: entry.scrollView.contentView.bounds.origin,
                selection: entry.textView.selectedRange()
            )
        }

        private func restore(_ state: SavedState, in entry: Entry) {
            entry.scrollView.layoutSubtreeIfNeeded()

            let clipView = entry.scrollView.contentView
            let contentSize = entry.scrollView.documentView?.frame.size ?? .zero
            let maxX = max(0, contentSize.width - clipView.bounds.width)
            let maxY = max(0, contentSize.height - clipView.bounds.height)
            let origin = NSPoint(
                x: min(max(0, state.scrollOrigin.x), maxX),
                y: min(max(0, state.scrollOrigin.y), maxY)
            )
            clipView.scroll(to: origin)
            entry.scrollView.reflectScrolledClipView(clipView)

            let length = (entry.textView.string as NSString).length
            let location = min(state.selection.location, length)
            let selectionLength = min(state.selection.length, max(0, length - location))
            entry.textView.setSelectedRange(NSRange(location: location, length: selectionLength))
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
                entry.scrollView.removeFromSuperview()
                entries.removeValue(forKey: victim)
            }
        }
    }
}

enum CodeTextFactory {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static func makeTextView() -> (scrollView: NSScrollView, textView: NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: true)
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
        textView.textContainerInset = NSSize(width: 16, height: 12)
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
        // Long lines scroll horizontally instead of wrapping, like an editor.
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
        style.lineSpacing = 1
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
