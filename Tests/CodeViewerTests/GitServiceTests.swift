import Foundation
import Testing
@testable import CodeViewer

/// Tests for the git CLI plumbing: repository discovery, porcelain parsing
/// and the observable status store. Live status uses a real `git init` repo
/// in a temporary directory — no commits needed for untracked statuses.
struct GitServiceTests {
    private let service = GitService.shared

    @Test("a workspace with .git at its root is a repository")
    func detectsRepositoryRoot() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(try #require(await service.repositoryRoot(for: base)) == base.standardizedFileURL)

        try? FileManager.default.removeItem(at: base)
    }

    @Test("a .git file (worktree-style) also marks a repository root")
    func acceptsGitFile() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("gitdir: /elsewhere".utf8).write(
            to: base.appendingPathComponent(".git")
        )

        #expect(try #require(await service.repositoryRoot(for: base)) == base.standardizedFileURL)

        try? FileManager.default.removeItem(at: base)
    }

    @Test("a workspace without .git is not a repository")
    func rejectsNonRepository() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        #expect(await service.repositoryRoot(for: base) == nil)

        try? FileManager.default.removeItem(at: base)
    }

    @Test("porcelain -z output maps to per-file statuses")
    func parsesPorcelainOutput() throws {
        let root = URL(fileURLWithPath: "/tmp/fake-repo")
        let output = " M src/main.swift\0"
            + "M  src/staged.swift\0"
            + "A  new.swift\0"
            + "D  gone.swift\0"
            + "D  half/combined\0"
            + "?? notes.txt\0"
            + "?? fresh-dir/\0"
            + "R  renamed.swift\0old-name.swift\0"

        let statuses = GitService.parseStatus(output, root: root)

        #expect(statuses.count == 8)
        #expect(statuses[root.appending(path: "src/main.swift")] == .modified)
        #expect(statuses[root.appending(path: "src/staged.swift")] == .modified)
        #expect(statuses[root.appending(path: "new.swift")] == .added)
        #expect(statuses[root.appending(path: "gone.swift")] == .deleted)
        #expect(statuses[root.appending(path: "half/combined")] == .deleted)
        #expect(statuses[root.appending(path: "notes.txt")] == .untracked)
        // Untracked directories collapse onto the directory itself.
        #expect(statuses[root.appending(path: "fresh-dir")] == .untracked)
        // The rename record's original path was skipped.
        #expect(statuses[root.appending(path: "renamed.swift")] == .modified)
        #expect(statuses[root.appending(path: "old-name.swift")] == nil)
    }

    @Test("malformed porcelain lines are skipped")
    func skipsMalformedLines() {
        let root = URL(fileURLWithPath: "/tmp/fake-repo")
        let output = "\0garbage\0 M ok.swift\0"

        let statuses = GitService.parseStatus(output, root: root)

        #expect(statuses.count == 1)
        #expect(statuses[root.appending(path: "ok.swift")] == .modified)
    }

    @Test("commit log records survive the newline git interleaves")
    func parsesCommitLogRecords() {
        let unit = "\u{1f}"
        let record = "\u{1e}"
        // `git log --pretty=format:` separates consecutive commits with a
        // bare newline, so records after the first begin with one.
        let output = "abc123\(unit)Ada\(unit)2026-01-02T03:04:05Z\(unit)HEAD -> main\(unit)first\(record)"
            + "\n"
            + "def456\(unit)Linus\(unit)2026-01-03T09:00:00Z\(unit)\(unit)second\(record)"

        let commits = output
            .split(separator: Character(record), omittingEmptySubsequences: true)
            .compactMap {
                GitService.parseCommit(
                    String($0).trimmingCharacters(in: .newlines),
                    unit: unit
                )
            }

        #expect(commits.count == 2)
        #expect(commits[0].hash == "abc123")
        #expect(commits[0].refName == "main")
        #expect(commits[0].date != nil)
        #expect(commits[1].hash == "def456")
        #expect(commits[1].subject == "second")
        #expect(commits[1].refName == nil)
    }

    @Test("live untracked files get badges from a real git repository")
    func liveRepositoryStatus() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        // git init makes the directory a real repository without a commit.
        guard let git = await gitBinary() else {
            Issue.record("git is unavailable; cannot run the live repository test")
            return
        }
        try run(git, arguments: ["init", "-q", repo.path])
        try Data("print(\"hi\")\n".utf8).write(to: repo.appendingPathComponent("main.py"))
        try Data("x\n".utf8).write(to: repo.appendingPathComponent("tracked.txt"))
        try run(git, arguments: ["-C", repo.path, "add", "tracked.txt"])

        let statuses = await service.fileStatuses(root: repo)

        #expect(statuses[repo.appending(path: "main.py")] == .untracked)
        // Staged without commit reads as an addition.
        #expect(statuses[repo.appending(path: "tracked.txt")] == .added)

        try? FileManager.default.removeItem(at: repo)
    }

    // MARK: Helpers

    private func gitBinary() async -> String? {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ path: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")) failed")
    }
}

@MainActor
struct GitStatusStoreTests {
    @Test("a workspace outside a repository degrades to no badges")
    func nonRepositoryDegrades() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let store = GitStatusStore()
        await store.refresh(workspaceURL: outside)

        #expect(store.repositoryRoot == nil)
        #expect(store.statuses.isEmpty)
        #expect(!store.hasRepository)
        #expect(store.status(for: outside.appending(path: "anything.txt")) == nil)
        #expect(!store.isRefreshing)

        try? FileManager.default.removeItem(at: outside)
    }
}
