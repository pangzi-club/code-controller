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

    /// Line height the pane pins through `minimumLineHeight`/`maximumLineHeight`
    /// (+2pt leading and rounded, the fixed-metrics contract the line-number
    /// ruler depends on — it derives visible lines from this without querying
    /// TextKit layout).
    public var lineHeight: CGFloat {
        (Self.lineHeight(for: nsFont) + 2).rounded()
    }

    /// The layout manager's default line height for `font` — the same metric
    /// TextKit lays out with, so the pinned paragraph style and the ruler
    /// agree. NSLayoutManager is not thread-safe; every caller runs on the
    /// main thread (the code pane's restyling paths all do).
    public static func lineHeight(for font: NSFont) -> CGFloat {
        metricsManager.defaultLineHeight(for: font)
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
