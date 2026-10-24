import AppKit
import Combine

/// Settings window content: a General section with the theme segmented
/// control and the language picker. Laid out like a native settings pane —
/// rows pinned to the top edge, no card chrome — so future sections stack
/// below without surgery.
@MainActor
final class SettingsViewController: NSViewController {
    private let settings: SettingsStore
    private var cancellables: [AnyCancellable] = []
    private let segmented = NSSegmentedControl()
    private let languagePopup = NSPopUpButton()
    private let relaunchHint = NSTextField(labelWithString: "")

    init(settings: SettingsStore) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = NSView()

        let heading = NSTextField(labelWithString: l10n("General"))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let icon = NSImageView(image: symbolImage("circle.lefthalf.filled", pointSize: 15, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        let themeLabel = NSTextField(labelWithString: l10n("Theme"))
        themeLabel.font = .systemFont(ofSize: 13)

        segmented.segmentCount = ThemePreference.allCases.count
        for (index, theme) in ThemePreference.allCases.enumerated() {
            segmented.setLabel(l10n(theme.labelKey), forSegment: index)
        }
        segmented.trackingMode = .selectOne
        segmented.segmentStyle = .automatic
        segmented.target = self
        segmented.action = #selector(themeChanged)
        segmented.widthAnchor.constraint(equalToConstant: 240).isActive = true

        // Leading group hugs left, trailing group hugs right — label left,
        // control right, the classic settings-row alignment.
        let themeRow = NSStackView()
        themeRow.addView(icon, in: .leading)
        themeRow.addView(themeLabel, in: .leading)
        themeRow.addView(segmented, in: .trailing)
        themeRow.spacing = 12

        let globe = NSImageView(image: symbolImage("globe", pointSize: 15, weight: .medium))
        globe.contentTintColor = .secondaryLabelColor
        let languageLabel = NSTextField(labelWithString: l10n("Language"))
        languageLabel.font = .systemFont(ofSize: 13)

        for language in LanguagePreference.allCases {
            languagePopup.addItem(withTitle: l10n(language.labelKey))
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        languagePopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let languageRow = NSStackView()
        languageRow.addView(globe, in: .leading)
        languageRow.addView(languageLabel, in: .leading)
        languageRow.addView(languagePopup, in: .trailing)
        languageRow.spacing = 12

        relaunchHint.font = .systemFont(ofSize: 11)
        relaunchHint.textColor = .secondaryLabelColor

        heading.translatesAutoresizingMaskIntoConstraints = false
        themeRow.translatesAutoresizingMaskIntoConstraints = false
        languageRow.translatesAutoresizingMaskIntoConstraints = false
        relaunchHint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heading)
        view.addSubview(themeRow)
        view.addSubview(languageRow)
        view.addSubview(relaunchHint)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            themeRow.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            themeRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            themeRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            languageRow.topAnchor.constraint(equalTo: themeRow.bottomAnchor, constant: 8),
            languageRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            languageRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            relaunchHint.topAnchor.constraint(equalTo: languageRow.bottomAnchor, constant: 6),
            relaunchHint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            relaunchHint.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])

        cancellables = [
            settings.$theme
                .receive(on: DispatchQueue.main)
                .sink { [weak self] theme in self?.syncSegments(theme) },
            settings.$language
                .receive(on: DispatchQueue.main)
                .sink { [weak self] language in
                    self?.syncPopup(language)
                    self?.updateRelaunchHint()
                },
        ]
        syncSegments(settings.theme)
        syncPopup(settings.language)
        updateRelaunchHint()
    }

    @objc private func themeChanged() {
        let index = segmented.selectedSegment
        guard ThemePreference.allCases.indices.contains(index) else { return }
        settings.theme = ThemePreference.allCases[index]
    }

    @objc private func languageChanged() {
        let index = languagePopup.indexOfSelectedItem
        guard LanguagePreference.allCases.indices.contains(index) else { return }
        settings.language = LanguagePreference.allCases[index]
    }

    private func syncSegments(_ theme: ThemePreference) {
        let index = ThemePreference.allCases.firstIndex(of: theme) ?? 0
        segmented.setSelected(true, forSegment: index)
    }

    private func syncPopup(_ language: LanguagePreference) {
        let index = LanguagePreference.allCases.firstIndex(of: language) ?? 0
        languagePopup.selectItem(at: index)
    }

    private func updateRelaunchHint() {
        // L10n bakes the UI language at launch, so a change only applies on
        // relaunch — point that out while the stored choice would still
        // resolve to a different language than the one running now.
        let chosen = settings.language == .system ? L10n.systemLanguage : settings.language
        relaunchHint.stringValue = l10n("Restart to apply the new language")
        relaunchHint.isHidden = chosen == L10n.launchLanguage
    }
}
