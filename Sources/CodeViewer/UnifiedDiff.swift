import Foundation
import SwiftUI

/// One rendered row of an inline diff: a code line with its old/new line
/// numbers, or a marker for lines the hunk header leaves out.
enum DiffLineKind: Equatable {
    case context
    case added
    case removed
    /// `\ No newline at end of file` and friends: informational, unnumbered.
    case meta
}

struct DiffLine: Equatable {
    let kind: DiffLineKind
    /// 1-based numbers into the old/new file; nil for meta lines.
    let oldNumber: Int?
    let newNumber: Int?
    /// The line content without the leading diff marker.
    let text: String
}

/// One hunk of a unified diff. The four header numbers are kept because the
/// "N hidden lines" gaps between hunks can only be derived from them.
struct DiffHunk: Equatable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

enum FileDiffStatus: Equatable {
    case added
    case deleted
    case renamed
    case modified
    case binary

    /// Single-letter badge, mirroring `GitFileStatus.badge`.
    var badge: String {
        switch self {
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .modified: return "M"
        case .binary: return "B"
        }
    }

    /// Localization key for the badge's accessibility label. Renamed has no
    /// `GitFileStatus` counterpart, so it owns a catalog entry of its own.
    var labelKey: String {
        switch self {
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .modified: return "Modified"
        case .binary: return "Binary file"
        }
    }

    var color: Color {
        switch self {
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .modified: return .orange
        case .binary: return .gray
        }
    }
}

/// The diff of one file inside a commit (`git show` output split on
/// `diff --git` boundaries).
struct FileDiff: Identifiable, Equatable {
    let oldPath: String
    let newPath: String
    let status: FileDiffStatus
    let hunks: [DiffHunk]

    var id: String { newPath }

    var isBinary: Bool { status == .binary }

    /// Added/removed line counts across all hunks, for the file header.
    var addedCount: Int {
        hunks.reduce(0) { count, hunk in
            count + hunk.lines.filter { $0.kind == .added }.count
        }
    }

    var removedCount: Int {
        hunks.reduce(0) { count, hunk in
            count + hunk.lines.filter { $0.kind == .removed }.count
        }
    }

    /// `old → new` display path: the bare new path, except renames show both.
    var displayPath: String {
        status == .renamed ? "\(oldPath) → \(newPath)" : newPath
    }

    /// Highlighter language for the diff lines, from the new path's
    /// extension; nil renders plain monospaced text.
    var language: String? {
        SyntaxLanguageMapper.highlightLanguage(forExtension: (newPath as NSString).pathExtension)
    }
}

/// One flat row of the per-file inline view: either a diff line or a static
/// "N hidden lines" band standing in for context the hunks omit.
struct DiffRow: Identifiable, Equatable {
    enum Payload: Equatable {
        case hiddenLines(Int)
        case line(DiffLine)
    }

    let id: String
    let payload: Payload
}

/// Parses the body of `git show --no-color --no-ext-diff --pretty=format:`
/// (pure unified diff, multiple files) into per-file structures. Parsing is
/// total: unrecognized lines are skipped, never fatal.
enum UnifiedDiffParser {
    static func parse(_ text: String) -> [FileDiff] {
        guard !text.isEmpty else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var files: [FileDiff] = []
        var chunk: [String] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            if let file = parseFile(chunk) {
                files.append(file)
            }
            chunk = []
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
            }
            chunk.append(line)
        }
        flush()
        return files
    }

    /// Parses one `diff --git` chunk: header lines first (status, paths),
    /// then every `@@` hunk until the next file or the end.
    static func parseFile(_ chunk: [String]) -> FileDiff? {
        guard let headerLine = chunk.first, headerLine.hasPrefix("diff --git ") else { return nil }

        var status: FileDiffStatus = .modified
        var oldPath = Self.gitHeaderPath(from: headerLine, prefix: "a/")
        var newPath = Self.gitHeaderPath(from: headerLine, prefix: "b/")

        for line in chunk.dropFirst() {
            if line.hasPrefix("@@ ") || line.hasPrefix("diff --git ") {
                break
            }
            if line.hasPrefix("new file mode") {
                status = .added
            } else if line.hasPrefix("deleted file mode") {
                status = .deleted
            } else if line.hasPrefix("rename from ") {
                status = .renamed
                oldPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                newPath = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                status = .binary
            } else if line.hasPrefix("--- ") {
                // `--- a/path` or `--- /dev/null`; authoritative when the
                // `diff --git` heuristic above guessed wrong.
                let path = Self.minusHeaderPath(line)
                if path == nil { status = .added }
                if let path { oldPath = path }
            } else if line.hasPrefix("+++ ") {
                let path = Self.minusHeaderPath(line)
                if path == nil { status = .deleted }
                if let path { newPath = path }
            }
        }

        let hunks = parseHunks(chunk)
        return FileDiff(
            oldPath: oldPath,
            newPath: newPath,
            status: status,
            hunks: status == .binary ? [] : hunks
        )
    }

    /// Best-effort path from the `diff --git a/x b/y` header: take the part
    /// after the last ` b/` (handles spaces in the old path; quoted paths
    /// fall through to the `---`/`+++` lines or rename records instead).
    private static func gitHeaderPath(from line: String, prefix: String) -> String {
        let body = line.dropFirst("diff --git ".count)
        guard let marker = body.range(of: " \(prefix)", options: .backwards) else {
            return ""
        }
        return String(body[marker.upperBound...])
    }

    /// Path from a `--- a/path` / `+++ b/path` line, or nil for `/dev/null`.
    /// Quoted paths are unquoted C-style; exotic escapes degrade to the raw
    /// text, which only affects exotic filenames' display.
    private static func minusHeaderPath(_ line: String) -> String? {
        var body = String(line.dropFirst(4))
        if body.hasPrefix("\""), body.hasSuffix("\""), body.count >= 2 {
            body = String(body.dropFirst().dropLast().replacingOccurrences(of: "\\\"", with: "\""))
        }
        if body.hasPrefix("a/") || body.hasPrefix("b/") {
            body = String(body.dropFirst(2))
        }
        return body == "/dev/null" ? nil : body
    }

    private static func parseHunks(_ chunk: [String]) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var header: (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)?
        var lines: [DiffLine] = []
        var old = 0
        var new = 0

        func flushHunk() {
            guard let header else { return }
            hunks.append(DiffHunk(
                oldStart: header.oldStart,
                oldCount: header.oldCount,
                newStart: header.newStart,
                newCount: header.newCount,
                lines: lines
            ))
            lines = []
        }

        for line in chunk {
            if line.hasPrefix("@@ ") {
                flushHunk()
                guard let parsed = parseHunkHeader(line) else {
                    header = nil
                    continue
                }
                header = parsed
                old = parsed.oldStart
                new = parsed.newStart
                continue
            }
            guard header != nil else { continue }  // header lines before the first hunk

            let marker = line.first
            let content = String(line.dropFirst())
            switch marker {
            case " ":
                lines.append(DiffLine(kind: .context, oldNumber: old, newNumber: new, text: content))
                old += 1
                new += 1
            case "+":
                lines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: new, text: content))
                new += 1
            case "-":
                lines.append(DiffLine(kind: .removed, oldNumber: old, newNumber: nil, text: content))
                old += 1
            case "\\":
                lines.append(DiffLine(kind: .meta, oldNumber: nil, newNumber: nil, text: line))
            default:
                break  // never a line inside a hunk; ignore defensively
            }
        }
        flushHunk()
        return hunks
    }

    /// `@@ -12,7 +12,9 @@ section` — the `,count` parts are optional (1 line).
    static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        let body = line.dropFirst("@@ ".count)
        let parts = body.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        func range(_ part: Substring) -> (start: Int, count: Int)? {
            let piece = part.hasPrefix("-") || part.hasPrefix("+") ? part.dropFirst() : part[...]
            let fields = piece.split(separator: ",")
            guard let start = Int(fields[0]) else { return nil }
            let count = fields.count > 1 ? Int(fields[1]) ?? 0 : 1
            return (start, count)
        }
        guard let oldRange = range(parts[0]), oldRange.start >= 0,
              let newRange = range(parts[1]), newRange.start >= 0 else {
            return nil
        }
        return (oldRange.start, oldRange.count, newRange.start, newRange.count)
    }
}

/// Flattens a `FileDiff` into display rows, inserting the static
/// "N hidden lines" bands the hunk headers imply: above the first hunk when
/// it does not start at the top of the file, and between hunks. The tail gap
/// is unknowable from the diff alone, so nothing is shown for it.
enum DiffRowsBuilder {
    static func rows(for file: FileDiff) -> [DiffRow] {
        var rows: [DiffRow] = []
        var index = 0
        func push(_ payload: DiffRow.Payload) {
            rows.append(DiffRow(id: "\(file.id)#\(index)", payload: payload))
            index += 1
        }

        if let first = file.hunks.first, first.oldStart > 1 {
            push(.hiddenLines(first.oldStart - 1))
        }
        for (position, hunk) in file.hunks.enumerated() {
            if position > 0 {
                let previous = file.hunks[position - 1]
                // The hunk's real old-side lines are the truth; the header
                // count is only a cross-check.
                let consumed = previous.oldStart + max(previous.oldCount, previousLines(previous))
                let gap = hunk.oldStart - consumed
                if gap > 0 {
                    push(.hiddenLines(gap))
                }
            }
            for line in hunk.lines {
                push(.line(line))
            }
        }
        return rows
    }

    /// Old-side lines a hunk actually carries: context plus removals.
    private static func previousLines(_ hunk: DiffHunk) -> Int {
        hunk.lines.reduce(0) { count, line in
            switch line.kind {
            case .context, .removed: count + 1
            case .added, .meta: count
            }
        }
    }
}
