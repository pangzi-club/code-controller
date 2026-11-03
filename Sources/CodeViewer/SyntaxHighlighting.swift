import Foundation
import Highlighter
import SwiftUI

/// Which highlight.js color set to render with: a bundled HighlighterSwift
/// theme by name — names must match a `.css` file in the dependency bundle.
/// The editor resolves one per interface appearance (see `SettingsStore`).
public struct HighlightTheme: Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public static let light = HighlightTheme(name: "xcode")
    public static let dark = HighlightTheme(name: "xcode-dusk")
}

public enum HighlightError: Error, LocalizedError {
    case engineUnavailable
    case unsupportedLanguage(String)
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "The highlighting engine could not be loaded."
        case .unsupportedLanguage(let language):
            return "Language is not supported: \(language)"
        case .renderFailed(let language):
            return "Highlighting failed for \(language)."
        }
    }
}

/// Immutable highlighted output crossing actor boundaries. `NSAttributedString`
/// has no Sendable conformance on macOS, but these instances are fully built
/// by the highlighter actor before handoff and never mutated afterwards.
public struct HighlightedText: @unchecked Sendable {
    public let attributed: NSAttributedString
    /// Background color parsed from the theme's `.hljs` CSS rule, if any.
    public let background: NSColor?

    public init(attributed: NSAttributedString, background: NSColor? = nil) {
        self.attributed = attributed
        self.background = background
    }
}

/// Renders source text as an attributed string. Implementations must keep the
/// characters identical and attach style attributes only (colors, fonts);
/// `CodeTextFactory` re-applies the pinned font and line height afterwards so
/// the line-number ruler never shifts. Backed by HighlighterSwift today, with
/// the door left open for a tree-sitter implementation.
public protocol SyntaxHighlighter: Sendable {
    func highlight(_ text: String, language: String, theme: HighlightTheme) async throws -> HighlightedText
}

/// Maps file extensions to canonical highlight.js language names. The adapter
/// validates against `supportedLanguages()`, so optimistic names here only
/// cost a failed lookup for exotic extensions, never a broken render.
public enum SyntaxLanguageMapper {
    private static let languagesByExtension: [String: String] = [
        "swift": "swift",
        "json": "json",
        "jsonc": "json",
        "md": "markdown",
        "markdown": "markdown",
        "c": "c",
        "h": "c",
        "cc": "cpp",
        "cpp": "cpp",
        "cxx": "cpp",
        "hpp": "cpp",
        "hh": "cpp",
        "hxx": "cpp",
        "m": "objectivec",
        "mm": "objectivec",
        "py": "python",
        "pyi": "python",
        "rb": "ruby",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "jsx": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "go": "go",
        "rs": "rust",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "cs": "csharp",
        "php": "php",
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "fish": "fish",
        "pl": "perl",
        "pm": "perl",
        "lua": "lua",
        "sql": "sql",
        "yml": "yaml",
        "yaml": "yaml",
        "xml": "xml",
        "html": "xml",
        "htm": "xml",
        "xhtml": "xml",
        "plist": "xml",
        "svg": "xml",
        "xib": "xml",
        "storyboard": "xml",
        "css": "css",
        "scss": "scss",
        "less": "less",
        "vim": "vim",
        "dockerfile": "dockerfile",
        "mk": "makefile",
        "makefile": "makefile",
        "toml": "ini",
        "ini": "ini",
        "cfg": "ini",
        "conf": "ini",
        "diff": "diff",
        "patch": "diff",
        "graphql": "graphql",
        "gql": "graphql",
        "proto": "protobuf",
        "dart": "dart",
        "scala": "scala",
        "hs": "haskell",
        "ex": "elixir",
        "exs": "elixir",
        "erl": "erlang",
        "clj": "clojure",
        "cljs": "clojure",
        "jl": "julia",
        "f90": "fortran",
        "vb": "vbnet",
        "ps1": "powershell",
        "psm1": "powershell",
        "bat": "dos",
        "cmd": "dos",
        "zig": "zig",
    ]

    /// Canonical language name for a file extension, or nil when the code
    /// pane should render plain text.
    public static func highlightLanguage(forExtension extensionName: String) -> String? {
        languagesByExtension[extensionName.lowercased()]
    }
}

/// `SyntaxHighlighter` backed by HighlighterSwift (highlight.js on
/// JavaScriptCore). The wrapped `Highlighter` is not thread-safe, so the
/// instance lives on this actor and theme loads serialize with highlight
/// runs — all CPU-heavy work stays off the main thread.
public actor HighlighterSwiftHighlighter: SyntaxHighlighter {
    public static let shared = HighlighterSwiftHighlighter()

    private var highlighter: Highlighter?
    private var loadedTheme: HighlightTheme?

    public init() {}

    public func highlight(_ text: String, language: String, theme: HighlightTheme) async throws -> HighlightedText {
        let engine = try self.engine()
        if loadedTheme != theme {
            guard engine.setTheme(theme.name) else {
                throw HighlightError.renderFailed(theme.name)
            }
            loadedTheme = theme
        }
        guard engine.supportedLanguages().contains(language) else {
            throw HighlightError.unsupportedLanguage(language)
        }
        guard let result = engine.highlight(text, as: language, doFastRender: true) else {
            throw HighlightError.renderFailed(language)
        }
        return HighlightedText(
            attributed: result,
            background: engine.theme?.themeBackgroundColour
        )
    }

    private func engine() throws -> Highlighter {
        if let highlighter { return highlighter }
        guard let created = Highlighter() else { throw HighlightError.engineUnavailable }
        created.ignoreIllegals = true
        highlighter = created
        loadedTheme = nil
        return created
    }
}

/// Collapses concurrent identical highlight requests into one running task
/// and gives the coordinator a seam to inject a stub highlighter in previews.
@MainActor
public final class HighlightService {
    public static let shared = HighlightService()

    private let highlighter: any SyntaxHighlighter
    private var inflight: [String: Task<HighlightedText, Error>] = [:]

    public init(highlighter: any SyntaxHighlighter = HighlighterSwiftHighlighter.shared) {
        self.highlighter = highlighter
    }

    /// `requestKey` identifies the content (tab + document version + language)
    /// so callers re-requesting the same document while a run is in flight
    /// share it instead of doubling the work on the highlighter actor.
    public func highlight(
        requestKey: String,
        text: String,
        language: String,
        theme: HighlightTheme
    ) async throws -> HighlightedText {
        if let existing = inflight[requestKey] {
            return try await existing.value
        }
        let highlighter = self.highlighter
        let task = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.inflight[requestKey] = nil } }
            return try await highlighter.highlight(text, language: language, theme: theme)
        }
        inflight[requestKey] = task
        return try await task.value
    }
}

/// LRU cache of finished highlight results, keyed by document version,
/// theme and editor font. Lives on the main actor so the code pane can check
/// it synchronously and paint a switched-to tab without a flash of plain text.
@MainActor
public final class HighlightCache {
    /// A finished styled result plus the theme background it was rendered
    /// with, so a cache hit can paint the pane background without
    /// re-highlighting.
    public struct Entry {
        public let attributed: NSAttributedString
        public let background: NSColor?

        public init(attributed: NSAttributedString, background: NSColor?) {
            self.attributed = attributed
            self.background = background
        }
    }

    private struct Slot {
        let entry: Entry
        var lastUsed: Int
    }

    private var slots: [String: Slot] = [:]
    private var clock = 0
    private let capacity: Int

    public init(capacity: Int = 12) {
        self.capacity = capacity
    }

    public func result(for key: String, theme: HighlightTheme, fontID: String) -> Entry? {
        let key = Self.cacheKey(key, theme: theme, fontID: fontID)
        guard var slot = slots[key] else { return nil }
        clock += 1
        slot.lastUsed = clock
        slots[key] = slot
        return slot.entry
    }

    public func store(_ entry: Entry, for key: String, theme: HighlightTheme, fontID: String) {
        let key = Self.cacheKey(key, theme: theme, fontID: fontID)
        guard slots[key] == nil else { return }
        clock += 1
        slots[key] = Slot(entry: entry, lastUsed: clock)
        evictIfNeeded()
    }

    private static func cacheKey(_ key: String, theme: HighlightTheme, fontID: String) -> String {
        "\(key)#\(theme.name)#\(fontID)"
    }

    private func evictIfNeeded() {
        while slots.count > capacity {
            guard let victim = slots.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else {
                break
            }
            slots.removeValue(forKey: victim)
        }
    }
}
