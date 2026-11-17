import Foundation
import Testing
@testable import CodeViewer

/// Tests for the editor's working-tree change marks: how hunks map onto the
/// file's *current* line numbers, which lines read as added versus modified,
/// and where removed blocks leave a seam. Fixtures are `git diff --unified=0`
/// bodies (the parser also accepts wider context).
struct LineChangeMapTests {
    private func firstFile(_ diff: String) throws -> FileDiff {
        try #require(UnifiedDiffParser.parse(diff).first)
    }

    /// Zero-context diff of one file, as the editor requests it.
    private func map(_ hunks: String) throws -> LineChangeMap {
        let diff = """
        diff --git a/f.txt b/f.txt
        index 1111111..2222222 100644
        --- a/f.txt
        +++ b/f.txt
        \(hunks)
        """
        return LineChangeMap(diff: try firstFile(diff))
    }

    @Test("an insertion-only hunk marks its new lines as added")
    func marksInsertion() throws {
        let changes = try map("""
        @@ -1,0 +2,2 @@
        +one
        +two
        """)

        #expect(changes.kinds == [2: .added, 3: .added])
        #expect(changes.deletionBoundaries.isEmpty)
        #expect(!changes.isEmpty)
    }

    @Test("a replaced line marks as modified, not added")
    func marksReplacement() throws {
        let changes = try map("""
        @@ -2 +2 @@
        -old
        +new
        """)

        #expect(changes.kinds == [2: .modified])
        #expect(changes.deletionBoundaries.isEmpty)
    }

    @Test("a removed block leaves a seam at the line below it")
    func marksDeletionInTheMiddle() throws {
        // `@@ -2 +1,0 @@` removes old line 2; git points at the last line that
        // survives above it, so the seam belongs to new line 2.
        let changes = try map("""
        @@ -2 +1,0 @@
        -gone
        """)

        #expect(changes.kinds.isEmpty)
        #expect(changes.deletionBoundaries == [2])
    }

    @Test("a block removed at the top leaves the seam on line 1")
    func marksDeletionAtTop() throws {
        let changes = try map("""
        @@ -1 +0,0 @@
        -first
        """)

        #expect(changes.deletionBoundaries == [1])
    }

    @Test("a block removed at the end leaves the seam behind the last line")
    func marksDeletionAtEnd() throws {
        // A three-line file with its last line removed: new side is 2 lines,
        // so the seam sits on line 3.
        let changes = try map("""
        @@ -3 +2,0 @@
        -last
        """)

        #expect(changes.deletionBoundaries == [3])
    }

    @Test("runs inside one hunk classify separately")
    func splitsRunsInsideHunk() throws {
        let changes = try map("""
        @@ -1,3 +1,4 @@
         a
        -b
        +B
         c
        +d
        """)

        #expect(changes.kinds == [2: .modified, 4: .added])
        #expect(changes.deletionBoundaries.isEmpty)
    }

    @Test("a removed block with a tail comment still leaves a seam")
    func marksDeletionBeforeMetaLine() throws {
        let changes = try map("""
        @@ -2 +1,0 @@
        -gone
        \\ No newline at end of file
        """)

        #expect(changes.deletionBoundaries == [2])
    }

    @Test("binary files carry no marks")
    func skipsBinaryFiles() throws {
        let diff = """
        diff --git a/image.png b/image.png
        index 1111111..2222222 100644
        Binary files a/image.png and b/image.png differ
        """
        let file = try firstFile(diff)

        #expect(file.status == .binary)
        #expect(LineChangeMap(diff: file).isEmpty)
    }

    @Test("a new file tints every line through one range")
    func tintsWholeNewFile() {
        let changes = LineChangeMap(isNewFile: true)
        let ranges = changes.tintedRanges(in: "one\ntwo\nthree\n" as NSString)

        #expect(ranges.count == 1)
        #expect(ranges[0].kind == .added)
        #expect(ranges[0].range == NSRange(location: 0, length: 14))
        #expect(changes.kind(forLine: 2) == .added)
    }

    @Test("marked lines map to whole-line ranges including their newline")
    func mapsLineNumbersToRanges() {
        var changes = LineChangeMap()
        changes.kinds = [2: .added, 3: .modified]

        let ranges = changes.tintedRanges(in: "a\nb\nc" as NSString)

        #expect(ranges.count == 2)
        #expect(ranges[0].kind == .added)
        #expect(ranges[0].range == NSRange(location: 2, length: 2))
        // Last line has no trailing newline, so the range stops at the text
        // end instead of swallowing a byte that is not there.
        #expect(ranges[1].kind == .modified)
        #expect(ranges[1].range == NSRange(location: 4, length: 1))
    }

    @Test("marks past the end of the text are dropped, not clamped")
    func dropsOutOfRangeLines() {
        var changes = LineChangeMap()
        changes.kinds = [9: .added]

        #expect(changes.tintedRanges(in: "a\nb\n" as NSString).isEmpty)
    }

    @Test("an empty map and empty text produce nothing to paint")
    func ignoresEmptyInput() {
        #expect(LineChangeMap.empty.tintedRanges(in: "a\nb" as NSString).isEmpty)
        #expect(LineChangeMap(isNewFile: true).tintedRanges(in: "" as NSString).isEmpty)
    }
}
