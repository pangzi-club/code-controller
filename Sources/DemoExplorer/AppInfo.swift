/// Canonical app identity — the single source of truth for name, bundle ID and
/// version. `Scripts/make-app.sh` parses these constants to generate the app
/// bundle's Info.plist, so they must be kept as simple string literals.
enum AppInfo {
    /// Display name shown in Finder, Dock and the menu bar.
    static let displayName = "DemoExplorer"

    /// Reverse-DNS bundle identifier; doubles as the preferences domain.
    static let bundleID = "org.bhwang.DemoExplorer"

    /// Marketing version, written to CFBundleShortVersionString / CFBundleVersion.
    static let version = "0.1"
}
