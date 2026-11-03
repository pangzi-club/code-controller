import Foundation
import Testing
@testable import CodeViewer

@Suite
struct URLDisplayTests {
    @Test("home paths are abbreviated without matching sibling prefixes")
    func abbreviatedHomePath() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let child = home.appendingPathComponent("Projects/Demo")
        let siblingPrefix = URL(fileURLWithPath: home.path + "-archive/Projects")

        #expect(home.abbreviatedPath == "~")
        #expect(child.abbreviatedPath == "~/Projects/Demo")
        #expect(siblingPrefix.abbreviatedPath == siblingPrefix.path)
    }
}
