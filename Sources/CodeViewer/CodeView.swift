import AppKit
import SwiftUI

/// Read-only TextKit 2 text view. SwiftUI creates the view once; a new
/// attributed string is applied only when `documentID` changes, so scrolling
/// and updates never rebuild the AppKit side.
struct CodeView: NSViewRepresentable {
    let text: String
    let documentID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
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
        textView.font = Self.font
        textView.defaultParagraphStyle = Self.paragraphStyle()
        textView.typingAttributes = Self.attributes()
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

        context.coordinator.attach(textView: textView, scrollView: scrollView)
        context.coordinator.apply(text: text, documentID: documentID)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.apply(text: text, documentID: documentID)
    }

    final class Coordinator {
        private var documentID: String?
        private weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?

        func attach(textView: NSTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView
        }

        func apply(text: String, documentID: String) {
            guard self.documentID != documentID, let textView else { return }
            self.documentID = documentID

            textView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: CodeView.attributes())
            )
            textView.scrollToBeginningOfDocument(nil)
            if let scrollView {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        style.tabStops = []
        style.defaultTabInterval = spaceWidth * 4
        return style
    }

    private static func attributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(),
        ]
    }
}

#if DEBUG
#Preview {
    CodeView(
        text: "struct Hello {\n\tlet message = \"Hello, Code Viewer\"\n}\n",
        documentID: "preview"
    )
    .frame(width: 700, height: 480)
}
#endif
