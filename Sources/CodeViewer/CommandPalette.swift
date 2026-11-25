import Foundation

/// What the quick-open query asks for. A leading `>` switches the panel from
/// files to commands, VS Code style; deleting it switches back.
enum QuickOpenQuery: Equatable {
    case files(String)
    case commands(String)

    init(_ text: String) {
        guard text.hasPrefix(">") else {
            self = .files(text)
            return
        }
        self = .commands(String(text.dropFirst()).trimmingCharacters(in: .whitespaces))
    }
}

/// One runnable command of the ⌘P panel's command mode. Pure data: the title
/// resolves at display time and the main window runs it, so the catalog, the
/// availability rules and the matcher are unit-testable without SwiftUI.
enum PaletteCommand: String, CaseIterable, Identifiable {
    case closeTab
    case closeOtherTabs
    case closeTabsToLeft
    case closeTabsToRight
    case closeAllTabs
    case selectNextTab
    case selectPreviousTab
    case showFiles
    case showGitGraph
    case toggleSidebar
    case refreshWorkspace
    case revealActiveFileInFinder
    case openSettings
    case toggleAppearance

    var id: String { rawValue }

    /// Shown on the row's trailing side, where file rows show the directory.
    enum Category: CaseIterable {
        case view
        case tabs
        case file
        case preferences

        var labelKey: String {
            switch self {
            case .view: "View"
            case .tabs: "Tabs"
            case .file: "File"
            case .preferences: "Preferences"
            }
        }
    }

    /// The declaration order is the palette's order for an empty query.
    var category: Category {
        switch self {
        case .closeTab, .closeOtherTabs, .closeTabsToLeft, .closeTabsToRight, .closeAllTabs,
             .selectNextTab, .selectPreviousTab:
            .tabs
        case .showFiles, .showGitGraph, .toggleSidebar, .refreshWorkspace:
            .view
        case .revealActiveFileInFinder:
            .file
        case .openSettings, .toggleAppearance:
            .preferences
        }
    }

    var titleKey: String {
        switch self {
        case .closeTab: "Close Tab"
        case .closeOtherTabs: "Close Other Tabs"
        case .closeTabsToLeft: "Close Tabs to the Left"
        case .closeTabsToRight: "Close Tabs to the Right"
        case .closeAllTabs: "Close All Tabs"
        case .selectNextTab: "Select Next Tab"
        case .selectPreviousTab: "Select Previous Tab"
        case .showFiles: "Show Files"
        case .showGitGraph: "Show Git Graph"
        case .toggleSidebar: "Toggle Sidebar"
        case .refreshWorkspace: "Refresh Workspace"
        case .revealActiveFileInFinder: "Reveal Active File in Finder"
        case .openSettings: "Open Settings"
        case .toggleAppearance: "Toggle Light/Dark Appearance"
        }
    }

    var title: String { l10nString(titleKey) }

    var symbolName: String {
        switch self {
        case .closeTab: "xmark"
        case .closeOtherTabs: "xmark.circle"
        case .closeTabsToLeft: "arrow.left.to.line"
        case .closeTabsToRight: "arrow.right.to.line"
        case .closeAllTabs: "xmark.square"
        case .selectNextTab: "chevron.right"
        case .selectPreviousTab: "chevron.left"
        case .showFiles: "folder"
        case .showGitGraph: "arrow.triangle.branch"
        case .toggleSidebar: "sidebar.leading"
        case .refreshWorkspace: "arrow.clockwise"
        case .revealActiveFileInFinder: "doc.text.magnifyingglass"
        case .openSettings: "gearshape"
        case .toggleAppearance: "circle.lefthalf.filled"
        }
    }

    /// Extra match words beyond the localized title, so "git" finds Show Git
    /// Graph whatever the UI language spells it. Never shown.
    var keywords: [String] {
        switch self {
        case .closeTab: []
        case .closeOtherTabs: []
        case .closeTabsToLeft: ["left"]
        case .closeTabsToRight: ["right"]
        case .closeAllTabs: ["all", "clear"]
        case .selectNextTab: ["next", "right", "cycle"]
        case .selectPreviousTab: ["previous", "prev", "left", "back"]
        case .showFiles: ["explorer", "tree"]
        case .showGitGraph: ["git", "scm", "history", "commits", "log", "branch"]
        case .toggleSidebar: ["sidebar", "panel"]
        case .refreshWorkspace: ["reload"]
        case .revealActiveFileInFinder: ["finder", "reveal"]
        case .openSettings: ["settings", "preferences", "config"]
        case .toggleAppearance: ["theme", "dark", "light", "color", "appearance"]
        }
    }

    /// Whether the command can do anything right now. Unavailable commands
    /// are left out of the palette rather than shown dimmed.
    func isAvailable(tabs: [DocumentTab], selectedTabID: DocumentTab.ID?) -> Bool {
        let selectedIndex = tabs.firstIndex { $0.id == selectedTabID }
        switch self {
        case .closeTab, .closeAllTabs:
            return !tabs.isEmpty
        case .closeOtherTabs, .selectNextTab, .selectPreviousTab:
            return tabs.count > 1
        case .closeTabsToLeft:
            return (selectedIndex ?? 0) > 0
        case .closeTabsToRight:
            guard let selectedIndex else { return false }
            return selectedIndex < tabs.count - 1
        case .revealActiveFileInFinder:
            return selectedIndex.map { tabs[$0].url != nil } ?? false
        default:
            return true
        }
    }
}

/// A command plus the parts of its title the query hit, so the row can
/// emphasize them, as character offsets. Empty for keyword-only matches and
/// the empty query.
struct PaletteCommandMatch {
    let command: PaletteCommand
    let titleRanges: [Range<Int>]
}

/// Pure command matching for the palette, free of SwiftUI so it can be unit
/// tested.
enum PaletteCommandMatcher {
    /// Title matches come first, best fuzzy score first (a literal substring
    /// outranks scattered characters, earlier hits outrank later ones);
    /// commands matched only through a keyword or their category follow in
    /// catalog order.
    static func filter(_ commands: [PaletteCommand], query: String) -> [PaletteCommandMatch] {
        guard !query.isEmpty else {
            return commands.map { PaletteCommandMatch(command: $0, titleRanges: []) }
        }

        var titleMatches: [(order: Int, match: PaletteCommandMatch, score: Int)] = []
        var keywordMatches: [PaletteCommandMatch] = []
        for (order, command) in commands.enumerated() {
            let title = command.title
            if let fuzzy = FuzzyMatcher.match(title, query: query) {
                let isSubstring = title.range(of: query, options: .caseInsensitive) != nil
                titleMatches.append((
                    order,
                    PaletteCommandMatch(command: command, titleRanges: fuzzy.ranges),
                    fuzzy.score + (isSubstring ? 100 : 0)
                ))
            } else if matchesKeywords(command, query: query) {
                keywordMatches.append(PaletteCommandMatch(command: command, titleRanges: []))
            }
        }

        return titleMatches
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.order < rhs.order
            }
            .map(\.match) + keywordMatches
    }

    private static func matchesKeywords(_ command: PaletteCommand, query: String) -> Bool {
        let words = command.keywords + [l10nString(command.category.labelKey)]
        return words.contains { word in
            word.range(of: query, options: .caseInsensitive) != nil
                || query.range(of: word, options: .caseInsensitive) != nil
        }
    }
}

/// Case-insensitive subsequence matching with a VS Code-like score: a
/// character is worth more at the start of a word, runs of adjacent matches
/// beat scattered ones, and the matched characters pay for the gap they span
/// and for how far into the title they start.
enum FuzzyMatcher {
    struct Match {
        let score: Int
        /// Character offsets of the matched characters inside the matched string.
        let ranges: [Range<Int>]
    }

    static func match(_ text: String, query: String) -> Match? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let haystack = Array(text.folding(options: options, locale: nil))
        let needles = Array(query.folding(options: options, locale: nil))
        // Folding can change the character count ("ß" → "ss"), which would
        // misalign the ranges; such text simply does not match.
        guard haystack.count == text.count, !needles.isEmpty, !haystack.isEmpty else {
            return nil
        }

        // best[j][i]: the best score with needle j matched at haystack i, and
        // previous[j][i] the haystack position of needle j - 1 in that
        // alignment. Int.min marks an impossible cell.
        let count = haystack.count
        var best = [[Int]](repeating: [Int](repeating: Int.min, count: count), count: needles.count)
        var previous = [[Int]](repeating: [Int](repeating: -1, count: count), count: needles.count)
        for i in 0..<count where haystack[i] == needles[0] {
            best[0][i] = characterScore(haystack, at: i, adjacent: false)
        }
        for j in 1..<needles.count {
            // The best earlier alignment of needle j - 1 at any position
            // before i, carried along so each cell costs O(1).
            var runningMax = Int.min
            var runningIndex = -1
            for i in 0..<count {
                if i > 0, best[j - 1][i - 1] > runningMax {
                    runningMax = best[j - 1][i - 1]
                    runningIndex = i - 1
                }
                guard haystack[i] == needles[j] else { continue }
                if i > 1, best[j - 1][i - 2] > Int.min {
                    let adjacent = best[j - 1][i - 2] + characterScore(haystack, at: i, adjacent: true)
                    if adjacent > best[j][i] {
                        best[j][i] = adjacent
                        previous[j][i] = i - 2
                    }
                }
                if runningMax > Int.min {
                    let apart = runningMax + characterScore(haystack, at: i, adjacent: false)
                    if apart > best[j][i] {
                        best[j][i] = apart
                        previous[j][i] = runningIndex
                    }
                }
            }
        }

        var endIndex = -1
        var endScore = Int.min
        for i in 0..<count where best[needles.count - 1][i] > endScore {
            endScore = best[needles.count - 1][i]
            endIndex = i
        }
        guard endIndex >= 0 else { return nil }

        var positions: [Int] = []
        var index = endIndex
        var needle = needles.count - 1
        while needle >= 0 {
            positions.append(index)
            index = previous[needle][index]
            needle -= 1
        }
        positions.reverse()

        var ranges: [Range<Int>] = []
        for position in positions {
            if let last = ranges.last, last.upperBound == position {
                ranges[ranges.count - 1] = last.lowerBound..<position + 1
            } else {
                ranges.append(position..<position + 1)
            }
        }

        // Characters skipped between the first and last hit, and the distance
        // of the first hit from the start.
        let gap = positions[positions.count - 1] - positions[0] - (needles.count - 1)
        return Match(score: endScore - gap - positions[0], ranges: ranges)
    }

    private static func characterScore(_ haystack: [Character], at index: Int, adjacent: Bool) -> Int {
        let isWordStart = index == 0
            || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber)
        return 1 + (isWordStart ? 5 : 0) + (adjacent ? 3 : 0)
    }
}

