import SwiftUI

/// User-selectable interface theme.
enum ThemePreference: String, CaseIterable {
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
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// App-wide user settings, persisted to UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var theme: ThemePreference {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    private static let themeKey = "theme"

    init() {
        theme = UserDefaults.standard.string(forKey: Self.themeKey)
            .flatMap(ThemePreference.init(rawValue:)) ?? .system
    }
}
