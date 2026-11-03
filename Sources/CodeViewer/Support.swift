import AppKit
import Foundation

enum FileOpener {
    /// Opens with the system default app.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Reveals and selects the item in Finder.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension URL {
    /// Replaces the home directory prefix with "~" for display.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
