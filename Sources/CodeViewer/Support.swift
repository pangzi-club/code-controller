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

/// SF Symbol per file type, shared by the tree and the tab strip.
enum FileIcon {
    static func symbolName(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "folder" }
        switch url.pathExtension.lowercased() {
        case "json", "yaml", "yml", "toml", "plist", "xml", "entitlements", "xcconfig", "lock":
            return "curlybraces"
        case "md", "markdown", "txt", "rtf", "log":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tiff", "pdf":
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
