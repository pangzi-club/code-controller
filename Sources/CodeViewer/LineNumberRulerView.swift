import AppKit

/// Line numbers for a non-wrapping text view. Because the code pane uses one
/// fixed line height, visible lines can be derived from the scroll offset
/// without laying out the whole document.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineCount = 1
    private var boundsObserver: NSObjectProtocol?

    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let horizontalPadding: CGFloat = 8

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView

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
        let thickness = max(36, CGFloat(digits) * 7 + horizontalPadding * 2)
        if abs(ruleThickness - thickness) > 0.5 {
            ruleThickness = thickness
            scrollView?.tile()
        }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.lineWidth = 1
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.stroke()

        guard let textView, let scrollView else { return }

        let visibleRect = scrollView.contentView.bounds
        let inset = textView.textContainerInset.height
        let lineHeight = CodeTextFactory.lineHeight
        let firstLine = max(0, Int(floor((visibleRect.minY - inset) / lineHeight)))
        let lastLine = min(lineCount - 1, Int(ceil((visibleRect.maxY - inset) / lineHeight)))
        guard firstLine <= lastLine else { return }

        let textViewOrigin = convert(NSPoint.zero, from: textView)
        let numberHeight = CodeTextFactory.lineHeight(for: Self.numberFont)
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
