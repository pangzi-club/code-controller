import AppKit
import Foundation

/// Immutable highlighted output crossing task boundaries. `NSAttributedString`
/// has no Sendable conformance on macOS, but these instances are fully built
/// by the scanner before handoff and never mutated afterwards.
public struct HighlightedText: @unchecked Sendable {
    public let attributed: NSAttributedString
    /// Background the theme renders on.
    public let background: NSColor

    public init(attributed: NSAttributedString, background: NSColor) {
        self.attributed = attributed
        self.background = background
    }
}

/// Renders source text as an attributed string. Implementations must keep the
/// characters identical and attach style attributes only (colors, font
/// traits); `CodeTextFactory` re-applies the pinned font and line height
/// afterwards so the line-number ruler never shifts.
public protocol SyntaxHighlighter: Sendable {
    func highlight(_ text: String, language: String, theme: EditorTheme) -> HighlightedText
}

/// The built-in highlighter: `SyntaxScanner` plus the theme palette. Pure
/// Swift with no engine to load or theme to parse, so it cannot fail — an
/// unknown language simply comes back in the plain color.
public struct NativeHighlighter: SyntaxHighlighter {
    public init() {}

    public func highlight(_ text: String, language: String, theme: EditorTheme) -> HighlightedText {
        HighlightedText(
            attributed: SyntaxScanner.attributedString(for: text, language: language, theme: theme),
            background: theme.background
        )
    }

    /// Whether the scanner has rules for the language.
    public static func supports(_ language: String) -> Bool {
        LanguageRules.mode(for: language) != nil
    }
}

/// Maps file extensions to canonical language names (see `LanguageRules`).
/// Every name here has scanner rules, so a mapped extension always renders
/// highlighted.
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

    /// Every language name any extension can produce.
    static var languages: Set<String> { Set(languagesByExtension.values) }
}

/// Collapses concurrent identical highlight requests into one running task
/// and gives the coordinator a seam to inject a stub highlighter in previews
/// and tests. Scanning runs on a detached task so the main actor never pays
/// for it.
@MainActor
public final class HighlightService {
    public static let shared = HighlightService()

    private let highlighter: any SyntaxHighlighter
    private var inflight: [String: Task<HighlightedText, Never>] = [:]

    public init(highlighter: any SyntaxHighlighter = NativeHighlighter()) {
        self.highlighter = highlighter
    }

    /// `requestKey` identifies the content (tab + document version + language)
    /// so callers re-requesting the same document while a run is in flight
    /// share it instead of doubling the work.
    public func highlight(
        requestKey: String,
        text: String,
        language: String,
        theme: EditorTheme
    ) async -> HighlightedText {
        if let existing = inflight[requestKey] {
            return await existing.value
        }
        let highlighter = self.highlighter
        // Deliberately not cancelled with the caller: a finished scan is
        // cached by the pane for the next time the document is shown, and a
        // half-styled result must never reach that cache.
        let task = Task.detached(priority: .userInitiated) {
            highlighter.highlight(text, language: language, theme: theme)
        }
        inflight[requestKey] = task
        defer { Task { @MainActor [weak self] in self?.inflight[requestKey] = nil } }
        return await task.value
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
        public let background: NSColor

        public init(attributed: NSAttributedString, background: NSColor) {
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

    public func result(for key: String, theme: EditorTheme, fontID: String) -> Entry? {
        let key = Self.cacheKey(key, theme: theme, fontID: fontID)
        guard var slot = slots[key] else { return nil }
        clock += 1
        slot.lastUsed = clock
        slots[key] = slot
        return slot.entry
    }

    public func store(_ entry: Entry, for key: String, theme: EditorTheme, fontID: String) {
        let key = Self.cacheKey(key, theme: theme, fontID: fontID)
        guard slots[key] == nil else { return }
        clock += 1
        slots[key] = Slot(entry: entry, lastUsed: clock)
        evictIfNeeded()
    }

    private static func cacheKey(_ key: String, theme: EditorTheme, fontID: String) -> String {
        "\(key)#\(theme.rawValue)#\(fontID)"
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
