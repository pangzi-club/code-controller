import AppKit
import Foundation

/// Working-tree change marks for one text file, keyed by 1-based line numbers
/// in the file's *current* content (the new side of its diff).
///
/// The editor tints every marked line — green where the diff only inserts
/// lines, yellow where the inserted lines replace content that was removed —
/// and the line-number ruler marks the seams where lines disappeared outright,
/// which no background can show because those lines are gone.
struct LineChangeMap: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Lines the diff only adds: nothing was removed to make room.
        case added
        /// Lines that replace a removed run: the block was rewritten.
        case modified
    }

    static let empty = LineChangeMap()

    /// The whole file is new (untracked, or added to the index): every line
    /// carries the added tint, painted as one range.
    var isNewFile = false
    /// Line number → tint kind.
    var kinds: [Int: Kind] = [:]
    /// 1-based lines that now follow a removed block, `lineCount + 1` when the
    /// removal sits at the end of the file. Drawn as ruler seam markers.
    var deletionBoundaries: Set<Int> = []

    var isEmpty: Bool {
        !isNewFile && kinds.isEmpty && deletionBoundaries.isEmpty
    }

    func kind(forLine line: Int) -> Kind? {
        isNewFile ? .added : kinds[line]
    }

    /// UTF-16 ranges of the tinted lines, newline included so a tint reaches
    /// the end of its row. One pass over the text; only marked lines cost an
    /// allocation, so a large file with few changes stays cheap.
    func tintedRanges(in text: NSString) -> [(kind: Kind, range: NSRange)] {
        let length = text.length
        guard length > 0 else { return [] }
        if isNewFile {
            return [(.added, NSRange(location: 0, length: length))]
        }
        guard !kinds.isEmpty else { return [] }

        let targets = kinds.keys.sorted()
        var ranges: [(Kind, NSRange)] = []
        ranges.reserveCapacity(targets.count)

        var targetIndex = 0
        var lineNumber = 1
        var lineStart = 0
        var index = 0
        while index < length, targetIndex < targets.count {
            if text.character(at: index) == 0x0A {
                if targets[targetIndex] == lineNumber {
                    ranges.append((
                        kinds[lineNumber]!,
                        NSRange(location: lineStart, length: index - lineStart + 1)
                    ))
                    targetIndex += 1
                }
                lineNumber += 1
                lineStart = index + 1
            }
            index += 1
        }
        // Last line when the text has no trailing newline.
        if targetIndex < targets.count, targets[targetIndex] == lineNumber {
            ranges.append((
                kinds[lineNumber]!,
                NSRange(location: lineStart, length: length - lineStart)
            ))
        }
        return ranges
    }
}

extension LineChangeMap {
    /// Classifies one file's hunks run by run: a `+` run that follows a `-`
    /// run replaced content (modified), a `+` run on its own is new (added),
    /// and a `-` run with no additions behind it leaves a seam at the line the
    /// removed block used to sit above.
    ///
    /// Works on the `--unified=0` diffs the editor asks for, and degrades
    /// gracefully on the five-line-context diffs the commit tab parses.
    init(diff: FileDiff) {
        self.init()
        guard diff.status != .binary else { return }

        for hunk in diff.hunks {
            // Git reports a removed block's position on the new side as the
            // line *before* it (0 at the top of the file), so the first line
            // after the removal is one further down.
            var newLine = hunk.newCount == 0 ? hunk.newStart + 1 : hunk.newStart
            let lines = hunk.lines
            var index = 0
            while index < lines.count {
                switch lines[index].kind {
                case .context:
                    newLine += 1
                    index += 1
                case .meta:
                    index += 1
                case .removed:
                    while index < lines.count, lines[index].kind == .removed {
                        index += 1
                    }
                    // A following `+` run consumes these lines' place; the
                    // additions are classified as modified on the next pass.
                    if index >= lines.count || lines[index].kind != .added {
                        deletionBoundaries.insert(newLine)
                    }
                case .added:
                    let replacesRemoval = index > 0 && lines[index - 1].kind == .removed
                    let kind: Kind = replacesRemoval ? .modified : .added
                    while index < lines.count, lines[index].kind == .added {
                        kinds[newLine] = kind
                        newLine += 1
                        index += 1
                    }
                }
            }
        }
    }
}

/// Colors shared by the editor's line tints and the ruler's change markers.
/// The tints reuse the commit diff tab's green/red language, dialed down so
/// syntax colors stay readable on top of them; markers are solid.
///
/// The backgrounds are dynamic: compositing a catalog yellow over a dark
/// theme turns muddy brown, so dark mode gets a warmer, brighter amber at the
/// same strength.
enum LineChangePalette {
    static func background(for kind: LineChangeMap.Kind) -> NSColor {
        switch kind {
        case .added:
            return NSColor(name: "lineChangeAdded") { appearance in
                NSColor.systemGreen.withAlphaComponent(appearance.isDark ? 0.20 : 0.13)
            }
        case .modified:
            return NSColor(name: "lineChangeModified") { appearance in
                appearance.isDark
                    ? NSColor(srgbRed: 1.0, green: 0.85, blue: 0.32, alpha: 0.26)
                    : NSColor.systemYellow.withAlphaComponent(0.20)
            }
        }
    }

    static func marker(for kind: LineChangeMap.Kind) -> NSColor {
        switch kind {
        case .added: return .systemGreen
        case .modified: return .systemYellow
        }
    }

    /// Seam marker for a removed block: the only place the diff can show
    /// removed content, since the lines themselves no longer exist.
    static let deletionMarker = NSColor.systemRed
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
