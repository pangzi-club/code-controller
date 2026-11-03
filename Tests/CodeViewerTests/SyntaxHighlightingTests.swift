import AppKit
import Testing
@testable import CodeViewer

struct SyntaxLanguageMapperTests {
    @Test("known extensions map to canonical highlight.js names")
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
}

@MainActor
struct HighlightCacheTests {
    @Test("round-trips a stored result and isolates themes")
    func roundTripsAndIsolatesThemes() {
        let cache = HighlightCache()
        let light = HighlightCache.Entry(attributed: NSAttributedString(string: "light"), background: nil)
        let dark = HighlightCache.Entry(attributed: NSAttributedString(string: "dark"), background: nil)
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
            HighlightCache.Entry(attributed: NSAttributedString(string: "a"), background: nil),
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
        cache.store(
            HighlightCache.Entry(attributed: NSAttributedString(string: "a"), background: nil),
            for: "a", theme: .light, fontID: fontID
        )
        cache.store(
            HighlightCache.Entry(attributed: NSAttributedString(string: "b"), background: nil),
            for: "b", theme: .light, fontID: fontID
        )

        // Touching "a" makes "b" the least recently used.
        _ = cache.result(for: "a", theme: .light, fontID: fontID)
        cache.store(
            HighlightCache.Entry(attributed: NSAttributedString(string: "c"), background: nil),
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
}

@Suite(.serialized)
struct HighlighterSwiftHighlighterTests {
    let highlighter = HighlighterSwiftHighlighter()

    @Test("highlighting preserves characters and adds theme colors")
    func highlightsSwiftPreservingCharacters() async throws {
        let source = "struct Hello {\n    let message = \"hi\"\n}\n"
        let result = try await highlighter.highlight(source, language: "swift", theme: .light)

        #expect(result.attributed.string == source)

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

    @Test("an unsupported language throws instead of rendering")
    func unsupportedLanguageThrows() async {
        await #expect(throws: HighlightError.self) {
            try await highlighter.highlight("x", language: "definitely-not-a-language", theme: .light)
        }
    }

    @Test("a user-picked theme reports its own background color")
    func pickedThemeReportsBackground() async throws {
        let source = "let x = 1\n"
        let result = try await highlighter.highlight(
            source,
            language: "swift",
            theme: HighlightTheme(name: "dracula")
        )

        #expect(result.attributed.string == source)
        #expect(result.background != nil)
    }

    @Test("a 1500-line Swift file highlights without trouble")
    func longFileStaysFast() async throws {
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
        let result = try await highlighter.highlight(source, language: "swift", theme: .dark)
        let elapsed = start.duration(to: .now)

        #expect(result.attributed.string == source)
        // Generous margin for CI machines; locally this lands well under 1s.
        #expect(elapsed < .seconds(10))
    }
}

@MainActor
struct HighlightServiceTests {
    private actor CountingHighlighter: SyntaxHighlighter {
        private(set) var callCount = 0

        func highlight(_ text: String, language: String, theme: HighlightTheme) async throws -> HighlightedText {
            callCount += 1
            try await Task.sleep(for: .milliseconds(150))
            return HighlightedText(attributed: NSAttributedString(string: text))
        }
    }

    @Test("concurrent identical requests share one highlight run")
    func concurrentIdenticalRequestsShareOneRun() async throws {
        let stub = CountingHighlighter()
        let service = HighlightService(highlighter: stub)

        async let first = service.highlight(requestKey: "k", text: "abc", language: "swift", theme: .light)
        async let second = service.highlight(requestKey: "k", text: "abc", language: "swift", theme: .light)
        let (a, b) = try await (first, second)

        #expect(a.attributed.string == "abc")
        #expect(b.attributed.string == "abc")
        #expect(await stub.callCount == 1)
    }

    @Test("different request keys run separately")
    func differentKeysRunSeparately() async throws {
        let stub = CountingHighlighter()
        let service = HighlightService(highlighter: stub)

        _ = try await service.highlight(requestKey: "k1", text: "abc", language: "swift", theme: .light)
        _ = try await service.highlight(requestKey: "k2", text: "abc", language: "swift", theme: .light)

        #expect(await stub.callCount == 2)
    }
}
