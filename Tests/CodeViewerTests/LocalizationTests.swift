import Foundation
import Testing
@testable import CodeViewer

@Suite
struct LocalizationTests {
    private func loadStrings(_ language: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CodeViewerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Sources/CodeViewer/Resources")
            .appendingPathComponent("\(language).lproj/Localizable.strings")

        let parsed = NSDictionary(contentsOfFile: url.path) as? [String: String]
        return try #require(parsed, "Could not parse \(url.path)")
    }

    @Test("English and Chinese catalogs have identical keys and no empty values")
    func keyParity() throws {
        let english = try loadStrings("en")
        let chinese = try loadStrings("zh-Hans")

        let missingInChinese = Set(english.keys).subtracting(chinese.keys).sorted()
        let missingInEnglish = Set(chinese.keys).subtracting(english.keys).sorted()

        #expect(!english.isEmpty)
        #expect(
            Set(english.keys) == Set(chinese.keys),
            "Missing zh-Hans: \(missingInChinese), missing en: \(missingInEnglish)"
        )
        #expect(english.values.allSatisfy { !$0.isEmpty })
        #expect(chinese.values.allSatisfy { !$0.isEmpty })
    }

    @Test("every enum label key resolves in both catalogs")
    func enumLabels() throws {
        let english = try loadStrings("en")
        let chinese = try loadStrings("zh-Hans")
        let keys = Set(
            ThemePreference.allCases.map(\.labelKey)
                + LanguagePreference.allCases.map(\.labelKey)
                + EditorTheme.allCases.map(\.labelKey)
                + SettingsPane.allCases.map(\.labelKey)
        )

        for key in keys {
            #expect(english[key] != nil, "Missing en key: \(key)")
            #expect(chinese[key] != nil, "Missing zh-Hans key: \(key)")
        }
    }

    @Test("the lookup helpers never return an empty string")
    func lookupHelpers() {
        #expect(!l10nString("Settings").isEmpty)
        #expect(!L10n.string(forKey: "Settings").isEmpty)
    }
}
