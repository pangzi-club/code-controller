import SwiftUI

/// User-selectable interface theme.
public enum ThemePreference: String, CaseIterable {
    case system
    case light
    case dark

    /// Localization key for the picker segment label.
    var labelKey: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The color scheme to apply; nil follows the system setting.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// User-selectable interface language.
enum LanguagePreference: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// UserDefaults key; L10n reads the same key when it fixes the launch
    /// language, so this is the single source of truth.
    static let defaultsKey = "language"

    /// Localization key for the picker item. Language names keep their
    /// autonyms ("English", "简体中文") in both localizations.
    var labelKey: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }
}

/// App-wide user settings, persisted to UserDefaults.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var theme: ThemePreference {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    @Published var language: LanguagePreference {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: LanguagePreference.defaultsKey) }
    }

    private static let themeKey = "theme"

    public init() {
        theme = UserDefaults.standard.string(forKey: Self.themeKey)
            .flatMap(ThemePreference.init(rawValue:)) ?? .system
        language = UserDefaults.standard.string(forKey: LanguagePreference.defaultsKey)
            .flatMap(LanguagePreference.init(rawValue:)) ?? .system
    }
}
