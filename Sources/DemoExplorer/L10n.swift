import SwiftUI

/// Resolves UI strings from the module's localization files.
///
/// Language selection is done by hand: CFBundle fails to match the user's
/// "zh-Hans" preference against the lowercased "zh-hans.lproj" directory that
/// SwiftPM produces, so `Bundle.localizedString` would always return English.
enum L10n {
    /// The language the system selects: the first preferred language the app
    /// localizes for; English when nothing matches.
    static let systemLanguage: LanguagePreference = {
        for language in Locale.preferredLanguages {
            // Only match Simplified Chinese variants; Traditional Chinese
            // (zh-Hant, zh-TW, zh-HK) falls through to English since no
            // Traditional localization exists.
            if language == "zh" || language.hasPrefix("zh-Hans") || language.hasPrefix("zh-hans") {
                return .simplifiedChinese
            }
            if language.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }()

    /// The language the UI strings resolve for, fixed at launch: the Settings
    /// override if one is stored, otherwise the system language. Strings are
    /// baked into views when they are built, so a changed setting takes
    /// effect on relaunch.
    static let launchLanguage: LanguagePreference = {
        guard let stored = LanguagePreference(
            rawValue: UserDefaults.standard.string(forKey: LanguagePreference.defaultsKey) ?? ""
        ), stored != .system else {
            return systemLanguage
        }
        return stored
    }()

    private static let chineseBundle: Bundle? = {
        // SwiftPM lowercases ".lproj" directory names, and Bundle's registered
        // resource names are case-sensitive — look up "zh-hans" explicitly.
        for name in ["zh-Hans", "zh-hans"] {
            if let path = Bundle.module.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }()

    private static let stringsBundle: Bundle = {
        switch launchLanguage {
        case .english, .system: return .module
        case .simplifiedChinese: return chineseBundle ?? .module
        }
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

/// Localized plain string for non-SwiftUI contexts (menus, window titles).
public func l10nString(_ key: String) -> String {
    L10n.string(forKey: key)
}
