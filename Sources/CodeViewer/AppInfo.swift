/// Canonical app identity — the single source of truth for name, bundle ID,
/// versions and build number. `Scripts/make-app.sh` parses these constants to
/// generate the app bundle's Info.plist, so they must be kept as simple string
/// literals.
enum AppInfo {
    /// Display name shown in Finder, Dock and the menu bar.
    static let displayName = "Code Viewer"

    /// Reverse-DNS bundle identifier; doubles as the preferences domain.
    static let bundleID = "org.bhwang.CodeViewer"

    /// Marketing version, written to CFBundleShortVersionString.
    static let version = "0.1"

    /// Build number, written to CFBundleVersion; bump it for every App Store upload.
    static let build = "1"
}
