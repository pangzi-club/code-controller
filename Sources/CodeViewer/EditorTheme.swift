import AppKit

/// Token classes the built-in scanner recognizes. A theme's palette maps
/// each one to a color, so the scanner itself never deals with colors.
public enum TokenKind: CaseIterable, Hashable, Sendable {
    case plain, comment, keyword, literal, string, number, type, function, builtIn
    case attribute, variable, tag, name, punctuation, operatorSymbol, property, meta
    case added, removed, link, bullet, section, quote, code, symbol
}

/// Code color scheme. Each case carries the palette of the highlight.js theme
/// of the same name, so the colors match what the editor showed when it still
/// rendered through highlight.js. Raw values are the persisted UserDefaults
/// values and must not change.
public enum EditorTheme: String, CaseIterable, Sendable {
    case xcode
    case xcodeDusk = "xcode-dusk"
    case github
    case githubDark = "github-dark"
    case atomOneLight = "atom-one-light"
    case atomOneDark = "atom-one-dark"
    case dracula
    case nord
    case monokai
    case solarizedLight = "solarized-light"
    case solarizedDark = "solarized-dark"
    case tokyoNight = "tokyo-night-dark"
    case vsDark = "vs-dark"

    /// The stock pair: Xcode in light mode, Xcode Dusk in dark.
    public static let light = EditorTheme.xcode
    public static let dark = EditorTheme.xcodeDusk

    /// Localization key for the picker item. Theme names are proper nouns and
    /// keep their spelling in both catalogs.
    var labelKey: String {
        switch self {
        case .xcode: "Xcode"
        case .xcodeDusk: "Xcode Dusk"
        case .github: "GitHub"
        case .githubDark: "GitHub Dark"
        case .atomOneLight: "Atom One Light"
        case .atomOneDark: "Atom One Dark"
        case .dracula: "Dracula"
        case .nord: "Nord"
        case .monokai: "Monokai"
        case .solarizedLight: "Solarized Light"
        case .solarizedDark: "Solarized Dark"
        case .tokyoNight: "Tokyo Night"
        case .vsDark: "VS Dark"
        }
    }

    /// Whether the palette is meant for a dark interface.
    public var isDark: Bool {
        switch self {
        case .xcode, .github, .atomOneLight, .solarizedLight: false
        case .xcodeDusk, .githubDark, .atomOneDark, .dracula, .nord, .monokai,
             .solarizedDark, .tokyoNight, .vsDark: true
        }
    }

    /// The background every theme renders on.
    public var background: NSColor { Self.palettes[self]!.background }

    func color(for kind: TokenKind) -> NSColor { Self.palettes[self]![kind] }

    /// Whether the palette has its own color for every token class (rather
    /// than falling back to the plain text color for an omitted one).
    var coversAllTokens: Bool { Self.palettes[self]!.isComplete }

    /// Built once per process; `NSColor` instances are immutable and safe to
    /// share across the scanner's background tasks.
    private static let palettes: [EditorTheme: Palette] = {
        var palettes: [EditorTheme: Palette] = [:]
        for theme in EditorTheme.allCases {
            palettes[theme] = Palette(hex: theme.hexValues)
        }
        return palettes
    }()

    /// Colors taken from the theme's highlight.js CSS: one entry per token
    /// class, resolved through the same fallbacks the old renderer applied
    /// (a class the CSS omits inherits from the closest related class, and
    /// finally from the base text color).
    private var hexValues: (background: String, colors: [TokenKind: String]) {
        switch self {
        case .xcode:
            return ("#FFFFFF", [
                .plain: "#000000", .comment: "#007400", .keyword: "#AA0D91",
                .literal: "#AA0D91", .string: "#C41A16", .number: "#1C00CF", .type: "#5C2699",
                .function: "#1C00CF", .builtIn: "#5C2699", .attribute: "#836C28", .variable: "#3F6E74",
                .tag: "#AA0D91", .name: "#AA0D91", .punctuation: "#000000", .operatorSymbol: "#000000",
                .property: "#AA0D91", .meta: "#643820", .added: "#000000", .removed: "#000000",
                .link: "#0E0EFF", .bullet: "#1C00CF", .section: "#643820", .quote: "#007400",
                .code: "#C41A16", .symbol: "#1C00CF",
            ])
        case .xcodeDusk:
            return ("#282B35", [
                .plain: "#939599", .comment: "#686A71", .keyword: "#B21889",
                .literal: "#786DC5", .string: "#DF0002", .number: "#786DC5", .type: "#B21889",
                .function: "#438288", .builtIn: "#00A0BE", .attribute: "#786DC5", .variable: "#B21889",
                .tag: "#7E8086", .name: "#B21889", .punctuation: "#939599", .operatorSymbol: "#939599",
                .property: "#790EAD", .meta: "#C77C48", .added: "#DF0002", .removed: "#B21889",
                .link: "#786DC5", .bullet: "#B21889", .section: "#790EAD", .quote: "#00A0BE",
                .code: "#DF0002", .symbol: "#786DC5",
            ])
        case .github:
            return ("#FFFFFF", [
                .plain: "#24292E", .comment: "#6A737D", .keyword: "#D73A49",
                .literal: "#005CC5", .string: "#032F62", .number: "#005CC5", .type: "#D73A49",
                .function: "#6F42C1", .builtIn: "#E36209", .attribute: "#005CC5", .variable: "#005CC5",
                .tag: "#22863A", .name: "#22863A", .punctuation: "#24292E", .operatorSymbol: "#005CC5",
                .property: "#005CC5", .meta: "#005CC5", .added: "#22863A", .removed: "#B31D28",
                .link: "#005CC5", .bullet: "#735C0F", .section: "#005CC5", .quote: "#22863A",
                .code: "#6A737D", .symbol: "#E36209",
            ])
        case .githubDark:
            return ("#0D1117", [
                .plain: "#C9D1D9", .comment: "#8B949E", .keyword: "#FF7B72",
                .literal: "#79C0FF", .string: "#A5D6FF", .number: "#79C0FF", .type: "#FF7B72",
                .function: "#D2A8FF", .builtIn: "#FFA657", .attribute: "#79C0FF", .variable: "#79C0FF",
                .tag: "#7EE787", .name: "#7EE787", .punctuation: "#C9D1D9", .operatorSymbol: "#79C0FF",
                .property: "#79C0FF", .meta: "#79C0FF", .added: "#AFF5B4", .removed: "#FFDCD7",
                .link: "#79C0FF", .bullet: "#F2CC60", .section: "#1F6FEB", .quote: "#7EE787",
                .code: "#8B949E", .symbol: "#FFA657",
            ])
        case .atomOneLight:
            return ("#FAFAFA", [
                .plain: "#383A42", .comment: "#A0A1A7", .keyword: "#A626A4",
                .literal: "#0184BB", .string: "#50A14F", .number: "#986801", .type: "#986801",
                .function: "#4078F2", .builtIn: "#C18401", .attribute: "#986801", .variable: "#986801",
                .tag: "#E45649", .name: "#E45649", .punctuation: "#383A42", .operatorSymbol: "#383A42",
                .property: "#50A14F", .meta: "#4078F2", .added: "#50A14F", .removed: "#E45649",
                .link: "#4078F2", .bullet: "#4078F2", .section: "#E45649", .quote: "#A0A1A7",
                .code: "#50A14F", .symbol: "#4078F2",
            ])
        case .atomOneDark:
            return ("#282C34", [
                .plain: "#ABB2BF", .comment: "#5C6370", .keyword: "#C678DD",
                .literal: "#56B6C2", .string: "#98C379", .number: "#D19A66", .type: "#D19A66",
                .function: "#61AEEE", .builtIn: "#E6C07B", .attribute: "#D19A66", .variable: "#D19A66",
                .tag: "#E06C75", .name: "#E06C75", .punctuation: "#ABB2BF", .operatorSymbol: "#ABB2BF",
                .property: "#98C379", .meta: "#61AEEE", .added: "#98C379", .removed: "#E06C75",
                .link: "#61AEEE", .bullet: "#61AEEE", .section: "#E06C75", .quote: "#5C6370",
                .code: "#98C379", .symbol: "#61AEEE",
            ])
        case .dracula:
            return ("#282936", [
                .plain: "#E9E9F4", .comment: "#626483", .keyword: "#B45BCF",
                .literal: "#B45BCF", .string: "#EBFF87", .number: "#B45BCF", .type: "#B45BCF",
                .function: "#00F769", .builtIn: "#A1EFE4", .attribute: "#B45BCF", .variable: "#EA51B2",
                .tag: "#62D6E8", .name: "#EA51B2", .punctuation: "#E9E9F4", .operatorSymbol: "#E9E9F4",
                .property: "#62D6E8", .meta: "#00F769", .added: "#EBFF87", .removed: "#EA51B2",
                .link: "#B45BCF", .bullet: "#EA51B2", .section: "#62D6E8", .quote: "#A1EFE4",
                .code: "#EBFF87", .symbol: "#B45BCF",
            ])
        case .nord:
            return ("#2E3440", [
                .plain: "#D8DEE9", .comment: "#4C566A", .keyword: "#81A1C1",
                .literal: "#81A1C1", .string: "#A3BE8C", .number: "#B48EAD", .type: "#8FBCBB",
                .function: "#8FBCBB", .builtIn: "#8FBCBB", .attribute: "#8FBCBB", .variable: "#D8DEE9",
                .tag: "#81A1C1", .name: "#81A1C1", .punctuation: "#D8DEE9", .operatorSymbol: "#D8DEE9",
                .property: "#88C0D0", .meta: "#5E81AC", .added: "#D8DEE9", .removed: "#D8DEE9",
                .link: "#D8DEE9", .bullet: "#81A1C1", .section: "#88C0D0", .quote: "#4C566A",
                .code: "#8FBCBB", .symbol: "#81A1C1",
            ])
        case .monokai:
            return ("#272822", [
                .plain: "#DDDDDD", .comment: "#75715E", .keyword: "#F92672",
                .literal: "#F92672", .string: "#A6E22E", .number: "#F92672", .type: "#A6E22E",
                .function: "#A6E22E", .builtIn: "#A6E22E", .attribute: "#BF79DB", .variable: "#A6E22E",
                .tag: "#F92672", .name: "#F92672", .punctuation: "#DDDDDD", .operatorSymbol: "#DDDDDD",
                .property: "#BF79DB", .meta: "#75715E", .added: "#A6E22E", .removed: "#75715E",
                .link: "#BF79DB", .bullet: "#A6E22E", .section: "#A6E22E", .quote: "#75715E",
                .code: "#66D9EF", .symbol: "#BF79DB",
            ])
        case .solarizedLight:
            return ("#FDF6E3", [
                .plain: "#586E75", .comment: "#839496", .keyword: "#6C71C4",
                .literal: "#CB4B16", .string: "#859900", .number: "#CB4B16", .type: "#6C71C4",
                .function: "#B58900", .builtIn: "#2AA198", .attribute: "#CB4B16", .variable: "#DC322F",
                .tag: "#657B83", .name: "#DC322F", .punctuation: "#586E75", .operatorSymbol: "#586E75",
                .property: "#268BD2", .meta: "#D33682", .added: "#859900", .removed: "#DC322F",
                .link: "#CB4B16", .bullet: "#DC322F", .section: "#268BD2", .quote: "#2AA198",
                .code: "#859900", .symbol: "#CB4B16",
            ])
        case .solarizedDark:
            return ("#002B36", [
                .plain: "#93A1A1", .comment: "#657B83", .keyword: "#6C71C4",
                .literal: "#CB4B16", .string: "#859900", .number: "#CB4B16", .type: "#6C71C4",
                .function: "#B58900", .builtIn: "#2AA198", .attribute: "#CB4B16", .variable: "#DC322F",
                .tag: "#839496", .name: "#DC322F", .punctuation: "#93A1A1", .operatorSymbol: "#93A1A1",
                .property: "#268BD2", .meta: "#D33682", .added: "#859900", .removed: "#DC322F",
                .link: "#CB4B16", .bullet: "#DC322F", .section: "#268BD2", .quote: "#2AA198",
                .code: "#859900", .symbol: "#CB4B16",
            ])
        case .tokyoNight:
            return ("#1A1B26", [
                .plain: "#9AA5CE", .comment: "#565F89", .keyword: "#BB9AF7",
                .literal: "#FF9E64", .string: "#9ECE6A", .number: "#FF9E64", .type: "#FF9E64",
                .function: "#7DCFFF", .builtIn: "#E0AF68", .attribute: "#BB9AF7", .variable: "#FF9E64",
                .tag: "#F7768E", .name: "#BB9AF7", .punctuation: "#C0CAF5", .operatorSymbol: "#BB9AF7",
                .property: "#7DCFFF", .meta: "#565F89", .added: "#9ECE6A", .removed: "#F7768E",
                .link: "#FF9E64", .bullet: "#9ECE6A", .section: "#7AA2F7", .quote: "#9ECE6A",
                .code: "#7AA2F7", .symbol: "#9ECE6A",
            ])
        case .vsDark:
            return ("#202020", [
                .plain: "#CCCCCC", .comment: "#6A9954", .keyword: "#579CD6",
                .literal: "#CE9178", .string: "#CE9178", .number: "#CE9178", .type: "#CE9178",
                .function: "#CE9178", .builtIn: "#579CD6", .attribute: "#9DDCFE", .variable: "#6A9954",
                .tag: "#579CD6", .name: "#579CD6", .punctuation: "#CCCCCC", .operatorSymbol: "#CCCCCC",
                .property: "#CE9178", .meta: "#D4D4D4", .added: "#CE9178", .removed: "#D4D4D4",
                .link: "#00B0E8", .bullet: "#00B0E8", .section: "#CE9178", .quote: "#6A9954",
                .code: "#CE9178", .symbol: "#00B0E8",
            ])
        }
    }
}

/// A theme's resolved colors. Built once per theme; immutable afterwards.
struct Palette: Sendable {
    let background: NSColor
    private let colors: [TokenKind: NSColor]

    init(hex: (background: String, colors: [TokenKind: String])) {
        self.background = NSColor(hex: hex.background)
        self.colors = hex.colors.mapValues { NSColor(hex: $0) }
    }

    subscript(kind: TokenKind) -> NSColor {
        colors[kind] ?? colors[.plain]!
    }

    /// Whether the source CSS covered every token class; a palette missing
    /// one still renders (through the plain fallback) but is a sign the
    /// table drifted from `TokenKind`.
    var isComplete: Bool {
        TokenKind.allCases.allSatisfy { colors[$0] != nil }
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
