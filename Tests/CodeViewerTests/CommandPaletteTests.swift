import Foundation
import Testing
@testable import CodeViewer

/// The catalog, availability rules and matcher are language independent: the
/// titles resolve in the test process's language, so queries are derived from
/// the titles themselves rather than spelled in English.
struct CommandPaletteTests {
    private func commands(_ commands: PaletteCommand...) -> [PaletteCommand] {
        commands
    }

    private func highlighted(_ title: String, _ match: PaletteCommandMatch) -> String {
        match.titleRanges.map { range in
            let lower = title.index(title.startIndex, offsetBy: range.lowerBound)
            let upper = title.index(title.startIndex, offsetBy: range.upperBound)
            return String(title[lower..<upper])
        }.joined()
    }

    /// The shortest prefix of the command's title that no other title contains.
    private func uniquePrefix(of command: PaletteCommand) -> String {
        let title = command.title
        let others = PaletteCommand.allCases.filter { $0 != command }.map(\.title)
        for length in 1...title.count {
            let prefix = String(title.prefix(length))
            if others.allSatisfy({ $0.range(of: prefix, options: .caseInsensitive) == nil }) {
                return prefix
            }
        }
        return title
    }

    // MARK: Query

    @Test("a leading > switches the query to commands and trims the rest")
    func queryPrefix() {
        #expect(QuickOpenQuery("log") == .files("log"))
        #expect(QuickOpenQuery(">") == .commands(""))
        #expect(QuickOpenQuery(">close") == .commands("close"))
        #expect(QuickOpenQuery(">  close tab ") == .commands("close tab"))
        // Only the very first character switches modes.
        #expect(QuickOpenQuery("a > b") == .files("a > b"))
    }

    // MARK: Catalog

    @Test("every command has a distinct title and icon")
    func distinctTitles() {
        let titles = PaletteCommand.allCases.map(\.title)
        let symbols = PaletteCommand.allCases.map(\.symbolName)
        #expect(Set(titles).count == titles.count)
        #expect(Set(symbols).count == symbols.count)
    }

    @MainActor
    @Test("tab commands appear only when they have something to act on")
    func tabCommandAvailability() {
        func available(_ tabs: [DocumentTab], selecting id: DocumentTab.ID?) -> Set<PaletteCommand> {
            Set(PaletteCommand.allCases.filter { $0.isAvailable(tabs: tabs, selectedTabID: id) })
        }

        // No tabs: the view, app and sidebar commands remain.
        #expect(available([], selecting: nil) == [
            .showFiles, .showGitGraph, .toggleSidebar, .refreshWorkspace, .openSettings, .toggleAppearance,
        ])

        let only = DocumentTab(url: URL(fileURLWithPath: "/tmp/CommandPaletteTests/A.swift"))
        #expect(available([only], selecting: only.id) == [
            .closeTab, .closeAllTabs,
            .showFiles, .showGitGraph, .toggleSidebar, .refreshWorkspace, .revealActiveFileInFinder,
            .openSettings, .toggleAppearance,
        ])

        let tabs = ["A", "B", "C"].map {
            DocumentTab(url: URL(fileURLWithPath: "/tmp/CommandPaletteTests/\($0).swift"))
        }
        let always: Set<PaletteCommand> = [
            .closeTab, .closeAllTabs, .closeOtherTabs, .selectNextTab, .selectPreviousTab,
            .showFiles, .showGitGraph, .toggleSidebar, .refreshWorkspace, .revealActiveFileInFinder,
            .openSettings, .toggleAppearance,
        ]
        // Middle tab: both sides can be closed.
        #expect(available(tabs, selecting: tabs[1].id) == always.union([.closeTabsToLeft, .closeTabsToRight]))
        // First tab: nothing to the left; last tab: nothing to the right.
        #expect(available(tabs, selecting: tabs[0].id) == always.union([.closeTabsToRight]))
        #expect(available(tabs, selecting: tabs[2].id) == always.union([.closeTabsToLeft]))

        // A commit diff has no file to reveal.
        let diff = DocumentTab(commit: GitCommit(
            hash: "abc123", subject: "Subject", authorName: "tester", date: nil, refName: nil
        ))
        #expect(!PaletteCommand.revealActiveFileInFinder.isAvailable(tabs: [diff], selectedTabID: diff.id))
        // A stale selection counts as nothing selected.
        #expect(!PaletteCommand.closeTabsToLeft.isAvailable(tabs: tabs, selectedTabID: "missing"))
    }

    // MARK: Matching

    @Test("an empty query lists every command in catalog order without highlights")
    func emptyQuery() {
        let matches = PaletteCommandMatcher.filter(PaletteCommand.allCases, query: "")
        #expect(matches.map(\.command) == PaletteCommand.allCases)
        #expect(matches.allSatisfy { $0.titleRanges.isEmpty })
    }

    @Test("a title substring is the first hit and its range covers the query")
    func substringRanksFirst() throws {
        let query = uniquePrefix(of: .showGitGraph)
        let title = PaletteCommand.showGitGraph.title
        let matches = PaletteCommandMatcher.filter(PaletteCommand.allCases, query: query)

        let first = try #require(matches.first)
        #expect(first.command == .showGitGraph)
        let hit = highlighted(title, first)
        #expect(hit.caseInsensitiveCompare(query) == .orderedSame)
    }

    @Test("fuzzy hits mark each matched character, keyword hits mark nothing")
    func fuzzyAndKeywordHits() throws {
        let title = PaletteCommand.toggleSidebar.title
        let first = String(title.prefix(1))
        let last = String(title.suffix(1))
        let fuzzy = try #require(
            PaletteCommandMatcher.filter(commands(.toggleSidebar), query: first + last).first
        )
        // Scattered characters: two separate ranges unless they are adjacent.
        #expect(fuzzy.titleRanges.count == 2)
        #expect(highlighted(title, fuzzy).caseInsensitiveCompare(first + last) == .orderedSame)

        // "scm" is a keyword only; the title (any language) does not contain it.
        let keyword = try #require(
            PaletteCommandMatcher.filter(PaletteCommand.allCases, query: "scm").first
        )
        #expect(keyword.command == .showGitGraph)
        #expect(keyword.titleRanges.isEmpty)

        #expect(PaletteCommandMatcher.filter(PaletteCommand.allCases, query: "zzqq").isEmpty)
    }

    @Test("the same title prefix keeps catalog order")
    func tiesKeepCatalogOrder() {
        let closeCommands = PaletteCommand.allCases.filter { $0.category == .tabs && $0.rawValue.hasPrefix("close") }
        let query = String(PaletteCommand.closeTab.title.prefix(2))
        let matches = PaletteCommandMatcher.filter(PaletteCommand.allCases, query: query)
        let closes = matches.map(\.command).filter { closeCommands.contains($0) }
        #expect(closes == closeCommands)
    }

    // MARK: Fuzzy matcher

    @Test("matches a scattered subsequence case-insensitively and reports each hit")
    func fuzzyRanges() throws {
        let match = try #require(FuzzyMatcher.match("Close Tab", query: "CLTAB"))
        #expect(match.ranges == [0..<2, 6..<9])

        let scattered = try #require(FuzzyMatcher.match("Close Other Tabs", query: "ct"))
        // "C" then either "t" — the scorer picks one; each hit is its own range.
        #expect(scattered.ranges.count == 2)
        #expect(scattered.ranges.allSatisfy { $0.count == 1 })
    }

    @Test("a literal run is one range; word starts and early hits score higher")
    func fuzzyScoring() throws {
        let literal = try #require(FuzzyMatcher.match("Close Other Tabs", query: "other"))
        #expect(literal.ranges == [6..<11])

        let earlier = try #require(FuzzyMatcher.match("Close Tab", query: "tab"))
        let later = try #require(FuzzyMatcher.match("Select Next Tab", query: "tab"))
        #expect(earlier.score > later.score)

        let wordStarts = try #require(FuzzyMatcher.match("Close Tab", query: "ct"))
        let insideWord = try #require(FuzzyMatcher.match("Select Next Tab", query: "ct"))
        #expect(wordStarts.score > insideWord.score)
    }

    @Test("no subsequence, an empty query or a folding mismatch does not match")
    func fuzzyMisses() {
        #expect(FuzzyMatcher.match("Close Tab", query: "zzz") == nil)
        #expect(FuzzyMatcher.match("Close Tab", query: "bat") == nil)
        #expect(FuzzyMatcher.match("Close Tab", query: "") == nil)
        #expect(FuzzyMatcher.match("Straße", query: "strasse") == nil)
    }
}
