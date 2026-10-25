import SwiftUI

/// Settings page: a General section with the theme picker and the interface
/// language picker. Rows share one card so future sections stack below
/// without surgery.
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                l10n("General")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                generalCard
                if needsRelaunch {
                    l10n("Restart to apply the new language")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle(l10n("Settings"))
    }

    private var generalCard: some View {
        VStack(spacing: 0) {
            themeRow
            Divider()
                .padding(.horizontal, 16)
            languageRow
        }
        .background(cardShape)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// L10n bakes the UI language at launch, so a change only applies on
    /// relaunch — point that out while the stored choice would still resolve
    /// to a different language than the one running now.
    private var needsRelaunch: Bool {
        let chosen = settings.language == .system ? L10n.systemLanguage : settings.language
        return chosen != L10n.launchLanguage
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .frame(width: 640, height: 400)
}
