import Foundation
import Observation
import SwiftUI

/// Working-tree status of one file, rendered as a single badge letter in the
/// tree and on tabs.
enum GitFileStatus: Equatable, Sendable {
    case untracked
    case added
    case deleted
    case modified

    var badge: String {
        switch self {
        case .untracked: return "?"
        case .added: return "A"
        case .deleted: return "D"
        case .modified: return "M"
        }
    }

    var labelKey: String {
        switch self {
        case .untracked: return "Untracked"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .modified: return "Modified"
        }
    }

    var color: Color {
        switch self {
        case .untracked: return .gray
        case .added: return .green
        case .deleted: return .red
        case .modified: return .orange
        }
    }
}

/// One entry of the commit history list.
struct GitCommit: Identifiable, Equatable, Sendable {
    let hash: String

    var id: String { hash }
    let subject: String
    let authorName: String
    let date: Date?
    /// Refs pointing at this commit, most relevant first (e.g. "main").
    let refName: String?
}

/// Runs git's read-only status and diff commands. Anything that can go wrong —
/// git not installed, no repository, an odd exit — degrades to empty results
/// so the rest of the UI simply shows no badges.
actor GitService {
    static let shared = GitService()

    private var resolvedGitPath: String?

    /// The workspace is a repository when its own root holds a `.git` entry
    /// (a directory, or a file for worktrees and submodules). Deliberately no
    /// walk-up: a workspace that is a subfolder of some enclosing repository
    /// stays badge-free instead of pulling statuses from a repo the user
    /// never chose.
    func repositoryRoot(for workspaceURL: URL) -> URL? {
        let root = workspaceURL.standardizedFileURL
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
            ? root
            : nil
    }

    /// Working-tree statuses keyed by absolute file URL. Untracked
    /// directories collapse to one entry on the directory itself.
    func fileStatuses(root: URL) -> [URL: GitFileStatus] {
        guard let git = resolveGit() else { return [:] }
        guard let output = run(
            git,
            arguments: ["-C", root.path, "status", "--porcelain=v1", "-z", "--untracked-files=normal"]
        ) else {
            return [:]
        }
        return Self.parseStatus(output, root: root)
    }

    /// Recent commit history, newest first. Fields arrive separated by unit
    /// separators and commits by record separators, so no quoting or escaping
    /// can corrupt the parse.
    func commits(root: URL, limit: Int = 100) async -> [GitCommit] {
        guard let git = resolveGit() else { return [] }
        let unit = "\u{1f}"
        let record = "\u{1e}"
        let format = "%H\(unit)%an\(unit)%ad\(unit)%D\(unit)%s\(record)"
        guard let output = run(git, arguments: [
            "-C", root.path,
            "log", "--no-color",
            "--max-count=\(limit)",
            "--date=iso-strict",
            "--pretty=format:\(format)",
        ]) else {
            return []
        }
        return output
            .split(separator: Character(record), omittingEmptySubsequences: true)
            // `--pretty=format:` interleaves a plain newline between commits,
            // so every record after the first starts with one.
            .compactMap {
                Self.parseCommit(
                    String($0).trimmingCharacters(in: .newlines),
                    unit: unit
                )
            }
    }

    static let commitDateParser = ISO8601DateFormatter()

    /// Field order matches the format string: hash, author, date, refs, subject.
    static func parseCommit(_ entry: String, unit: String) -> GitCommit? {
        let fields = entry.components(separatedBy: unit)
        guard fields.count >= 5 else { return nil }
        return GitCommit(
            hash: fields[0],
            subject: fields[4],
            authorName: fields[1],
            date: commitDateParser.date(from: fields[2]),
            refName: branchName(fromRefs: fields[3])
        )
    }

    /// "HEAD -> main, origin/main" → "main"; plain refs → first branch name.
    private static func branchName(fromRefs refs: String) -> String? {
        guard !refs.isEmpty else { return nil }
        let first = refs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.first ?? ""
        if first.hasPrefix("HEAD -> ") {
            return String(first.dropFirst("HEAD -> ".count))
        }
        return first
    }

    /// The full diff of one commit (`git show`, diff body only). Five lines
    /// of context per hunk — the inline view's "N hidden lines" bands adapt
    /// to whatever the headers say.
    func commitDiff(root: URL, hash: String) async -> String? {
        guard let git = resolveGit() else { return nil }
        return run(git, arguments: [
            "-C", root.path,
            "show", "--no-color", "--no-ext-diff",
            "--unified=5",
            "--pretty=format:",
            hash,
        ])
    }

    /// Marker for the editor's line tints: which of a file's current lines
    /// differ from HEAD, and where blocks were removed outright. Untracked
    /// files are new top to bottom; clean and deleted files carry no marks.
    func lineChanges(root: URL, relativePath: String, status: GitFileStatus?) -> LineChangeMap {
        switch status {
        case .none, .deleted:
            return .empty
        case .untracked:
            return LineChangeMap(isNewFile: true)
        case .added, .modified:
            break
        }
        guard let output = workingTreeDiff(root: root, path: relativePath),
              let file = UnifiedDiffParser.parse(output).first else {
            return .empty
        }
        return LineChangeMap(diff: file)
    }

    /// `git diff HEAD` for one path against the working tree, with no context
    /// lines: the editor only needs the changed ranges, and a zero-context
    /// diff of an untouched file is empty. Staged and unstaged changes both
    /// count, so the marks describe the file as the user sees it.
    func workingTreeDiff(root: URL, path: String) -> String? {
        guard let git = resolveGit() else { return nil }
        func arguments(against revision: String?) -> [String] {
            var arguments = [
                "-C", root.path, "diff", "--no-color", "--no-ext-diff", "--unified=0",
            ]
            if let revision {
                arguments.append(revision)
            }
            arguments.append(contentsOf: ["--", path])
            return arguments
        }

        if let output = run(git, arguments: arguments(against: "HEAD")) {
            return output
        }
        // No commit yet: diff against the empty tree so a staged new file
        // still reads as a whole-file addition.
        return run(git, arguments: arguments(against: Self.emptyTreeHash))
    }

    /// Well-known hash of the empty tree; `HEAD` does not resolve in a
    /// repository whose first commit does not exist yet.
    private static let emptyTreeHash = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// Parses `git status --porcelain=v1 -z` output. With `-z` paths arrive
    /// NUL-separated and never quoted, and rename records carry the original
    /// path as one extra NUL-terminated field.
    static func parseStatus(_ output: String, root: URL) -> [URL: GitFileStatus] {
        var statuses: [URL: GitFileStatus] = [:]
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)

        var index = 0
        while index < entries.count {
            let entry = entries[index]
            index += 1
            guard entry.count >= 3 else { continue }

            let x = entry.first!
            let y = entry[entry.index(after: entry.startIndex)]
            guard entry[entry.index(entry.startIndex, offsetBy: 2)] == " " else { continue }
            if x == "R" || x == "C" {
                index += 1  // skip the original-path record
            }

            var relative = String(entry.dropFirst(3))
            if relative.hasSuffix("/") {
                relative.removeLast()
            }
            statuses[root.appending(path: relative)] = Self.mapStatus(x: x, y: y)
        }
        return statuses
    }

    private static func mapStatus(x: Character, y: Character) -> GitFileStatus {
        if x == "?" && y == "?" { return .untracked }
        if x == "D" || y == "D" { return .deleted }
        if x == "A" || y == "A" { return .added }
        return .modified
    }

    /// Locates a git binary. The nil result is deliberately not cached —
    /// installing git later should pick up badges on the next refresh.
    private func resolveGit() -> String? {
        if let resolvedGitPath { return resolvedGitPath }
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git",
            "/bin/git",
        ]
        guard let path = candidates.first(
            where: { FileManager.default.isExecutableFile(atPath: $0) }
        ) else {
            Log.git.notice("git is unavailable; repository status is disabled")
            return nil
        }
        resolvedGitPath = path
        return path
    }

    private func run(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            Log.git.error("Could not launch git: \(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            Log.git.debug("git exited \(process.terminationStatus) for \(arguments.joined(separator: " "))")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Observable snapshot of one workspace's git state: whether the workspace
/// sits inside a repository and each file's working-tree status. Lives on the
/// session; views read it for badges and diff availability.
@MainActor
@Observable
final class GitStatusStore {
    private(set) var repositoryRoot: URL?
    private(set) var statuses: [URL: GitFileStatus] = [:]
    private(set) var commits: [GitCommit] = []
    private(set) var isRefreshing = false
    /// Editor line marks for the open files, keyed by file URL. Rebuilt from
    /// the working tree on every refresh, so clean files drop out instead of
    /// leaving stale tints behind.
    private(set) var lineChanges: [URL: LineChangeMap] = [:]

    private let service: GitService
    private var generation = 0
    private var lineChangeGeneration = 0

    init(service: GitService = .shared) {
        self.service = service
    }

    var hasRepository: Bool {
        repositoryRoot != nil
    }

    func status(for url: URL) -> GitFileStatus? {
        statuses[url.standardizedFileURL]
    }

    /// Editor marks for one open file, or nil when it is clean.
    func lineChanges(for url: URL) -> LineChangeMap? {
        lineChanges[url.standardizedFileURL]
    }

    /// Recomputes the editor marks for exactly these files — normally every
    /// open file tab — after `refresh` settled the statuses. A newer call
    /// supersedes an older one, so a tab opened mid-refresh still ends up with
    /// the marks for the current working tree.
    func refreshLineChanges(for urls: [URL]) async {
        lineChangeGeneration += 1
        let run = lineChangeGeneration

        guard let root = repositoryRoot else {
            lineChanges = [:]
            return
        }

        var fresh: [URL: LineChangeMap] = [:]
        for url in urls {
            let standardized = url.standardizedFileURL
            guard let relativePath = relativePath(of: standardized, in: root),
                  let status = resolvedStatus(for: standardized) else { continue }
            let changes = await service.lineChanges(
                root: root,
                relativePath: relativePath,
                status: status
            )
            guard run == lineChangeGeneration else { return }
            if !changes.isEmpty {
                fresh[standardized] = changes
            }
        }
        lineChanges = fresh
    }

    /// The file's status, with files inside an untracked directory inheriting
    /// it: `git status` collapses such a directory onto one entry, so its
    /// files would otherwise look clean.
    private func resolvedStatus(for url: URL) -> GitFileStatus? {
        if let status = statuses[url] { return status }
        let path = url.path
        return statuses.first { directory, status in
            status == .untracked && path.hasPrefix(directory.path + "/")
        }?.value
    }

    /// Path relative to the repository root, for git's pathspec.
    private func relativePath(of url: URL, in root: URL) -> String? {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(prefix) else { return nil }
        return String(url.path.dropFirst(prefix.count))
    }

    /// Discovers the repository and loads statuses. A newer call supersedes
    /// an older one: stale results are dropped instead of overwriting.
    func refresh(workspaceURL: URL) async {
        generation += 1
        let run = generation
        isRefreshing = true
        defer {
            if run == generation {
                isRefreshing = false
            }
        }

        let root = await service.repositoryRoot(for: workspaceURL)
        guard run == generation else { return }
        repositoryRoot = root

        guard let root else {
            statuses = [:]
            commits = []
            return
        }
        let freshStatuses = await service.fileStatuses(root: root)
        guard run == generation else { return }
        statuses = freshStatuses
        commits = await service.commits(root: root)
    }
}
