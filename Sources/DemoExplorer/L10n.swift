import SwiftUI

/// Resolves UI strings from the module's localization files.
///
/// Language selection is done by hand: CFBundle fails to match the user's
/// "zh-Hans" preference against the lowercased "zh-hans.lproj" directory that
/// SwiftPM produces, so `Bundle.localizedString` would always return English.
enum L10n {
    private static let stringsBundle: Bundle = {
        // SwiftPM lowercases ".lproj" directory names, and Bundle's registered
        // resource names are case-sensitive — look up "zh-hans" explicitly.
        func chineseBundle() -> Bundle? {
            for name in ["zh-Hans", "zh-hans"] {
                if let path = Bundle.module.path(forResource: name, ofType: "lproj"),
                   let bundle = Bundle(path: path) {
                    return bundle
                }
            }
            return nil
        }
        for language in Locale.preferredLanguages {
            if language.hasPrefix("zh"), let bundle = chineseBundle() { return bundle }
            if language.hasPrefix("en") { return .module }
        }
        return .module
    }()

    static func string(forKey key: String) -> String {
        stringsBundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Localized SwiftUI text; supports format arguments, e.g. `l10n("%lld items", count)`.
func l10n(_ key: String, _ args: CVarArg...) -> Text {
    if args.isEmpty {
        Text(L10n.string(forKey: key))
    } else {
        Text(String(format: L10n.string(forKey: key), arguments: args))
    }
}

/// Localized plain string for non-SwiftUI contexts (e.g. NSPanel messages).
func l10nString(_ key: String) -> String {
    L10n.string(forKey: key)
}
