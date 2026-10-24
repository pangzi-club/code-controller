import AppKit

/// Plain NSView that fills itself with a dynamic NSColor at draw time, so
/// backgrounds follow light/dark appearance without layer-color bookkeeping.
/// With `topHairline` it also draws the template's 1pt separator at its top
/// edge — both main-window panes enable it, so the line under the toolbar
/// spans the sidebar and the content in one continuous stroke (the system
/// titlebar separator skips sidebar regions and may not render at all when
/// the titlebar is transparent).
final class BackgroundColorView: NSView {
    private let backgroundColor: NSColor
    private let topHairline: Bool

    init(backgroundColor: NSColor, topHairline: Bool = false) {
        self.backgroundColor = backgroundColor
        self.topHairline = topHairline
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        if topHairline, dirtyRect.minY < 1 {
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
    }
}

/// Layer-backed container that casts the template's soft card shadow on its
/// content (NSBox itself cannot draw shadows).
final class ShadowContainer: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 8
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Small rounded pill showing a count, e.g. the sidebar folder total.
final class CountBadge: NSView {
    private var count = 0

    private var text: String { "\(count)" }
    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
    }

    func setCount(_ newCount: Int) {
        count = newCount
        isHidden = newCount == 0
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let width = count == 0
            ? NSView.noIntrinsicMetric
            : text.size(withAttributes: textAttributes).width + 14
        return NSSize(width: width, height: 16)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard count > 0 else { return }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let size = text.size(withAttributes: textAttributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: textAttributes
        )
    }
}

/// Dashed-outline button matching the sidebar footer: a rounded rect with a
/// dashed hairline that darkens on hover, containing an optional symbol plus
/// a title, both tinted accent on hover.
final class DashedButton: NSControl {
    private let symbol: NSImage?
    private let titleText: String
    private var hovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(symbol name: String? = nil, title: String, target: AnyObject?, action: Selector) {
        symbol = name.map { symbolImage($0, pointSize: 11, weight: .semibold) }
        titleText = title
        super.init(frame: .zero)
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        path.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(hovered ? 0.35 : 0.15).setStroke()
        path.stroke()

        let tint: NSColor = hovered ? .controlAccentColor : .secondaryLabelColor
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: tint,
        ]
        let titleSize = titleText.size(withAttributes: titleAttributes)
        let iconSize = symbol?.size ?? .zero
        let spacing: CGFloat = symbol != nil && !titleText.isEmpty ? 6 : 0
        var x = bounds.midX - (iconSize.width + spacing + titleSize.width) / 2

        if let symbol {
            Self.tinted(symbol, tint).draw(
                in: NSRect(x: x, y: bounds.midY - iconSize.height / 2, width: iconSize.width, height: iconSize.height)
            )
            x += iconSize.width + spacing
        }
        titleText.draw(
            at: NSPoint(x: x, y: bounds.midY - titleSize.height / 2),
            withAttributes: titleAttributes
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        guard let action, let target else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    /// Renders a template symbol in the given color (symbols draw black by
    /// default; compositing sourceAtop recolors them).
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
