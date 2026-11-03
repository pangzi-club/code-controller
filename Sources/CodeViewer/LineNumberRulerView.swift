import AppKit

/// Line numbers for a non-wrapping text view. Because the code pane uses one
/// fixed line height, visible lines can be derived from the scroll offset
/// without laying out the whole document.
final class LineNumberRulerView: NSView {
    static let minimumWidth: CGFloat = 36

    var onWidthChange: ((CGFloat) -> Void)?

    /// The editor font's pinned line height (see `EditorFont.lineHeight`):
    /// visible lines derive from the scroll offset without laying out the
    /// document, so this must match the attributed text's paragraph style.
    var lineHeight: CGFloat {
        didSet { needsDisplay = true }
    }

    /// Fill color behind the numbers; themed code panes pass their theme
    /// background, the stock look keeps the system control background.
    var backgroundColor: NSColor = .controlBackgroundColor {
        didSet { needsDisplay = true }
    }

    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?
    private var lineCount = 1
    private var boundsObserver: NSObjectProtocol?

    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let horizontalPadding: CGFloat = 8

    init(textView: NSTextView, scrollView: NSScrollView, lineHeight: CGFloat) {
        self.textView = textView
        self.scrollView = scrollView
        self.lineHeight = lineHeight
        super.init(frame: .zero)

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override var isFlipped: Bool { true }

    static func lineCount(in text: String) -> Int {
        var count = 1
        for byte in text.utf8 where byte == 0x0A {
            count += 1
        }
        return count
    }

    func update(text: String) {
        lineCount = Self.lineCount(in: text)
        let digits = String(lineCount).count
        let width = max(Self.minimumWidth, CGFloat(digits) * 7 + horizontalPadding * 2)
        onWidthChange?(width)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.lineWidth = 1
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        separator.stroke()

        guard let textView, let scrollView else { return }

        let visibleRect = scrollView.contentView.bounds
        let inset = textView.textContainerInset.height
        let lineHeight = self.lineHeight
        let firstLine = max(0, Int(floor((visibleRect.minY - inset) / lineHeight)))
        let lastLine = min(lineCount - 1, Int(ceil((visibleRect.maxY - inset) / lineHeight)))
        guard firstLine <= lastLine else { return }

        let textViewOrigin = convert(NSPoint.zero, from: textView)
        let numberHeight = EditorFont.lineHeight(for: Self.numberFont)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.numberFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        for line in firstLine...lastLine {
            let y = textViewOrigin.y
                + inset
                + CGFloat(line) * lineHeight
                + (lineHeight - numberHeight) / 2
            let numberRect = NSRect(
                x: 0,
                y: y,
                width: bounds.width - horizontalPadding,
                height: numberHeight
            )
            "\(line + 1)".draw(in: numberRect, withAttributes: attributes)
        }
    }
}
