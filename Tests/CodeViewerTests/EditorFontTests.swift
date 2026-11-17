import AppKit
import Testing
@testable import CodeViewer

struct EditorFontTests {
    @Test("the default is the 13pt system monospaced font")
    func defaultIsSystemMono() {
        #expect(EditorFont.default.fontName == nil)
        #expect(EditorFont.default.size == 13)
        #expect(
            EditorFont.default.nsFont == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )
    }

    @Test("line height matches the layout-manager metric the ruler relies on")
    func lineHeightMatchesLayoutManager() {
        let font = EditorFont.default.nsFont
        let manager = NSLayoutManager()
        #expect(EditorFont.lineHeight(for: font) == manager.defaultLineHeight(for: font))
        #expect(
            EditorFont.default.lineHeight == (manager.defaultLineHeight(for: font) + 2).rounded()
        )
    }

    /// The row height the pinned paragraph style actually produces — the value
    /// the line-number ruler and the change markers must place themselves with.
    @MainActor
    private func laidOutHeight(_ font: EditorFont) -> CGFloat {
        let storage = NSTextStorage(
            string: "Ag\nAg\n",
            attributes: [
                .font: font.nsFont,
                .paragraphStyle: CodeTextFactory.paragraphStyle(font),
            ]
        )
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 1_000, height: 1_000))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
    }

    @Test("the line height is the height TextKit lays out, fractional leading included")
    @MainActor
    func lineHeightIsTheLaidOutHeight() {
        let fonts = [
            EditorFont.default,
            EditorFont(fontName: "Monaco", size: 12),
            EditorFont(fontName: "Monaco", size: 14),
            EditorFont(fontName: "Menlo", size: 15),
        ]
        for font in fonts {
            #expect(
                abs(font.lineHeight - laidOutHeight(font)) < 0.001,
                "\(font.id): ruler \(font.lineHeight) vs layout \(laidOutHeight(font))"
            )
            #expect(font.pinnedLineHeight == (EditorFont.lineHeight(for: font.nsFont) + 2).rounded())
        }
    }

    @Test("Monaco's fractional leading lands on the laid-out height, not the metric")
    @MainActor
    func monacoCorrectsFractionalLeading() {
        let font = EditorFont(fontName: "Monaco", size: 12)
        let metric = (EditorFont.lineHeight(for: font.nsFont) + 2).rounded()

        // Without the correction the ruler would sit a point high per line.
        #expect(font.lineHeight > metric)
        #expect(abs(font.lineHeight - laidOutHeight(font)) < 0.001)
    }

    @Test("sizes clamp into the offered range; empty names mean the system font")
    func clampingAndEmptyName() {
        #expect(EditorFont(fontName: nil, size: 42).size == EditorFont.sizeRange.upperBound)
        #expect(EditorFont(fontName: nil, size: 2).size == EditorFont.sizeRange.lowerBound)
        #expect(EditorFont(fontName: "", size: 13).fontName == nil)
        #expect(EditorFont(fontName: "Menlo", size: 15).fontName == "Menlo")
    }

    @Test("an unknown family falls back to the system monospaced font")
    func unknownFamilyFallsBack() {
        let font = EditorFont(fontName: "Not A Real Family", size: 13).nsFont
        #expect(font == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    @Test("ids distinguish family and size")
    func ids() {
        #expect(EditorFont.default.id == "system#13.0")
        #expect(EditorFont(fontName: "Menlo", size: 15).id == "Menlo#15.0")
    }

    @Test("the monospaced family list is populated with known mono families")
    func availableFamilies() {
        let families = EditorFont.availableFamilies()
        #expect(!families.isEmpty)
        // Menlo ships with macOS; the monospace filter must not drop it.
        #expect(families.contains("Menlo"))
        #expect(
            families == families.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        )
    }
}
