import AppKit
import Testing
@testable import DemoExplorer

// Serialized: the tests share the `theme` and `language` UserDefaults keys.
@Suite(.serialized)
@MainActor
struct SettingsStoreTests {
    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "theme")
        UserDefaults.standard.removeObject(forKey: LanguagePreference.defaultsKey)
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

    @Test("language falls back to system when nothing (or garbage) is stored")
    func languageFallback() {
        cleanUp()
        #expect(SettingsStore().language == .system)

        UserDefaults.standard.set("klingon", forKey: LanguagePreference.defaultsKey)
        defer { cleanUp() }
        #expect(SettingsStore().language == .system)
    }

    @Test("setting a language persists it for the next launch")
    func languagePersists() {
        cleanUp()
        defer { cleanUp() }

        SettingsStore().language = .simplifiedChinese

        #expect(UserDefaults.standard.string(forKey: LanguagePreference.defaultsKey) == "zh-Hans")
        #expect(SettingsStore().language == .simplifiedChinese)
    }

    @Test("every language round-trips through its raw value")
    func languageRawValueRoundTrip() {
        for language in LanguagePreference.allCases {
            #expect(LanguagePreference(rawValue: language.rawValue) == language)
        }
    }
}
