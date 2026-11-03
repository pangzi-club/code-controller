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

/// User-selectable code-highlighting theme: "Automatic" follows the interface
/// appearance (the stock behavior); the rest name a bundled HighlighterSwift
/// CSS theme directly. Raw values must match a `.css` file bundled with
/// HighlighterSwift.
public enum EditorThemeOption: String, CaseIterable {
    case automatic = ""
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

    static let defaultsKey = "editorTheme"

    /// Localization key for the picker item. Theme names are proper nouns and
    /// keep their spelling in both catalogs.
    var labelKey: String {
        switch self {
        case .automatic: "Automatic"
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

    @Published public var editorTheme: EditorThemeOption {
        didSet { UserDefaults.standard.set(editorTheme.rawValue, forKey: EditorThemeOption.defaultsKey) }
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
    private static let editorFontNameKey = "editorFontName"
    private static let editorFontSizeKey = "editorFontSize"

    /// The editor font resolved from the family and size settings.
    public var editorFont: EditorFont {
        EditorFont(fontName: editorFontName.isEmpty ? nil : editorFontName, size: editorFontSize)
    }

    /// The highlighting theme to render with: user-picked themes render with
    /// their own name and adopt the theme's background color; "Automatic"
    /// mirrors the interface appearance and keeps the stock control
    /// background.
    func resolvedHighlightTheme(for colorScheme: ColorScheme) -> HighlightTheme {
        switch editorTheme {
        case .automatic: HighlightTheme(colorScheme: colorScheme)
        case let option: HighlightTheme(name: option.rawValue)
        }
    }

    public init() {
        theme = UserDefaults.standard.string(forKey: Self.themeKey)
            .flatMap(ThemePreference.init(rawValue:)) ?? .system
        editorTheme = UserDefaults.standard.string(forKey: EditorThemeOption.defaultsKey)
            .flatMap(EditorThemeOption.init(rawValue:)) ?? .automatic
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
