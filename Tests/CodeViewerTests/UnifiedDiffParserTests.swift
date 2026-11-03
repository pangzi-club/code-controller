import Foundation
import Testing
@testable import CodeViewer

/// Tests for the unified diff parser and the inline row assembly: multi-file
/// splitting, status detection, numbering rules and the "N hidden lines"
/// gap arithmetic. All fixtures are `git show --pretty=format:` bodies.
struct UnifiedDiffParserTests {
    @Test("empty input parses to no files")
    func parsesEmptyInput() {
        #expect(UnifiedDiffParser.parse("").isEmpty)
    }

    @Test("multi-file output splits into per-file diffs")
    func splitsMultipleFiles() {
        let files = UnifiedDiffParser.parse(sampleTwoFiles)

        #expect(files.count == 2)
        #expect(files[0].newPath == "Sources/App.swift")
        #expect(files[1].newPath == "README.md")
        #expect(files[0].status == .modified)
        #expect(files[1].status == .modified)
    }

    @Test("context, added and removed lines number per side")
    func numbersLines() throws {
        let files = UnifiedDiffParser.parse(sampleTwoFiles)
        let hunk = try #require(files[0].hunks.first)
        let lines = hunk.lines

        // " import Foundation" context: old 5, new 5.
        #expect(lines[0].kind == .context)
        #expect(lines[0].oldNumber == 5)
        #expect(lines[0].newNumber == 5)
        // "-let a = 1" removed: old 6, no new number.
        #expect(lines[1].kind == .removed)
        #expect(lines[1].oldNumber == 6)
        #expect(lines[1].newNumber == nil)
        // "+let a = 2" added: new 6, no old number.
        #expect(lines[2].kind == .added)
        #expect(lines[2].oldNumber == nil)
        #expect(lines[2].newNumber == 6)
        // Context resumes on both sides at 7.
        #expect(lines[3].oldNumber == 7)
        #expect(lines[3].newNumber == 7)
        #expect(lines[3].text == "let b = 3")
    }

    @Test("hunk headers without a count suffix mean one line")
    func parsesCountlessHunkHeaders() throws {
        let diff = """
        diff --git a/single.txt b/single.txt
        index 111..222 100644
        --- a/single.txt
        +++ b/single.txt
        @@ -3 +3 @@
        -old
        +new

        """
        let hunk = try #require(UnifiedDiffParser.parse(diff).first?.hunks.first)
        #expect(hunk.oldStart == 3)
        #expect(hunk.oldCount == 1)
        #expect(hunk.newStart == 3)
        #expect(hunk.newCount == 1)
    }

    @Test("new, deleted, renamed and binary files report their status")
    func detectsFileStatuses() {
        let files = UnifiedDiffParser.parse(sampleMixedStatuses)

        #expect(files.count == 4)
        #expect(files[0].status == .added)
        #expect(files[0].newPath == "new.swift")
        #expect(files[1].status == .deleted)
        #expect(files[1].oldPath == "gone.swift")
        #expect(files[2].status == .renamed)
        #expect(files[2].displayPath == "before.swift → after.swift")
        #expect(files[3].status == .binary)
        #expect(files[3].isBinary)
        #expect(files[3].hunks.isEmpty)
    }

    @Test("the no-newline marker becomes an unnumbered meta line")
    func parsesNoNewlineMarker() throws {
        let hunk = try #require(UnifiedDiffParser.parse(sampleNoNewline).first?.hunks.first)
        let meta = hunk.lines.last

        #expect(meta?.kind == .meta)
        #expect(meta?.oldNumber == nil)
        #expect(meta?.newNumber == nil)
        #expect(meta?.text.contains("No newline at end of file") == true)
    }

    @Test("malformed hunk headers are skipped without killing the file")
    func skipsMalformedHunkHeader() throws {
        let diff = """
        diff --git a/x.txt b/x.txt
        --- a/x.txt
        +++ b/x.txt
        @@ nonsense @@
        @@ -1 +1,2 @@
        -a
        +b
        +c

        """
        let file = try #require(UnifiedDiffParser.parse(diff).first)
        #expect(file.hunks.count == 1)
        #expect(file.hunks[0].lines.map(\.text) == ["a", "b", "c"])
    }

    @Test("row assembly inserts hidden-line bands the hunk headers imply")
    func buildsHiddenLineBands() {
        let file = UnifiedDiffParser.parse(sampleTwoFiles)[0]
        let rows = DiffRowsBuilder.rows(for: file)
        var bands: [Int] = []
        for row in rows {
            if case .hiddenLines(let count) = row.payload {
                bands.append(count)
            }
        }

        // First hunk starts at old 5 → 4 lines hidden above; second hunk
        // starts at old 20, the first consumes old 5..8 → 11 hidden between.
        #expect(bands == [4, 11])
    }

    @Test("a diff starting at the top has no leading band")
    func buildsNoLeadingBandAtFileTop() throws {
        let diff = """
        diff --git a/top.txt b/top.txt
        --- a/top.txt
        +++ b/top.txt
        @@ -1,2 +1,3 @@
         a
        -b
        +B
         c

        """
        let rows = DiffRowsBuilder.rows(for: try #require(UnifiedDiffParser.parse(diff).first))
        guard case .line(let first) = rows[0].payload else {
            Issue.record("expected the first row to be a diff line")
            return
        }
        #expect(first.text == "a")
    }

    @Test("row ids are stable and unique")
    func rowIdsAreUnique() {
        let file = UnifiedDiffParser.parse(sampleTwoFiles)[0]
        let rows = DiffRowsBuilder.rows(for: file)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("added and removed counts derive from the hunks")
    func countsAddedRemovedLines() {
        let files = UnifiedDiffParser.parse(sampleTwoFiles)
        #expect(files[0].addedCount == 5)     // App.swift: +3 in hunk 1, +2 in hunk 2
        #expect(files[0].removedCount == 3)   //           -2 in hunk 1, -1 in hunk 2
        #expect(files[1].addedCount == 1)     // README.md: intro line
        #expect(files[1].removedCount == 0)

        let mixed = UnifiedDiffParser.parse(sampleMixedStatuses)
        #expect(mixed[0].addedCount == 2)     // new.swift
        #expect(mixed[3].addedCount == 0)     // binary: no hunks
    }

    @Test("languages resolve from the new path's extension")
    func resolvesLanguages() throws {
        let files = UnifiedDiffParser.parse(sampleMixedStatuses)
        #expect(files[0].language == "swift")   // new.swift
        #expect(files[3].language == nil)       // asset.dat has no mapping

        let swiftFile = try #require(UnifiedDiffParser.parse(sampleTwoFiles).first)
        #expect(swiftFile.language == "swift")  // Sources/App.swift
    }

    // MARK: Fixtures

    /// Two modified files; the first hunk starts at old line 5 and a second
    /// hunk follows after a gap (old 11..19 hidden).
    private let sampleTwoFiles = """
    diff --git a/Sources/App.swift b/Sources/App.swift
    index 1111111..2222222 100644
    --- a/Sources/App.swift
    +++ b/Sources/App.swift
    @@ -5,4 +5,5 @@ import SwiftUI
     import Foundation
    -let a = 1
    +let a = 2
     let b = 3
    -let c = 4
    +let c = 5
    +let d = 6
    @@ -20,3 +21,4 @@ struct App
     struct App {
    -    static let name = "old"
    +    static let name = "new"
    +    static let other = 1
     }
    diff --git a/README.md b/README.md
    index 3333333..4444444 100644
    --- a/README.md
    +++ b/README.md
    @@ -1,3 +1,4 @@
     # Title
    +intro line
     body

    """

    private let sampleMixedStatuses = """
    diff --git a/new.swift b/new.swift
    new file mode 100644
    index 0000000..5555555
    --- /dev/null
    +++ b/new.swift
    @@ -0,0 +1,2 @@
    +print("hi")
    +print("bye")
    diff --git a/gone.swift b/gone.swift
    deleted file mode 100644
    index 6666666..0000000
    --- a/gone.swift
    +++ /dev/null
    @@ -1,1 +0,0 @@
    -print("gone")
    diff --git a/before.swift b/after.swift
    similarity index 90%
    rename from before.swift
    rename to after.swift
    index 7777777..8888888 100644
    --- a/before.swift
    +++ b/after.swift
    @@ -1 +1 @@
    -struct Before
    +struct After
    diff --git a/asset.dat b/asset.dat
    index 9999999..aaaaaaa 100644
    Binary files a/asset.dat and b/asset.dat differ

    """

    private let sampleNoNewline = """
    diff --git a/last.txt b/last.txt
    index bbbb...cccc 100644
    --- a/last.txt
    +++ b/last.txt
    @@ -1 +1 @@
    -old without newline
    \\ No newline at end of file
    +new without newline
    \\ No newline at end of file

    """
}
