import AppKit
import Testing
@testable import DemoExplorer

// Serialized: the tests share the `theme` UserDefaults key.
@Suite(.serialized)
@MainActor
struct SettingsStoreTests {
    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "theme")
    }

    @Test("theme falls back to system when nothing (or garbage) is stored")
    func themeFallback() {
        cleanUp()
        #expect(SettingsStore().theme == .system)

        UserDefaults.standard.set("solarized", forKey: "theme")
        defer { cleanUp() }
        #expect(SettingsStore().theme == .system)
    }

    @Test("setting a theme persists it for the next launch")
    func themePersists() {
        cleanUp()
        defer { cleanUp() }

        SettingsStore().theme = .dark

        #expect(UserDefaults.standard.string(forKey: "theme") == "dark")
        #expect(SettingsStore().theme == .dark)
    }

    @Test("every theme maps to the expected app appearance")
    func appearanceMapping() {
        #expect(ThemePreference.system.appearance == nil)
        #expect(ThemePreference.light.appearance?.name == .aqua)
        #expect(ThemePreference.dark.appearance?.name == .darkAqua)
    }

    @Test("every theme round-trips through its raw value")
    func rawValueRoundTrip() {
        for theme in ThemePreference.allCases {
            #expect(ThemePreference(rawValue: theme.rawValue) == theme)
        }
    }
}
