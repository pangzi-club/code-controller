import Testing
@testable import DemoExplorer

struct FolderPaletteTests {
    @Test("the same path always maps to the same color")
    func stablePerPath() {
        #expect(FolderPalette.colorIndex(for: "/Users/a/Docs") == FolderPalette.colorIndex(for: "/Users/a/Docs"))
        #expect(FolderPalette.color(for: "/Users/a/Docs") == FolderPalette.color(for: "/Users/a/Docs"))
    }

    @Test("indices stay in range and spread across the palette")
    func inRange() {
        let indices = (0..<50).map { FolderPalette.colorIndex(for: "/folder/\($0)") }
        #expect(indices.allSatisfy { (0..<FolderPalette.colors.count).contains($0) })
        #expect(Set(indices).count > 1)
    }
}
