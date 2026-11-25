import Foundation
import Testing
@testable import CodeViewer

/// The preview tree as swift-markdown + the adapter produce it. These pin
/// the shapes the renderer relies on, not CommonMark itself.
@Suite
struct MarkdownDocumentTests {
    private func parse(_ text: String) -> [MarkdownDocument.Block] {
        MarkdownDocument(parsing: text).blocks
    }

    @Test("ATX and setext headings")
    func headings() {
        #expect(parse("# Title ##\n### Sub\n\nSubtitle\n-----") == [
            .heading(level: 1, content: [.text("Title")]),
            .heading(level: 3, content: [.text("Sub")]),
            .heading(level: 2, content: [.text("Subtitle")]),
        ])
    }

    @Test("soft breaks become spaces; trailing spaces or a backslash make a hard break")
    func lineBreaks() {
        #expect(parse("first\nsecond  \nthird\\\nfourth") == [
            .paragraph([.text("first second"), .lineBreak, .text("third"), .lineBreak, .text("fourth")]),
        ])
    }

    @Test("fenced and indented code keep their language and content")
    func codeBlocks() {
        #expect(parse("```swift\nlet x = 1\n    indented\n```\n\n    plain code\n") == [
            .codeBlock(language: "swift", code: "let x = 1\n    indented"),
            .codeBlock(language: nil, code: "plain code"),
        ])
    }

    @Test("quotes nest and take lazy continuation lines")
    func blockQuotes() {
        #expect(parse("> first\n> > nested\nlazy\n\nafter") == [
            .quote([
                .paragraph([.text("first")]),
                .quote([.paragraph([.text("nested lazy")])]),
            ]),
            .paragraph([.text("after")]),
        ])
    }

    @Test("lists nest, continue lazily, keep their start and lose task checkboxes")
    func lists() {
        #expect(parse(
            "- one\ntwo\n- three\n  - nested\n\n- four\n\n3. third\n4. fourth\n\n- [ ] todo\n- [x] done"
        ) == [
            .list(MarkdownDocument.List(isOrdered: false, start: 1, isLoose: true, items: [
                MarkdownDocument.Item(task: .none, blocks: [.paragraph([.text("one two")])]),
                MarkdownDocument.Item(task: .none, blocks: [
                    .paragraph([.text("three")]),
                    .list(MarkdownDocument.List(isOrdered: false, start: 1, isLoose: false, items: [
                        MarkdownDocument.Item(task: .none, blocks: [.paragraph([.text("nested")])]),
                    ])),
                ]),
                MarkdownDocument.Item(task: .none, blocks: [.paragraph([.text("four")])]),
            ])),
            .list(MarkdownDocument.List(isOrdered: true, start: 3, isLoose: false, items: [
                MarkdownDocument.Item(task: .none, blocks: [.paragraph([.text("third")])]),
                MarkdownDocument.Item(task: .none, blocks: [.paragraph([.text("fourth")])]),
            ])),
            .list(MarkdownDocument.List(isOrdered: false, start: 1, isLoose: false, items: [
                MarkdownDocument.Item(task: .unchecked, blocks: [.paragraph([.text("todo")])]),
                MarkdownDocument.Item(task: .checked, blocks: [.paragraph([.text("done")])]),
            ])),
        ])
    }

    @Test("tables carry alignment, unescape pipes and pad short rows")
    func tables() {
        #expect(parse("| Name | Note |\n| :--- | ---: |\n| a | b \\| c |\n| d |") == [
            .table(MarkdownDocument.Table(
                alignments: [.leading, .trailing],
                header: [[.text("Name")], [.text("Note")]],
                rows: [
                    [[.text("a")], [.text("b | c")]],
                    [[.text("d")], []],
                ]
            )),
        ])
    }

    @Test("inline code, links, reference links and images")
    func linksAndImages() {
        #expect(parse(
            "Use `npm run` now. See [docs](docs/guide.md#x \"Title\"), [ref][r], [R].\n\n"
            + "![Alt](img/a.png) and ![b]\n\n[r]: https://example.com/ \"t\"\n[b]: assets/b.png"
        ) == [
            .paragraph([
                .text("Use "), .code("npm run"), .text(" now. See "),
                .link(destination: "docs/guide.md#x", content: [.text("docs")]), .text(", "),
                .link(destination: "https://example.com/", content: [.text("ref")]), .text(", "),
                .link(destination: "https://example.com/", content: [.text("R")]), .text("."),
            ]),
            .paragraph([
                .image(source: "img/a.png", alt: "Alt"), .text(" and "),
                .image(source: "assets/b.png", alt: "b"),
            ]),
        ])
    }

    @Test("emphasis follows the CommonMark flanking rules")
    func emphasis() {
        #expect(parse("*a* **b** ***c*** _d_ ~~e~~ snake_case_word a*b*c") == [
            .paragraph([
                .emphasis([.text("a")]), .text(" "),
                .strong([.text("b")]), .text(" "),
                .emphasis([.strong([.text("c")])]), .text(" "),
                .emphasis([.text("d")]), .text(" "),
                .strikethrough([.text("e")]), .text(" snake_case_word a"),
                .emphasis([.text("b")]), .text("c"),
            ]),
        ])
    }

    @Test("raw HTML keeps its text and resolves <img> and <br>")
    func html() {
        #expect(parse(
            "<div align=\"center\">\n  <img src=\"docs/shot.png\" alt=\"Shot\">\n</div>\n\n"
            + "Press <kbd>⌘</kbd><br>now <!-- hidden --> <b>bold</b>"
        ) == [
            .html([.image(source: "docs/shot.png", alt: "Shot")]),
            .paragraph([.text("Press ⌘"), .lineBreak, .text("now bold")]),
        ])
    }

    @Test("autolinks and bare URLs become links")
    func autolinks() {
        #expect(parse("<https://example.com/a> and https://example.com/b, <me@example.com>") == [
            .paragraph([
                .link(destination: "https://example.com/a", content: [.text("https://example.com/a")]),
                .text(" and "),
                .link(destination: "https://example.com/b", content: [.text("https://example.com/b")]),
                .text(", "),
                .link(destination: "mailto:me@example.com", content: [.text("me@example.com")]),
            ]),
        ])
    }

    @Test("only .md and .markdown count as Markdown files")
    func fileExtensions() {
        #expect(URL(fileURLWithPath: "/tmp/README.md").isMarkdown)
        #expect(URL(fileURLWithPath: "/tmp/README.MARKDOWN").isMarkdown)
        #expect(!URL(fileURLWithPath: "/tmp/README.mdx").isMarkdown)
        #expect(!URL(fileURLWithPath: "/tmp/README.txt").isMarkdown)
    }
}

