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

public extension Notification.Name {
    /// Posted by the View menu's Toggle Sidebar command; the main window owns
    /// the split view's column visibility.
    static let toggleSidebar = Notification.Name("\(AppInfo.bundleID).toggleSidebar")

    /// Posted by the View menu's Refresh command; the workspace detail view
    /// reloads the tree, git statuses and the selected document.
    static let refreshWorkspace = Notification.Name("\(AppInfo.bundleID).refreshWorkspace")

    /// Posted by the ⌘W key monitor: close the selected tab. With no tabs
    /// open the event falls through and the system closes the window.
    static let closeCurrentTab = Notification.Name("\(AppInfo.bundleID).closeCurrentTab")

    /// Posted by the ⌘1…⌘9 key monitor with a 0-based tab index.
    static let selectTab = Notification.Name("\(AppInfo.bundleID).selectTab")

    /// Posted by the View menu's Go to File command; the workspace detail view
    /// toggles the quick-open panel.
    static let quickOpen = Notification.Name("\(AppInfo.bundleID).quickOpen")

    /// Posted by the View menu's Command Palette command (⌘⇧P); the panel
    /// opens in — or switches to — command mode.
    static let commandPalette = Notification.Name("\(AppInfo.bundleID).commandPalette")
}

/// Weak holder for the app's main window, filled in by WindowChrome's
/// tracking view. The tab key monitor uses it to tell the main window from
/// the Settings window, which keeps the system ⌘W.
@MainActor
enum MainWindowTracker {
    private static weak var window: NSWindow?

    static var isCurrentKey: Bool {
        guard let window else { return false }
        return window === NSApp.keyWindow
    }

    static func set(_ window: NSWindow?) {
        self.window = window
    }
}

/// SF Symbol per file type, shared by the tree and the tab strip.
enum FileIcon {
    static func symbolName(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "folder" }
        switch url.pathExtension.lowercased() {
        case "json", "yaml", "yml", "toml", "plist", "xml", "entitlements", "xcconfig", "lock":
            return "curlybraces"
        case "md", "markdown":
            return "doc.richtext"
        case "txt", "rtf", "log":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "heif",
             "tiff", "tif", "bmp", "avif", "pdf":
            return "photo"
        case "swift", "js", "jsx", "ts", "tsx", "mjs", "cjs", "py", "rb", "go", "rs",
             "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "kts", "cs", "php",
             "sh", "zsh", "bash", "fish", "lua", "pl", "r", "sql", "html", "css",
             "scss", "less", "vue", "svelte", "dart", "ex", "exs", "erl", "hs", "clj",
             "scala":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }
}
