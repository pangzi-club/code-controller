import SwiftUI

/// A settings category in the sidebar.
enum SettingsPane: String, CaseIterable {
    case general
    case appearance
    case editor
    case shortcuts

    /// Localization key for the sidebar row and the detail header.
    var labelKey: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .editor: "Editor"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .editor: "chevron.left.forwardslash.chevron.right"
        case .shortcuts: "command"
        }
    }
}

/// Settings window content: a sidebar with the four categories (General,
/// Appearance, Editor, Shortcuts) and a detail pane for the selected one.
/// The standard `Settings` scene owns the window (system titlebar, ⌘,);
/// this view only lays out its fixed-size content.
public struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var pane: SettingsPane = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 680, height: 460)
    }

    private var sidebar: some View {
        List(selection: $pane) {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                Label {
                    l10n(pane.labelKey)
                } icon: {
                    Image(systemName: pane.symbolName)
                }
                .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 180)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            l10n(pane.labelKey)
                .font(.system(size: 15, weight: .semibold))

            switch pane {
            case .general: GeneralPane()
            case .appearance: AppearancePane()
            case .editor: EditorPane()
            case .shortcuts: ShortcutsPane()
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Label left, control right — the one row shape every settings pane uses.
private struct SettingsRow<Content: View>: View {
    let labelKey: String
    let content: () -> Content

    init(_ labelKey: String, @ViewBuilder content: @escaping () -> Content) {
        self.labelKey = labelKey
        self.content = content
    }

    var body: some View {
        HStack(spacing: 16) {
            l10n(labelKey)
                .font(.system(size: 13))
            Spacer(minLength: 16)
            content()
        }
    }
}

/// Interface language. L10n bakes the UI language at launch, so a change
/// only applies on relaunch — pointed out while the stored choice would
/// still resolve to a different language than the one running now.
private struct GeneralPane: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow("Language") {
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

            if needsRelaunch {
                l10n("Restart to apply the new language")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var needsRelaunch: Bool {
        let chosen = settings.language == .system ? L10n.systemLanguage : settings.language
        return chosen != L10n.launchLanguage
    }
}

/// Interface theme: follow the system or force light/dark.
private struct AppearancePane: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        SettingsRow("Theme") {
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
}

/// Code highlighting theme and editor font, with a live preview so both are
/// visible before leaving settings.
private struct EditorPane: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private var sizeBounds: ClosedRange<Double> {
        Double(EditorFont.sizeRange.lowerBound)...Double(EditorFont.sizeRange.upperBound)
    }

    /// One built-in palette per interface appearance, with a live preview
    /// below showing whichever the current appearance resolves to.
    private func themePickerRow(
        _ labelKey: String,
        selection: Binding<EditorTheme>
    ) -> some View {
        SettingsRow(labelKey) {
            Picker(selection: selection) {
                ForEach(EditorTheme.allCases, id: \.self) { option in
                    l10n(option.labelKey).tag(option)
                }
            } label: {
                l10n(labelKey)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
    }

    static let previewCode = """
        import SwiftUI

        /// A small sample so theme and font changes show at a glance.
        struct SampleView: View {
            @State private var items = ["apple", "banana"]

            var body: some View {
                List(items, id: \\.self) { item in
                    Label(item, systemImage: "star")
                }
                .padding()
            }
        }
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                themePickerRow("Light Theme", selection: $settings.lightTheme)
                themePickerRow("Dark Theme", selection: $settings.darkTheme)

                SettingsRow("Font") {
                    Picker(selection: $settings.editorFontName) {
                        Text(l10nString("System Mono")).tag("")
                        ForEach(EditorFont.availableFamilies(), id: \.self) { family in
                            Text(family).tag(family)
                        }
                    } label: {
                        l10n("Font")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 180)
                }

                SettingsRow("Font Size") {
                    Stepper(value: $settings.editorFontSize, in: sizeBounds) {
                        Text("\(Int(settings.editorFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .leading)
                    }
                }
            }

            l10n("Preview")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            CodePane(
                tabID: "settings-preview",
                text: Self.previewCode,
                documentID: "settings-preview#1",
                language: "swift",
                theme: settings.resolvedHighlightTheme(for: colorScheme),
                font: settings.editorFont
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
            .frame(maxHeight: .infinity)
        }
    }
}

/// The app's keyboard shortcuts, for reference — they are fixed, not
/// rebindable.
private struct ShortcutsPane: View {
    private static let rows: [(keys: String, actionKey: String)] = [
        ("⌘P", "Go to File…"),
        ("⌘W", "Close Tab"),
        ("⌘1…⌘9", "Select Tab"),
        ("⌃⌘S", "Toggle Sidebar"),
        ("⌘R", "Refresh Workspace"),
        ("⌘,", "Open Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.rows, id: \.keys) { row in
                HStack(spacing: 16) {
                    l10n(row.actionKey)
                        .font(.system(size: 13))
                    Spacer(minLength: 16)
                    keyBadge(row.keys)
                }
            }
        }
    }

    private func keyBadge(_ keys: String) -> some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.15))
            )
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .frame(width: 680, height: 460)
}
