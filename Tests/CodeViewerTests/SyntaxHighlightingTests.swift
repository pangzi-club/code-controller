import AppKit
import Testing
@testable import CodeViewer

struct SyntaxLanguageMapperTests {
    @Test("known extensions map to canonical language names")
    func mapsKnownExtensions() {
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "swift") == "swift")
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "json") == "json")
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "md") == "markdown")
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "mm") == "objectivec")
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "yml") == "yaml")
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "h") == "c")
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "tsx") == "typescript")
    }

    @Test("extension lookup is case-insensitive")
    func isCaseInsensitive() {
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "SWIFT") == "swift")
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "Md") == "markdown")
    }

    @Test("unknown extensions render plain text")
    func unknownExtensionsReturnNil() {
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "xyzzy") == nil)
        #expect(SyntaxLanguageMapper.highlightLanguage(forExtension: "") == nil)
    }

    @Test("every mapped language has scanner rules")
    func mappedLanguagesHaveRules() {
        #expect(!SyntaxLanguageMapper.languages.isEmpty)
        for language in SyntaxLanguageMapper.languages {
            #expect(NativeHighlighter.supports(language), "no scanner rules for \(language)")
        }
    }
}

@MainActor
struct HighlightCacheTests {
    @Test("round-trips a stored result and isolates themes")
    func roundTripsAndIsolatesThemes() {
        let cache = HighlightCache()
        let light = HighlightCache.Entry(attributed: NSAttributedString(string: "light"), background: EditorTheme.light.background)
        let fontID = EditorFont.default.id

        #expect(cache.result(for: "doc#1", theme: .light, fontID: fontID) == nil)

        cache.store(light, for: "doc#1", theme: .light, fontID: fontID)
        #expect(cache.result(for: "doc#1", theme: .light, fontID: fontID)?.attributed == light.attributed)
        #expect(cache.result(for: "doc#1", theme: .dark, fontID: fontID) == nil)
    }

    @Test("a font change misses the cache")
    func isolatesFonts() {
        let cache = HighlightCache()
        cache.store(
            HighlightCache.Entry(attributed: NSAttributedString(string: "a"), background: EditorTheme.light.background),
            for: "doc#1",
            theme: .light,
            fontID: "system#13.0"
        )

        #expect(cache.result(for: "doc#1", theme: .light, fontID: "system#13.0") != nil)
        #expect(cache.result(for: "doc#1", theme: .light, fontID: "system#15.0") == nil)
    }

    @Test("evicts the least recently used entry")
    func evictsLeastRecentlyUsed() {
        let cache = HighlightCache(capacity: 2)
        let fontID = EditorFont.default.id
        let background = EditorTheme.light.background
        cache.store(
            HighlightCache.Entry(attributed: NSAttributedString(string: "a"), background: background),
            for: "a", theme: .light, fontID: fontID
        )
        cache.store(
            HighlightCache.Entry(attributed: NSAttributedString(string: "b"), background: background),
            for: "b", theme: .light, fontID: fontID
        )

        // Touching "a" makes "b" the least recently used.
        _ = cache.result(for: "a", theme: .light, fontID: fontID)
        cache.store(
            HighlightCache.Entry(attributed: NSAttributedString(string: "c"), background: background),
            for: "c", theme: .light, fontID: fontID
        )

        #expect(cache.result(for: "a", theme: .light, fontID: fontID) != nil)
        #expect(cache.result(for: "b", theme: .light, fontID: fontID) == nil)
        #expect(cache.result(for: "c", theme: .light, fontID: fontID) != nil)
    }
}

@MainActor
struct CodeTextFactoryStylingTests {
    @Test("styling keeps characters and pins the line metrics")
    func preservesCharactersAndPinsMetrics() {
        let input = NSMutableAttributedString(string: "let x = 1\n")
        input.addAttributes(
            [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.boldSystemFont(ofSize: 17),
                .backgroundColor: NSColor.yellow,
            ],
            range: NSRange(location: 0, length: 3)
        )

        let editorFont = EditorFont.default
        let styled = CodeTextFactory.styled(input, font: editorFont)

        #expect(styled.string == input.string)

        let paragraph = styled.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(paragraph?.minimumLineHeight == editorFont.lineHeight)
        #expect(paragraph?.maximumLineHeight == editorFont.lineHeight)

        // The pinned mono font wins, but the theme's bold trait survives so
        // themes can still emphasize keywords.
        let font = styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == editorFont.nsFont.pointSize)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let plainFont = styled.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        #expect(plainFont?.fontDescriptor.symbolicTraits.contains(.bold) == false)

        // The pane owns the background; theme colors are kept.
        #expect(styled.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.systemRed)
    }

    @Test("falls back to label color when the highlighter omits one")
    func fillsMissingForeground() {
        let styled = CodeTextFactory.styled(
            NSAttributedString(string: "plain"),
            font: .default
        )
        let color = styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.labelColor)
    }

    @Test("a custom editor font replaces the highlighter's fonts, traits preserved")
    func usesCustomEditorFont() throws {
        let editorFont = EditorFont(fontName: "Menlo", size: 15)
        let input = NSAttributedString(string: "let x = 1")
        let styled = CodeTextFactory.styled(input, font: editorFont)

        let font = try #require(styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 15)
        #expect(font.familyName == "Menlo")
    }

    @Test("markdown emphasis traits survive the font swap")
    func preservesEmphasisTraits() {
        let input = NSMutableAttributedString(string: "**bold** and *em*")
        input.addAttribute(.font, value: SyntaxScanner.boldMarker, range: NSRange(location: 0, length: 8))
        input.addAttribute(.font, value: SyntaxScanner.italicMarker, range: NSRange(location: 13, length: 4))

        let styled = CodeTextFactory.styled(input, font: .default)
        let bold = styled.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        let italic = styled.attribute(.font, at: 14, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(italic?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }
}

struct EditorThemeTests {
    @Test("every theme covers every token kind")
    func palettesAreComplete() {
        for theme in EditorTheme.allCases {
            #expect(theme.coversAllTokens, "\(theme.rawValue) is missing token colors")
        }
    }

    @Test("dark themes have dark backgrounds and light themes light ones")
    func backgroundMatchesAppearance() {
        for theme in EditorTheme.allCases {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            theme.background.usingColorSpace(.sRGB)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            #expect((luminance < 0.5) == theme.isDark, "\(theme.rawValue) background \(luminance)")
        }
    }

    @Test("theme raw values round-trip and the stock pair matches the defaults")
    func rawValuesRoundTrip() {
        for theme in EditorTheme.allCases {
            #expect(EditorTheme(rawValue: theme.rawValue) == theme)
        }
        #expect(EditorTheme.light == .xcode)
        #expect(EditorTheme.dark == .xcodeDusk)
        #expect(EditorTheme.xcodeDusk.rawValue == "xcode-dusk")
    }
}

struct NativeHighlighterTests {
    let highlighter = NativeHighlighter()

    @Test("highlighting preserves characters and adds theme colors")
    func highlightsSwiftPreservingCharacters() {
        let source = "struct Hello {\n    let message = \"hi\"\n}\n"
        let result = highlighter.highlight(source, language: "swift", theme: .light)

        #expect(result.attributed.string == source)
        #expect(result.background == EditorTheme.light.background)

        var colors = Set<ObjectIdentifier>()
        result.attributed.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: result.attributed.length)
        ) { value, _, _ in
            if let color = value as? NSColor {
                colors.insert(ObjectIdentifier(color))
            }
        }
        #expect(colors.count > 1)
    }

    @Test("an unsupported language renders plain text in the theme's colors")
    func unsupportedLanguageIsPlain() {
        let result = highlighter.highlight("x = 1", language: "definitely-not-a-language", theme: .dark)

        #expect(result.attributed.string == "x = 1")
        #expect(result.attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == EditorTheme.dark.color(for: .plain))
        #expect(result.background == EditorTheme.dark.background)
    }

    @Test("a 1500-line Swift file highlights quickly")
    func longFileStaysFast() {
        var lines: [String] = []
        lines.reserveCapacity(1500)
        for index in 0..<375 {
            lines.append("func generated_\(index)(_ value: Int) -> Int {")
            lines.append("    let label = \"row \(index)\" // annotate")
            lines.append("    return value + \(index)")
            lines.append("}")
        }
        let source = lines.joined(separator: "\n") + "\n"
        #expect(lines.count == 1500)

        let start = ContinuousClock.now
        let result = highlighter.highlight(source, language: "swift", theme: .dark)
        let elapsed = start.duration(to: .now)

        #expect(result.attributed.string == source)
        // Generous margin for CI machines; locally this lands in a few ms.
        #expect(elapsed < .seconds(2))
    }
}

@MainActor
struct HighlightServiceTests {
    private final class CountingHighlighter: SyntaxHighlighter, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func highlight(_ text: String, language: String, theme: EditorTheme) -> HighlightedText {
            lock.lock()
            count += 1
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.05)
            return HighlightedText(attributed: NSAttributedString(string: text), background: theme.background)
        }
    }

    @Test("concurrent identical requests share one highlight run")
    func concurrentIdenticalRequestsShareOneRun() async {
        let stub = CountingHighlighter()
        let service = HighlightService(highlighter: stub)

        async let first = service.highlight(requestKey: "k", text: "abc", language: "swift", theme: .light)
        async let second = service.highlight(requestKey: "k", text: "abc", language: "swift", theme: .light)
        let (a, b) = await (first, second)

        #expect(a.attributed.string == "abc")
        #expect(b.attributed.string == "abc")
        #expect(stub.callCount == 1)
    }

    @Test("different request keys run separately")
    func differentKeysRunSeparately() async {
        let stub = CountingHighlighter()
        let service = HighlightService(highlighter: stub)

        _ = await service.highlight(requestKey: "k1", text: "abc", language: "swift", theme: .light)
        _ = await service.highlight(requestKey: "k2", text: "abc", language: "swift", theme: .light)

        #expect(stub.callCount == 2)
    }
}
