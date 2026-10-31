import SwiftUI

/// Settings window content: a General section with the theme picker and the
/// interface language picker. Rows are pinned to the top edge with no card
/// chrome — like a native settings pane — so future sections stack below
/// without surgery.
public struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            l10n("General")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            themeRow
            languageRow

            if needsRelaunch {
                l10n("Restart to apply the new language")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 480, height: 320, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var themeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            l10n("Theme")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 16)
            Picker(selection: $settings.theme) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    l10n(theme.labelKey).tag(theme)
                }
            } label: {
                l10n("Theme")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
        }
    }

    private var languageRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            l10n("Language")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 16)
            Picker(selection: $settings.language) {
                ForEach(LanguagePreference.allCases, id: \.self) { language in
                    l10n(language.labelKey).tag(language)
                }
            } label: {
                l10n("Language")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
    }

    /// L10n bakes the UI language at launch, so a change only applies on
    /// relaunch — point that out while the stored choice would still resolve
    /// to a different language than the one running now.
    private var needsRelaunch: Bool {
        let chosen = settings.language == .system ? L10n.systemLanguage : settings.language
        return chosen != L10n.launchLanguage
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .frame(width: 480, height: 320)
}
