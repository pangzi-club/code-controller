import Foundation
import Markdown

/// Parsed Markdown reduced to the blocks and inline runs the preview
/// renders. swift-markdown does the parsing (CommonMark plus the GitHub
/// extensions a README uses); this tree keeps the SwiftUI layer free of its
/// types and gives tests a plain value to compare.
struct MarkdownDocument: Equatable, Sendable {
    indirect enum Block: Equatable, Sendable {
        case heading(level: Int, content: [Inline])
        case paragraph([Inline])
        /// Fenced or indented code; `language` is the fence's first info word.
        case codeBlock(language: String?, code: String)
        case quote([Block])
        case list(List)
        case thematicBreak
        case table(Table)
        /// Raw HTML as inline runs: `<img>` becomes an image, `<br>` a hard
        /// break, other tags are dropped and their text kept — so the common
        /// `<div align="center"><img …></div>` header renders as the image.
        case html([Inline])
    }

    struct List: Equatable, Sendable {
        var isOrdered: Bool
        var start: Int
        /// Loose lists get paragraph spacing between their items.
        var isLoose: Bool
        var items: [Item]
    }

    struct Item: Equatable, Sendable {
        enum TaskState: Equatable, Sendable {
            case none, unchecked, checked
        }

        var task: TaskState
        var blocks: [Block]
    }

    struct Table: Equatable, Sendable {
        enum Alignment: Equatable, Sendable {
            case leading, center, trailing
        }

        var alignments: [Alignment]
        var header: [[Inline]]
        var rows: [[[Inline]]]
    }

    indirect enum Inline: Equatable, Sendable {
        case text(String)
        case code(String)
        case emphasis([Inline])
        case strong([Inline])
        case strikethrough([Inline])
        case link(destination: String, content: [Inline])
        /// A local image resolves against the document's directory; remote
        /// ones stay a link (the sandboxed build has no network anyway).
        case image(source: String, alt: String)
        case lineBreak
    }

    var blocks: [Block]

    init(parsing text: String) {
        // The text decoder already normalizes line endings, but this init
        // also takes arbitrary strings.
        let source = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        blocks = TreeBuilder().blocks(Document(parsing: source).children)
    }

    /// Extensions that open as a rendered preview instead of source.
    static let fileExtensions: Set<String> = ["md", "markdown"]

    /// Joins adjacent text runs and drops whitespace-only text at both ends,
    /// so a soft break or an image never drags a stray space along.
    static func mergingText(_ inlines: [Inline]) -> [Inline] {
        var result: [Inline] = []
        for inline in inlines {
            if case .text(let text) = inline, case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + text)
            } else {
                result.append(inline)
            }
        }
        // Whitespace runs collapse the way HTML renders them, so an inline
        // tag between two words never leaves a double space.
        result = result.map { inline in
            guard case .text(let text) = inline else { return inline }
            return .text(collapsing(text))
        }
        while case .text(let text)? = result.first, text.allSatisfy(\.isWhitespace) {
            result.removeFirst()
        }
        while case .text(let text)? = result.last, text.allSatisfy(\.isWhitespace) {
            result.removeLast()
        }
        return result
    }

    private static func collapsing(_ text: String) -> String {
        let body = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !body.isEmpty else { return text.isEmpty ? "" : " " }
        return (text.first?.isWhitespace == true ? " " : "") + body
            + (text.last?.isWhitespace == true ? " " : "")
    }

    /// Maps swift-markdown's tree onto this one. Nodes without a place in it
    /// (DocC directives, custom blocks) are dropped rather than shown as text.
    private struct TreeBuilder {
        func blocks(_ children: MarkupChildren) -> [Block] {
            children.compactMap(block)
        }

        func block(_ markup: Markup) -> Block? {
            switch markup {
            case let heading as Heading:
                return .heading(level: heading.level, content: inlines(heading.children))
            case let paragraph as Paragraph:
                return .paragraph(inlines(paragraph.children))
            case let quote as BlockQuote:
                return .quote(blocks(quote.children))
            case let list as UnorderedList:
                return .list(listBlock(list))
            case let list as OrderedList:
                var result = listBlock(list)
                result.isOrdered = true
                result.start = Int(list.startIndex)
                return .list(result)
            case let code as CodeBlock:
                let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
                return .codeBlock(language: language, code: Self.codeText(code.code))
            case let table as Markdown.Table:
                return tableBlock(table)
            case let html as HTMLBlock:
                let runs = MarkdownHTML.runs(html.rawHTML)
                return runs.isEmpty ? nil : .html(runs)
            case is ThematicBreak:
                return .thematicBreak
            default:
                return nil
            }
        }

        /// cmark keeps the block's final newline.
        private static func codeText(_ code: String) -> String {
            var code = code
            if code.hasSuffix("\n") { code.removeLast() }
            return code
        }

        func listBlock(_ list: ListItemContainer) -> List {
            let items = list.children.compactMap { $0 as? ListItem }.map { item in
                Item(task: taskState(item.checkbox), blocks: blocks(item.children))
            }
            // swift-markdown does not expose whether blank lines separated the
            // items; an item holding more than one block is the usual shape of
            // a loose list.
            let isLoose = items.contains { $0.blocks.count > 1 }
            return List(isOrdered: false, start: 1, isLoose: isLoose, items: items)
        }

        private func taskState(_ checkbox: Checkbox?) -> Item.TaskState {
            switch checkbox {
            case .checked?: return .checked
            case .unchecked?: return .unchecked
            default: return .none
            }
        }

        func tableBlock(_ table: Markdown.Table) -> Block {
            let alignments = table.columnAlignments.map { alignment -> Table.Alignment in
                switch alignment {
                case .center?: return .center
                case .right?: return .trailing
                default: return .leading
                }
            }
            return .table(Table(
                alignments: alignments,
                header: table.head.cells.map { inlines($0.children) },
                rows: table.body.rows.map { row in row.cells.map { inlines($0.children) } }
            ))
        }

        /// Bare URLs are linked unless the run already sits inside a link.
        func inlines(_ children: MarkupChildren, insideLink: Bool = false) -> [Inline] {
            let runs = children.flatMap { inline($0, insideLink: insideLink) }
            return mergingText(insideLink ? runs : runs.flatMap(Self.autolinking))
        }

        /// swift-markdown turns on the table, strikethrough and task-list
        /// extensions but not autolink, so a bare `https://…` inside a text
        /// run is linked here the way GitHub renders it.
        private static func autolinking(_ inline: Inline) -> [Inline] {
            guard case .text(let text) = inline else { return [inline] }
            let chars = Array(text)
            var result: [Inline] = []
            var plainStart = 0
            var index = 0
            while index + 2 < chars.count {
                guard chars[index] == ":", chars[index + 1] == "/", chars[index + 2] == "/",
                      let start = schemeStart(chars, before: index),
                      start == 0 || chars[start - 1].isWhitespace || "(*_~".contains(chars[start - 1]) else {
                    index += 1
                    continue
                }
                var end = index + 3
                while end < chars.count, !chars[end].isWhitespace, chars[end] != "<" { end += 1 }
                // Trailing punctuation is not part of the URL, and neither is
                // an unbalanced closing parenthesis.
                while end > index + 3, "?!.,:*_~'\"".contains(chars[end - 1]) { end -= 1 }
                let opens = chars[start..<end].filter { $0 == "(" }.count
                while end > index + 3, chars[end - 1] == ")",
                      chars[start..<end].filter { $0 == ")" }.count > opens {
                    end -= 1
                }
                guard end > index + 3 else {
                    index += 1
                    continue
                }
                if plainStart < start {
                    result.append(.text(String(chars[plainStart..<start])))
                }
                let url = String(chars[start..<end])
                result.append(.link(destination: url, content: [.text(url)]))
                plainStart = end
                index = end
            }
            if plainStart < chars.count {
                result.append(.text(String(chars[plainStart...])))
            }
            return result
        }

        /// The start of an `http` / `https` scheme ending right before `colon`.
        private static func schemeStart(_ chars: [Character], before colon: Int) -> Int? {
            var start = colon
            while start > 0, chars[start - 1].isASCII, chars[start - 1].isLetter { start -= 1 }
            let scheme = String(chars[start..<colon]).lowercased()
            return scheme == "http" || scheme == "https" ? start : nil
        }

        func inline(_ markup: Markup, insideLink: Bool) -> [Inline] {
            switch markup {
            case let text as Text:
                return [.text(String(text.string))]
            case let code as InlineCode:
                return [.code(String(code.code))]
            case let emphasis as Emphasis:
                return [.emphasis(inlines(emphasis.children, insideLink: insideLink))]
            case let strong as Strong:
                return [.strong(inlines(strong.children, insideLink: insideLink))]
            case let strike as Strikethrough:
                return [.strikethrough(inlines(strike.children, insideLink: insideLink))]
            case let link as Link:
                return [.link(destination: link.destination ?? "", content: inlines(link.children, insideLink: true))]
            case let image as Image:
                return [.image(source: image.source ?? "", alt: plainText(image.children))]
            case is SoftBreak:
                return [.text(" ")]
            case is LineBreak:
                return [.lineBreak]
            case let html as InlineHTML:
                return MarkdownHTML.runs(html.rawHTML)
            case let attributes as InlineAttributes:
                return attributes.children.flatMap { inline($0, insideLink: insideLink) }
            case let symbol as SymbolLink:
                return [.text(symbol.plainText)]
            default:
                return []
            }
        }

        /// Image alt text is plain text by spec.
        private func plainText(_ children: MarkupChildren) -> String {
            children.map { child in
                if let text = child as? Text { return String(text.string) }
                if let code = child as? InlineCode { return String(code.code) }
                if child is SoftBreak || child is LineBreak { return " " }
                return plainText(child.children)
            }.joined()
        }
    }
}

extension URL {
    /// Whether the file opens as a rendered Markdown preview by default.
    var isMarkdown: Bool {
        MarkdownDocument.fileExtensions.contains(pathExtension.lowercased())
    }
}

/// The little HTML a README's raw markup needs: `<img>` becomes an image,
/// `<br>` a hard break, every other tag is dropped while the text between
/// tags survives with its whitespace collapsed. There is no HTML engine
/// behind the preview, so anything else would only show up as markup.
private enum MarkdownHTML {
    static func runs(_ html: String) -> [MarkdownDocument.Inline] {
        let chars = Array(html)
        var result: [MarkdownDocument.Inline] = []
        var text = ""
        /// Whether whitespace was seen before the next word (tags in between
        /// must not glue words together, nor add space around an image).
        var pendingSpace = false
        var index = 0

        func flush() {
            guard !text.isEmpty else { return }
            let leading = text.first?.isWhitespace == true
            let trailing = text.last?.isWhitespace == true
            let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text = ""
            guard !words.isEmpty else {
                pendingSpace = pendingSpace || (trailing && !result.isEmpty)
                return
            }
            let space = pendingSpace || (leading && !result.isEmpty) ? " " : ""
            result.append(.text(space + words))
            pendingSpace = trailing
        }

        while index < chars.count {
            guard chars[index] == "<" else {
                text.append(chars[index])
                index += 1
                continue
            }
            if chars[index...].starts(with: Array("<!--")) {
                var close = index + 4
                while close + 2 < chars.count,
                      !(chars[close] == "-" && chars[close + 1] == "-" && chars[close + 2] == ">") {
                    close += 1
                }
                index = close + 2 < chars.count ? close + 3 : chars.count
                continue
            }
            var close = index + 1
            while close < chars.count, chars[close] != ">" { close += 1 }
            guard close < chars.count else {
                text.append("<")
                index += 1
                continue
            }
            let tag = String(chars[(index + 1)..<close]).trimmingCharacters(in: .whitespaces)
            flush()
            apply(tag, to: &result)
            index = close + 1
        }
        flush()
        return MarkdownDocument.mergingText(result)
    }

    private static func apply(_ tag: String, to result: inout [MarkdownDocument.Inline]) {
        guard !tag.hasPrefix("/") else { return }  // closing tags carry nothing
        let nameEnd = tag.firstIndex(where: { $0.isWhitespace || $0 == "/" }) ?? tag.endIndex
        let name = tag[..<nameEnd].lowercased()
        switch name {
        case "br":
            result.append(.lineBreak)
        case "img":
            let attributes = attributes(tag, after: nameEnd)
            result.append(.image(source: attributes["src"] ?? "", alt: attributes["alt"] ?? ""))
        default:
            break
        }
    }

    /// `key="value"`, `key='value'` and `key=value` pairs after the tag name.
    private static func attributes(_ tag: String, after nameEnd: String.Index) -> [String: String] {
        let chars = Array(tag[nameEnd...])
        var result: [String: String] = [:]
        var index = 0
        while index < chars.count {
            let start = index
            while index < chars.count,
                  chars[index].isLetter || chars[index].isNumber || "_-:".contains(chars[index]) {
                index += 1
            }
            guard index > start else {
                index += 1
                continue
            }
            let name = String(chars[start..<index]).lowercased()
            while index < chars.count, chars[index] == " " { index += 1 }
            guard index < chars.count, chars[index] == "=" else { continue }
            index += 1
            while index < chars.count, chars[index] == " " { index += 1 }
            guard index < chars.count else { continue }
            let quote = chars[index]
            let value: String
            if quote == "\"" || quote == "'" {
                index += 1
                let valueStart = index
                while index < chars.count, chars[index] != quote { index += 1 }
                value = String(chars[valueStart..<index])
                index += 1
            } else {
                let valueStart = index
                while index < chars.count, !chars[index].isWhitespace,
                      !"\"'=<>`".contains(chars[index]) {
                    index += 1
                }
                value = String(chars[valueStart..<index])
            }
            result[name] = decodeEntities(value)
        }
        return result
    }

    /// Numeric character references and the handful of named entities an
    /// image path or alt text is likely to contain.
    private static func decodeEntities(_ text: String) -> String {
        guard let ampersand = text.firstIndex(of: "&") else { return text }
        let body = text[ampersand...].dropFirst()
        guard let semicolon = body.firstIndex(of: ";"),
              body.distance(from: body.startIndex, to: semicolon) <= 10 else {
            return text
        }
        let name = String(body[..<semicolon])
        let scalar: Unicode.Scalar?
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            scalar = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init)
        } else if name.hasPrefix("#") {
            scalar = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init)
        } else {
            scalar = ["amp": 0x26, "lt": 0x3C, "gt": 0x3E, "quot": 0x22, "apos": 0x27, "nbsp": 0xA0][name]
                .flatMap(Unicode.Scalar.init)
        }
        guard let scalar else { return text }
        let rest = decodeEntities(String(body[semicolon...].dropFirst()))
        return text[..<ampersand] + String(Character(scalar)) + rest
    }
}

