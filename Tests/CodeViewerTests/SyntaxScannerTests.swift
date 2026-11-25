import AppKit
import Testing
@testable import CodeViewer

/// Token-level checks against the scanner. Atom One Dark keeps every kind
/// asserted here visually distinct from its neighbors, so a color at a given
/// offset identifies the kind unambiguously.
struct SyntaxScannerTests {
    private let theme = EditorTheme.atomOneDark

    /// Foreground color at the first character of `needle` inside `source`.
    private func color(of needle: String, in source: String, language: String) -> NSColor? {
        let result = SyntaxScanner.attributedString(for: source, language: language, theme: theme)
        #expect(result.string == source, "characters changed for \(language)")
        let range = (source as NSString).range(of: needle)
        #expect(range.location != NSNotFound, "\(needle) not in sample")
        guard range.location != NSNotFound else { return nil }
        return result.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    private func expect(_ needle: String, _ kind: TokenKind, in source: String, language: String) {
        #expect(color(of: needle, in: source, language: language) == theme.color(for: kind),
                "\(needle) in \(language) should be \(kind)")
    }

    @Test("Swift keywords, types, calls, numbers, strings and comments")
    func swiftTokens() {
        let source = "struct View: View {\n    @State var count = 42 // done\n    render(\"hi\")\n}"
        expect("struct", .keyword, in: source, language: "swift")
        expect("View", .type, in: source, language: "swift")
        expect("@State", .meta, in: source, language: "swift")
        expect("count", .plain, in: source, language: "swift")
        expect("42", .number, in: source, language: "swift")
        expect("// done", .comment, in: source, language: "swift")
        expect("render", .function, in: source, language: "swift")
        expect("\"hi\"", .string, in: source, language: "swift")
        expect("(", .punctuation, in: source, language: "swift")
        expect("=", .operatorSymbol, in: source, language: "swift")
    }

    @Test("Swift raw, multi-line and nested comment forms")
    func swiftStringAndCommentForms() {
        expect("if #available(iOS 15, *)", .keyword, in: "if #available(iOS 15, *) {}", language: "swift")
        expect("#available", .meta, in: "if #available(iOS 15, *) {}", language: "swift")
        let raw = "let s = #\"a \"b\" c\"#"
        expect("a \"b\" c", .string, in: raw, language: "swift")
        let nested = "/* outer /* inner */ still comment */ let x = 1"
        expect("still comment", .comment, in: nested, language: "swift")
        expect("let", .keyword, in: nested, language: "swift")
        expect("multi", .string, in: "let t = \"\"\"\nmulti\n\"\"\"", language: "swift")
    }

    @Test("numbers in the usual bases and with exponents")
    func numbers() {
        for literal in ["0xFF", "1.5e-3", "1_000", "0b1010", ".5"] {
            expect(literal, .number, in: "let n = \(literal) // c", language: "swift")
        }
        expect("true", .literal, in: "let on = true", language: "swift")
    }

    @Test("Python comments, docstrings, keywords and builtins")
    func python() {
        let source = "# note\ndef run(x):\n    \"\"\"doc\"\"\"\n    return None"
        expect("# note", .comment, in: source, language: "python")
        expect("def", .keyword, in: source, language: "python")
        expect("\"\"\"doc\"\"\"", .string, in: source, language: "python")
        expect("None", .literal, in: source, language: "python")
        expect("print", .builtIn, in: "print(x)", language: "python")
    }

    @Test("shell keywords, variables and comments")
    func shell() {
        let source = "export PATH=\"$HOME/bin\" # note\necho $HOME"
        expect("export", .keyword, in: source, language: "bash")
        expect("\"$HOME/bin\"", .string, in: source, language: "bash")
        expect("# note", .comment, in: source, language: "bash")
        expect("$HOME", .variable, in: "echo $HOME", language: "bash")
        expect("echo", .builtIn, in: "echo hi", language: "bash")
    }

    @Test("JSON keys, strings, numbers and literals")
    func json() {
        let source = "{\"key\": \"value\", \"n\": 1, \"ok\": true, \"neg\": -2.5}"
        expect("\"key\"", .attribute, in: source, language: "json")
        expect("\"value\"", .string, in: source, language: "json")
        expect("1", .number, in: source, language: "json")
        expect("true", .literal, in: source, language: "json")
        expect("-2.5", .number, in: source, language: "json")
        expect(":", .punctuation, in: source, language: "json")
    }

    @Test("YAML keys, lists, scalars and literal blocks")
    func yaml() {
        let source = "name: value # note\n- item\nenabled: true\nscript: |\n  echo hi\nnext: 1"
        expect("name", .attribute, in: source, language: "yaml")
        expect("# note", .comment, in: source, language: "yaml")
        expect("-", .bullet, in: source, language: "yaml")
        expect("true", .literal, in: source, language: "yaml")
        expect("echo hi", .string, in: source, language: "yaml")
        expect("next", .attribute, in: source, language: "yaml")
    }

    @Test("XML tags, attributes, strings and comments")
    func markup() {
        let source = "<!-- note --><a href=\"x\">text</a>"
        expect("<!-- note -->", .comment, in: source, language: "xml")
        expect("a", .name, in: source, language: "xml")
        expect("href", .attribute, in: source, language: "xml")
        expect("\"x\"", .string, in: source, language: "xml")
        expect("text", .plain, in: source, language: "xml")
    }

    @Test("CSS selectors, properties, values and at-rules")
    func stylesheet() {
        let source = "/* note */ @media (max-width: 600px) { .cls { color: #fff; } }"
        expect("/* note */", .comment, in: source, language: "css")
        expect("@media", .meta, in: source, language: "css")
        expect(".cls", .type, in: source, language: "css")
        expect("color", .property, in: source, language: "css")
        expect("#fff", .number, in: source, language: "css")
        expect("600", .number, in: source, language: "css")
    }

    @Test("Markdown headings, lists, emphasis, code and links")
    func markdown() {
        let source = "# Title\n- item with  `code` and **bold**\n[link](http://x)\n```\nfenced\n```"
        expect("Title", .section, in: source, language: "markdown")
        expect("-", .bullet, in: source, language: "markdown")
        expect("`code`", .code, in: source, language: "markdown")
        expect("**bold**", .plain, in: source, language: "markdown")
        expect("[link]", .link, in: source, language: "markdown")
        expect("(http://x)", .attribute, in: source, language: "markdown")
        expect("fenced", .code, in: source, language: "markdown")
    }

    @Test("markdown emphasis carries bold and italic traits")
    func markdownTraits() {
        let result = SyntaxScanner.attributedString(for: "**bold** *em*", language: "markdown", theme: theme)
        let bold = result.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        let italic = result.attribute(.font, at: 10, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(italic?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(result.attribute(.font, at: 8, effectiveRange: nil) == nil)
    }

    @Test("INI sections, keys, values and comments")
    func ini() {
        let source = "[section] ; note\nkey = \"value\"\nflag = true\nn = 3"
        expect("[section]", .tag, in: source, language: "ini")
        expect("; note", .comment, in: source, language: "ini")
        expect("key", .attribute, in: source, language: "ini")
        expect("\"value\"", .string, in: source, language: "ini")
        expect("true", .literal, in: source, language: "ini")
        expect("3", .number, in: source, language: "ini")
    }

    @Test("diff lines by kind")
    func diff() {
        let source = "diff --git a b\n@@ -1 +1 @@\n+added\n-removed\n context"
        expect("diff --git a b", .meta, in: source, language: "diff")
        expect("@@ -1 +1 @@", .meta, in: source, language: "diff")
        expect("+added", .added, in: source, language: "diff")
        expect("-removed", .removed, in: source, language: "diff")
        expect("context", .plain, in: source, language: "diff")
    }

    @Test("case-insensitive keyword languages")
    func caseInsensitiveKeywords() {
        expect("SELECT", .keyword, in: "SELECT * FROM t", language: "sql")
        expect("FROM", .keyword, in: "select 1 FROM t", language: "sql")
        expect("FROM", .keyword, in: "FROM alpine", language: "dockerfile")
        expect("If", .keyword, in: "If ($x) { }", language: "powershell")
    }

    @Test("C preprocessor directives, include paths and type keywords")
    func cPreprocessor() {
        let source = "#include <stdio.h>\nint main(void) { return 0; } // trailing"
        expect("#include", .meta, in: source, language: "c")
        expect("<stdio.h>", .string, in: source, language: "c")
        expect("int", .keyword, in: source, language: "c")
        expect("main", .function, in: source, language: "c")
        expect("// trailing", .comment, in: source, language: "c")
        // A hash that does not start a line is not a directive.
        expect("x", .plain, in: "int x = a # b", language: "c")
    }

    @Test("every scanner language preserves the input characters")
    func preservesCharactersEverywhere() {
        let sample = "let s = \"a \\\"b\" // /* \n caf\u{00E9} \u{1F600}\n" + "x = 1.5e-3 # @ $ : ~"
        for language in LanguageRules.languages {
            let result = SyntaxScanner.attributedString(for: sample, language: language, theme: theme)
            #expect(result.string == sample, "characters changed for \(language)")
        }
        let empty = SyntaxScanner.attributedString(for: "", language: "swift", theme: theme)
        #expect(empty.length == 0)
    }

    @Test("unterminated strings and comments reach the end of the text")
    func unterminatedForms() {
        let source = "let s = \"never closed\nlet t = 1 // trailing"
        expect("never closed", .string, in: source, language: "swift")
        // The newline is not part of the string: the next line still scans.
        expect("let", .keyword, in: source, language: "swift")
        let comment = "/* open forever\nstill comment"
        expect("still comment", .comment, in: comment, language: "swift")
    }
}
