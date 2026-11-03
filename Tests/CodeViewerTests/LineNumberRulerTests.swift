import Testing
@testable import CodeViewer

@MainActor
struct LineNumberRulerTests {
    @Test("line count counts newline-separated lines")
    func countsLines() {
        #expect(LineNumberRulerView.lineCount(in: "") == 1)
        #expect(LineNumberRulerView.lineCount(in: "one") == 1)
        #expect(LineNumberRulerView.lineCount(in: "one\n") == 2)
        #expect(LineNumberRulerView.lineCount(in: "one\ntwo") == 2)
        #expect(LineNumberRulerView.lineCount(in: "a\n\nb") == 3)
    }
}
