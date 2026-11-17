import AppKit

/// User-selectable editor font: a monospaced family plus size. Resolves into
/// the concrete font and the pinned line height the code pane and its
/// line-number ruler lay out with (see `CodeTextFactory`).
public struct EditorFont: Equatable, Sendable {
    /// The size range the settings UI offers; stored values outside the range
    /// clamp on load.
    public static let sizeRange: ClosedRange<CGFloat> = 9...28

    /// Font family name, or nil for the system monospaced font (SF Mono).
    public let fontName: String?
    public let size: CGFloat

    public static let `default` = EditorFont(fontName: nil, size: 13)

    /// Clamps `size` into `sizeRange`; an empty name means the system font.
    public init(fontName: String?, size: CGFloat) {
        self.fontName = (fontName?.isEmpty ?? true) ? nil : fontName
        self.size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
    }

    /// The concrete font. An unknown family name (uninstalled since it was
    /// picked) falls back to the system monospaced font so a stale stored
    /// name can never break rendering.
    public var nsFont: NSFont {
        guard let fontName, let font = NSFont(name: fontName, size: size) else {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return font
    }

    /// Line height the pane lays out with: the pinned paragraph metric plus
    /// whatever fraction of a point TextKit adds on top of it. The line-number
    /// ruler draws with this value (see `CodeTextFactory`), and the code pane
    /// derives its diff tints from the same rows, so the three can never drift
    /// apart.
    ///
    /// It is measured once per font rather than derived: for a font with
    /// fractional leading (Monaco at 12pt reports 16.002) TextKit lays each
    /// line out one point taller than `defaultLineHeight + 2` suggests, and a
    /// derived value left every ruler number a point higher per line than the
    /// text it labelled.
    public var lineHeight: CGFloat {
        Self.metricsLock.lock()
        defer { Self.metricsLock.unlock() }
        if let measured = Self.layoutHeights[id] { return measured }
        let measured = Self.layoutHeight(for: nsFont)
        Self.layoutHeights[id] = measured
        return measured
    }

    /// The `minimumLineHeight`/`maximumLineHeight` value the pane pins; the
    /// laid-out height above is this value as TextKit rounds it.
    public var pinnedLineHeight: CGFloat {
        Self.pinnedHeight(for: nsFont)
    }

    static func pinnedHeight(for font: NSFont) -> CGFloat {
        (lineHeight(for: font) + 2).rounded()
    }

    /// Rendered row heights per font id. The metrics below are pure
    /// functions of the font, so one recursive lock (NSLayoutManager is not
    /// thread-safe, and parallel tests reach the same metrics) keeps them
    /// callable from any thread.
    nonisolated(unsafe) private static var layoutHeights: [String: CGFloat] = [:]
    private static let metricsLock = NSRecursiveLock()

    /// Lays one line out with the pinned paragraph style and reports the row
    /// height TextKit actually produced.
    static func layoutHeight(for font: NSFont) -> CGFloat {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        let pinned = pinnedHeight(for: font)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = pinned
        style.maximumLineHeight = pinned
        style.lineSpacing = 0

        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 1_000, height: 1_000))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        storage.setAttributedString(NSAttributedString(
            string: "Ag",
            attributes: [.font: font, .paragraphStyle: style]
        ))
        layoutManager.ensureLayout(for: container)
        let height = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        return height > 0 ? height : pinned
    }

    /// The layout manager's default line height for `font` — the same metric
    /// TextKit lays out with, so the pinned paragraph style and the ruler
    /// agree.
    public static func lineHeight(for font: NSFont) -> CGFloat {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return metricsManager.defaultLineHeight(for: font)
    }

    private static let metricsManager = NSLayoutManager()

    /// Stable fragment for cache keys: family (or "system") and size.
    public var id: String {
        "\(fontName ?? "system")#\(size)"
    }

    /// Monospaced families installed on this machine, sorted for a picker.
    public static func availableFamilies() -> [String] {
        cachedFamilies
    }

    private static let cachedFamilies: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family),
                  let postScriptName = members.first?.first as? String,
                  let specimen = NSFont(name: postScriptName, size: 12) else {
                return false
            }
            return isMonospaced(specimen)
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    /// A narrow and a wide glyph share an advance only in a monospaced
    /// design — independent of how (or whether) the font reports traits.
    private static func isMonospaced(_ font: NSFont) -> Bool {
        if font.fontDescriptor.symbolicTraits.contains(.monoSpace) {
            return true
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let narrow = ("i" as NSString).size(withAttributes: attributes).width
        let wide = ("W" as NSString).size(withAttributes: attributes).width
        return narrow == wide
    }
}
