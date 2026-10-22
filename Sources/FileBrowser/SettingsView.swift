import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                l10n("Appearance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                appearanceCard
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(l10n("Settings"))
    }

    private var appearanceCard: some View {
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
        .background(cardShape)
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
