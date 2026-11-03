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

/// User-selectable code-highlighting theme. Raw values must match a `.css`
/// file bundled with HighlighterSwift. The editor keeps one theme per
/// interface appearance (`SettingsStore.lightTheme` / `darkTheme`), so the
/// defaults below reproduce the stock appearance-following pair.
public enum EditorThemeOption: String, CaseIterable {
    case xcode
    case xcodeDusk = "xcode-dusk"
    case github
    case githubDark = "github-dark"
    case atomOneLight = "atom-one-light"
    case atomOneDark = "atom-one-dark"
    case dracula
    case nord
    case monokai
    case solarizedLight = "solarized-light"
    case solarizedDark = "solarized-dark"
    case tokyoNight = "tokyo-night-dark"
    case vsDark = "vs-dark"

    /// Localization key for the picker item. Theme names are proper nouns and
    /// keep their spelling in both catalogs.
    var labelKey: String {
        switch self {
        case .xcode: "Xcode"
        case .xcodeDusk: "Xcode Dusk"
        case .github: "GitHub"
        case .githubDark: "GitHub Dark"
        case .atomOneLight: "Atom One Light"
        case .atomOneDark: "Atom One Dark"
        case .dracula: "Dracula"
        case .nord: "Nord"
        case .monokai: "Monokai"
        case .solarizedLight: "Solarized Light"
        case .solarizedDark: "Solarized Dark"
        case .tokyoNight: "Tokyo Night"
        case .vsDark: "VS Dark"
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

    /// The highlighting theme used while the interface is in light mode.
    @Published public var lightTheme: EditorThemeOption {
        didSet { UserDefaults.standard.set(lightTheme.rawValue, forKey: Self.lightThemeKey) }
    }

    /// The highlighting theme used while the interface is in dark mode.
    @Published public var darkTheme: EditorThemeOption {
        didSet { UserDefaults.standard.set(darkTheme.rawValue, forKey: Self.darkThemeKey) }
    }

    /// Editor font family; an empty string means the system monospaced font.
    @Published public var editorFontName: String {
        didSet { UserDefaults.standard.set(editorFontName, forKey: Self.editorFontNameKey) }
    }

    @Published public var editorFontSize: Double {
        didSet { UserDefaults.standard.set(editorFontSize, forKey: Self.editorFontSizeKey) }
    }

    @Published var language: LanguagePreference {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: LanguagePreference.defaultsKey) }
    }

    private static let themeKey = "theme"
    private static let lightThemeKey = "lightTheme"
    private static let darkThemeKey = "darkTheme"
    /// Pre-split single editor theme; read once to seed both slots.
    private static let legacyThemeKey = "editorTheme"
    private static let editorFontNameKey = "editorFontName"
    private static let editorFontSizeKey = "editorFontSize"

    /// The editor font resolved from the family and size settings.
    public var editorFont: EditorFont {
        EditorFont(fontName: editorFontName.isEmpty ? nil : editorFontName, size: editorFontSize)
    }

    /// The highlighting theme for the interface appearance currently in
    /// effect. Themes always render on their own background color.
    func resolvedHighlightTheme(for colorScheme: ColorScheme) -> HighlightTheme {
        HighlightTheme(name: colorScheme == .dark ? darkTheme.rawValue : lightTheme.rawValue)
    }

    public init() {
        theme = UserDefaults.standard.string(forKey: Self.themeKey)
            .flatMap(ThemePreference.init(rawValue:)) ?? .system
        // A previously stored single editor theme ("always this theme")
        // seeds both slots; each slot defaults to the stock appearance
        // pair (Xcode in light, Xcode Dusk in dark).
        let legacyTheme = UserDefaults.standard.string(forKey: Self.legacyThemeKey)
            .flatMap(EditorThemeOption.init(rawValue:))
        lightTheme = UserDefaults.standard.string(forKey: Self.lightThemeKey)
            .flatMap(EditorThemeOption.init(rawValue:))
            ?? legacyTheme ?? .xcode
        darkTheme = UserDefaults.standard.string(forKey: Self.darkThemeKey)
            .flatMap(EditorThemeOption.init(rawValue:))
            ?? legacyTheme ?? .xcodeDusk
        editorFontName = UserDefaults.standard.string(forKey: Self.editorFontNameKey) ?? ""
        // A missing size is 13; a stored one clamps into the offered range so
        // the stepper and the effective font never disagree after a relaunch.
        let storedFontSize = UserDefaults.standard.double(forKey: Self.editorFontSizeKey)
        let baseSize: Double = storedFontSize > 0 ? storedFontSize : 13
        editorFontSize = min(
            max(baseSize, Double(EditorFont.sizeRange.lowerBound)),
            Double(EditorFont.sizeRange.upperBound)
        )
        language = UserDefaults.standard.string(forKey: LanguagePreference.defaultsKey)
            .flatMap(LanguagePreference.init(rawValue:)) ?? .system
    }
}
