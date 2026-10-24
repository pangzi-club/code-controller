import AppKit
import Foundation

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

    /// The appearance applied to the whole app; nil follows the system setting.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
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
