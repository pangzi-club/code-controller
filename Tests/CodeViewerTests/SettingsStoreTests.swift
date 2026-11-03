import SwiftUI
import Testing
@testable import CodeViewer

// Serialized: the tests share the theme, editor, and language UserDefaults keys.
@Suite(.serialized)
@MainActor
struct SettingsStoreTests {
    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "theme")
        UserDefaults.standard.removeObject(forKey: LanguagePreference.defaultsKey)
        UserDefaults.standard.removeObject(forKey: "lightTheme")
        UserDefaults.standard.removeObject(forKey: "darkTheme")
        UserDefaults.standard.removeObject(forKey: "editorTheme")
        UserDefaults.standard.removeObject(forKey: "editorFontName")
        UserDefaults.standard.removeObject(forKey: "editorFontSize")
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

    @Test("every theme maps to the expected color scheme")
    func colorSchemeMapping() {
        #expect(ThemePreference.system.colorScheme == nil)
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
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

    @Test("light and dark themes default to the stock appearance pair; garbage falls back")
    func lightDarkThemeFallback() {
        cleanUp()
        let fresh = SettingsStore()
        #expect(fresh.lightTheme == .xcode)
        #expect(fresh.darkTheme == .xcodeDusk)

        UserDefaults.standard.set("klingon", forKey: "lightTheme")
        UserDefaults.standard.set("solarized", forKey: "darkTheme")
        defer { cleanUp() }
        let fallback = SettingsStore()
        #expect(fallback.lightTheme == .xcode)
        #expect(fallback.darkTheme == .xcodeDusk)
    }

    @Test("setting the light and dark themes persists them for the next launch")
    func lightDarkThemePersists() {
        cleanUp()
        defer { cleanUp() }

        let store = SettingsStore()
        store.lightTheme = .solarizedLight
        store.darkTheme = .nord

        #expect(UserDefaults.standard.string(forKey: "lightTheme") == "solarized-light")
        #expect(UserDefaults.standard.string(forKey: "darkTheme") == "nord")
        let relaunched = SettingsStore()
        #expect(relaunched.lightTheme == .solarizedLight)
        #expect(relaunched.darkTheme == .nord)
    }

    @Test("a stored single editor theme seeds both slots once")
    func legacySingleThemeSeedsBothSlots() {
        cleanUp()
        UserDefaults.standard.set("dracula", forKey: "editorTheme")
        defer { cleanUp() }

        let migrated = SettingsStore()
        #expect(migrated.lightTheme == .dracula)
        #expect(migrated.darkTheme == .dracula)

        // Once the split keys exist, the legacy key no longer wins.
        migrated.lightTheme = .nord
        #expect(SettingsStore().lightTheme == .nord)
        #expect(SettingsStore().darkTheme == .dracula)
    }

    @Test("every editor theme round-trips through its raw value")
    func editorThemeRawValueRoundTrip() {
        for option in EditorThemeOption.allCases {
            #expect(EditorThemeOption(rawValue: option.rawValue) == option)
        }
    }

    @Test("each interface appearance resolves to its own editor theme")
    func resolvedHighlightTheme() {
        cleanUp()
        defer { cleanUp() }

        let store = SettingsStore()
        #expect(store.resolvedHighlightTheme(for: .light) == HighlightTheme.light)
        #expect(store.resolvedHighlightTheme(for: .dark) == HighlightTheme.dark)

        store.lightTheme = .solarizedLight
        store.darkTheme = .nord
        #expect(store.resolvedHighlightTheme(for: .light) == HighlightTheme(name: "solarized-light"))
        #expect(store.resolvedHighlightTheme(for: .dark) == HighlightTheme(name: "nord"))
    }

    @Test("editor font settings resolve into an EditorFont with a clamped size")
    func editorFontResolution() {
        cleanUp()
        defer { cleanUp() }

        let store = SettingsStore()
        #expect(store.editorFont == EditorFont.default)

        store.editorFontSize = 42
        #expect(store.editorFont.size == EditorFont.sizeRange.upperBound)
        store.editorFontSize = 2
        #expect(store.editorFont.size == EditorFont.sizeRange.lowerBound)

        store.editorFontName = "Menlo"
        #expect(
            store.editorFont
                == EditorFont(fontName: "Menlo", size: EditorFont.sizeRange.lowerBound)
        )
        #expect(UserDefaults.standard.string(forKey: "editorFontName") == "Menlo")
    }

    @Test("out-of-range stored font sizes clamp on load")
    func editorFontSizeClampsOnLoad() {
        cleanUp()
        UserDefaults.standard.set(42.0, forKey: "editorFontSize")
        defer { cleanUp() }
        #expect(SettingsStore().editorFontSize == Double(EditorFont.sizeRange.upperBound))
    }

    @Test("editor font settings persist for the next launch")
    func editorFontPersists() {
        cleanUp()
        defer { cleanUp() }

        let store = SettingsStore()
        store.editorFontName = "Menlo"
        store.editorFontSize = 15

        let relaunched = SettingsStore()
        #expect(relaunched.editorFont == EditorFont(fontName: "Menlo", size: 15))
    }
}
